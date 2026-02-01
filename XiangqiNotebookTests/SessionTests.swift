import Testing
import Foundation
@testable import XiangqiNotebook

/// Session 集成测试
/// 测试 Session 如何使用 DatabaseView 进行数据访问
struct SessionTests {

    // MARK: - Helper Methods

    /// 创建测试用的 Database（共享数据）
    private func createTestDatabase() -> Database {
        // 创建一个空的测试数据库，避免与共享单例产生并发访问问题
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        // 创建起始局面（在两个开局库中，因为起始局面两边都会使用）
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fen1 = FenObject(fen: startFen, fenId: 1)
        fen1.setInRedOpening(true)
        fen1.setInBlackOpening(true)
        database.databaseData.fenObjects2[1] = fen1
        database.databaseData.fenToId[startFen] = 1

        // 创建几个后续局面
        // fenId 2: 在红方开局库中
        let fen2 = FenObject(fen: "fen2 - - 1 1", fenId: 2)
        fen2.setInRedOpening(true)
        database.databaseData.fenObjects2[2] = fen2
        database.databaseData.fenToId["fen2 - - 1 1"] = 2

        // fenId 3: 在黑方开局库中
        let fen3 = FenObject(fen: "fen3 - - 1 1", fenId: 3)
        fen3.setInBlackOpening(true)
        database.databaseData.fenObjects2[3] = fen3
        database.databaseData.fenToId["fen3 - - 1 1"] = 3

        // fenId 4: 在红方开局库中
        let fen4 = FenObject(fen: "fen4 - - 1 1", fenId: 4)
        fen4.setInRedOpening(true)
        database.databaseData.fenObjects2[4] = fen4
        database.databaseData.fenToId["fen4 - - 1 1"] = 4

        // fenId 5: 不在任何开局库中
        let fen5 = FenObject(fen: "fen5 - - 1 1", fenId: 5)
        database.databaseData.fenObjects2[5] = fen5
        database.databaseData.fenToId["fen5 - - 1 1"] = 5

        // 添加 moves: 1 -> 2, 1 -> 3, 2 -> 4, 3 -> 5
        let move1to2 = Move(sourceFenId: 1, targetFenId: 2)
        fen1.addMoveIfNeeded(move: move1to2)
        database.databaseData.moveObjects[1] = move1to2
        database.databaseData.moveToId[[1, 2]] = 1

        let move1to3 = Move(sourceFenId: 1, targetFenId: 3)
        fen1.addMoveIfNeeded(move: move1to3)
        database.databaseData.moveObjects[2] = move1to3
        database.databaseData.moveToId[[1, 3]] = 2

        let move2to4 = Move(sourceFenId: 2, targetFenId: 4)
        fen2.addMoveIfNeeded(move: move2to4)
        database.databaseData.moveObjects[3] = move2to4
        database.databaseData.moveToId[[2, 4]] = 3

        let move3to5 = Move(sourceFenId: 3, targetFenId: 5)
        fen3.addMoveIfNeeded(move: move3to5)
        database.databaseData.moveObjects[4] = move3to5
        database.databaseData.moveToId[[3, 5]] = 4

        return database
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

    // MARK: - GenerateAllGamePaths Tests

    @Test func testGenerateAllGamePaths_FullView() {
        let session = createTestSession()

        // 设置起始局面为 fenId 1，锁定步骤为 0
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0
        session.sessionData.lockedStep = 0

        let (paths, fenIdToPathCount) = session.generateAllGamePaths()

        // 在完整视图中，应该有 2 条路径：
        // [1, 2, 4] 和 [1, 3, 5]
        #expect(paths.count == 2)
        #expect(paths.contains([1, 2, 4]))
        #expect(paths.contains([1, 3, 5]))

        // fenId 1 应该有 2 条路径
        #expect(fenIdToPathCount[1] == 2)
    }

    @Test func testGenerateAllGamePaths_WithRedOpeningFilter() {
        // 创建带红方开局库过滤器的 Session
        let session = createTestSessionWithFilter(Session.filterRedOpeningOnly)

        // 设置起始局面为 fenId 1，锁定步骤为 0
        session.sessionData.currentGame2 = [1]
        session.sessionData.currentGameStep = 0
        session.sessionData.lockedStep = 0

        let (paths, fenIdToPathCount) = session.generateAllGamePaths()

        // 在红方开局库视图中，只有一条路径：[1, 2, 4]
        // （因为 fenId 3 和 5 不在红方开局库中）
        #expect(paths.count == 1)
        #expect(paths.first == [1, 2, 4])

        // fenId 1 应该有 1 条路径
        #expect(fenIdToPathCount[1] == 1)
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
}
