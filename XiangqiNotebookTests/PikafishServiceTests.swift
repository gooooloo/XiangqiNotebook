import Testing
import Foundation
@testable import XiangqiNotebook

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
}
