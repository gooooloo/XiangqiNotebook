import Testing
import Foundation
@testable import XiangqiNotebook

/// Session 集成测试
/// 测试 Session 如何使用 DatabaseView 进行数据访问
struct SessionTests {

    // MARK: - Helper Methods

    /// 创建测试用的 Database（共享数据）
    private func createTestDatabase() -> Database {
        // fenId 1-5 钻石结构：1(红黑)→2(红)→4(红)，1→3(黑)→5(无)
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        return TestDatabaseBuilder()
            .addFen(1, fen: startFen, inRedOpening: true, inBlackOpening: true)
            .addFen(2, fen: "fen2 - - 1 1", inRedOpening: true)
            .addFen(3, fen: "fen3 - - 1 1", inBlackOpening: true)
            .addFen(4, fen: "fen4 - - 1 1", inRedOpening: true)
            .addFen(5, fen: "fen5 - - 1 1")
            .addMove(from: 1, to: 2)
            .addMove(from: 1, to: 3)
            .addMove(from: 2, to: 4)
            .addMove(from: 3, to: 5)
            .build()
    }

    /// 创建测试用的 Session（使用完整视图）
    private func createTestSession() -> Session {
        let database = createTestDatabase()
        let sessionData = SessionData()
        sessionData.currentGame2 = [1]  // 起始局面
        sessionData.currentGameStep = 0
        let databaseView = DatabaseView.full(database: database)
        return try! Session(sessionData: sessionData, databaseView: databaseView)
    }

    /// 创建测试用的 Session（带指定过滤器）
    private func createTestSessionWithFilter(_ filter: String?) -> Session {
        let database = createTestDatabase()
        let sessionData = SessionData()
        sessionData.filters = filter.map { [$0] } ?? []
        sessionData.currentGame2 = [1]  // 起始局面
        sessionData.currentGameStep = 0
        // 根据 filter 创建相应的 DatabaseView
        let databaseView = SessionManager.createDatabaseView(
            for: filter.map { [$0] } ?? [],
            focusedPath: nil,
            specificGameId: nil,
            specificBookId: nil,
            database: database
        )
        return try! Session(sessionData: sessionData, databaseView: databaseView)
    }

    // MARK: - CurrentMove Tests

    @Test func testCurrentMove_WithFullView() {
        let session = createTestSession()

        // 设置 currentGame 为 [1, 2]，当前步骤为 1
        session.sessionData.currentGame2 = [1, 2]
        session.sessionData.currentGameStep = 1

        // 在完整视图中，应该能找到 move
        let move = session.currentMove
        #expect(move != nil)
        #expect(move?.sourceFenId == 1)
        #expect(move?.targetFenId == 2)
    }

    @Test func testCurrentMove_WithRedOpeningFilter() {
        // 创建带红方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterRedOpeningOnly)

        // 设置 currentGame 为 [1, 2]，当前步骤为 1
        session.sessionData.currentGame2 = [1, 2]
        session.sessionData.currentGameStep = 1

        // fenId 1 和 2 都在红方开局库中，应该能找到 move
        let move = session.currentMove
        #expect(move != nil)
        #expect(move?.sourceFenId == 1)
        #expect(move?.targetFenId == 2)
    }

    @Test func testCurrentMove_WithBlackOpeningFilter_TargetNotInScope() {
        // 创建带黑方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterBlackOpeningOnly)

        // 设置 currentGame 为 [1, 2]，当前步骤为 1
        session.sessionData.currentGame2 = [1, 2]
        session.sessionData.currentGameStep = 1

        // fenId 2 不在黑方开局库中，应该找不到 move
        let move = session.currentMove
        #expect(move == nil)
    }

    // MARK: - CurrentGameVariantMoves Tests

    @Test func testCurrentGameVariantMoves_WithFullView() {
        let session = createTestSession()

        // 设置 currentGame 为 [1, 2]，当前步骤为 1
        session.sessionData.currentGame2 = [1, 2]
        session.sessionData.currentGameStep = 1

        // 在完整视图中，fenId 1 有两个变着：1 -> 2 和 1 -> 3
        let variantMoves = session.currentGameVariantMoves
        #expect(variantMoves.count == 2)
    }

    @Test func testCurrentGameVariantMoves_WithRedOpeningFilter() {
        // 创建带红方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterRedOpeningOnly)

        // 设置 currentGame 为 [1, 2]，当前步骤为 1
        session.sessionData.currentGame2 = [1, 2]
        session.sessionData.currentGameStep = 1

        // 在红方开局库视图中，fenId 1 只有一个在 scope 内的变着：1 -> 2
        // （1 -> 3 的目标不在红方开局库中）
        let variantMoves = session.currentGameVariantMoves
        #expect(variantMoves.count == 1)
        #expect(variantMoves.first?.targetFenId == 2)
    }

    @Test func testCurrentGameVariantMoves_AtStep0() {
        let session = createTestSession()

        // 在步骤 0 时，没有变着
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        let variantMoves = session.currentGameVariantMoves
        #expect(variantMoves.isEmpty)
    }

    // MARK: - CheckBoardFenInNextMoveList Tests

    @Test func testCheckBoardFenInNextMoveList_FenInNextMoves() {
        let session = createTestSession()

        // 设置当前局面为 fenId 1
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        // 检查 fen2 是否在下一步的列表中（传入任意格式，会被 normalizeFen 标准化）
        let result = session.checkBoardFenInNextMoveList("fen2")
        #expect(result == true)
    }

    @Test func testCheckBoardFenInNextMoveList_FenNotInNextMoves() {
        let session = createTestSession()

        // 设置当前局面为 fenId 1
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        // 检查 fen4 是否在下一步的列表中（不是）
        let result = session.checkBoardFenInNextMoveList("fen4")
        #expect(result == false)
    }

    @Test func testCheckBoardFenInNextMoveList_WithFilter() {
        // 创建带红方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterRedOpeningOnly)

        // 设置当前局面为 fenId 1
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        // 检查 fen2 是否在下一步的列表中（是，在红方开局库中）（传入任意格式，会被 normalizeFen 标准化）
        let result1 = session.checkBoardFenInNextMoveList("fen2")
        #expect(result1 == true)

        // 检查 fen3 是否在下一步的列表中（否，不在红方开局库中）
        let result2 = session.checkBoardFenInNextMoveList("fen3")
        #expect(result2 == false)
    }

    // MARK: - HasNextMove Tests

    @Test func testHasNextMove_WithNextMoves() {
        let session = createTestSession()

        // 设置当前局面为 fenId 1
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        // fenId 1 有下一步
        #expect(session.hasNextMove == true)
    }

    @Test func testHasNextMove_WithoutNextMoves() {
        let session = createTestSession()

        // 设置当前局面为 fenId 5（没有下一步）
        session.sessionData.currentGame2 = [1, 3, 5]
        session.sessionData.currentGameStep = 2

        // fenId 5 没有下一步
        #expect(session.hasNextMove == false)
    }

    @Test func testHasNextMove_WithFilter() {
        // 创建带黑方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterBlackOpeningOnly)

        // 设置当前局面为 fenId 1
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        // fenId 1 在黑方开局库视图中只有一个在 scope 内的 move：1 -> 3
        #expect(session.hasNextMove == true)
    }

    // MARK: - GetRandomNextMove Tests

    @Test func testGetRandomNextMove_ReturnsValidMove() {
        let session = createTestSession()

        // 设置当前局面为 fenId 1
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        // 获取随机的下一步
        let move = session.getRandomNextMove()
        #expect(move != nil)
        #expect(move?.sourceFenId == 1)
        #expect(move?.targetFenId == 2 || move?.targetFenId == 3)
    }

    @Test func testGetRandomNextMove_WithFilter() {
        // 创建带红方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterRedOpeningOnly)

        // 设置当前局面为 fenId 1
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        // 在红方开局库视图中，只有 1 -> 2 在 scope 内
        let move = session.getRandomNextMove()
        #expect(move != nil)
        #expect(move?.sourceFenId == 1)
        #expect(move?.targetFenId == 2)
    }

    @Test func testGetRandomNextMove_NoNextMoves() {
        let session = createTestSession()

        // 设置当前局面为 fenId 5（没有下一步）
        session.sessionData.currentGame2 = [1, 3, 5]
        session.sessionData.currentGameStep = 2

        // 没有下一步，应该返回 nil
        let move = session.getRandomNextMove()
        #expect(move == nil)
    }

    // MARK: - 路径枚举 Tests（计数枚举，issue #162）

    @Test func testPathEnumeration_FullView() {
        let session = createTestSession()

        // 设置起始局面为 fenId 1，锁定步骤为 0
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0
        session.sessionData.lockedStep = 0

        let enumerator = session.makePathEnumerator()

        // 在完整视图中，应该有 2 条路径：[1, 2, 4] 和 [1, 3, 5]
        #expect(enumerator.totalCount == 2)
        #expect(enumerator.path(at: 0) == [1, 2, 4])
        #expect(enumerator.path(at: 1) == [1, 3, 5])

        // fenId 1 应该有 2 条路径
        #expect(enumerator.pathCountMap()[1] == 2)
    }

    @Test func testPathEnumeration_WithRedOpeningFilter() {
        // 创建带红方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterRedOpeningOnly)

        // 设置起始局面为 fenId 1，锁定步骤为 0
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0
        session.sessionData.lockedStep = 0

        let enumerator = session.makePathEnumerator()

        // 在红方开局库视图中，只有一条路径：[1, 2, 4]
        // （因为 fenId 3 和 5 不在红方开局库中）
        #expect(enumerator.totalCount == 1)
        #expect(enumerator.path(at: 0) == [1, 2, 4])

        // fenId 1 应该有 1 条路径
        #expect(enumerator.pathCountMap()[1] == 1)
    }

    @Test func testGoToNextPath_CyclesThroughPaths() {
        let session = createTestSession()
        session.sessionData.currentGame2 = [1, 2, 4]
        session.sessionData.currentGameStep = 0
        session.sessionData.lockedStep = 0

        session.goToNextPath()
        #expect(session.sessionData.currentGame2 == [1, 3, 5])
        #expect(session.sessionData.currentPathIndex == 1)

        session.goToNextPath()  // 环回第一条
        #expect(session.sessionData.currentGame2 == [1, 2, 4])
        #expect(session.sessionData.currentPathIndex == 0)

        session.goToPreviousPath()
        #expect(session.sessionData.currentGame2 == [1, 3, 5])
        #expect(session.sessionData.currentPathIndex == 1)
    }

    // MARK: - Edge Cases

    @Test func testCurrentMove_AtStartPosition() {
        let session = createTestSession()

        // 在起始位置（步骤 0），没有 currentMove
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0

        let move = session.currentMove
        #expect(move == nil)
    }

    @Test func testCurrentGameVariantMoves_FilteredByScope() {
        // 创建带红方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterRedOpeningOnly)

        // 设置 currentGame 为 [1, 2]，当前步骤为 1（在红方开局库的有效路径中）
        session.sessionData.currentGame2 = [1, 2]
        session.sessionData.currentGameStep = 1

        // fenId 1 在红方开局库中，当前步骤是 1（previousFenId = 1）
        // 从 fenId 1 出发的变着应该只包含目标也在 scope 内的
        let variantMoves = session.currentGameVariantMoves

        // 应该只有 1 -> 2（目标在红方开局库中），不包括 1 -> 3（目标不在红方开局库）
        #expect(variantMoves.count == 1)
        #expect(variantMoves.first?.targetFenId == 2)
    }

    // MARK: - 删招后重新走同一招

    @Test func testRemoveCurrentStep_ThenReplaySameMove_Succeeds() {
        let session = createTestSession()
        session.sessionData.currentGame2 = [1, 2]
        session.sessionData.currentGameStep = 1
        session.sessionData.allowAddingNewMoves = true
        session.sessionData.autoExtendGameWhenPlayingBoardFen = false

        // 删招：移除 1 -> 2
        session.removeCurrentStep()

        // 重新走同一招：修复前 ensureMove 返回僵尸 move，
        // autoExtendGame 拒绝扩展，棋子无声弹回
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0
        let ok = session.playNewBoardFen("fen2 - - 1 1")

        #expect(ok)
        #expect(session.sessionData.currentGame2.count >= 2)
        #expect(session.sessionData.currentGame2[1] == 2)
        #expect(session.currentMove?.targetFenId == 2)
    }

    // MARK: - playRandomGame 空路径防护

    @Test func testPlayRandomGame_NoPathsInScope_ReturnsNil() {
        let database = createTestDatabase()
        let sessionData = SessionData()
        sessionData.currentGame2 = [1]
        sessionData.currentGameStep = 0
        // 视图范围只含 fenId 2，当前局面（fenId 1）不在范围内 → 生成不出任何路径
        let databaseView = DatabaseView.focusedPractice(database: database, path: [2])
        let session = try! Session(sessionData: sessionData, databaseView: databaseView)

        // 修复前这里会因 Int.random(in: 0..<0) 崩溃
        let result = session.playRandomGame()

        #expect(result == nil)
    }
}
