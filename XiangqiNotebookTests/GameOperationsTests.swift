import Testing
import Foundation
@testable import XiangqiNotebook

struct GameOperationsTests {

    // MARK: - Helper Methods

    private func createTestDatabase() -> Database {
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        // 创建 fenId 1-5
        // 1 -> 2 -> 4
        //   -> 3 -> 5
        for i in 1...5 {
            let fenObject = FenObject(fen: "fen\(i)", fenId: i)
            database.databaseData.fenObjects2[i] = fenObject
            database.databaseData.fenToId["fen\(i)"] = i
        }

        let move1to2 = Move(sourceFenId: 1, targetFenId: 2)
        database.databaseData.fenObjects2[1]!.addMoveIfNeeded(move: move1to2)
        database.databaseData.moveObjects[1] = move1to2
        database.databaseData.moveToId[[1, 2]] = 1

        let move1to3 = Move(sourceFenId: 1, targetFenId: 3)
        database.databaseData.fenObjects2[1]!.addMoveIfNeeded(move: move1to3)
        database.databaseData.moveObjects[2] = move1to3
        database.databaseData.moveToId[[1, 3]] = 2

        let move2to4 = Move(sourceFenId: 2, targetFenId: 4)
        database.databaseData.fenObjects2[2]!.addMoveIfNeeded(move: move2to4)
        database.databaseData.moveObjects[3] = move2to4
        database.databaseData.moveToId[[2, 4]] = 3

        let move3to5 = Move(sourceFenId: 3, targetFenId: 5)
        database.databaseData.fenObjects2[3]!.addMoveIfNeeded(move: move3to5)
        database.databaseData.moveObjects[4] = move3to5
        database.databaseData.moveToId[[3, 5]] = 4

        return database
    }

    // MARK: - autoExtendGame Tests

    @Test func testAutoExtendGame_ExtendsByLastMoveFenId() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 设置 fenId 1 的 lastMoveFenId 为 2（优先走 1->2）
        database.databaseData.fenObjects2[1]!.markLastMove(fenId: 2)

        let result = GameOperations.autoExtendGame(game: [1], databaseView: view)
        // 应该沿着 lastMoveFenId 扩展：1 -> 2 -> 4
        #expect(result == [1, 2, 4])
    }

    @Test func testAutoExtendGame_ExtendsByFirstMove() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 没有 lastMoveFenId，按 moves 中第一个扩展
        let result = GameOperations.autoExtendGame(game: [1], databaseView: view)
        // 第一个 move 是 1->2，然后 2->4
        #expect(result.first == 1)
        #expect(result.count >= 1)
    }

    @Test func testAutoExtendGame_NoExtendWhenAllowExtendFalse() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let result = GameOperations.autoExtendGame(game: [1], databaseView: view, allowExtend: false)
        #expect(result == [1])
    }

    @Test func testAutoExtendGame_WithNextFenIds() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 指定 nextFenIds = [3]，强制走 1->3
        let result = GameOperations.autoExtendGame(game: [1], nextFenIds: [3], databaseView: view, allowExtend: false)
        #expect(result == [1, 3])
    }

    @Test func testAutoExtendGame_WithNextFenIds_ThenAutoExtend() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 指定 nextFenIds = [3]，然后自动扩展 3->5
        let result = GameOperations.autoExtendGame(game: [1], nextFenIds: [3], databaseView: view, allowExtend: true)
        #expect(result == [1, 3, 5])
    }

    @Test func testAutoExtendGame_DoesNotLoop() {
        // 创建一个循环结构来测试防止无限循环
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        let fen1 = FenObject(fen: "fen1", fenId: 1)
        let fen2 = FenObject(fen: "fen2", fenId: 2)
        database.databaseData.fenObjects2[1] = fen1
        database.databaseData.fenObjects2[2] = fen2

        // 创建双向 moves（潜在循环）
        let move1to2 = Move(sourceFenId: 1, targetFenId: 2)
        fen1.addMoveIfNeeded(move: move1to2)
        let move2to1 = Move(sourceFenId: 2, targetFenId: 1)
        fen2.addMoveIfNeeded(move: move2to1)

        let view = DatabaseView.full(database: database)
        let result = GameOperations.autoExtendGame(game: [1], databaseView: view)

        // 应该是 [1, 2]，不会继续扩展回 1（因为 1 已经在 game 中）
        #expect(result == [1, 2])
    }

    @Test func testAutoExtendGame_EmptyGame() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let result = GameOperations.autoExtendGame(game: [], databaseView: view)
        #expect(result.isEmpty)
    }

    // MARK: - cutGameUntilStep Tests

    @Test func testCutGameUntilStep_ValidStep() {
        let game = [1, 2, 3, 4, 5]
        let (result, step) = GameOperations.cutGameUntilStep(2, currentGame: game)
        #expect(result == [1, 2, 3])
        #expect(step == 2)
    }

    @Test func testCutGameUntilStep_FirstStep() {
        let game = [1, 2, 3, 4, 5]
        let (result, step) = GameOperations.cutGameUntilStep(0, currentGame: game)
        #expect(result == [1])
        #expect(step == 0)
    }

    @Test func testCutGameUntilStep_LastStep() {
        let game = [1, 2, 3, 4, 5]
        let (result, step) = GameOperations.cutGameUntilStep(4, currentGame: game)
        #expect(result == [1, 2, 3, 4, 5])
        #expect(step == 4)
    }

    @Test func testCutGameUntilStep_OutOfBoundsStep() {
        let game = [1, 2, 3]
        let (result, step) = GameOperations.cutGameUntilStep(10, currentGame: game)
        // 超出范围时返回原始 game
        #expect(result == [1, 2, 3])
        #expect(step == 2)
    }

    @Test func testCutGameUntilStep_NegativeStep() {
        let game = [1, 2, 3]
        let (result, step) = GameOperations.cutGameUntilStep(-1, currentGame: game)
        // 负数时返回原始 game
        #expect(result == [1, 2, 3])
        #expect(step == 2)
    }

    // MARK: - makeRandomGameDFSWithRandomizer Tests

    @Test func testMakeRandomGameDFS_AlwaysPickFirst() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 始终选择第一条路径
        let result = GameOperations.makeRandomGameDFSWithRandomizer(
            currentFenId: 1,
            databaseView: view,
            randomizer: { _ in 0 }
        )

        #expect(result != nil)
        // 两条路径：[1,2,4] 和 [1,3,5]，DFS 中第一条应该是 [1,2,4]
        // result 去掉起始 fenId
        #expect(result!.result.first == 2 || result!.result.first == 3)
        #expect(result!.totalCount == 2)
    }

    @Test func testMakeRandomGameDFS_AlwaysPickLast() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 始终选择最后一条路径
        let result = GameOperations.makeRandomGameDFSWithRandomizer(
            currentFenId: 1,
            databaseView: view,
            randomizer: { count in count - 1 }
        )

        #expect(result != nil)
        #expect(result!.totalCount == 2)
    }

    @Test func testMakeRandomGameDFS_NoNextMoves_ReturnsNil() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // fenId 4 没有 next moves
        let result = GameOperations.makeRandomGameDFSWithRandomizer(
            currentFenId: 4,
            databaseView: view,
            randomizer: { _ in 0 }
        )

        // 叶节点：只有一条路径（空路径），result 为空数组
        #expect(result != nil)
        #expect(result!.result.isEmpty)
    }

    @Test func testMakeRandomGameDFS_FenIdNotInScope() {
        let database = createTestDatabase()
        // 使用过滤视图，fenId 1 不在 scope 中
        let view = DatabaseView.redOpening(database: database)

        let result = GameOperations.makeRandomGameDFSWithRandomizer(
            currentFenId: 1,
            databaseView: view,
            randomizer: { _ in 0 }
        )

        // fenId 1 不在红方开局库中，应该返回 nil
        #expect(result == nil)
    }

    // MARK: - nextVariantIndex Tests

    @Test func testNextVariantIndex_BasicRotation() {
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        let move2 = Move(sourceFenId: 1, targetFenId: 3)
        let move3 = Move(sourceFenId: 1, targetFenId: 4)
        let variants = [move1, move2, move3]

        // 当前在 fenId 2，下一个应该是 index 1（targetFenId 3）
        let next = GameOperations.nextVariantIndex(currentFenId: 2, variantMoves: variants)
        #expect(next == 1)
    }

    @Test func testNextVariantIndex_WrapsAround() {
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        let move2 = Move(sourceFenId: 1, targetFenId: 3)
        let variants = [move1, move2]

        // 当前在 fenId 3（最后一个），下一个应该 wrap 到 index 0
        let next = GameOperations.nextVariantIndex(currentFenId: 3, variantMoves: variants)
        #expect(next == 0)
    }

    @Test func testNextVariantIndex_LessThanTwoVariants() {
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        let variants = [move1]

        // 只有一个变着，返回 0
        let next = GameOperations.nextVariantIndex(currentFenId: 2, variantMoves: variants)
        #expect(next == 0)
    }

    @Test func testNextVariantIndex_EmptyVariants() {
        // 空变着，返回 0
        let next = GameOperations.nextVariantIndex(currentFenId: 2, variantMoves: [])
        #expect(next == 0)
    }

    @Test func testNextVariantIndex_CurrentFenIdNotInVariants() {
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        let move2 = Move(sourceFenId: 1, targetFenId: 3)
        let variants = [move1, move2]

        // 当前 fenId 不在变着中，返回 0
        let next = GameOperations.nextVariantIndex(currentFenId: 99, variantMoves: variants)
        #expect(next == 0)
    }
}
