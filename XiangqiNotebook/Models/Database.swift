import Foundation
import Combine

/// Database 负责管理全局共享的 DatabaseData
/// 确保多个窗口之间的数据同步
///
/// 注意：Database 现在是 internal，不应在 Models 模块外直接访问
/// 请通过 DatabaseView 访问所有数据库操作（包括数据访问和持久化）
internal class Database: ObservableObject {
    // MARK: - Singleton
    internal static let shared = Database()

    // MARK: - Properties
    @Published private(set) var databaseData: DatabaseData
    @Published private(set) var isDirty: Bool = false

    // MARK: - Real Games Index
    /// 实战反查表：fenId → 包含该局面的实战 gameId 集合（仅限"我的实战"书下的游戏）
    private(set) var realGamesByFenId: [Int: Set<UUID>] = [:]
    /// 索引是否已构建完成
    private(set) var isRealGamesIndexReady: Bool = false

    // MARK: - Engine Score Properties
    /// 引擎分数数据，key 为 engineKey（如 "Pikafish_2024-12-28_d34"）
    private(set) var engineScores: [String: EngineScoreData] = [:]
    /// 需要保存的 engineKey 集合
    private(set) var dirtyEngineKeys: Set<String> = []
    /// 当前活跃的引擎 key（PikafishService 启动时设置）
    var activeEngineKey: String?

    // MARK: - Initialization
    private init() {
        // 尝试加载数据库
        if let loadedData = DatabaseStorage.loadDatabaseFromDefault() {
            self.databaseData = loadedData
            print("✅ Database: 成功加载数据库")
        } else {
            // 创建空的数据库（包含起始局面）
            self.databaseData = DatabaseStorage.createEmptyDatabase()
            print("⚠️ Database: 创建新数据库")
        }

        // 确保虚拟根局面 origin 存在，并把所有棋谱的起始局面挂载到 origin 之下
        Self.ensureVirtualOriginAndMoves(in: databaseData)

        // 加载所有引擎分数文件
        loadAllEngineScores()
    }

    #if DEBUG
    /// 测试专用构造器：直接用提供的 DatabaseData 创建实例
    /// 注意：不自动调用 ensureVirtualOriginAndMoves，因为测试通常在 init 后才填充 fenObjects2。
    /// 测试需要 origin 时请在数据填充完毕后手动调用 Database.ensureVirtualOriginAndMoves(in:)
    init(testDatabaseData: DatabaseData) {
        self.databaseData = testDatabaseData
        print("✅ Database: 创建测试数据库实例")
    }
    #endif

    /// 当前数据库中虚拟根局面的 fenId
    /// 生产代码中 init 已确保存在；测试代码若未调用 ensureVirtualOriginAndMoves 可能返回 nil
    var originFenId: Int? {
        databaseData.originFenId
    }

    /// 确保数据库中存在虚拟根局面 origin，并把所有 gameObjects 的起始局面挂载到 origin 之下（创建虚拟着法）
    /// 此操作幂等：origin 已存在则复用，虚拟着法已存在则跳过
    static func ensureVirtualOriginAndMoves(in data: DatabaseData) {
        // 1. 确保 origin FenObject 存在
        let originFenId: Int
        if let existing = data.originFenId {
            originFenId = existing
        } else {
            // 分配下一个可用 fenId
            let maxId = data.fenObjects2.keys.max() ?? 0
            originFenId = maxId + 1
            let origin = FenObject(fen: DatabaseData.originFen, fenId: originFenId)
            data.fenObjects2[originFenId] = origin
            data.fenToId[DatabaseData.originFen] = originFenId
        }

        // 2. 为每个 gameObject 的起始局面创建虚拟着法 origin → startingFenId
        guard let originFenObject = data.fenObjects2[originFenId] else { return }
        for (_, game) in data.gameObjects {
            guard let startFenId = game.startingFenId else { continue }
            guard startFenId != originFenId else { continue }
            // 检查是否已存在 origin → startFenId 的着法
            if data.moveToId[[originFenId, startFenId]] != nil { continue }
            // 创建新的虚拟着法
            let newMove = Move(sourceFenId: originFenId, targetFenId: startFenId)
            let newMoveId = (data.moveObjects.keys.max() ?? 0) + 1
            data.moveObjects[newMoveId] = newMove
            data.moveToId[[originFenId, startFenId]] = newMoveId
            _ = originFenObject.addMoveIfNeeded(move: newMove)
        }
    }

    // MARK: - Data Mutation

    /// 标记数据已修改
    func markDirty() {
        guard !isDirty else { return }

        invalidateRealGamesIndex()

        DispatchQueue.main.async {
            self.isDirty = true
            self.databaseData.dataVersion += 1
            print("🔄 Database: 数据已标记为脏 (版本 \(self.databaseData.dataVersion))")
        }
    }

    /// 清除脏标记
    func markClean() {
        DispatchQueue.main.async {
            self.isDirty = false
            print("✅ Database: 数据已标记为干净")
        }
    }

    // MARK: - Persistence

    /// 保存数据库到默认位置
    func save() throws {
        guard isDirty else {
            print("ℹ️ Database: 数据无变化，跳过保存")
            return
        }

        guard let dbURL = DatabaseStorage.getDatabaseURL() else {
            throw DatabaseError.urlUnavailable
        }

        try DatabaseStorage.saveDatabaseToURL(databaseData, url: dbURL)
        markClean()
        print("✅ Database: 数据已保存到 \(dbURL)")
    }

    /// 从默认位置重新加载数据库
    func reload() throws {
        guard let newData = DatabaseStorage.loadDatabaseFromDefault() else {
            throw DatabaseError.loadFailed
        }

        DispatchQueue.main.async {
            self.databaseData = newData
            self.isDirty = false
            print("✅ Database: 数据已重新加载")
        }
    }

    // MARK: - Engine Score Operations

    /// 加载所有引擎分数文件
    private func loadAllEngineScores() {
        let keys = EngineScoreStorage.listEngineKeys()
        for key in keys {
            if let data = EngineScoreStorage.loadEngineScore(engineKey: key) {
                engineScores[key] = data
            }
        }
        print("✅ Database: 加载了 \(engineScores.count) 个引擎分数文件")
    }

    /// 获取指定 fenId 和 engineKey 的引擎分数
    func getEngineScore(fenId: Int, engineKey: String) -> Int? {
        return engineScores[engineKey]?.scores[fenId]
    }

    /// 使用 activeEngineKey 获取引擎分数（便捷方法）
    func getActiveEngineScore(fenId: Int) -> Int? {
        guard let key = activeEngineKey else { return nil }
        return getEngineScore(fenId: fenId, engineKey: key)
    }

    /// 写入引擎分数到内存并标记脏
    func setEngineScore(fenId: Int, engineKey: String, score: Int) {
        if engineScores[engineKey] == nil {
            engineScores[engineKey] = EngineScoreData()
        }
        engineScores[engineKey]?.scores[fenId] = score
        engineScores[engineKey]?.dataVersion += 1
        dirtyEngineKeys.insert(engineKey)
    }

    /// 保存所有脏的引擎分数文件
    func saveEngineScores() throws {
        for key in dirtyEngineKeys {
            guard let data = engineScores[key] else { continue }
            try EngineScoreStorage.saveEngineScore(data, engineKey: key)
        }
        if !dirtyEngineKeys.isEmpty {
            print("✅ Database: 保存了 \(dirtyEngineKeys.count) 个引擎分数文件")
        }
        dirtyEngineKeys.removeAll()
    }

    /// 清除引擎分数脏标记
    func markEngineScoreClean() {
        dirtyEngineKeys.removeAll()
    }

    /// 引擎分数是否有未保存的修改
    var isEngineScoreDirty: Bool {
        !dirtyEngineKeys.isEmpty
    }

    // MARK: - Real Games Index Operations

    /// 构建实战反查表索引
    /// 遍历"我的实战"书下所有游戏，建立 fenId → gameId 映射
    func buildRealGamesIndex() {
        let myRealGameBookId = Session.myRealGameBookId

        guard let book = databaseData.bookObjects[myRealGameBookId] else {
            realGamesByFenId = [:]
            isRealGamesIndexReady = true
            return
        }

        var index: [Int: Set<UUID>] = [:]
        var visitedBookIds = Set<UUID>()

        func collectGames(from bookId: UUID) {
            guard !visitedBookIds.contains(bookId) else { return }
            visitedBookIds.insert(bookId)

            guard let currentBook = databaseData.bookObjects[bookId] else { return }

            for gameId in currentBook.gameIds {
                guard let game = databaseData.gameObjects[gameId] else { continue }

                // 索引 startingFenId
                if let startingFenId = game.startingFenId {
                    index[startingFenId, default: []].insert(gameId)
                }

                // 索引所有着法的 sourceFenId 和 targetFenId
                for moveId in game.moveIds {
                    guard let move = databaseData.moveObjects[moveId] else { continue }
                    index[move.sourceFenId, default: []].insert(gameId)
                    if let targetFenId = move.targetFenId {
                        index[targetFenId, default: []].insert(gameId)
                    }
                }
            }

            for subBookId in currentBook.subBookIds {
                collectGames(from: subBookId)
            }
        }

        collectGames(from: myRealGameBookId)
        realGamesByFenId = index
        isRealGamesIndexReady = true
    }

    /// 使索引失效（数据变更时调用）
    func invalidateRealGamesIndex() {
        isRealGamesIndexReady = false
    }

    // MARK: - Backup/Restore

    /// 从备份恢复数据库（用于用户手动恢复备份）
    /// - Parameter database: 要恢复的数据库数据
    func restoreFromBackup(_ database: DatabaseData) {
        // 必须在主线程同步执行，确保数据立即更新
        // 注意：索引已在 DatabaseData.init(from:) 中自动重建
        if Thread.isMainThread {
            let oldVersion = self.databaseData.dataVersion

            self.objectWillChange.send()  // 手动触发通知
            self.databaseData = database
            self.isDirty = true  // 标记为脏，需要保存
            print("✅ Database: 数据已从备份恢复 (版本 \(oldVersion) → \(database.dataVersion))")
        } else {
            DispatchQueue.main.sync {
                let oldVersion = self.databaseData.dataVersion

                self.objectWillChange.send()  // 手动触发通知
                self.databaseData = database
                self.isDirty = true
                print("✅ Database: 数据已从备份恢复 (版本 \(oldVersion) → \(database.dataVersion))")
            }
        }
    }

}

// MARK: - Errors
enum DatabaseError: Error {
    case urlUnavailable
    case fileOperationFailed
    case loadFailed
}
