import Testing
import Foundation
@testable import XiangqiNotebook

/// DatabaseView 单元测试
/// 测试各种过滤场景、严格语义和便利构造器
struct DatabaseViewTests {

    // MARK: - Helper Methods

    /// 创建测试用的数据库（使用独立实例，避免并发污染）
    private func createTestDatabase() -> Database {
        // fenId 1-5 钻石结构 + 开局标志 + 实战统计：
        // 1(红) 2(黑) 3(红黑) 4(红方实战) 5(黑方实战)；着法 1→2,1→3,2→4,3→5
        TestDatabaseBuilder()
            .addFen(1, fen: "fen1", inRedOpening: true, inBlackOpening: false)
            .addFen(2, fen: "fen2", inRedOpening: false, inBlackOpening: true)
            .addFen(3, fen: "fen3", inRedOpening: true, inBlackOpening: true)
            .addFen(4, fen: "fen4", inRedOpening: false, inBlackOpening: false)
            .addFen(5, fen: "fen5", inRedOpening: false, inBlackOpening: false)
            .addRedRealGameStats(fenId: 4, redWin: 1)
            .addBlackRealGameStats(fenId: 5, blackWin: 1)
            .addMove(from: 1, to: 2)
            .addMove(from: 1, to: 3)
            .addMove(from: 2, to: 4)
            .addMove(from: 3, to: 5)
            .build()
    }

    // MARK: - Full View Tests

    @Test func testFullView_ReturnsAllFenObjects() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 完整视图应该包含所有 fenId
        #expect(view.containsFenId(1) == true)
        #expect(view.containsFenId(2) == true)
        #expect(view.containsFenId(3) == true)
        #expect(view.containsFenId(4) == true)
        #expect(view.containsFenId(5) == true)

        // 可以获取所有 FenObject
        #expect(view.getFenObject(1) != nil)
        #expect(view.getFenObject(2) != nil)
        #expect(view.getFenObject(3) != nil)
        #expect(view.getFenObject(4) != nil)
        #expect(view.getFenObject(5) != nil)
    }

    // MARK: - Red Opening View Tests

    @Test func testRedOpeningView_FiltersCorrectly() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // fenId 1 和 3 在红方开局库中
        #expect(view.containsFenId(1) == true)
        #expect(view.containsFenId(3) == true)

        // fenId 2, 4, 5 不在红方开局库中
        #expect(view.containsFenId(2) == false)
        #expect(view.containsFenId(4) == false)
        #expect(view.containsFenId(5) == false)

        // 可以获取在 scope 内的 FenObject
        #expect(view.getFenObject(1) != nil)
        #expect(view.getFenObject(3) != nil)

        // 无法获取不在 scope 内的 FenObject
        #expect(view.getFenObject(2) == nil)
        #expect(view.getFenObject(4) == nil)
    }

    // MARK: - Black Opening View Tests

    @Test func testBlackOpeningView_FiltersCorrectly() {
        let database = createTestDatabase()
        let view = DatabaseView.blackOpening(database: database)

        // fenId 2 和 3 在黑方开局库中
        #expect(view.containsFenId(2) == true)
        #expect(view.containsFenId(3) == true)

        // fenId 1, 4, 5 不在黑方开局库中
        #expect(view.containsFenId(1) == false)
        #expect(view.containsFenId(4) == false)
        #expect(view.containsFenId(5) == false)
    }

    // MARK: - Real Game View Tests

    @Test func testRedRealGameView_FiltersCorrectly() {
        let database = createTestDatabase()
        let view = DatabaseView.redRealGame(database: database)

        // 只有 fenId 4 在红方实战中
        #expect(view.containsFenId(4) == true)

        // 其他都不在
        #expect(view.containsFenId(1) == false)
        #expect(view.containsFenId(2) == false)
        #expect(view.containsFenId(3) == false)
        #expect(view.containsFenId(5) == false)
    }

    @Test func testBlackRealGameView_FiltersCorrectly() {
        let database = createTestDatabase()
        let view = DatabaseView.blackRealGame(database: database)

        // 只有 fenId 5 在黑方实战中
        #expect(view.containsFenId(5) == true)

        // 其他都不在
        #expect(view.containsFenId(1) == false)
        #expect(view.containsFenId(2) == false)
        #expect(view.containsFenId(3) == false)
        #expect(view.containsFenId(4) == false)
    }

    // MARK: - Focused Practice View Tests

    @Test func testFocusedPracticeView_FiltersCorrectly() {
        let database = createTestDatabase()
        let path = [1, 3, 5]
        let view = DatabaseView.focusedPractice(database: database, path: path)

        // 只有路径中的 fenId 在 scope 内
        #expect(view.containsFenId(1) == true)
        #expect(view.containsFenId(3) == true)
        #expect(view.containsFenId(5) == true)

        // 不在路径中的不在 scope 内
        #expect(view.containsFenId(2) == false)
        #expect(view.containsFenId(4) == false)
    }

    // MARK: - Dynamic Update Tests

    @Test func testContains_ReflectsDynamicUpdates() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // 初始状态：fenId 2 不在红方开局库中
        #expect(view.containsFenId(2) == false)

        // 动态修改：将 fenId 2 添加到红方开局库
        database.databaseData.fenObjects2[2]?.setInRedOpening(true)

        // 验证 contains 反映了动态更新
        #expect(view.containsFenId(2) == true)

        // 再次修改：从红方开局库中移除
        database.databaseData.fenObjects2[2]?.setInRedOpening(false)

        // 验证更新
        #expect(view.containsFenId(2) == false)
    }

    // MARK: - Strict Filtering Tests (moves)

    @Test func testMoves_StrictFiltering_SourceNotInScope() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // fenId 2 不在红方开局库中
        // moves(from: 2) 应该返回空数组（源不在 scope）
        let moves = view.moves(from: 2)
        #expect(moves.isEmpty)
    }

    @Test func testMoves_StrictFiltering_SourceInScope_TargetsFiltered() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // fenId 1 在红方开局库中，有两个 moves：1 -> 2 和 1 -> 3
        // fenId 2 不在红方开局库中，fenId 3 在红方开局库中
        // 严格语义：只返回目标也在 scope 内的 move
        let moves = view.moves(from: 1)

        // 应该只返回 1 -> 3，不返回 1 -> 2
        #expect(moves.count == 1)
        #expect(moves.first?.targetFenId == 3)
    }

    @Test func testMoves_StrictFiltering_AllTargetsInScope() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 在完整视图中，所有 move 都应该返回
        let moves = view.moves(from: 1)
        #expect(moves.count == 2)
    }

    @Test func testMoves_WithFenId_UsesCorrectFenId() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // 使用 moves(from:) 方法获取 fenId 1 的 moves
        let moves = view.moves(from: 1)

        // 应该只返回目标在 scope 内的 move
        #expect(moves.count == 1)
        #expect(moves.first?.targetFenId == 3)
    }

    // MARK: - Strict Filtering Tests (move)

    @Test func testMove_StrictFiltering_SourceNotInScope() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // fenId 2 不在红方开局库中
        // move(from: 2, to: 4) 应该返回 nil（源不在 scope）
        let move = view.move(from: 2, to: 4)
        #expect(move == nil)
    }

    @Test func testMove_StrictFiltering_TargetNotInScope() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // fenId 1 在红方开局库中，fenId 2 不在
        // move(from: 1, to: 2) 应该返回 nil（目标不在 scope）
        let move = view.move(from: 1, to: 2)
        #expect(move == nil)
    }

    @Test func testMove_StrictFiltering_BothInScope() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        // fenId 1 和 3 都在红方开局库中
        // move(from: 1, to: 3) 应该找到 move
        let move = view.move(from: 1, to: 3)
        #expect(move != nil)
        #expect(move?.sourceFenId == 1)
        #expect(move?.targetFenId == 3)
    }

    @Test func testMove_MoveDoesNotExist() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 在完整视图中，1 -> 4 这个 move 不存在
        let move = view.move(from: 1, to: 4)
        #expect(move == nil)
    }

    // MARK: - Direct Access Tests

    @Test func testEncapsulatedAccess_AllFenObjectsAccessible() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // All fenObjects should be accessible through getFenObject (though filtering may apply in specialized views)
        #expect(view.getFenObject(1) != nil)
        #expect(view.getFenObject(2) != nil)
        #expect(view.getFenObject(3) != nil)
        #expect(view.getFenObject(4) != nil)
        #expect(view.getFenObject(5) != nil)

        // 统计信息也应该完整访问
        #expect(view.myRealRedGameStatisticsByFenId[4] != nil)
        #expect(view.myRealBlackGameStatisticsByFenId[5] != nil)
    }

    // MARK: - Dirty State Tests

    @Test @MainActor func testDirtyState_Management() async throws {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 初始状态
        let initialDirty = view.isDirty

        // 标记为 dirty
        view.markDirty()

        // 等待主线程异步操作完成
        try await Task.sleep(for: .milliseconds(100))
        #expect(view.isDirty == true)

        // 清除 dirty（通过 database）
        database.markClean()

        // 等待主线程异步操作完成
        try await Task.sleep(for: .milliseconds(100))
        #expect(view.isDirty == false)
    }

    // MARK: - Edge Cases

    @Test func testGetFenObject_NonExistentFenId() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 访问不存在的 fenId
        let fenObject = view.getFenObject(999)
        #expect(fenObject == nil)
    }

    @Test func testMoves_FenObjectNotInDatabase() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 访问不存在的 fenId 的 moves
        let moves = view.moves(from: 999)
        #expect(moves.isEmpty)
    }

    @Test func testFocusedPractice_EmptyPath() {
        let database = createTestDatabase()
        let view = DatabaseView.focusedPractice(database: database, path: [])

        // 空路径意味着没有任何 fenId 在 scope 内
        #expect(view.containsFenId(1) == false)
        #expect(view.containsFenId(2) == false)
        #expect(view.containsFenId(3) == false)
    }

    @Test func testEnsureMove_AfterMarkAsRemoved_CreatesNewMove() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 取得已有着法 1 -> 2 并软删除（模拟"删招"）
        let (move, moveId, _) = view.ensureMove(from: 1, to: 2)
        move.markAsRemoved()
        view.unregisterMove(from: 1, to: 2)

        // 重新创建同一着法：不应返回 targetFenId 为 nil 的僵尸 move
        let (newMove, newMoveId, isNew) = view.ensureMove(from: 1, to: 2)
        #expect(newMove.targetFenId == 2)
        #expect(isNew == true)
        #expect(newMoveId != moveId)
    }

    @Test func testEnsureMove_StaleZombieMapping_CreatesNewMove() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 只软删除、不清理 moveToId（老数据中的遗留状态）
        let (move, moveId, _) = view.ensureMove(from: 1, to: 2)
        move.markAsRemoved()

        // ensureMove 应跳过僵尸映射并新建
        let (newMove, newMoveId, isNew) = view.ensureMove(from: 1, to: 2)
        #expect(newMove.targetFenId == 2)
        #expect(isNew == true)
        #expect(newMoveId != moveId)
    }

    // MARK: - specificGame / specificBook / 组合视图（issue #167 关键链路补测）

    /// 在测试库上创建一个覆盖 1→2 的棋局
    private func addTestGame(to database: Database) -> GameObject {
        let move = Move(sourceFenId: 1, targetFenId: 2)
        database.databaseData.moveObjects[100] = move
        database.databaseData.moveToId[[1, 2]] = 100
        let game = GameObject(id: UUID())
        game.startingFenId = 1
        game.moveIds = [100]
        database.databaseData.gameObjects[game.id] = game
        return game
    }

    @Test func testSpecificGameView_OnlyGamePathInScope() {
        let database = createTestDatabase()
        let game = addTestGame(to: database)

        let view = DatabaseView.specificGame(database: database, gameId: game.id)
        #expect(view.containsFenId(1) == true)
        #expect(view.containsFenId(2) == true)
        #expect(view.containsFenId(3) == false)
        #expect(view.containsFenId(4) == false)
        #expect(view.containsFenId(5) == false)
    }

    @Test func testSpecificGameView_DeletedGame_EmptyScope() {
        let database = createTestDatabase()
        // 指向不存在（已删除）的棋局：范围应为空而不是崩溃或放行
        let view = DatabaseView.specificGame(database: database, gameId: UUID())
        for fenId in 1...5 {
            #expect(view.containsFenId(fenId) == false)
        }
    }

    @Test func testSpecificBookView_CollectsGameData() {
        let database = createTestDatabase()
        let game = addTestGame(to: database)
        let book = BookObject(id: UUID(), name: "测试书")
        book.gameIds = [game.id]
        database.databaseData.bookObjects[book.id] = book

        let view = DatabaseView.specificBook(database: database, bookId: book.id)
        #expect(view.containsFenId(1) == true)
        #expect(view.containsFenId(2) == true)
        #expect(view.containsFenId(3) == false)
        #expect(view.getGameObject(game.id) != nil)
    }

    @Test func testSpecificBookView_SubBookGamesIncluded() {
        let database = createTestDatabase()
        let game = addTestGame(to: database)
        let subBook = BookObject(id: UUID(), name: "子书")
        subBook.gameIds = [game.id]
        let parent = BookObject(id: UUID(), name: "父书")
        parent.subBookIds = [subBook.id]
        database.databaseData.bookObjects[subBook.id] = subBook
        database.databaseData.bookObjects[parent.id] = parent

        // 父书视图应递归包含子书的棋局数据
        let view = DatabaseView.specificBook(database: database, bookId: parent.id)
        #expect(view.containsFenId(1) == true)
        #expect(view.containsFenId(2) == true)
    }

    @Test func testWithStepLimit_IntersectsBaseScope() {
        let database = createTestDatabase()
        let base = DatabaseView.redOpening(database: database)  // 范围 {1, 3}

        let view = DatabaseView.withStepLimit(base, reachableFenIds: [1, 2])
        #expect(view.containsFenId(1) == true)   // base ∩ 可达
        #expect(view.containsFenId(3) == false)  // 在 base 但不可达
        #expect(view.containsFenId(2) == false)  // 可达但不在 base
    }

    @Test func testWithLock_IntersectsBaseScope() {
        let database = createTestDatabase()
        let base = DatabaseView.full(database: database)

        let view = DatabaseView.withLock(base, reachableFenIds: [3, 5])
        #expect(view.containsFenId(3) == true)
        #expect(view.containsFenId(5) == true)
        #expect(view.containsFenId(1) == false)
    }

    @Test func testCombined_MultipleFilters_ANDSemantics() {
        let database = createTestDatabase()
        // 红方开局 {1, 3} ∩ 黑方开局 {2, 3} = {3}
        let view = DatabaseView.combined(
            database: database,
            filters: [Session.filterRedOpeningOnly, Session.filterBlackOpeningOnly]
        )
        #expect(view.containsFenId(3) == true)
        #expect(view.containsFenId(1) == false)
        #expect(view.containsFenId(2) == false)
    }

    @Test func testCombined_EmptyFilters_FullView() {
        let database = createTestDatabase()
        let view = DatabaseView.combined(database: database, filters: [])
        for fenId in 1...5 {
            #expect(view.containsFenId(fenId) == true)
        }
    }

    @Test func testCombined_SpecificGameWithoutId_NoOpFilter() {
        let database = createTestDatabase()
        // filters 含 specificGame 但未传 id：该过滤器被忽略（不收窄范围）
        let view = DatabaseView.combined(
            database: database,
            filters: [Session.filterSpecificGame],
            specificGameId: nil
        )
        #expect(view.containsFenId(1) == true)
    }

    @Test func testGetGamesInBookUnfiltered_DanglingGameId_DoesNotCrash() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 棋书引用一个存在的棋局和一个已被删除（悬空）的棋局
        let bookId = UUID()
        let book = BookObject(id: bookId, name: "测试棋书")
        let game = GameObject(id: UUID())
        database.databaseData.gameObjects[game.id] = game
        book.gameIds = [game.id, UUID()] // 第二个是悬空引用
        database.databaseData.bookObjects[bookId] = book

        // 修复前这里会因强制解包悬空 gameId 崩溃
        let games = view.getGamesInBookUnfiltered(bookId)

        #expect(games.count == 1)
        #expect(games.first?.id == game.id)
    }
}
