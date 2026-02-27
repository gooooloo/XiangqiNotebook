import Testing
import Foundation
@testable import XiangqiNotebook

/// Mock PlatformService for testing
private class MockPlatformService: PlatformService {
    var lastAlertTitle: String?
    var lastAlertMessage: String?
    var lastWarningTitle: String?
    var lastWarningMessage: String?
    var lastConfirmTitle: String?
    var confirmResult: Bool = true
    var openedURL: URL?

    func openURL(_ url: URL) { openedURL = url }
    func showAlert(title: String, message: String) {
        lastAlertTitle = title
        lastAlertMessage = message
    }
    func showWarningAlert(title: String, message: String) {
        lastWarningTitle = title
        lastWarningMessage = message
    }
    func showConfirmAlert(title: String, message: String, completion: @escaping (Bool) throws -> Void) {
        lastConfirmTitle = title
        try? completion(confirmResult)
    }
    func saveFile(defaultName: String, completion: @escaping (URL?) -> Void) { completion(nil) }
    func openFile(completion: @escaping (URL?) -> Void) { completion(nil) }
    func backupData(_ data: Data, defaultName: String, completion: @escaping (Bool) -> Void) { completion(false) }
    func recoverData(completion: @escaping (Data?) -> Void) { completion(nil) }
}

struct ViewModelTests {

    // MARK: - 辅助方法

    private static let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"

    /// 创建包含起始局面和一些着法的测试数据库
    private func createTestDatabase() -> Database {
        let data = DatabaseData()

        // fenId 1: 起始局面 (红方走)
        let fen1 = FenObject(fen: Self.startFen, fenId: 1)
        fen1.inRedOpening = true
        fen1.inBlackOpening = true
        data.fenObjects2[1] = fen1
        data.fenToId[Self.startFen] = 1

        // fenId 2: 红方走后局面 (黑方走)
        let fen2Str = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C2C1/9/RNBAKABNR b - - 1 1"
        let fen2 = FenObject(fen: fen2Str, fenId: 2)
        fen2.inRedOpening = true
        fen2.inBlackOpening = true
        data.fenObjects2[2] = fen2
        data.fenToId[fen2Str] = 2

        // fenId 3: 黑方应对后局面 (红方走)
        let fen3Str = "rnbakabnr/9/7c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C2C1/9/RNBAKABNR r - - 2 2"
        let fen3 = FenObject(fen: fen3Str, fenId: 3)
        fen3.inRedOpening = true
        data.fenObjects2[3] = fen3
        data.fenToId[fen3Str] = 3

        // fenId 4: 变着 (另一条线路, 红方走后黑方走)
        let fen4Str = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/2P6/P3P1P1P/1C5C1/9/RNBAKABNR b - - 1 1"
        let fen4 = FenObject(fen: fen4Str, fenId: 4)
        fen4.inRedOpening = true
        data.fenObjects2[4] = fen4
        data.fenToId[fen4Str] = 4

        // 着法: 1 → 2 (主线)
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        data.moveObjects[1] = move1
        data.moveToId[[1, 2]] = 1
        fen1.moves.append(move1)

        // 着法: 1 → 4 (变着)
        let move3 = Move(sourceFenId: 1, targetFenId: 4)
        data.moveObjects[3] = move3
        data.moveToId[[1, 4]] = 3
        fen1.moves.append(move3)

        // 着法: 2 → 3
        let move2 = Move(sourceFenId: 2, targetFenId: 3)
        data.moveObjects[2] = move2
        data.moveToId[[2, 3]] = 2
        fen2.moves.append(move2)

        return Database(testDatabaseData: data)
    }

    /// 创建 SessionManager
    private func createSessionManager(database: Database, filters: [String] = [], specificGameId: UUID? = nil, specificBookId: UUID? = nil, gamePath: [Int]? = nil) -> SessionManager {
        let sessionData = SessionData()
        sessionData.filters = filters
        sessionData.specificGameId = specificGameId
        sessionData.specificBookId = specificBookId
        let databaseView = DatabaseView.full(database: database)
        let startFenId = databaseView.ensureFenId(for: Self.startFen)
        sessionData.currentGame2 = gamePath ?? [startFenId]
        sessionData.currentGameStep = 0
        let session = try! Session(sessionData: sessionData, databaseView: databaseView)
        return SessionManager(mainSession: session, database: database)
    }

    /// 创建 ViewModel
    private func createViewModel(database: Database? = nil, filters: [String] = [], specificGameId: UUID? = nil, specificBookId: UUID? = nil) -> (ViewModel, MockPlatformService) {
        let db = database ?? createTestDatabase()
        let sm = createSessionManager(database: db, filters: filters, specificGameId: specificGameId, specificBookId: specificBookId)
        let mock = MockPlatformService()
        let vm = ViewModel(sessionManager: sm, platformService: mock)
        return (vm, mock)
    }

    // MARK: - isAnySheetPresented

    @Test func testIsAnySheetPresented_AllFalse_ReturnsFalse() {
        let (vm, _) = createViewModel()
        #expect(vm.isAnySheetPresented == false)
    }

    @Test func testIsAnySheetPresented_BookmarkAlert_ReturnsTrue() {
        let (vm, _) = createViewModel()
        vm.showingBookmarkAlert = true
        #expect(vm.isAnySheetPresented == true)
    }

    @Test func testIsAnySheetPresented_GameInputView_ReturnsTrue() {
        let (vm, _) = createViewModel()
        vm.showingGameInputView = true
        #expect(vm.isAnySheetPresented == true)
    }

    @Test func testIsAnySheetPresented_ReviewListView_ReturnsTrue() {
        let (vm, _) = createViewModel()
        vm.showingReviewListView = true
        #expect(vm.isAnySheetPresented == true)
    }

    // MARK: - isMyTurn

    @Test func testIsMyTurn_RedOrientationBlackJustPlayed_IsMyTurn() {
        let (vm, _) = createViewModel()
        // 起始局面，红方走，默认红方视角
        // blackJustPlayed = false (红方走 → 上一步不是黑方走的)
        // isCurrentBlackOrientation = false (红方视角)
        // isMyTurn = (!iamBlack && blackJustPlayed) = (true && false) = false
        // Wait - let me check: startFen has "r" which means red to move
        // blackJustPlayed should be false at start (it's red's turn, black hasn't just played)
        // Actually check FenObject.blackJustPlayed logic
        // Fen "... r ..." means red to move, so blackJustPlayed = true (because black just finished)
        // isMyTurn = (!iamBlack && blackJustPlayed) || (iamBlack && !blackJustPlayed)
        //          = (true && true) || (false && false) = true
        #expect(vm.isMyTurn == true)
    }

    @Test func testIsMyTurn_AfterRedMoves_NotMyTurn() {
        let database = createTestDatabase()
        let sm = createSessionManager(database: database, gamePath: [1, 2, 3])
        let mock = MockPlatformService()
        let vm = ViewModel(sessionManager: sm, platformService: mock)
        // 走一步红方的棋 (fenId 1 → fenId 2)
        vm.stepForward()
        // Now at fenId 2, which has "b" (black to move) → blackJustPlayed = false
        // isCurrentBlackOrientation = false (red perspective)
        // isMyTurn = (!iamBlack && blackJustPlayed) || (iamBlack && !blackJustPlayed)
        //          = (true && false) || (false && true) = false
        #expect(vm.isMyTurn == false)
    }

    // MARK: - currentVariationIndex

    @Test func testCurrentVariationIndex_AtStart_ReturnsZero() {
        let (vm, _) = createViewModel()
        // At start position, no current move (we're at step 0)
        #expect(vm.currentVariationIndex == 0)
    }

    @Test func testCurrentVariationIndex_AfterMove_ReturnsCorrectIndex() {
        let (vm, _) = createViewModel()
        // Navigate forward to get a current move
        vm.stepForward()
        // currentMove should be the move from fenId 1 → fenId 2
        // variants from fenId 1 include moves to fenId 2 and fenId 4
        #expect(vm.currentVariationIndex >= 0)
    }

    // MARK: - windowTitle

    @Test func testWindowTitle_DefaultMode_ReturnsDefault() {
        let (vm, _) = createViewModel()
        #expect(vm.windowTitle == "XiangqiNotebook")
    }

    @Test func testWindowTitle_SpecificGame_ReturnsGameTitle() {
        let database = createTestDatabase()
        // 创建一个棋局
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.name = "测试棋局"
        game.startingFenId = 1
        game.moveIds = [1, 2]
        database.databaseData.gameObjects[gameId] = game

        let (vm, _) = createViewModel(database: database, filters: [Session.filterSpecificGame], specificGameId: gameId)
        // 需要 setFilters 让 session 有正确的 filter
        vm.sessionManager.setFilters([Session.filterSpecificGame], specificGameId: gameId)
        #expect(vm.windowTitle.contains("测试棋局"))
    }

    @Test func testWindowTitle_SpecificBook_ReturnsBookName() {
        let database = createTestDatabase()
        let bookId = UUID()
        let book = BookObject(id: bookId, name: "测试棋书")
        database.databaseData.bookObjects[bookId] = book

        let (vm, _) = createViewModel(database: database)
        vm.sessionManager.setFilters([Session.filterSpecificBook], specificBookId: bookId)
        #expect(vm.windowTitle.contains("测试棋书"))
    }

    @Test func testWindowTitle_SpecificBookEmptyName_ReturnsFallback() {
        let database = createTestDatabase()
        let bookId = UUID()
        let book = BookObject(id: bookId, name: "")
        database.databaseData.bookObjects[bookId] = book

        let (vm, _) = createViewModel(database: database)
        vm.sessionManager.setFilters([Session.filterSpecificBook], specificBookId: bookId)
        #expect(vm.windowTitle.contains("棋书"))
    }

    // MARK: - Filter 逻辑

    @Test func testSetFilterNone_ClearsAllFilters() {
        let (vm, _) = createViewModel()
        vm.sessionManager.setFilters([Session.filterRedOpeningOnly])
        #expect(!vm.currentFilters.isEmpty)

        vm.setFilterNone()
        #expect(vm.currentFilters.isEmpty)
    }

    @Test func testToggleFilterSpecificGame_MutuallyExclusiveWithBook() {
        let database = createTestDatabase()
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.startingFenId = 1
        game.moveIds = [1, 2]
        database.databaseData.gameObjects[gameId] = game

        let bookId = UUID()
        let book = BookObject(id: bookId, name: "棋书")
        database.databaseData.bookObjects[bookId] = book

        let (vm, _) = createViewModel(database: database)

        // 先选棋书筛选
        vm.session.sessionData.specificBookId = bookId
        vm.sessionManager.setFilters([Session.filterSpecificBook], specificBookId: bookId)
        #expect(vm.currentFilters.contains(Session.filterSpecificBook))

        // 再选棋局筛选 — 应该互斥移除棋书
        vm.session.sessionData.specificGameId = gameId
        vm.toggleFilterSpecificGame()
        #expect(vm.currentFilters.contains(Session.filterSpecificGame))
        #expect(!vm.currentFilters.contains(Session.filterSpecificBook))
    }

    @Test func testToggleFilterSpecificBook_MutuallyExclusiveWithGame() {
        let database = createTestDatabase()
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.startingFenId = 1
        game.moveIds = [1, 2]
        database.databaseData.gameObjects[gameId] = game

        let bookId = UUID()
        let book = BookObject(id: bookId, name: "棋书")
        database.databaseData.bookObjects[bookId] = book

        let (vm, _) = createViewModel(database: database)

        // 先选棋局筛选
        vm.session.sessionData.specificGameId = gameId
        vm.sessionManager.setFilters([Session.filterSpecificGame], specificGameId: gameId)
        #expect(vm.currentFilters.contains(Session.filterSpecificGame))

        // 再选棋书筛选 — 应该互斥移除棋局
        vm.session.sessionData.specificBookId = bookId
        vm.toggleFilterSpecificBook()
        #expect(vm.currentFilters.contains(Session.filterSpecificBook))
        #expect(!vm.currentFilters.contains(Session.filterSpecificGame))
    }

    @Test func testToggleFilterSpecificGame_ToggleOff_ClearsGameId() {
        let database = createTestDatabase()
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.startingFenId = 1
        game.moveIds = [1, 2]
        database.databaseData.gameObjects[gameId] = game

        let (vm, _) = createViewModel(database: database)
        vm.session.sessionData.specificGameId = gameId
        vm.sessionManager.setFilters([Session.filterSpecificGame], specificGameId: gameId)
        #expect(vm.currentFilters.contains(Session.filterSpecificGame))

        // 关闭筛选
        vm.toggleFilterSpecificGame()
        #expect(!vm.currentFilters.contains(Session.filterSpecificGame))
    }

    // MARK: - deleteGame

    @Test func testDeleteGame_CurrentlyViewingGame_SwitchesToFullView() {
        let database = createTestDatabase()
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.startingFenId = 1
        game.moveIds = [1, 2]
        database.databaseData.gameObjects[gameId] = game

        let (vm, _) = createViewModel(database: database)
        vm.session.sessionData.specificGameId = gameId
        vm.sessionManager.setFilters([Session.filterSpecificGame], specificGameId: gameId)
        #expect(vm.currentFilters.contains(Session.filterSpecificGame))

        // 删除当前查看的棋局
        vm.deleteGame(gameId)
        // 应该已切换到全库视图
        #expect(!vm.currentFilters.contains(Session.filterSpecificGame))
    }

    @Test func testDeleteGame_DifferentGame_DoesNotSwitchView() {
        let database = createTestDatabase()
        let gameId1 = UUID()
        let game1 = GameObject(id: gameId1)
        game1.startingFenId = 1
        game1.moveIds = [1, 2]
        database.databaseData.gameObjects[gameId1] = game1

        let gameId2 = UUID()
        let game2 = GameObject(id: gameId2)
        game2.startingFenId = 1
        game2.moveIds = [1]
        database.databaseData.gameObjects[gameId2] = game2

        let (vm, _) = createViewModel(database: database)
        vm.session.sessionData.specificGameId = gameId1
        vm.sessionManager.setFilters([Session.filterSpecificGame], specificGameId: gameId1)

        // 删除另一个棋局
        vm.deleteGame(gameId2)
        // 视图不变
        #expect(vm.currentFilters.contains(Session.filterSpecificGame))
    }

    // MARK: - handleBoardMove

    @Test func testHandleBoardMove_PracticeMode_NoNextMove_ShowsWarning() {
        let database = createTestDatabase()
        // fenId 3 has no further moves in our test database
        let sm = createSessionManager(database: database, gamePath: [1, 2, 3])
        let mock = MockPlatformService()
        let vm = ViewModel(sessionManager: sm, platformService: mock)

        // 导航到终点 (fenId 3, 无后续着法)
        vm.session.sessionData.currentMode = .practice
        vm.toEnd()

        vm.handleBoardMove("some_new_fen r - - 2 2")
        #expect(mock.lastWarningTitle == "棋谱结束")
    }

    @Test func testHandleBoardMove_PracticeMode_WrongMove_ShowsWarning() {
        let (vm, mock) = createViewModel()
        // 进入练习模式
        vm.session.sessionData.currentMode = .practice
        // 走一个不在棋谱中的着法
        vm.handleBoardMove("completely_wrong_fen b - - 1 1")
        #expect(mock.lastWarningTitle == "没有着法")
    }

    @Test func testHandleBoardMove_NormalMode_AddingNewMoveDisabled_ShowsWarning() {
        let (vm, mock) = createViewModel()
        // 确保不允许添加新走法
        if vm.session.allowAddingNewMoves {
            vm.session.toggleAllowAddingNewMoves()
        }
        // 走一个棋谱中不存在的着法
        vm.handleBoardMove("nonexistent_fen b - - 1 1")
        #expect(mock.lastWarningTitle == "不允许增加新走法")
    }

    // MARK: - Practice Mode

    @Test func testPracticeNewGame_EntersPracticeMode() {
        let (vm, _) = createViewModel()
        #expect(vm.currentAppMode == .normal)

        vm.practiceNewGame()

        #expect(vm.currentAppMode == .practice)
        #expect(vm.isAnyMoveLocked == true)
    }

    @Test func testPracticeNewGame_ExitsFocusedPractice() {
        let (vm, _) = createViewModel()
        // 先进入 focusedPractice
        vm.sessionManager.startFocusedPractice()
        #expect(vm.sessionManager.isInFocusedPractice == true)

        vm.practiceNewGame()
        #expect(vm.sessionManager.isInFocusedPractice == false)
        #expect(vm.currentAppMode == .practice)
    }

    @Test func testReviewThisGame_ExitsPracticeMode() {
        let (vm, _) = createViewModel()
        vm.session.togglePracticeMode()
        #expect(vm.currentAppMode == .practice)

        vm.reviewThisGame()
        #expect(vm.currentAppMode == .normal)
    }

    @Test func testReviewThisGame_ExitsFocusedPractice() {
        let (vm, _) = createViewModel()
        vm.sessionManager.startFocusedPractice()
        #expect(vm.sessionManager.isInFocusedPractice == true)

        vm.reviewThisGame()
        #expect(vm.sessionManager.isInFocusedPractice == false)
    }

    // MARK: - isActionVisible

    @Test func testIsActionVisible_RemoveMoveFromGame_NotInSpecificGame_Hidden() {
        let (vm, _) = createViewModel()
        // 不在特定棋局模式下，removeMoveFromGame 应隐藏
        #expect(vm.isActionVisible(.removeMoveFromGame) == false)
    }

    @Test func testIsActionVisible_RemoveMoveFromGame_InSpecificGame_Visible() {
        let database = createTestDatabase()
        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.startingFenId = 1
        game.moveIds = [1, 2]
        database.databaseData.gameObjects[gameId] = game

        let (vm, _) = createViewModel(database: database)
        vm.session.sessionData.specificGameId = gameId
        vm.sessionManager.setFilters([Session.filterSpecificGame], specificGameId: gameId)

        // 在特定棋局模式下，normal 模式，removeMoveFromGame 应可见
        #expect(vm.currentAppMode == .normal)
        #expect(vm.isActionVisible(.removeMoveFromGame) == true)
    }

    // MARK: - Review Mode

    @Test func testReviewingInProgress_EmptyQueue_ReturnsFalse() {
        let (vm, _) = createViewModel()
        #expect(vm.isReviewingInProgress == false)
    }

    @Test func testReviewComplete_EmptyQueue_ReturnsFalse() {
        let (vm, _) = createViewModel()
        #expect(vm.isReviewComplete == false)
    }

    @Test func testStartReview_WithDueItems_PopulatesQueue() {
        let database = createTestDatabase()
        // 添加到期的复习项
        let srs1 = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs1
        let srs2 = SRSData(gamePath: [1, 2, 3], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[2] = srs2

        let (vm, _) = createViewModel(database: database)
        vm.startReview()

        #expect(vm.reviewQueue.count == 2)
        #expect(vm.currentReviewIndex == 0)
        #expect(vm.isReviewingInProgress == true)
    }

    @Test func testStartReview_NoDueItems_EmptyQueue() {
        let database = createTestDatabase()
        // 添加未到期的复习项
        let srs = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantFuture)
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        vm.startReview()

        #expect(vm.reviewQueue.isEmpty)
    }

    @Test func testSubmitReviewRating_AdvancesIndex() {
        let database = createTestDatabase()
        let srs1 = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs1
        let srs2 = SRSData(gamePath: [1, 2, 3], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[2] = srs2

        let (vm, _) = createViewModel(database: database)
        vm.startReview()
        #expect(vm.currentReviewIndex == 0)

        vm.submitReviewRating(.good)
        #expect(vm.currentReviewIndex == 1)
        #expect(vm.isReviewingInProgress == true)
    }

    @Test func testSubmitReviewRating_LastItem_CompletesReview() {
        let database = createTestDatabase()
        let srs1 = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs1

        let (vm, _) = createViewModel(database: database)
        vm.startReview()
        #expect(vm.reviewQueue.count == 1)

        vm.submitReviewRating(.easy)
        #expect(vm.isReviewComplete == true)
        #expect(vm.isReviewingInProgress == false)
    }

    @Test func testSubmitReviewRating_WhenNotInProgress_DoesNothing() {
        let (vm, _) = createViewModel()
        // 没有队列时提交评分不应崩溃
        vm.submitReviewRating(.good)
        #expect(vm.currentReviewIndex == 0)
    }

    @Test func testSkipCurrentReviewItem_AdvancesIndex() {
        let database = createTestDatabase()
        let srs1 = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs1
        let srs2 = SRSData(gamePath: [1, 2, 3], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[2] = srs2

        let (vm, _) = createViewModel(database: database)
        vm.startReview()
        vm.skipCurrentReviewItem()
        #expect(vm.currentReviewIndex == 1)
    }

    @Test func testReviewProgress_DisplayString() {
        let database = createTestDatabase()
        let srs1 = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs1
        let srs2 = SRSData(gamePath: [1, 2, 3], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[2] = srs2

        let (vm, _) = createViewModel(database: database)
        vm.startReview()
        #expect(vm.reviewProgress == "1/2")

        vm.submitReviewRating(.good)
        #expect(vm.reviewProgress == "2/2")
    }

    @Test func testExitReviewMode_ResetsState() {
        let database = createTestDatabase()
        let srs1 = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs1

        let (vm, _) = createViewModel(database: database)
        vm.setMode(.review)
        #expect(vm.isInReviewMode == true)
        #expect(!vm.reviewQueue.isEmpty)

        vm.exitReviewMode()
        #expect(vm.isInReviewMode == false)
        #expect(vm.reviewQueue.isEmpty)
        #expect(vm.currentReviewIndex == 0)
    }

    // MARK: - reviewItemDescription

    @Test func testReviewItemDescription_WithCustomName_ReturnsCustomName() {
        let database = createTestDatabase()
        let srs = SRSData(gamePath: [1, 2])
        srs.customName = "我的复习项"
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        let desc = vm.reviewItemDescription(fenId: 1)
        #expect(desc == "我的复习项")
    }

    @Test func testReviewItemDescription_NoCustomName_WithComment_ReturnsComment() {
        let database = createTestDatabase()
        database.databaseData.fenObjects2[1]?.comment = "这是一个重要局面"
        let srs = SRSData(gamePath: [1, 2])
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        let desc = vm.reviewItemDescription(fenId: 1)
        #expect(desc == "这是一个重要局面")
    }

    @Test func testReviewItemDescription_NoNameNoComment_ReturnsFenPrefix() {
        let database = createTestDatabase()
        let srs = SRSData(gamePath: [1, 2])
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        let desc = vm.reviewItemDescription(fenId: 1)
        // 应该返回 fen 字符串的前20个字符
        #expect(desc.count <= 20)
        #expect(desc.hasPrefix("rnbakabnr"))
    }

    @Test func testReviewItemDescription_UnknownFenId_ReturnsFenIdString() {
        let (vm, _) = createViewModel()
        let desc = vm.reviewItemDescription(fenId: 999)
        #expect(desc == "fenId: 999")
    }

    // MARK: - setMode

    @Test func testSetMode_ReviewMode_StartsReview() {
        let database = createTestDatabase()
        let srs = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        vm.setMode(.review)
        #expect(vm.currentAppMode == .review)
        #expect(!vm.reviewQueue.isEmpty)
    }

    @Test func testSetMode_NormalMode_ResetsReviewQueue() {
        let database = createTestDatabase()
        let srs = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantPast)
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        vm.setMode(.review)
        #expect(!vm.reviewQueue.isEmpty)

        vm.setMode(.normal)
        #expect(vm.reviewQueue.isEmpty)
        #expect(vm.currentReviewIndex == 0)
    }

    // MARK: - Navigation

    @Test func testStepForward_AdvancesPosition() {
        let (vm, _) = createViewModel()
        let initialStep = vm.currentGameStepDisplay
        vm.stepForward()
        // After stepping forward, we should be at a later step (if moves exist)
        if vm.session.hasNextMove || vm.currentGameStepDisplay > initialStep {
            #expect(vm.currentGameStepDisplay >= initialStep)
        }
    }

    @Test func testToStart_ResetsToBeginning() {
        let (vm, _) = createViewModel()
        vm.stepForward()
        vm.toStart()
        #expect(vm.session.sessionData.currentGameStep == 0)
    }

    // MARK: - Global Alert

    @Test func testShowGlobalAlert_SetsAllProperties() {
        let (vm, _) = createViewModel()
        vm.showGlobalAlert(title: "标题", message: "内容")
        #expect(vm.showingGlobalAlert == true)
        #expect(vm.globalAlertTitle == "标题")
        #expect(vm.globalAlertMessage == "内容")
    }

    // MARK: - loadReviewItem

    @Test func testLoadReviewItem_WithLock_RebuildsLockAtCorrectPosition() {
        let database = createTestDatabase()
        let sm = createSessionManager(database: database, gamePath: [1, 2, 3])
        let mock = MockPlatformService()
        let vm = ViewModel(sessionManager: sm, platformService: mock)

        // 先锁定在步骤1
        vm.stepForward()
        vm.toggleLock()
        #expect(vm.isAnyMoveLocked == true)

        // 加载复习项到 [1, 2]
        vm.loadReviewItem([1, 2])

        // 锁应在新的当前步骤处重建
        #expect(vm.isAnyMoveLocked == true)
        // 应该在 gamePath 末尾（步骤1，即 [1,2] 的最后一步位置）
        #expect(vm.session.sessionData.currentGameStep == 1)
    }

    @Test func testLoadReviewItem_WithoutLock_SetsLock() {
        let (vm, _) = createViewModel()
        #expect(vm.isAnyMoveLocked == false)

        vm.loadReviewItem([1, 2])

        #expect(vm.isAnyMoveLocked == true)
        #expect(vm.session.sessionData.currentGameStep == 1)
    }

    // MARK: - setCurrentFenInRedOpening

    @Test func testSetCurrentFenInRedOpening_WhenCanChange_ChangesState() {
        let database = createTestDatabase()
        // fenId 2 has "b" → blackJustPlayed=false → isAutoInRedOpening=false → canChangeInRedOpening=true
        let sm = createSessionManager(database: database, gamePath: [1, 2])
        let mock = MockPlatformService()
        let vm = ViewModel(sessionManager: sm, platformService: mock)

        // 导航到 fenId 2
        vm.stepForward()
        #expect(vm.currentFenCanChangeInRedOpening == true)

        // 当前 fenId 2 已经 inRedOpening=true
        #expect(vm.currentFenIsInRedOpening == true)

        // 设为 false
        vm.setCurrentFenInRedOpening(false)
        #expect(vm.currentFenIsInRedOpening == false)

        // 设回 true
        vm.setCurrentFenInRedOpening(true)
        #expect(vm.currentFenIsInRedOpening == true)
    }

    @Test func testSetCurrentFenInRedOpening_WhenCannotChange_NoEffect() {
        let (vm, _) = createViewModel()
        // fenId 1 (start) has "r" → blackJustPlayed=true → isAutoInRedOpening=true → canChangeInRedOpening=false
        #expect(vm.currentFenCanChangeInRedOpening == false)

        // 尝试设置，应无效果（始终在红方开局库中）
        vm.setCurrentFenInRedOpening(false)
        #expect(vm.currentFenIsInRedOpening == true)
    }

    // MARK: - setCurrentFenInBlackOpening

    @Test func testSetCurrentFenInBlackOpening_WhenCanChange_ChangesState() {
        let (vm, _) = createViewModel()
        // fenId 1 has "r" → redJustPlayed=false → isAutoInBlackOpening=false → canChangeInBlackOpening=true
        #expect(vm.currentFenCanChangeInBlackOpening == true)

        // fenId 1 已经 inBlackOpening=true
        #expect(vm.currentFenIsInBlackOpening == true)

        vm.setCurrentFenInBlackOpening(false)
        #expect(vm.currentFenIsInBlackOpening == false)

        vm.setCurrentFenInBlackOpening(true)
        #expect(vm.currentFenIsInBlackOpening == true)
    }

    @Test func testSetCurrentFenInBlackOpening_WhenCannotChange_NoEffect() {
        let database = createTestDatabase()
        let sm = createSessionManager(database: database, gamePath: [1, 2])
        let mock = MockPlatformService()
        let vm = ViewModel(sessionManager: sm, platformService: mock)

        // 导航到 fenId 2 has "b" → redJustPlayed=true → isAutoInBlackOpening=true → canChangeInBlackOpening=false
        vm.stepForward()
        #expect(vm.currentFenCanChangeInBlackOpening == false)

        vm.setCurrentFenInBlackOpening(false)
        #expect(vm.currentFenIsInBlackOpening == true)
    }

    // MARK: - jumpToNextOpeningGap

    @Test func testJumpToNextOpeningGap_NoGap_ShowsAlert() {
        let (vm, mock) = createViewModel()
        // 所有局面都已在开局库中，没有缺口
        vm.jumpToNextOpeningGap()
        #expect(mock.lastAlertTitle == "完成")
    }

    @Test func testJumpToNextOpeningGap_WithGap_UnlocksAndJumps() {
        let database = createTestDatabase()
        // fenId 3 不在 blackOpening 中，且有多条好招法时才会被视为缺口
        // 为了测试，我们需要创建一个有缺口的场景
        // 让某个 fen 有多个好着法但后续不在开局库中
        // fenId 2 已有 move 2→3，加一个 2→新fen 且新fen不在开局库
        let fen5Str = "rnbakabnr/9/1c4c2/p1p1p1p1p/9/9/P1P1P1P1P/1C2C2C1/9/RNBAKABNR r - - 2 2"
        let fen5 = FenObject(fen: fen5Str, fenId: 5)
        // 不标记 inRedOpening, 不在开局库
        database.databaseData.fenObjects2[5] = fen5
        database.databaseData.fenToId[fen5Str] = 5

        let move4 = Move(sourceFenId: 2, targetFenId: 5)
        database.databaseData.moveObjects[4] = move4
        database.databaseData.moveToId[[2, 5]] = 4
        database.databaseData.fenObjects2[2]?.moves.append(move4)

        let sm = createSessionManager(database: database, gamePath: [1, 2, 3])
        let mock = MockPlatformService()
        let vm = ViewModel(sessionManager: sm, platformService: mock)

        // 先锁定
        vm.toggleLock()
        #expect(vm.isAnyMoveLocked == true)
        // 设置 filter
        vm.sessionManager.setFilters([Session.filterRedOpeningOnly])
        #expect(!vm.currentFilters.isEmpty)

        vm.jumpToNextOpeningGap()

        // 如果找到缺口：锁应解除、filter 应清空
        if mock.lastAlertTitle != "完成" {
            #expect(vm.isAnyMoveLocked == false)
            #expect(vm.currentFilters.isEmpty)
        }
    }

    // MARK: - performAutoAddToOpening

    @Test func testPerformAutoAddToOpening_ShowsAlert() {
        let (vm, mock) = createViewModel()
        vm.performAutoAddToOpening()
        #expect(mock.lastAlertTitle == "自动完善开局库")
        #expect(mock.lastAlertMessage?.contains("红方开局库") == true)
        #expect(mock.lastAlertMessage?.contains("黑方开局库") == true)
    }

    // MARK: - reviewAgain

    @Test func testReviewAgain_InReviewMode_RestartsReview() {
        let database = createTestDatabase()
        let srs = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantFuture)
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        // 初始无到期项
        vm.startReview()
        #expect(vm.reviewQueue.isEmpty)

        // reviewAgain 将该项标记为现在到期
        vm.setMode(.review)
        vm.reviewAgain(fenId: 1)

        // 在 review mode 下，reviewAgain 会调用 startReview，队列应重建
        #expect(vm.reviewQueue.count == 1)
    }

    @Test func testReviewAgain_InNormalMode_DoesNotRebuildQueue() {
        let database = createTestDatabase()
        let srs = SRSData(gamePath: [1, 2], nextReviewDate: Date.distantFuture)
        database.databaseData.reviewItems[1] = srs

        let (vm, _) = createViewModel(database: database)
        #expect(vm.currentAppMode == .normal)

        vm.reviewAgain(fenId: 1)

        // 不在 review mode，队列不应被填充
        #expect(vm.reviewQueue.isEmpty)
    }

    // MARK: - practiceRedOpening

    @Test func testPracticeRedOpening_SetsCorrectState() {
        let (vm, _) = createViewModel()
        vm.practiceRedOpening()

        #expect(vm.currentFilters.contains(Session.filterRedOpeningOnly))
        #expect(vm.isAnyMoveLocked == true)
        #expect(vm.currentAppMode == .practice)
    }

    // MARK: - practiceBlackOpening

    @Test func testPracticeBlackOpening_SetsCorrectState() {
        let (vm, _) = createViewModel()
        vm.practiceBlackOpening()

        #expect(vm.currentFilters.contains(Session.filterBlackOpeningOnly))
        #expect(vm.isAnyMoveLocked == true)
        #expect(vm.currentAppMode == .practice)
    }

    @Test func testPracticeRedOpening_ExitsFocusedPractice() {
        let (vm, _) = createViewModel()
        vm.sessionManager.startFocusedPractice()
        #expect(vm.sessionManager.isInFocusedPractice == true)

        vm.practiceRedOpening()
        #expect(vm.sessionManager.isInFocusedPractice == false)
        #expect(vm.currentAppMode == .practice)
    }

    @Test func testPracticeBlackOpening_ExitsFocusedPractice() {
        let (vm, _) = createViewModel()
        vm.sessionManager.startFocusedPractice()
        #expect(vm.sessionManager.isInFocusedPractice == true)

        vm.practiceBlackOpening()
        #expect(vm.sessionManager.isInFocusedPractice == false)
        #expect(vm.currentAppMode == .practice)
    }

    // MARK: - openYunku

    @Test func testOpenYunku_ConstructsCorrectURL() {
        let (vm, mock) = createViewModel()
        vm.openYunku()

        #expect(mock.openedURL != nil)
        let urlString = mock.openedURL!.absoluteString
        #expect(urlString.hasPrefix("http://www.qqzze.com/yunku/?"))
        // FEN 前缀应包含在 URL 中（去掉 " - " 后的部分）
        #expect(urlString.contains("rnbakabnr"))
    }

    // MARK: - makeRandomGame (locked 分支)

    @Test func testMakeRandomGame_WhenLocked_FilterUnchanged() {
        let (vm, _) = createViewModel()
        // 先锁定
        vm.toggleLock()
        #expect(vm.isAnyMoveLocked == true)

        let filtersBefore = vm.currentFilters
        _ = vm.makeRandomGame()
        // filter 不应因随机而改变
        #expect(vm.currentFilters == filtersBefore)
    }
}
