import Foundation

class DatabaseData: Codable {
    var fenObjects2: [Int: FenObject] = [:]
    var fenToId: [String: Int] = [:]
    var moveObjects: [Int: Move] = [:]
    var moveToId: [[Int]: Int] = [:]
    var gameObjects: [UUID: GameObject] = [:]
    var bookObjects: [UUID: BookObject] = [:]
    var bookmarks: [[Int]: String] = [:]
    var reviewItems: [Int: SRSData] = [:]
    /// 练习模式走错统计：fenId → 该局面下出现过的所有错招记录
    var practiceMistakes: [Int: [PracticeMistakeRecord]] = [:]
    var myRealRedGameStatisticsByFenId: [Int: GameResultStatistics] = [:]
    var myRealBlackGameStatisticsByFenId: [Int: GameResultStatistics] = [:]
    var dataVersion: Int = 0

    /// 当前代码支持的数据库 schema 版本。
    /// 与 dataVersion（数据内容版本，每次保存递增）不同，
    /// schemaVersion 标识文件结构本身，仅在结构不兼容演进时递增
    static let currentSchemaVersion = 1
    var schemaVersion: Int = DatabaseData.currentSchemaVersion

    enum SchemaError: Error, LocalizedError {
        case newerSchema(found: Int, supported: Int)

        var errorDescription: String? {
            switch self {
            case .newerSchema(let found, let supported):
                return "数据库文件 schema 版本 \(found) 高于本版本应用支持的 \(supported)，请升级应用后再打开"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case fenObjects2 = "fenObjects2"
        case moveObjects = "MoveObjects"
        case gameObjects = "game_objects"
        case bookObjects = "book_objects"
        case bookmarks
        case reviewItems = "review_items"
        case practiceMistakes = "practice_mistakes"
        case myRealRedGameStatisticsByFenId = "my_real_red_game_statistics_by_fen_id"
        case myRealBlackGameStatisticsByFenId = "my_real_black_game_statistics_by_fen_id"
        case dataVersion = "data_version"
        case schemaVersion = "schema_version"
    }

    // MARK: - Initialization

    init() {
        // 默认初始化器，用于创建空的 DatabaseData
    }

    // MARK: - Codable Implementation

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 迁移判断：无该字段的存量文件视为版本 1；
        // 文件来自更新版本的应用（schema 更高）时显式报错，避免静默误读
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw SchemaError.newerSchema(found: schemaVersion, supported: Self.currentSchemaVersion)
        }

        fenObjects2 = try container.decode([Int: FenObject].self, forKey: .fenObjects2)
        moveObjects = try container.decode([Int: Move].self, forKey: .moveObjects)
        gameObjects = try container.decode([UUID: GameObject].self, forKey: .gameObjects)
        bookObjects = try container.decode([UUID: BookObject].self, forKey: .bookObjects)
        bookmarks = try container.decode([[Int]: String].self, forKey: .bookmarks)
        reviewItems = try container.decodeIfPresent([Int: SRSData].self, forKey: .reviewItems) ?? [:]
        practiceMistakes = try container.decodeIfPresent([Int: [PracticeMistakeRecord]].self, forKey: .practiceMistakes) ?? [:]
        myRealRedGameStatisticsByFenId = try container.decode([Int: GameResultStatistics].self, forKey: .myRealRedGameStatisticsByFenId)
        myRealBlackGameStatisticsByFenId = try container.decode([Int: GameResultStatistics].self, forKey: .myRealBlackGameStatisticsByFenId)
        dataVersion = try container.decode(Int.self, forKey: .dataVersion)

        // 反序列化后立即重建索引
        rebuildIndexes()
    }

    /// 重建派生索引（从备份恢复后需要调用）
    func rebuildIndexes() {
        // 1. 重建 fenToId 索引
        fenToId = fenObjects2.reduce(into: [String: Int]()) { result, pair in
            result[pair.value.fen] = pair.key
        }

        // 2. 重建 moveToId 索引
        moveToId = [:]
        for (moveId, move) in moveObjects {
            if let targetFenId = move.targetFenId {
                moveToId[[move.sourceFenId, targetFenId]] = moveId
            }
        }

        // 3. 重建 FenObject 的 fenId 引用
        for (fenId, fenObject) in fenObjects2 {
            fenObject.fenId = fenId
        }

        // 4. 重建 FenObject 中的 moves 关联
        for (_, move) in moveObjects {
            if move.targetFenId != nil,
               let sourceFenObject = fenObjects2[move.sourceFenId] {
                _ = sourceFenObject.addMoveIfNeeded(move: move)
            }
        }

        print("✅ DatabaseData: 索引重建完成 (fenToId: \(fenToId.count), moveToId: \(moveToId.count))")
    }
}
