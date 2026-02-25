import Testing
import Foundation
@testable import XiangqiNotebook

/// 重新统计实战统计功能的测试
struct RecalculateGameStatisticsTests {

    // MARK: - Helper Methods

    /// 创建测试用 Database，包含基本的局面和着法
    private func createTestDatabase() -> Database {
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        // fenId 1: 起始局面
        let fen1 = FenObject(fen: "startFen - - 1 1", fenId: 1)
        database.databaseData.fenObjects2[1] = fen1
        database.databaseData.fenToId["startFen - - 1 1"] = 1

        // fenId 2: 后续局面
        let fen2 = FenObject(fen: "fen2 - - 1 1", fenId: 2)
        database.databaseData.fenObjects2[2] = fen2
        database.databaseData.fenToId["fen2 - - 1 1"] = 2

        // fenId 3: 另一个后续局面
        let fen3 = FenObject(fen: "fen3 - - 1 1", fenId: 3)
        database.databaseData.fenObjects2[3] = fen3
        database.databaseData.fenToId["fen3 - - 1 1"] = 3

        // move 1->2
        let move1to2 = Move(sourceFenId: 1, targetFenId: 2)
        fen1.addMoveIfNeeded(move: move1to2)
        database.databaseData.moveObjects[1] = move1to2
        database.databaseData.moveToId[[1, 2]] = 1

        // move 2->3
        let move2to3 = Move(sourceFenId: 2, targetFenId: 3)
        fen2.addMoveIfNeeded(move: move2to3)
        database.databaseData.moveObjects[2] = move2to3
        database.databaseData.moveToId[[2, 3]] = 2

        return database
    }

    /// 创建一个 GameObject 并添加到数据库
    private func addGame(to database: Database, gameResult: GameResult, iAmRed: Bool, iAmBlack: Bool, startingFenId: Int?, moveIds: [Int]) -> UUID {
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.gameResult = gameResult
        game.iAmRed = iAmRed
        game.iAmBlack = iAmBlack
        game.startingFenId = startingFenId
        game.moveIds = moveIds
        database.databaseData.gameObjects[gameId] = game
        return gameId
    }

    /// 创建测试用的 Session
    private func createSession(database: Database) -> Session {
        let sessionData = SessionData()
        sessionData.currentGame2 = [1]
        sessionData.currentGameStep = 0
        let databaseView = DatabaseView.full(database: database)
        return try! Session(sessionData: sessionData, databaseView: databaseView)
    }

    // MARK: - Tests

    @Test func testRecalculate_noGames_clearsStatistics() {
        let database = createTestDatabase()
        let session = createSession(database: database)

        // 预先设置一些虚假统计
        let fakeStats = GameResultStatistics()
        fakeStats.redWin = 5
        database.databaseData.myRealRedGameStatisticsByFenId[1] = fakeStats

        // 重新统计（没有棋局）
        session.recalculateGameStatistics(database: database)

        // 统计应该被清空
        #expect(database.databaseData.myRealRedGameStatisticsByFenId.isEmpty)
        #expect(database.databaseData.myRealBlackGameStatisticsByFenId.isEmpty)
    }

    @Test func testRecalculate_withRedGame_correctStatistics() {
        let database = createTestDatabase()
        let session = createSession(database: database)

        // 添加一个执红棋局：红胜，起始 fenId=1，move 1->2, 2->3
        _ = addGame(to: database, gameResult: .redWin, iAmRed: true, iAmBlack: false, startingFenId: 1, moveIds: [1, 2])

        session.recalculateGameStatistics(database: database)

        // fenId 1, 2, 3 都应该有红方统计
        for fenId in [1, 2, 3] {
            let stats = database.databaseData.myRealRedGameStatisticsByFenId[fenId]
            #expect(stats != nil, "fenId \(fenId) should have red statistics")
            #expect(stats?.redWin == 1)
            #expect(stats?.blackWin == 0)
            #expect(stats?.draw == 0)
        }
        // 黑方统计应该为空
        #expect(database.databaseData.myRealBlackGameStatisticsByFenId.isEmpty)
    }

    @Test func testRecalculate_withBlackGame_correctStatistics() {
        let database = createTestDatabase()
        let session = createSession(database: database)

        // 添加一个执黑棋局：黑胜
        _ = addGame(to: database, gameResult: .blackWin, iAmRed: false, iAmBlack: true, startingFenId: 1, moveIds: [1])

        session.recalculateGameStatistics(database: database)

        // fenId 1, 2 应该有黑方统计
        let stats1 = database.databaseData.myRealBlackGameStatisticsByFenId[1]
        #expect(stats1 != nil)
        #expect(stats1?.blackWin == 1)

        let stats2 = database.databaseData.myRealBlackGameStatisticsByFenId[2]
        #expect(stats2 != nil)
        #expect(stats2?.blackWin == 1)

        // 红方统计应该为空
        #expect(database.databaseData.myRealRedGameStatisticsByFenId.isEmpty)
    }

    @Test func testRecalculate_noChange_doesNotMarkDirty() {
        let database = createTestDatabase()
        let session = createSession(database: database)

        // 添加一个执红棋局
        _ = addGame(to: database, gameResult: .redWin, iAmRed: true, iAmBlack: false, startingFenId: 1, moveIds: [1, 2])

        // 先统计一次
        session.recalculateGameStatistics(database: database)

        // 记录当前版本号
        let versionAfterFirst = database.databaseData.dataVersion

        // 再统计一次（数据未变化）
        session.recalculateGameStatistics(database: database)

        // 版本号应该不变（因为 notifyDataChanged 不会被调用）
        #expect(database.databaseData.dataVersion == versionAfterFirst)
    }

    @Test func testRecalculate_correctsMismatch() {
        let database = createTestDatabase()
        let session = createSession(database: database)

        // 添加一个执红棋局：红胜
        _ = addGame(to: database, gameResult: .redWin, iAmRed: true, iAmBlack: false, startingFenId: 1, moveIds: [1, 2])

        // 手动设置错误的统计
        let wrongStats = GameResultStatistics()
        wrongStats.blackWin = 99
        database.databaseData.myRealRedGameStatisticsByFenId[1] = wrongStats

        session.recalculateGameStatistics(database: database)

        // 统计应该被修正
        let corrected = database.databaseData.myRealRedGameStatisticsByFenId[1]
        #expect(corrected != nil)
        #expect(corrected?.redWin == 1)
        #expect(corrected?.blackWin == 0)
    }

    @Test func testRecalculate_multipleGames_aggregatesCorrectly() {
        let database = createTestDatabase()
        let session = createSession(database: database)

        // 添加两个执红棋局，不同结果
        _ = addGame(to: database, gameResult: .redWin, iAmRed: true, iAmBlack: false, startingFenId: 1, moveIds: [1])
        _ = addGame(to: database, gameResult: .draw, iAmRed: true, iAmBlack: false, startingFenId: 1, moveIds: [1, 2])

        session.recalculateGameStatistics(database: database)

        // fenId 1 应该有 redWin=1, draw=1（两个棋局都涉及 fenId 1）
        let stats1 = database.databaseData.myRealRedGameStatisticsByFenId[1]
        #expect(stats1?.redWin == 1)
        #expect(stats1?.draw == 1)

        // fenId 2 也应该有两个棋局的统计（move 1->2 的目标）
        let stats2 = database.databaseData.myRealRedGameStatisticsByFenId[2]
        #expect(stats2?.redWin == 1)
        #expect(stats2?.draw == 1)

        // fenId 3 只有第二个棋局涉及（move 2->3）
        let stats3 = database.databaseData.myRealRedGameStatisticsByFenId[3]
        #expect(stats3?.redWin == 0 || stats3 == nil || stats3?.draw == 1)
        // 第二个棋局有 moveIds [1, 2]，对应 move 1->2 和 move 2->3
        // 所以 fenId 3 应该有 draw=1
        #expect(stats3?.draw == 1)
    }

    @Test func testRecalculate_ignoresNonMyGames() {
        let database = createTestDatabase()
        let session = createSession(database: database)

        // 添加一个非我的棋局
        _ = addGame(to: database, gameResult: .redWin, iAmRed: false, iAmBlack: false, startingFenId: 1, moveIds: [1])

        session.recalculateGameStatistics(database: database)

        // 统计应该为空
        #expect(database.databaseData.myRealRedGameStatisticsByFenId.isEmpty)
        #expect(database.databaseData.myRealBlackGameStatisticsByFenId.isEmpty)
    }

    @Test func testGameResultStatistics_equatable() {
        let a = GameResultStatistics()
        let b = GameResultStatistics()
        #expect(a == b)

        a.redWin = 1
        #expect(a != b)

        b.redWin = 1
        #expect(a == b)
    }
}
