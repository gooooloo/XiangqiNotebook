import Testing
import Foundation
@testable import XiangqiNotebook

struct FenObjectTests {
    
    @Test func testFenObjectInitialization() {
        let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
        let fenId = 1
        let fenObject = FenObject(fen: fen, fenId: fenId)
        
        #expect(fenObject.fen == fen)
        #expect(fenObject.fenId == fenId)
        #expect(fenObject.moves.isEmpty)
        #expect(fenObject.score == nil)
        #expect(fenObject.comment == nil)
        #expect(fenObject.lastMoveFenId == nil)
    }
    
    @Test func testFenObjectProperties() {
        let redToMoveFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
        let blackToMoveFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 0 1"
        
        let redFenObject = FenObject(fen: redToMoveFen, fenId: 1)
        let blackFenObject = FenObject(fen: blackToMoveFen, fenId: 2)
        
        // 测试红方轮次 (r表示红方轮次，意味着黑方刚下完)
        #expect(redFenObject.blackJustPlayed == true)
        #expect(redFenObject.redJustPlayed == false)
        
        // 测试黑方轮次 (b表示黑方轮次，意味着红方刚下完)
        #expect(blackFenObject.blackJustPlayed == false)
        #expect(blackFenObject.redJustPlayed == true)
    }
    
    @Test func testFenObjectOpeningProperties() {
        let redToMoveFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
        let fenObject = FenObject(fen: redToMoveFen, fenId: 1)
        
        // 红方轮次时的开局属性 (r表示红方轮次，黑方刚下完)
        // blackJustPlayed = true, redJustPlayed = false
        // isAutoInBlackOpening = redJustPlayed = false
        // isAutoInRedOpening = blackJustPlayed = true
        #expect(fenObject.isAutoInBlackOpening == false)
        #expect(fenObject.isAutoInRedOpening == true)
        #expect(fenObject.canChangeInRedOpening == false)
        #expect(fenObject.canChangeInBlackOpening == true)
        
        // 设置开局标记
        fenObject.setInRedOpening(true)
        fenObject.setInBlackOpening(false)
        
        #expect(fenObject.isInRedOpening == true) // isAutoInRedOpening || inRedOpening = true || true = true
        #expect(fenObject.isInBlackOpening == false) // isAutoInBlackOpening || inBlackOpening = false || false = false
    }
    
    @Test func testFenObjectMoveManagement() {
        let sourceFenObject = FenObject(fen: "startFen", fenId: 1)
        let targetFenObject = FenObject(fen: "targetFen", fenId: 2)
        
        let move = Move(sourceFenId: 1, targetFenId: 2)
        
        // 添加移动
        sourceFenObject.addMoveIfNeeded(move: move)
        #expect(sourceFenObject.moves.count == 1)
        
        // 查找移动
        let foundMove = sourceFenObject.findMove(targetFenId: 2, fenIdFilter: { _ in true })
        #expect(foundMove != nil)
        #expect(foundMove?.targetFenId == 2)
        
        // 标记最后移动
        sourceFenObject.markLastMove(fenId: 2)
        #expect(sourceFenObject.lastMoveFenId == 2)
        
        // 移除移动
        sourceFenObject.removeMove(targetFenId: 2)
        #expect(sourceFenObject.lastMoveFenId == nil)
    }
    
    @Test func testFenObjectPracticeCount() {
        let fenObject = FenObject(fen: "testFen", fenId: 1)
        
        #expect(fenObject.practiceCount == 0)
        
        fenObject.incrementPracticeCount()
        #expect(fenObject.practiceCount == 1)
        
        fenObject.incrementPracticeCount()
        #expect(fenObject.practiceCount == 2)
    }
    
    @Test func testFenObjectEncoding() throws {
        let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
        let fenObject = FenObject(fen: fen, fenId: 1)

        fenObject.score = 100
        fenObject.comment = "测试局面"
        fenObject.lastMoveFenId = 2
        fenObject.setInRedOpening(true)
        fenObject.setInBlackOpening(false)

        // 编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(fenObject)

        // 解码
        let decoder = JSONDecoder()
        let decodedObject = try decoder.decode(FenObject.self, from: data)

        // 验证基本属性
        #expect(decodedObject.fen == fen)
        #expect(decodedObject.score == 100)
        #expect(decodedObject.comment == "测试局面")
        #expect(decodedObject.lastMoveFenId == 2)
        #expect(decodedObject.inRedOpening == true)
        #expect(decodedObject.inBlackOpening == false)

        // 验证 engineScore 不再在 FenObject 中（已独立到 EngineScoreData）

        // 验证moves数组为空（不在JSON中编码）
        #expect(decodedObject.moves.isEmpty)
    }

    @Test func testFenObjectEncodingBackwardCompatibility() throws {
        // 验证旧格式的 JSON（包含 engine_score/engine_version）仍然可以正常解码
        let json = """
        {
            "fen": "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1",
            "score": 50,
            "engine_score": 42,
            "engine_version": "pikafish-2024.12"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let decodedObject = try decoder.decode(FenObject.self, from: data)

        // 旧字段被忽略（不会报错），基本属性正常
        #expect(decodedObject.score == 50)
        #expect(decodedObject.fen.contains("rnbakabnr"))
    }
    
} 
