import Testing
import Foundation
@testable import XiangqiNotebook

struct GameOperationsTests {

    // MARK: - Helper Methods

    private func createTestDatabase() -> Database {
        // fenId 1-5 钻石结构：1→2→4 与 1→3→5
        TestDatabaseBuilder()
            .addFens(1...5)
            .addMove(from: 1, to: 2)  // moveId 1
            .addMove(from: 1, to: 3)  // moveId 2
            .addMove(from: 2, to: 4)  // moveId 3
            .addMove(from: 3, to: 5)  // moveId 4
            .build()
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

    // MARK: - GamePathEnumerator Tests（计数枚举代替全路径物化，issue #162）

    @Test func testPathEnumerator_TotalCountAndLexicographicOrder() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // 测试库：两条路径 [1,2,4] 与 [1,3,5]，子节点按 fenId 升序枚举
        let enumerator = GamePathEnumerator(databaseView: view, prefix: [1])

        #expect(enumerator.totalCount == 2)
        #expect(enumerator.path(at: 0) == [1, 2, 4])
        #expect(enumerator.path(at: 1) == [1, 3, 5])
        #expect(enumerator.path(at: 2) == nil)   // 越界
        #expect(enumerator.path(at: -1) == nil)
    }

    @Test func testPathEnumerator_IndexOfPath_RoundTrip() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)
        let enumerator = GamePathEnumerator(databaseView: view, prefix: [1])

        for i in 0..<enumerator.totalCount {
            let path = enumerator.path(at: i)!
            #expect(enumerator.index(of: path) == i)
        }
        // 非完整路径：返回以它为前缀的第一条路径的序号
        #expect(enumerator.index(of: [1, 3]) == 1)
        #expect(enumerator.index(of: [1]) == 0)
        // 不以 prefix 开头或子节点不存在
        #expect(enumerator.index(of: [2]) == nil)
        #expect(enumerator.index(of: [1, 9]) == nil)
    }

    @Test func testPathEnumerator_LeafStart_SinglePath() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        // fenId 4 是叶子：唯一路径就是前缀本身
        let enumerator = GamePathEnumerator(databaseView: view, prefix: [4])
        #expect(enumerator.totalCount == 1)
        #expect(enumerator.path(at: 0) == [4])
    }

    @Test func testPathEnumerator_StartNotInScope_ZeroPaths() {
        let database = createTestDatabase()
        // 过滤视图：fenId 1 不在红方开局库中
        let view = DatabaseView.redOpening(database: database)

        let enumerator = GamePathEnumerator(databaseView: view, prefix: [1])
        #expect(enumerator.totalCount == 0)
        #expect(enumerator.path(at: 0) == nil)
    }

    @Test func testPathEnumerator_PathCountMap_MatchesOldSemantics() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)
        let enumerator = GamePathEnumerator(databaseView: view, prefix: [1])

        let map = enumerator.pathCountMap()
        #expect(map[1] == 2)  // 起点 = 总路径数
        #expect(map[2] == 1)
        #expect(map[3] == 1)
        #expect(map[4] == 1)  // 叶子计 1
        #expect(map[5] == 1)
    }

    @Test func testPathEnumerator_CycleSafety() {
        // 构造 1 → 2 → 1 的环：不应死循环，计数有限
        let data = DatabaseData()
        let fen1 = FenObject(fen: "cycle_fen_1", fenId: 1)
        let fen2 = FenObject(fen: "cycle_fen_2", fenId: 2)
        data.fenObjects2[1] = fen1
        data.fenObjects2[2] = fen2
        data.fenToId["cycle_fen_1"] = 1
        data.fenToId["cycle_fen_2"] = 2
        let m12 = Move(sourceFenId: 1, targetFenId: 2)
        let m21 = Move(sourceFenId: 2, targetFenId: 1)
        data.moveObjects[1] = m12
        data.moveObjects[2] = m21
        data.moveToId[[1, 2]] = 1
        data.moveToId[[2, 1]] = 2
        fen1.moves.append(m12)
        fen2.moves.append(m21)
        let view = DatabaseView.full(database: Database(testDatabaseData: data))

        let enumerator = GamePathEnumerator(databaseView: view, prefix: [1])
        #expect(enumerator.totalCount == 1)       // 1 → 2（2 的唯一子节点在环上，视为叶）
        #expect(enumerator.path(at: 0) == [1, 2]) // 走子终止于环入口
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
