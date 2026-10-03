import Testing
import Foundation
@testable import XiangqiNotebook

/// 回答里变着的识别与起点推断。
///
/// 认错起点比认不出更糟：棋盘会摆出一个看似合理、实则不是模型所讲的局面，
/// 用户还看不出来。所以既要测「能认」，也要测「走不通就别认」。
struct AnswerVariationsTests {

    private static let start = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"

    private static func fen(after uciMoves: [String]) -> String {
        AnalysisToolbox.applyUCIMoves(fen: start, uciMoves: uciMoves).applied.last!.fen
    }

    // MARK: - 识别与走子

    @Test func testResolve_mapsOrderedRowsToPlies() {
        let markdown = "主变：\n1. 红炮二平五　黑马8进7\n2. 红马二进三　黑车9平8"
        let result = AnswerVariations.resolve(markdown: markdown, candidateFens: [Self.start], flipped: false)

        #expect(result.lines.count == 1)
        #expect(result.lines[0].startFen == Self.start)
        #expect(result.lines[0].plies.map(\.uci) == ["h2e2", "h9g7", "h0g2", "i9h9"])
        // 块 0 是「主变：」段落，编号项从块 1 开始
        #expect(result.rows[1] == AnswerVariations.Row(line: 0, firstPly: 0, tokens: ["红炮二平五", "黑马8进7"]))
        #expect(result.rows[2]?.firstPly == 2)
        #expect(result.rows[0] == nil)
    }

    @Test func testResolve_picksFirstCandidateThatPlaysThrough() {
        // 正在讨论的是炮二平五之后（黑走）的局面，但变着从开局走起——要落到第二个候选上
        let afterCannon = Self.fen(after: ["h2e2"])
        let result = AnswerVariations.resolve(
            markdown: "1. 炮二平五 马8进7", candidateFens: [afterCannon, Self.start], flipped: false)
        #expect(result.lines.first?.startFen == Self.start)
    }

    @Test func testResolve_unplayableGroupStaysText() {
        let result = AnswerVariations.resolve(
            markdown: "1. 炮二平五 炮二平五", candidateFens: [Self.start], flipped: false)
        #expect(result == .empty)
    }

    @Test func testResolve_rowsWithCommentaryAreNotVariations() {
        let result = AnswerVariations.resolve(
            markdown: "1. 炮二平五，抢占中路\n2. 马二进三", candidateFens: [Self.start], flipped: false)
        // 第一项夹了讲解，不算；第二项单独成组，从开局走得通
        #expect(result.rows[0] == nil)
        #expect(result.rows[1]?.tokens == ["马二进三"])
    }

    @Test func testResolve_laterGroupCanContinueFromEarlierLine() {
        let markdown = "1. 炮二平五 马8进7\n\n接着：\n\n1. 马二进三 车9平8"
        let result = AnswerVariations.resolve(markdown: markdown, candidateFens: [Self.start], flipped: false)
        #expect(result.lines.count == 2)
        #expect(result.lines[1].startFen == result.lines[0].plies.last?.fen)
    }

    @Test func testSide_readsPrefixThenNumeralStyle() {
        #expect(AnswerVariations.side(of: "黑炮二平五") == "black", "明写的红黑优先")
        #expect(AnswerVariations.side(of: "炮二平五") == "red")
        #expect(AnswerVariations.side(of: "炮2平5") == "black")
        #expect(AnswerVariations.side(of: "车９平６") == "black", "全角数字也算黑方")
    }

    @Test func testMoveText_stripsSideAndPunctuation() {
        #expect(AnswerVariations.moveText("红方炮二平五。") == "炮二平五")
        #expect(AnswerVariations.moveText("黑马8进7") == "马8进7")
    }

    // MARK: - 工具结果里的局面

    @Test func testFensInToolJSON_collectsNestedFens() {
        let afterCannon = Self.fen(after: ["h2e2"])
        let json = AnalysisToolbox.json([
            "startFen": Self.start,
            "steps": [["uci": "h2e2", "fen": afterCannon]],
            "fen": "不是局面",
        ])
        #expect(Set(AnswerVariations.fens(inToolJSON: json)) == [Self.start, afterCannon])
    }
}
