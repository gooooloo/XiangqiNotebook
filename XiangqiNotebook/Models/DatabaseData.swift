import Foundation

class DatabaseData: Codable {
    var fenObjects2: [Int: FenObject] = [:]
    var fenToId: [String: Int] = [:]
    var moveObjects: [Int: Move] = [:]
    var moveToId: [[Int]: Int] = [:]
    var gameObjects: [UUID: GameObject] = [:]
    var bookObjects: [UUID: BookObject] = [:]
    var bookmarks: [[Int]: String] = [:]
    var myRealRedGameStatisticsByFenId: [Int: GameResultStatistics] = [:]
    var myRealBlackGameStatisticsByFenId: [Int: GameResultStatistics] = [:]
    var dataVersion: Int = 0
    
    enum CodingKeys: String, CodingKey {
        case fenObjects2 = "fenObjects2"
        case moveObjects = "MoveObjects"
        case gameObjects = "game_objects"
        case bookObjects = "book_objects"
        case bookmarks
        case myRealRedGameStatisticsByFenId = "my_real_red_game_statistics_by_fen_id"
        case myRealBlackGameStatisticsByFenId = "my_real_black_game_statistics_by_fen_id"
        case dataVersion = "data_version"
    }

    // MARK: - Initialization

    init() {
        // 默认初始化器，用于创建空的 DatabaseData
    }

    // MARK: - Codable Implementation

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        fenObjects2 = try container.decode([Int: FenObject].self, forKey: .fenObjects2)
        moveObjects = try container.decode([Int: Move].self, forKey: .moveObjects)
        gameObjects = try container.decode([UUID: GameObject].self, forKey: .gameObjects)
        bookObjects = try container.decode([UUID: BookObject].self, forKey: .bookObjects)
        bookmarks = try container.decode([[Int]: String].self, forKey: .bookmarks)
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
            if let targetFenId = move.targetFenId,
               let sourceFenObject = fenObjects2[move.sourceFenId] {
                sourceFenObject.addMoveIfNeeded(move: move)
            }
        }

        print("✅ DatabaseData: 索引重建完成 (fenToId: \(fenToId.count), moveToId: \(moveToId.count))")
    }
}
