import Foundation
import Testing
@testable import XiangqiNotebook

struct PGNImportTests {

    // MARK: - Coordinate Conversion

    @Test func testPgnCoordToAppCoord() {
        // PGN row 7 → app row 2 (9-7=2)
        #expect(PGNParser.pgnCoordToAppCoord("h7e7") == "h2e2")
        // PGN row 0 → app row 9 (9-0=9)
        #expect(PGNParser.pgnCoordToAppCoord("h0g2") == "h9g7")
        // PGN row 9 → app row 0 (9-9=0)
        #expect(PGNParser.pgnCoordToAppCoord("i9h9") == "i0h0")
        // PGN row 3 → app row 6 (9-3=6)
        #expect(PGNParser.pgnCoordToAppCoord("c3c4") == "c6c5")
    }

    // MARK: - FEN Conversion

    @Test func testPgnFenToAppFen() {
        let pgnFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"
        let appFen = PGNParser.pgnFenToAppFen(pgnFen)
        #expect(appFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1")
    }

    @Test func testPgnFenToAppFenBlackTurn() {
        let pgnFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b"
        let appFen = PGNParser.pgnFenToAppFen(pgnFen)
        #expect(appFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b - - 1 1")
    }

    // MARK: - Single Game Parsing

    @Test func testParseSingleGame() {
        let pgn = """
        [Game "Chinese Chess"]
        [Date "2026.02.21"]
        [Red "Player1"]
        [Black "Player2"]
        [Result "1-0"]
        [FEN "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"]

        1. h7e7 h0g2 2. h9g7 i0h0  1-0
        """
        let games = PGNParser.parseFile(pgn)
        #expect(games.count == 1)
        #expect(games[0].headers["Red"] == "Player1")
        #expect(games[0].headers["Black"] == "Player2")
        #expect(games[0].headers["Result"] == "1-0")
        #expect(games[0].coordinateMoves.count == 4)
        #expect(games[0].coordinateMoves[0] == "h7e7")
        #expect(games[0].coordinateMoves[1] == "h0g2")
        #expect(games[0].coordinateMoves[2] == "h9g7")
        #expect(games[0].coordinateMoves[3] == "i0h0")
    }

    // MARK: - Multi Game Parsing

    @Test func testParseMultipleGames() {
        let pgn = """
        [Game "Chinese Chess"]
        [Red "A"]
        [Black "B"]
        [Result "1-0"]
        [FEN "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"]

        1. h7e7 h0g2  1-0

        [Game "Chinese Chess"]
        [Red "C"]
        [Black "D"]
        [Result "0-1"]
        [FEN "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"]

        1. b7e7 h0g2  0-1
        """
        let games = PGNParser.parseFile(pgn)
        #expect(games.count == 2)
        #expect(games[0].headers["Red"] == "A")
        #expect(games[1].headers["Red"] == "C")
    }

    // MARK: - Game with no moves (forfeit/timeout)

    @Test func testParseGameWithNoMoves() {
        let pgn = """
        [Game "Chinese Chess"]
        [Red "Player1"]
        [Black "Player2"]
        [Result "0-1"]
        [FEN "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"]

        0-1
        """
        let games = PGNParser.parseFile(pgn)
        #expect(games.count == 1)
        #expect(games[0].coordinateMoves.isEmpty)
    }

    // MARK: - FEN Sequence Generation

    @Test func testGenerateFenSequence() {
        var game = PGNGame()
        game.startingFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"
        game.coordinateMoves = ["h7e7"]  // Red cannon h7→e7 (PGN coords), app: h2→e2

        let fens = PGNParser.generateFenSequence(game)
        #expect(fens != nil)
        #expect(fens!.count == 2)
        // Starting FEN should be the standard normalized one
        let startFen = normalizeFen("rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r")
        #expect(fens![0] == startFen)
        // After the cannon move, black's turn
        #expect(fens![1].contains(" b "))
        // After h2→e2, cannon moved from h to e column, b column cannon stays
        // Row 2 in app = FEN row index 7: 1C3C3 (a=empty, b=C, c-e=empty, e... wait)
        // Let's just verify the FEN is valid by checking it can be parsed
        let pieces = XiangqiBoardUtils.fenToPiecesBySquare(fens![1])
        #expect(pieces["e2"] == "rC")  // Red cannon now at e2
        #expect(pieces["b2"] == "rC")  // Red cannon still at b2
        #expect(pieces["h2"] == nil)   // No cannon at h2 anymore
    }

    @Test func testGenerateFenSequenceInvalidMove() {
        var game = PGNGame()
        game.startingFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"
        game.coordinateMoves = ["a0a1"]  // Invalid: no piece at a0 in PGN = a9 in app (there is a piece there actually)

        // Let's use a truly invalid move - moving from an empty square
        var game2 = PGNGame()
        game2.startingFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"
        game2.coordinateMoves = ["e5e6"]  // e5 in PGN = e4 in app, which is empty

        let fens = PGNParser.generateFenSequence(game2)
        #expect(fens == nil)
    }

    // MARK: - Mirror FEN

    @Test func testMirrorFen() {
        // Standard starting position is symmetric, so mirror should equal original
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let mirrored = PGNParser.mirrorFen(startFen)
        #expect(mirrored == startFen)
    }

    @Test func testMirrorFenAsymmetric() {
        // Start from standard position, move red cannon h2→e2
        // This gives cannons at b2 and e2
        let startPieces = XiangqiBoardUtils.fenToPiecesBySquare(XiangqiBoardUtils.startFEN)
        let fenAfterMove = XiangqiBoardUtils.getNewFenAfterMove(from: "h2", to: "e2", currentPieces: startPieces)!
        let fen = normalizeFen(fenAfterMove)

        let mirrored = PGNParser.mirrorFen(fen)
        // Original: cannons at b2 and e2
        // Mirrored: b→h, e→e → cannons at h2 and e2
        let mirroredPieces = XiangqiBoardUtils.fenToPiecesBySquare(mirrored)
        #expect(mirroredPieces["h2"] == "rC")  // b2 mirrored to h2
        #expect(mirroredPieces["e2"] == "rC")  // e2 stays (center column)
        #expect(mirroredPieces["b2"] == nil)    // b2 no longer has cannon

        // The mirrored FEN should be different from the original
        #expect(mirrored != fen)
    }

    // MARK: - Normalize Game Orientation

    @Test func testNormalizeCannonRightSideStandard() {
        // 炮二平五: right cannon h2→e2 (PGN: h7e7) → standard, no mirror
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "h7e7")
        #expect(!wasMirrored)
    }

    @Test func testNormalizeCannonLeftSideNeedsMirror() {
        // 炮八平五: left cannon b2→e2 (PGN: b7e7) → non-standard, needs mirror
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "b7e7")
        #expect(wasMirrored)
    }

    @Test func testNormalizeRookLeftSideNeedsMirror() {
        // 九路车: left rook a0 (PGN: a9) → non-standard
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "a9a8")
        #expect(wasMirrored)
    }

    @Test func testNormalizeRookRightSideStandard() {
        // 一路车: right rook i0 (PGN: i9) → standard
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "i9i8")
        #expect(!wasMirrored)
    }

    @Test func testNormalizeKnightLeftSideStandard() {
        // 马八进七: left knight b0→c2 (PGN: b9c7) → standard for knight!
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "b9c7")
        #expect(!wasMirrored)
    }

    @Test func testNormalizeKnightRightSideNeedsMirror() {
        // 马二进三: right knight h0→g2 (PGN: h9g7) → non-standard for knight, needs mirror
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "h9g7")
        #expect(wasMirrored)
    }

    @Test func testNormalizePawnLeftSideStandard() {
        // 兵七进一: left pawn c3→c4 (PGN: c6c5) → standard for pawn
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "c6c5")
        #expect(!wasMirrored)
    }

    @Test func testNormalizePawnRightSideNeedsMirror() {
        // 兵三进一: right pawn g3→g4 (PGN: g6g5) → non-standard for pawn, needs mirror
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        let fens = [startFen]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: "g6g5")
        #expect(wasMirrored)
    }

    @Test func testNormalizeNoMoves() {
        let fens = [normalizeFen(XiangqiBoardUtils.startFEN)]
        let (_, wasMirrored) = PGNParser.normalizeGameOrientation(fens, firstMoveCoord: nil)
        #expect(!wasMirrored)
    }

    // MARK: - Result Parsing

    @Test func testParseResult() {
        #expect(PGNParser.parseResult("1-0") == .redWin)
        #expect(PGNParser.parseResult("0-1") == .blackWin)
        #expect(PGNParser.parseResult("1/2-1/2") == .draw)
        #expect(PGNParser.parseResult("*") == .unknown)
        #expect(PGNParser.parseResult(nil) == .unknown)
    }

    // MARK: - Date Parsing

    @Test func testParseDate() {
        let date = PGNParser.parseDate("2026.02.21")
        let calendar = Calendar.current
        #expect(calendar.component(.year, from: date) == 2026)
        #expect(calendar.component(.month, from: date) == 2)
        #expect(calendar.component(.day, from: date) == 21)
    }

    @Test func testParseDateNil() {
        // Should return current date (just verify it doesn't crash)
        let date = PGNParser.parseDate(nil)
        #expect(date.timeIntervalSinceNow < 1)
    }

    // MARK: - Full Pipeline Test

    @Test func testFullPipelineFromPGN() {
        let pgn = """
        [Game "Chinese Chess"]
        [Red "gooooloo"]
        [Black "Opponent"]
        [Result "1-0"]
        [FEN "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w"]

        1. h7e7 h0g2  1-0
        """
        let games = PGNParser.parseFile(pgn)
        #expect(games.count == 1)

        let fenSequence = PGNParser.generateFenSequence(games[0])
        #expect(fenSequence != nil)
        #expect(fenSequence!.count == 3) // start + 2 moves

        let (normalizedFens, wasMirrored) = PGNParser.normalizeGameOrientation(fenSequence!, firstMoveCoord: games[0].coordinateMoves.first)
        #expect(normalizedFens.count == 3)
        // h7e7 starts from column h (right side) → no mirror needed
        #expect(!wasMirrored)
    }
}
