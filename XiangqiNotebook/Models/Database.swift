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

        // 加载所有引擎分数文件
        loadAllEngineScores()
    }

    #if DEBUG
    /// 测试专用构造器：直接用提供的 DatabaseData 创建实例
    /// 这样可以避免测试之间的相互影响，以及与UI线程的并发访问问题
    init(testDatabaseData: DatabaseData) {
        self.databaseData = testDatabaseData
        print("✅ Database: 创建测试数据库实例")
    }
    #endif

    // MARK: - Data Mutation

    /// 标记数据已修改
    func markDirty() {
        guard !isDirty else { return }

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
