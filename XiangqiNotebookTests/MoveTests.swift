import Testing
import Foundation
@testable import XiangqiNotebook

struct MoveTests {
    
    @Test func testMoveInitialization() {
        let sourceFenId = 1
        let targetFenId = 2
        let move = Move(sourceFenId: sourceFenId, targetFenId: targetFenId)
        
        #expect(move.sourceFenId == sourceFenId)
        #expect(move.targetFenId == targetFenId)
        #expect(move.comment == nil)
        #expect(move.badReason == nil)
    }
    
    @Test func testMoveWithNilTarget() {
        let sourceFenId = 1
        let move = Move(sourceFenId: sourceFenId, targetFenId: nil)
        
        #expect(move.sourceFenId == sourceFenId)
        #expect(move.targetFenId == nil)
    }
    
    @Test func testMoveMarkAsRemoved() {
        let move = Move(sourceFenId: 1, targetFenId: 2)
        
        #expect(move.targetFenId == 2)
        
        move.markAsRemoved()
        #expect(move.targetFenId == nil)
    }
    
    @Test func testMoveIsRecommended() {
        let move = Move(sourceFenId: 1, targetFenId: 2)
        
        // 默认不推荐
        #expect(move.isRecommended == false)
        
        // 添加推荐标签
        move.comment = "这是一步#妙棋"
        #expect(move.isRecommended == true)
        
        move.comment = "#党大师推荐的走法"
        #expect(move.isRecommended == true)
        
        move.comment = "#飞刀战术"
        #expect(move.isRecommended == true)
        
        move.comment = "#重要的一步"
        #expect(move.isRecommended == true)
        
        // 普通评论不推荐
        move.comment = "普通的一步棋"
        #expect(move.isRecommended == false)
    }
    
    @Test func testMoveIsBad() {
        let move = Move(sourceFenId: 1, targetFenId: 2)
        
        // 模拟分数获取函数
        let getScore: (Int) -> Int? = { fenId in
            switch fenId {
            case 1: return 100  // 源局面分数
            case 2: return -50  // 目标局面分数
            default: return nil
            }
        }
        
        // 默认不是坏棋
        #expect(move.isBad(getScore) == false)
        
        // 添加坏棋标签
        move.comment = "这是一步#不好的棋"
        #expect(move.isBad(getScore) == true)
        
        move.comment = "#错误的走法"
        #expect(move.isBad(getScore) == true)
        
        move.comment = "中刀了"
        #expect(move.isBad(getScore) == true)
    }
    
    @Test func testMoveEncoding() throws {
        let sourceFenId = 1
        let targetFenId = 2
        let comment = "这是一步好棋"
        let badReason = "分析错误"
        
        let move = Move(sourceFenId: sourceFenId, targetFenId: targetFenId)
        move.comment = comment
        move.badReason = badReason
        
        // 编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(move)
        
        // 解码
        let decoder = JSONDecoder()
        let decodedMove = try decoder.decode(Move.self, from: data)
        
        // 验证
        #expect(decodedMove.sourceFenId == sourceFenId)
        #expect(decodedMove.targetFenId == targetFenId)
        #expect(decodedMove.comment == comment)
        #expect(decodedMove.badReason == badReason)
    }
    
    @Test func testMoveEncodingWithNilValues() throws {
        let move = Move(sourceFenId: 1, targetFenId: nil)
        
        // 编码
        let encoder = JSONEncoder()
        let data = try encoder.encode(move)
        
        // 解码
        let decoder = JSONDecoder()
        let decodedMove = try decoder.decode(Move.self, from: data)
        
        // 验证
        #expect(decodedMove.sourceFenId == 1)
        #expect(decodedMove.targetFenId == nil)
        #expect(decodedMove.comment == nil)
        #expect(decodedMove.badReason == nil)
    }
    
    @Test func testMoveHashable() {
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        let move2 = Move(sourceFenId: 1, targetFenId: 2)
        let move3 = Move(sourceFenId: 1, targetFenId: 3)
        
        // 测试相等性
        #expect(move1 == move2)
        #expect(move1 != move3)
        
        // 测试哈希
        let set: Set<Move> = [move1, move2, move3]
        #expect(set.count == 2) // move1和move2应该被认为是同一个
    }
    
} 