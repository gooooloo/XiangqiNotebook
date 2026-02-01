import Testing
import Foundation
@testable import XiangqiNotebook

/// DatabaseView 单元测试
/// 测试各种过滤场景、严格语义和便利构造器
struct DatabaseViewTests {

    // MARK: - Helper Methods

    /// 创建测试用的数据库（使用独立实例，避免并发污染）
    private func createTestDatabase() -> Database {
        // 创建一个空的测试数据库，避免与共享单例产生并发访问问题
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        // 创建测试局面：fenId 1-5
        // fenId 1: 在红方开局库中
        let fen1 = FenObject(fen: "fen1", fenId: 1)
        fen1.setInRedOpening(true)
        fen1.setInBlackOpening(false)
        database.databaseData.fenObjects2[1] = fen1

        // fenId 2: 在黑方开局库中
        let fen2 = FenObject(fen: "fen2", fenId: 2)
        fen2.setInRedOpening(false)
        fen2.setInBlackOpening(true)
        database.databaseData.fenObjects2[2] = fen2

        // fenId 3: 在两个开局库中
        let fen3 = FenObject(fen: "fen3", fenId: 3)
        fen3.setInRedOpening(true)
        fen3.setInBlackOpening(true)
        database.databaseData.fenObjects2[3] = fen3

        // fenId 4: 不在开局库中，但在红方实战中
        let fen4 = FenObject(fen: "fen4", fenId: 4)
        fen4.setInRedOpening(false)
        fen4.setInBlackOpening(false)
        database.databaseData.fenObjects2[4] = fen4
        let stats4 = GameResultStatistics()
        stats4.redWin = 1
        database.databaseData.myRealRedGameStatisticsByFenId[4] = stats4

        // fenId 5: 不在开局库中，但在黑方实战中
        let fen5 = FenObject(fen: "fen5", fenId: 5)
        fen5.setInRedOpening(false)
        fen5.setInBlackOpening(false)
        database.databaseData.fenObjects2[5] = fen5
        let stats5 = GameResultStatistics()
        stats5.blackWin = 1
        database.databaseData.myRealBlackGameStatisticsByFenId[5] = stats5

        // 添加一些 moves：1 -> 2, 1 -> 3, 2 -> 4, 3 -> 5
        let move1to2 = Move(sourceFenId: 1, targetFenId: 2)
        fen1.addMoveIfNeeded(move: move1to2)

        let move1to3 = Move(sourceFenId: 1, targetFenId: 3)
        fen1.addMoveIfNeeded(move: move1to3)

        let move2to4 = Move(sourceFenId: 2, targetFenId: 4)
        fen2.addMoveIfNeeded(move: move2to4)

        let move3to5 = Move(sourceFenId: 3, targetFenId: 5)
        fen3.addMoveIfNeeded(move: move3to5)

        return database
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
}
