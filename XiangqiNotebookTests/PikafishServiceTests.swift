import Testing
import Foundation
@testable import XiangqiNotebook

#if os(macOS)
struct PikafishServiceTests {

    // MARK: - FEN Conversion Tests

    @Test func testConvertFenToUCI_redToMove() {
        let appFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        let uciFen = PikafishService.convertFenToUCI(appFen)
        #expect(uciFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1")
    }

    @Test func testConvertFenToUCI_blackToMove() {
        let appFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/4P4/P1P3P1P/1C5C1/9/RNBAKABNR b"
        let uciFen = PikafishService.convertFenToUCI(appFen)
        #expect(uciFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/4P4/P1P3P1P/1C5C1/9/RNBAKABNR b - - 0 1")
    }

    @Test func testConvertFenToUCI_alreadyFullFormat() {
        let appFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let uciFen = PikafishService.convertFenToUCI(appFen)
        #expect(uciFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 1 1")
    }

    @Test func testConvertFenToUCI_withDashSeparator() {
        // App sometimes uses "r - - 0 1" format with extra fields
        let appFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
        let uciFen = PikafishService.convertFenToUCI(appFen)
        #expect(uciFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1")
    }

    // MARK: - Score Parsing Tests

    @Test func testParseScore_centipawns() {
        let infoLine = "info depth 18 seldepth 22 multipv 1 score cp 35 nodes 123456 nps 1234567 time 100 pv e2e4"
        let score = PikafishService.parseScore(from: infoLine)
        #expect(score == 35)
    }

    @Test func testParseScore_negativeCentipawns() {
        let infoLine = "info depth 18 seldepth 20 multipv 1 score cp -42 nodes 234567 nps 2345678 time 100 pv d7d5"
        let score = PikafishService.parseScore(from: infoLine)
        #expect(score == -42)
    }

    @Test func testParseScore_mate() {
        let infoLine = "info depth 18 seldepth 5 multipv 1 score mate 3 nodes 5000 nps 500000 time 10 pv h2e2"
        let score = PikafishService.parseScore(from: infoLine)
        #expect(score == 30000 - 3)
    }

    @Test func testParseScore_negativeMate() {
        let infoLine = "info depth 18 seldepth 5 multipv 1 score mate -2 nodes 3000 nps 300000 time 10 pv a1a2"
        let score = PikafishService.parseScore(from: infoLine)
        #expect(score == -30000 - (-2))
    }

    @Test func testParseScore_noScoreInLine() {
        let infoLine = "info depth 18 seldepth 22 nodes 123456 nps 1234567 time 100"
        let score = PikafishService.parseScore(from: infoLine)
        #expect(score == nil)
    }

    @Test func testParseScore_zeroCentipawns() {
        let infoLine = "info depth 18 seldepth 20 multipv 1 score cp 0 nodes 100000 nps 1000000 time 100 pv e2e4"
        let score = PikafishService.parseScore(from: infoLine)
        #expect(score == 0)
    }

    // MARK: - Best Move Parsing Tests

    @Test func testParseBestMove_normal() {
        let response = "info depth 18 score cp 35 nodes 123456\nbestmove h2e2 ponder b9c7"
        let move = PikafishService.parseBestMove(from: response)
        #expect(move == "h2e2")
    }

    @Test func testParseBestMove_noPonder() {
        let response = "info depth 10 score cp 0\nbestmove e2e4"
        let move = PikafishService.parseBestMove(from: response)
        #expect(move == "e2e4")
    }

    @Test func testParseBestMove_none() {
        let response = "bestmove (none)"
        let move = PikafishService.parseBestMove(from: response)
        #expect(move == nil)
    }

    @Test func testParseBestMove_noLine() {
        let response = "info depth 18 score cp 35 nodes 123456"
        let move = PikafishService.parseBestMove(from: response)
        #expect(move == nil)
    }

    // MARK: - completedPortion（整行匹配）

    @Test func testCompletedPortion_keywordInCompleteLine() {
        let buffer = "info depth 18 score cp 35\nbestmove h2e2 ponder h9g7\n"
        let result = PikafishService.completedPortion(of: buffer, containing: "bestmove")
        #expect(result == buffer)
    }

    @Test func testCompletedPortion_truncatedLine_NotMatched() {
        // 管道半行送达："bestmove h2" 尚未换行，不应匹配
        let buffer = "info depth 18 score cp 35\nbestmove h2"
        let result = PikafishService.completedPortion(of: buffer, containing: "bestmove")
        #expect(result == nil)
    }

    @Test func testCompletedPortion_truncatedTailExcluded() {
        // 关键字行已完整，后续半行不包含在返回值中
        let buffer = "bestmove h2e2\ninfo dep"
        let result = PikafishService.completedPortion(of: buffer, containing: "bestmove")
        #expect(result == "bestmove h2e2\n")
    }

    @Test func testCompletedPortion_noNewline_ReturnsNil() {
        let result = PikafishService.completedPortion(of: "bestmove h2e2", containing: "bestmove")
        #expect(result == nil)
    }

    @Test func testCompletedPortion_keywordAbsent_ReturnsNil() {
        let result = PikafishService.completedPortion(of: "readyok\n", containing: "bestmove")
        #expect(result == nil)
    }
}
#endif

// MARK: - UCI Move to FEN Tests

struct UCIMoveToFenTests {

    @Test func testGetNewFenAfterUCIMove_initialPosition() {
        let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        // 红方炮二平五: h2e2
        let newFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: "h2e2", fen: fen)
        #expect(newFen != nil)
        // 炮从 h2 移到 e2，黑方走
        #expect(newFen!.hasSuffix(" b"))
        // 验证原位置 h2 不再有炮，目标位置 e2 有炮
        let pieces = XiangqiBoardUtils.fenToPiecesBySquare(newFen!)
        #expect(pieces["h2"] == nil)
        #expect(pieces["e2"] == "rC")
    }

    @Test func testGetNewFenAfterUCIMove_invalidLength() {
        let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        let result = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: "h2", fen: fen)
        #expect(result == nil)
    }

    @Test func testGetNewFenAfterUCIMove_noPieceAtSource() {
        let fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        // e5 is empty
        let result = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: "e5e4", fen: fen)
        #expect(result == nil)
    }

    // MARK: - MultiPV Parsing Tests

    @Test func testParsePVLines_keepsDeepestPerIndex() {
        let response = """
        info depth 10 seldepth 12 multipv 1 score cp 20 nodes 1000 time 50 pv h2e2 h9g7
        info depth 10 seldepth 12 multipv 2 score cp -5 nodes 1000 time 50 pv b2e2 b9c7
        info depth 12 seldepth 15 multipv 1 score cp 35 nodes 5000 time 120 pv h2e2 h9g7 b2c2
        info depth 12 seldepth 15 multipv 2 score cp -10 nodes 5000 time 120 pv b2e2 h9g7
        bestmove h2e2 ponder h9g7
        """
        let lines = PikafishService.parsePVLines(from: response)
        #expect(lines.count == 2)
        #expect(lines[0].multipv == 1)
        #expect(lines[0].scoreCp == 35)
        #expect(lines[0].depth == 12)
        #expect(lines[0].moves == ["h2e2", "h9g7", "b2c2"])
        #expect(lines[1].multipv == 2)
        #expect(lines[1].scoreCp == -10)
        #expect(lines[1].moves == ["b2e2", "h9g7"])
    }

    @Test func testParsePVLines_noMultipvToken_defaultsToIndex1() {
        let response = """
        info depth 8 seldepth 10 score cp 42 nodes 800 time 30 pv h2e2
        bestmove h2e2
        """
        let lines = PikafishService.parsePVLines(from: response)
        #expect(lines.count == 1)
        #expect(lines[0].multipv == 1)
        #expect(lines[0].scoreCp == 42)
        #expect(lines[0].moves == ["h2e2"])
    }

    @Test func testParsePVLines_mateScore() {
        let response = """
        info depth 15 seldepth 5 multipv 1 score mate 3 nodes 5000 time 10 pv h2e2 e9d9 e2d2
        bestmove h2e2
        """
        let lines = PikafishService.parsePVLines(from: response)
        #expect(lines.count == 1)
        #expect(lines[0].scoreCp == 30000 - 3)
    }

    @Test func testParsePVLines_ignoresLinesWithoutPV() {
        let response = """
        info depth 5 score cp 10 nodes 100 time 5
        info string NNUE evaluation enabled
        bestmove h2e2
        """
        let lines = PikafishService.parsePVLines(from: response)
        #expect(lines.isEmpty)
    }
}
