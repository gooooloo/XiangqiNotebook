import Testing
@testable import XiangqiNotebook

struct XiangqiNotebookTests {

    @Test func testBasicFunctionality() async throws {
        // 测试基本的FenObject和Move交互
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
        let fenObject = FenObject(fen: startFen, fenId: 1)
        
        // 验证初始状态
        #expect(fenObject.moves.isEmpty)
        #expect(fenObject.practiceCount == 0)
        
        // 添加一个移动
        let move = Move(sourceFenId: 1, targetFenId: 2)
        move.comment = "测试移动"
        fenObject.addMoveIfNeeded(move: move)
        
        // 验证移动已添加
        #expect(fenObject.moves.count == 1)
        #expect(fenObject.moves.first?.comment == "测试移动")
        
        // 测试练习计数
        fenObject.incrementPracticeCount()
        #expect(fenObject.practiceCount == 1)
    }

}
