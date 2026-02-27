import Testing
import Foundation
@testable import XiangqiNotebook

struct SessionManagerTests {

    // MARK: - 辅助方法

    /// 创建包含起始局面和一些着法的测试数据库
    private func createTestDatabase() -> Database {
        let data = DatabaseData()
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"

        // fenId 1: 起始局面
        let fen1 = FenObject(fen: startFen, fenId: 1)
        fen1.inRedOpening = true
        fen1.inBlackOpening = true
        data.fenObjects2[1] = fen1
        data.fenToId[startFen] = 1

        // fenId 2: 红方开局后局面
        let fen2 = FenObject(fen: "fen_after_red_move", fenId: 2)
        fen2.inRedOpening = true
        fen2.inBlackOpening = true
        data.fenObjects2[2] = fen2
        data.fenToId["fen_after_red_move"] = 2

        // fenId 3: 黑方应对后局面
        let fen3 = FenObject(fen: "fen_after_black_move", fenId: 3)
        fen3.inRedOpening = true
        fen3.inBlackOpening = true
        data.fenObjects2[3] = fen3
        data.fenToId["fen_after_black_move"] = 3

        // 着法: 1 → 2, 2 → 3
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        data.moveObjects[1] = move1
        data.moveToId[[1, 2]] = 1
        fen1.moves.append(move1)

        let move2 = Move(sourceFenId: 2, targetFenId: 3)
        data.moveObjects[2] = move2
        data.moveToId[[2, 3]] = 2
        fen2.moves.append(move2)

        return Database(testDatabaseData: data)
    }

    /// 创建 SessionManager 的便捷方法
    private func createSessionManager(database: Database) -> SessionManager {
        let sessionData = SessionData()
        let databaseView = DatabaseView.full(database: database)
        let startFenId = databaseView.ensureFenId(
            for: "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        )
        sessionData.currentGame2 = [startFenId]
        sessionData.currentGameStep = 0
        let session = try! Session(sessionData: sessionData, databaseView: databaseView)
        return SessionManager(mainSession: session, database: database)
    }

    // MARK: - Factory Creation Tests

    @Test func testCreate_FromSessionData_CreatesValidManager() {
        let database = createTestDatabase()
        let sessionData = SessionData()
        sessionData.currentGame2 = [1]
        sessionData.currentGameStep = 0

        let manager = SessionManager.create(from: sessionData, database: database)

        #expect(manager.currentSession.sessionData.currentGame2.first == 1)
        #expect(manager.isInFocusedPractice == false)
    }

    @Test func testCreate_FromDefaultSessionData_Succeeds() {
        let database = createTestDatabase()
        let sessionData = SessionData()

        let manager = SessionManager.create(from: sessionData, database: database)

        // 应该成功创建，即使使用默认值
        #expect(manager.currentSession.sessionData.currentGameStep >= 0)
    }

    @Test func testCreate_WithFilters_AppliesFilters() {
        let database = createTestDatabase()
        let sessionData = SessionData()
        sessionData.currentGame2 = [1]
        sessionData.currentGameStep = 0
        sessionData.filters = [Session.filterRedOpeningOnly]

        let manager = SessionManager.create(from: sessionData, database: database)

        #expect(manager.mainSession.sessionData.filters.contains(Session.filterRedOpeningOnly))
    }

    // MARK: - currentSession Tests

    @Test func testCurrentSession_ReturnsMainSessionByDefault() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        // currentSession 应该返回 mainSession
        #expect(manager.currentSession === manager.mainSession)
    }

    // MARK: - isInFocusedPractice Tests

    @Test func testIsInFocusedPractice_FalseByDefault() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        #expect(manager.isInFocusedPractice == false)
    }

    // MARK: - setFilters Tests

    @Test func testSetFilters_RedOpening_ChangesDatabaseView() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        manager.setFilters([Session.filterRedOpeningOnly])

        #expect(manager.mainSession.sessionData.filters == [Session.filterRedOpeningOnly])
        // 红方开局应设置为红方朝向
        #expect(manager.mainSession.sessionData.isBlackOrientation == false)
    }

    @Test func testSetFilters_BlackOpening_SetsBlackOrientation() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        manager.setFilters([Session.filterBlackOpeningOnly])

        #expect(manager.mainSession.sessionData.filters == [Session.filterBlackOpeningOnly])
        // 黑方开局应设置为黑方朝向
        #expect(manager.mainSession.sessionData.isBlackOrientation == true)
    }

    @Test func testSetFilters_EmptyFilters_FullView() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        // 先设为有过滤器
        manager.setFilters([Session.filterRedOpeningOnly])
        // 再切换回全局视图
        manager.setFilters([])

        #expect(manager.mainSession.sessionData.filters.isEmpty)
    }

    @Test func testSetFilters_PreservesCurrentGame() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        // 设置当前棋局为 [1, 2, 3]（全部在红方开局范围内）
        manager.mainSession.sessionData.currentGame2 = [1, 2, 3]
        manager.mainSession.sessionData.currentGameStep = 2

        // 切换到红方开局视图
        manager.setFilters([Session.filterRedOpeningOnly])

        // 因为 fenId 1, 2, 3 都标记了 inRedOpening，应该保留完整路径
        let game = manager.mainSession.sessionData.currentGame2
        #expect(game.contains(1))
        #expect(game.contains(2))
        #expect(game.contains(3))
    }

    // MARK: - loadGame Tests

    @Test func testLoadGame_SwitchesToSpecificGameView() {
        let database = createTestDatabase()

        // 添加一个棋局
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.name = "测试棋局"
        game.startingFenId = 1
        database.databaseData.gameObjects[gameId] = game

        let manager = createSessionManager(database: database)
        manager.loadGame(gameId)

        #expect(manager.mainSession.sessionData.filters.contains(Session.filterSpecificGame))
    }

    // MARK: - loadBook Tests

    @Test func testLoadBook_SwitchesToSpecificBookView() {
        let database = createTestDatabase()

        // 添加一个棋书
        let bookId = UUID()
        let book = BookObject(id: bookId, name: "测试棋书")
        database.databaseData.bookObjects[bookId] = book

        let manager = createSessionManager(database: database)
        manager.loadBook(bookId)

        #expect(manager.mainSession.sessionData.filters.contains(Session.filterSpecificBook))
    }

    // MARK: - loadBookmark Tests

    @Test func testLoadBookmark_SwitchesToFullView() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        // 先设为有过滤器
        manager.setFilters([Session.filterRedOpeningOnly])
        // loadBookmark 应切换到 Full 视图
        manager.loadBookmark([1, 2])

        #expect(manager.mainSession.sessionData.filters.isEmpty)
    }

    // MARK: - Focused Practice Tests

    @Test func testStartFocusedPractice_CreatesPracticeSession() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        // 设置当前棋局有多步
        manager.mainSession.sessionData.currentGame2 = [1, 2, 3]
        manager.mainSession.sessionData.currentGameStep = 2

        manager.startFocusedPractice()

        #expect(manager.practiceSession != nil)
        #expect(manager.isInFocusedPractice == true)
    }

    @Test func testStartFocusedPractice_CurrentSessionReturnsPractice() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        manager.mainSession.sessionData.currentGame2 = [1, 2, 3]
        manager.mainSession.sessionData.currentGameStep = 2

        manager.startFocusedPractice()

        // currentSession 应返回 practiceSession
        #expect(manager.currentSession === manager.practiceSession)
        #expect(manager.currentSession !== manager.mainSession)
    }

    @Test func testExitFocusedPractice_ClearsPracticeSession() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        manager.mainSession.sessionData.currentGame2 = [1, 2, 3]
        manager.mainSession.sessionData.currentGameStep = 2

        manager.startFocusedPractice()
        #expect(manager.isInFocusedPractice == true)

        manager.exitFocusedPractice()

        #expect(manager.practiceSession == nil)
        #expect(manager.isInFocusedPractice == false)
        #expect(manager.currentSession === manager.mainSession)
    }

    @Test func testExitFocusedPractice_WhenNotInPractice_NoOp() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        // 不在练习模式下调用 exit 应该是安全的
        manager.exitFocusedPractice()

        #expect(manager.isInFocusedPractice == false)
    }

    // MARK: - createDatabaseView Tests

    @Test func testCreateDatabaseView_EmptyFilters_ReturnsFull() {
        let database = createTestDatabase()
        let view = SessionManager.createDatabaseView(
            for: [],
            focusedPath: nil,
            specificGameId: nil,
            specificBookId: nil,
            database: database
        )

        // Full 视图应该包含所有 fenId
        #expect(view.containsFenId(1) == true)
        #expect(view.containsFenId(2) == true)
        #expect(view.containsFenId(3) == true)
    }

    @Test func testCreateDatabaseView_RedOpening() {
        let database = createTestDatabase()
        let view = SessionManager.createDatabaseView(
            for: [Session.filterRedOpeningOnly],
            focusedPath: nil,
            specificGameId: nil,
            specificBookId: nil,
            database: database
        )

        // 测试数据中标记了 isInRedOpening 的 fenId 应该可见
        #expect(view.containsFenId(1) == true)
    }

    // MARK: - mainSessionData Tests

    @Test func testMainSessionData_ReturnMainSessionSessionData() {
        let database = createTestDatabase()
        let manager = createSessionManager(database: database)

        let sessionData = manager.mainSessionData
        #expect(sessionData === manager.mainSession.sessionData)
    }
}
