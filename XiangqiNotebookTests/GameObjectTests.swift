import Testing
import Foundation
@testable import XiangqiNotebook

struct GameObjectTests {

    // MARK: - Initialization Tests

    @Test func testGameObjectInitialization() {
        let id = UUID()
        let game = GameObject(id: id)

        #expect(game.id == id)
        #expect(game.name == nil)
        #expect(game.creationDate == nil)
        #expect(game.gameDate == nil)
        #expect(game.redPlayerName == "")
        #expect(game.blackPlayerName == "")
        #expect(game.iAmRed == false)
        #expect(game.iAmBlack == false)
        #expect(game.gameResult == .unknown)
        #expect(game.startingFenId == nil)
        #expect(game.moveIds.isEmpty)
        #expect(game.isFullyRecorded == false)
    }

    // MARK: - containsMoveId Tests

    @Test func testContainsMoveId_Found() {
        let game = GameObject(id: UUID())
        game.moveIds = [1, 2, 3]

        #expect(game.containsMoveId(1) == true)
        #expect(game.containsMoveId(2) == true)
        #expect(game.containsMoveId(3) == true)
    }

    @Test func testContainsMoveId_NotFound() {
        let game = GameObject(id: UUID())
        game.moveIds = [1, 2, 3]

        #expect(game.containsMoveId(4) == false)
        #expect(game.containsMoveId(0) == false)
    }

    @Test func testContainsMoveId_EmptyMoveIds() {
        let game = GameObject(id: UUID())
        #expect(game.containsMoveId(1) == false)
    }

    // MARK: - containsFenId Tests

    @Test func testContainsFenId_StartingFen() {
        let game = GameObject(id: UUID())
        game.startingFenId = 5

        let moveObjects: [Int: Move] = [:]
        #expect(game.containsFenId(5, moveObjects: moveObjects) == true)
    }

    @Test func testContainsFenId_FromMoveSource() {
        let game = GameObject(id: UUID())
        game.moveIds = [1]

        let move = Move(sourceFenId: 10, targetFenId: 20)
        let moveObjects: [Int: Move] = [1: move]

        #expect(game.containsFenId(10, moveObjects: moveObjects) == true)
    }

    @Test func testContainsFenId_FromMoveTarget() {
        let game = GameObject(id: UUID())
        game.moveIds = [1]

        let move = Move(sourceFenId: 10, targetFenId: 20)
        let moveObjects: [Int: Move] = [1: move]

        #expect(game.containsFenId(20, moveObjects: moveObjects) == true)
    }

    @Test func testContainsFenId_NotFound() {
        let game = GameObject(id: UUID())
        game.moveIds = [1]
        game.startingFenId = 5

        let move = Move(sourceFenId: 10, targetFenId: 20)
        let moveObjects: [Int: Move] = [1: move]

        #expect(game.containsFenId(99, moveObjects: moveObjects) == false)
    }

    // MARK: - appendMoveId Tests

    @Test func testAppendMoveId_UpdatesArray() {
        let game = GameObject(id: UUID())
        let move = Move(sourceFenId: 1, targetFenId: 2)

        game.appendMoveId(10, move: move)
        #expect(game.moveIds == [10])
        #expect(game.containsMoveId(10) == true)
    }

    @Test func testAppendMoveId_UpdatesFenIdSet() {
        let game = GameObject(id: UUID())
        let move = Move(sourceFenId: 1, targetFenId: 2)

        // First build the cache
        let moveObjects: [Int: Move] = [10: move]
        _ = game.containsFenId(1, moveObjects: moveObjects)  // 触发 fenIdSet 构建

        // 追加新 move
        let move2 = Move(sourceFenId: 3, targetFenId: 4)
        game.appendMoveId(11, move: move2)

        let moveObjects2: [Int: Move] = [10: move, 11: move2]
        #expect(game.containsFenId(3, moveObjects: moveObjects2) == true)
        #expect(game.containsFenId(4, moveObjects: moveObjects2) == true)
    }

    // MARK: - removeMoveId Tests

    @Test func testRemoveMoveId_UpdatesArray() {
        let game = GameObject(id: UUID())
        game.moveIds = [1, 2, 3]

        game.removeMoveId(2)
        #expect(game.moveIds == [1, 3])
    }

    @Test func testRemoveMoveId_UpdatesMoveIdSet() {
        let game = GameObject(id: UUID())
        game.moveIds = [1, 2, 3]

        // 触发 moveIdSet 构建
        _ = game.containsMoveId(1)

        game.removeMoveId(1)
        #expect(game.containsMoveId(1) == false)
        #expect(game.containsMoveId(2) == true)
    }

    @Test func testRemoveMoveId_InvalidatesFenIdSet() {
        let game = GameObject(id: UUID())
        game.moveIds = [1]

        let move = Move(sourceFenId: 10, targetFenId: 20)
        let moveObjects: [Int: Move] = [1: move]

        // 触发 fenIdSet 构建
        _ = game.containsFenId(10, moveObjects: moveObjects)

        // 移除 move 后 fenIdSet 应被重置
        game.removeMoveId(1)
        let newMoveObjects: [Int: Move] = [:]
        #expect(game.containsFenId(10, moveObjects: newMoveObjects) == false)
    }

    // MARK: - displayTitle Tests

    @Test func testDisplayTitle_WithName() {
        let game = GameObject(id: UUID())
        game.name = "我的棋局"
        #expect(game.displayTitle == "我的棋局")
    }

    @Test func testDisplayTitle_WithEmptyName_IAmRed_RedWin() {
        let game = GameObject(id: UUID())
        game.name = ""
        game.iAmRed = true
        game.blackPlayerName = "对手"
        game.gameResult = .redWin

        #expect(game.displayTitle == "我 胜 对手")
    }

    @Test func testDisplayTitle_WithEmptyName_IAmRed_BlackWin() {
        let game = GameObject(id: UUID())
        game.name = ""
        game.iAmRed = true
        game.blackPlayerName = "对手"
        game.gameResult = .blackWin

        #expect(game.displayTitle == "我 负 对手")
    }

    @Test func testDisplayTitle_WithEmptyName_IAmRed_Draw() {
        let game = GameObject(id: UUID())
        game.name = ""
        game.iAmRed = true
        game.blackPlayerName = "对手"
        game.gameResult = .draw

        #expect(game.displayTitle == "我 和 对手")
    }

    @Test func testDisplayTitle_WithEmptyName_IAmRed_NotFinished() {
        let game = GameObject(id: UUID())
        game.name = ""
        game.iAmRed = true
        game.blackPlayerName = "对手"
        game.gameResult = .notFinished

        #expect(game.displayTitle == "我 vs 对手")
    }

    @Test func testDisplayTitle_WithEmptyName_IAmBlack_RedWin() {
        let game = GameObject(id: UUID())
        game.name = ""
        game.iAmBlack = true
        game.redPlayerName = "对手"
        game.gameResult = .redWin

        // iAmBlack，红胜意味着我负
        #expect(game.displayTitle == "对手 胜 我")
    }

    @Test func testDisplayTitle_NoPlayerNames() {
        let game = GameObject(id: UUID())
        // 没有名字，没有指定玩家
        #expect(game.displayTitle == "红方 vs 黑方")
    }

    @Test func testDisplayTitle_WithPlayerNames_NoMe() {
        let game = GameObject(id: UUID())
        game.redPlayerName = "王天一"
        game.blackPlayerName = "许银川"
        #expect(game.displayTitle == "王天一 vs 许银川")
    }

    // MARK: - Codable Tests

    @Test func testGameObjectEncoding() throws {
        let id = UUID()
        let game = GameObject(id: id)
        game.name = "测试棋局"
        game.iAmRed = true
        game.gameResult = .redWin
        game.startingFenId = 1
        game.moveIds = [1, 2, 3]
        game.isFullyRecorded = true

        let encoder = JSONEncoder()
        let data = try encoder.encode(game)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GameObject.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.name == "测试棋局")
        #expect(decoded.iAmRed == true)
        #expect(decoded.gameResult == .redWin)
        #expect(decoded.startingFenId == 1)
        #expect(decoded.moveIds == [1, 2, 3])
        #expect(decoded.isFullyRecorded == true)
    }

    @Test func testGameObjectDecodingBackwardCompatibility() throws {
        // 旧格式 JSON（缺少部分字段）
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "redPlayerName": "王天一",
            "blackPlayerName": "许银川",
            "gameResult": "红胜",
            "moveIds": [1, 2]
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GameObject.self, from: data)

        #expect(decoded.redPlayerName == "王天一")
        #expect(decoded.gameResult == .redWin)
        #expect(decoded.moveIds == [1, 2])
        // 默认值验证
        #expect(decoded.iAmRed == false)
        #expect(decoded.iAmBlack == false)
        #expect(decoded.isFullyRecorded == false)
    }
}

// MARK: - GameResult Tests

struct GameResultTests {

    @Test func testGameResultRawValues() {
        #expect(GameResult.redWin.rawValue == "红胜")
        #expect(GameResult.blackWin.rawValue == "黑胜")
        #expect(GameResult.draw.rawValue == "和棋")
        #expect(GameResult.notFinished.rawValue == "未完")
        #expect(GameResult.unknown.rawValue == "不知")
    }

    @Test func testGameResultCaseIterable() {
        #expect(GameResult.allCases.count == 5)
        #expect(GameResult.allCases.contains(.redWin))
        #expect(GameResult.allCases.contains(.blackWin))
        #expect(GameResult.allCases.contains(.draw))
        #expect(GameResult.allCases.contains(.notFinished))
        #expect(GameResult.allCases.contains(.unknown))
    }

    @Test func testGameResultCodable() throws {
        let results: [GameResult] = [.redWin, .blackWin, .draw, .notFinished, .unknown]
        for result in results {
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(GameResult.self, from: data)
            #expect(decoded == result)
        }
    }
}

// MARK: - GameResultStatistics Tests

struct GameResultStatisticsTests {

    @Test func testDefaultInitialization() {
        let stats = GameResultStatistics()
        #expect(stats.redWin == 0)
        #expect(stats.blackWin == 0)
        #expect(stats.draw == 0)
        #expect(stats.notFinished == 0)
        #expect(stats.unknown == 0)
    }

    @Test func testEquality_Equal() {
        let a = GameResultStatistics()
        let b = GameResultStatistics()
        #expect(a == b)
    }

    @Test func testEquality_NotEqual() {
        let a = GameResultStatistics()
        let b = GameResultStatistics()
        a.redWin = 1
        #expect(a != b)
    }

    @Test func testEquality_AllFields() {
        let a = GameResultStatistics()
        let b = GameResultStatistics()
        a.redWin = 1
        a.blackWin = 2
        a.draw = 3
        a.notFinished = 4
        a.unknown = 5
        b.redWin = 1
        b.blackWin = 2
        b.draw = 3
        b.notFinished = 4
        b.unknown = 5
        #expect(a == b)
    }

    @Test func testCodable() throws {
        let stats = GameResultStatistics()
        stats.redWin = 10
        stats.blackWin = 5
        stats.draw = 2

        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(GameResultStatistics.self, from: data)

        #expect(decoded == stats)
        #expect(decoded.redWin == 10)
        #expect(decoded.blackWin == 5)
        #expect(decoded.draw == 2)
    }
}
