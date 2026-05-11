import Testing
import Foundation
@testable import XiangqiNotebook

/// 虚拟根局面 origin 的集成测试
struct VirtualOriginTests {

    // MARK: - createEmptyDatabase 行为

    @Test func emptyDatabaseHasStandardOpeningAndOrigin() {
        let db = DatabaseStorage.createEmptyDatabase()
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        // fenId=1 标准开局，fenId=2 虚拟根 origin
        #expect(db.fenObjects2[1]?.fen == startFen)
        #expect(db.fenObjects2[2]?.fen == DatabaseData.originFen)
        #expect(db.originFenId == 2)
    }

    // MARK: - ensureVirtualOriginAndMoves 行为

    @Test func ensureAddsOriginToExistingDatabaseAtMaxIdPlusOne() {
        // 模拟旧版本数据库：只有标准开局在 fenId=1，没有 origin
        let data = DatabaseData()
        let fen1 = FenObject(fen: "standardOpening", fenId: 1)
        data.fenObjects2[1] = fen1
        data.fenToId["standardOpening"] = 1
        let fen2 = FenObject(fen: "someOtherFen", fenId: 2)
        data.fenObjects2[2] = fen2
        data.fenToId["someOtherFen"] = 2

        // 此时还没有 origin
        #expect(data.originFenId == nil)

        Database.ensureVirtualOriginAndMoves(in: data)

        // origin 被分配到 maxId+1 = 3，且原有数据不受影响
        #expect(data.originFenId == 3)
        #expect(data.fenObjects2[3]?.fen == DatabaseData.originFen)
        #expect(data.fenObjects2[1]?.fen == "standardOpening")  // 未被覆盖
        #expect(data.fenObjects2[2]?.fen == "someOtherFen")
    }

    @Test func ensureIsIdempotent() {
        let data = DatabaseData()
        let fen1 = FenObject(fen: "abc", fenId: 1)
        data.fenObjects2[1] = fen1
        data.fenToId["abc"] = 1

        Database.ensureVirtualOriginAndMoves(in: data)
        let firstOriginId = data.originFenId
        let firstCount = data.fenObjects2.count

        Database.ensureVirtualOriginAndMoves(in: data)
        #expect(data.originFenId == firstOriginId)
        #expect(data.fenObjects2.count == firstCount)
    }

    @Test func ensureCreatesVirtualMovesForGamesStartingFens() {
        let data = DatabaseData()
        let fenA = FenObject(fen: "fenA", fenId: 1)
        data.fenObjects2[1] = fenA
        data.fenToId["fenA"] = 1
        let fenB = FenObject(fen: "fenB", fenId: 2)
        data.fenObjects2[2] = fenB
        data.fenToId["fenB"] = 2

        // 两个棋谱：一个从 fenId=1 起始（标准开局），一个从 fenId=2 起始（中局题）
        let game1 = GameObject(id: UUID()); game1.startingFenId = 1; game1.name = "g1"
        let game2 = GameObject(id: UUID()); game2.startingFenId = 2; game2.name = "g2"
        data.gameObjects[game1.id] = game1
        data.gameObjects[game2.id] = game2

        Database.ensureVirtualOriginAndMoves(in: data)

        let originFenId = data.originFenId!
        // 应当为每个 startingFen 创建一个 origin → startingFen 的虚拟着法
        #expect(data.moveToId[[originFenId, 1]] != nil)
        #expect(data.moveToId[[originFenId, 2]] != nil)
        // origin 的 moves 列表中包含这两条虚拟着法
        let originMoves = data.fenObjects2[originFenId]?.moves ?? []
        let targetIds = Set(originMoves.compactMap { $0.targetFenId })
        #expect(targetIds.contains(1))
        #expect(targetIds.contains(2))
    }

    @Test func ensureDoesNotDuplicateExistingVirtualMoves() {
        let data = DatabaseData()
        let fenA = FenObject(fen: "fenA", fenId: 1)
        data.fenObjects2[1] = fenA
        data.fenToId["fenA"] = 1
        let game = GameObject(id: UUID()); game.startingFenId = 1; game.name = "g"
        data.gameObjects[game.id] = game

        Database.ensureVirtualOriginAndMoves(in: data)
        let count1 = data.moveObjects.count

        Database.ensureVirtualOriginAndMoves(in: data)
        // 重复调用不应当创建新的虚拟着法
        #expect(data.moveObjects.count == count1)
    }

    // MARK: - DatabaseView origin 包含

    @Test func allViewsContainOrigin() {
        let data = DatabaseData()
        let fen1 = FenObject(fen: "fen1", fenId: 1)
        fen1.setInRedOpening(true)
        data.fenObjects2[1] = fen1
        data.fenToId["fen1"] = 1
        let fen2 = FenObject(fen: "fen2", fenId: 2)
        fen2.setInBlackOpening(true)
        data.fenObjects2[2] = fen2
        data.fenToId["fen2"] = 2
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let originId = db.originFenId!

        // origin 应该在所有便利视图的 scope 内
        #expect(DatabaseView.full(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.redOpening(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.blackOpening(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.redRealGame(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.blackRealGame(database: db).containsFenId(originId) == true)
    }

    @Test func nonOriginFensStillRespectFilters() {
        // 验证 origin 的特殊处理不会让 filter 对其他 fenId 失效
        let data = DatabaseData()
        let fen1 = FenObject(fen: "fen1", fenId: 1)
        fen1.setInRedOpening(true)
        data.fenObjects2[1] = fen1
        data.fenToId["fen1"] = 1
        let fen2 = FenObject(fen: "fen2", fenId: 2)
        fen2.setInRedOpening(false)
        data.fenObjects2[2] = fen2
        data.fenToId["fen2"] = 2
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let redView = DatabaseView.redOpening(database: db)
        #expect(redView.containsFenId(1) == true)   // 红方开局内
        #expect(redView.containsFenId(2) == false)  // 不在红方开局
    }

    // MARK: - allFenWithoutScore 排除 origin

    @Test func allFenWithoutScoreExcludesOrigin() {
        let data = DatabaseData()
        let fen1 = FenObject(fen: "fen1", fenId: 1)
        // score 为 nil
        data.fenObjects2[1] = fen1
        data.fenToId["fen1"] = 1
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let view = DatabaseView.full(database: db)
        let unscoredFens = view.allFenWithoutScore
        #expect(unscoredFens.contains("fen1") == true)
        #expect(unscoredFens.contains(DatabaseData.originFen) == false)
    }

    // MARK: - Codable 持久化兼容性

    @Test func encodeAndDecodePreservesOrigin() throws {
        let data = DatabaseData()
        Database.ensureVirtualOriginAndMoves(in: data)
        let originId = data.originFenId!

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DatabaseData.self, from: encoded)
        #expect(decoded.originFenId == originId)
        #expect(decoded.fenObjects2[originId]?.fen == DatabaseData.originFen)
    }

    @Test func decodingLegacyDataWithoutOriginThenEnsuringIsIdempotent() throws {
        // 模拟旧版本数据库 JSON（无 origin）
        let legacy = DatabaseData()
        let fen1 = FenObject(fen: "legacy_fen", fenId: 1)
        legacy.fenObjects2[1] = fen1
        legacy.fenToId["legacy_fen"] = 1

        let encoded = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(DatabaseData.self, from: encoded)
        #expect(decoded.originFenId == nil)

        Database.ensureVirtualOriginAndMoves(in: decoded)
        #expect(decoded.originFenId == 2)

        // 再次 encode/decode + ensure 应保持稳定
        let encoded2 = try JSONEncoder().encode(decoded)
        let decoded2 = try JSONDecoder().decode(DatabaseData.self, from: encoded2)
        Database.ensureVirtualOriginAndMoves(in: decoded2)
        #expect(decoded2.originFenId == 2)
        #expect(decoded2.fenObjects2.count == 2)
    }

    // MARK: - DatabaseView 兜底：containsFenId 对 origin 总是返回 true

    /// 验证 setFilters 中的兜底前提：origin 在任何 view 中都可达
    /// 这是 setFilters 在 currentGame2[0] 不在 scope 时回退到 origin 的关键依据
    @Test func originAlwaysReachableAcrossViews() {
        let data = DatabaseData()
        let middleFen = "middlegame_puzzle_fen"
        let fen = FenObject(fen: middleFen, fenId: 1)
        // 不在任何开局/实战
        data.fenObjects2[1] = fen
        data.fenToId[middleFen] = 1
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let originId = db.originFenId!

        // 中局题局面在红方/黑方开局视图中均不可达
        let redView = DatabaseView.redOpening(database: db)
        #expect(redView.containsFenId(1) == false)
        // 但 origin 始终可达——setFilters 据此进行兜底
        #expect(redView.containsFenId(originId) == true)

        let blackView = DatabaseView.blackOpening(database: db)
        #expect(blackView.containsFenId(1) == false)
        #expect(blackView.containsFenId(originId) == true)
    }
}
