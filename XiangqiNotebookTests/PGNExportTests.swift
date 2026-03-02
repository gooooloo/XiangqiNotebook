import Foundation
import Testing
@testable import XiangqiNotebook

struct PGNExportTests {

    // MARK: - PGNParser helper tests (preserved)

    @Test func testAppFenToPgnFen() {
        let appFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let pgnFen = PGNParser.appFenToPgnFen(appFen)
        #expect(pgnFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w")
    }

    @Test func testAppFenToPgnFenBlackTurn() {
        let appFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C2C1/9/RNBAKABNR b - - 1 1"
        let pgnFen = PGNParser.appFenToPgnFen(appFen)
        #expect(pgnFen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C2C1/9/RNBAKABNR b")
    }

    @Test func testPieceMoveToCoord() {
        let move = PieceMove(piece: "C", fromRow: 7, fromColumn: 7, toRow: 7, toColumn: 4)
        #expect(PGNParser.pieceMoveToCoord(move) == "h7e7")
    }

    @Test func testPieceMoveToCoordKnightMove() {
        let move = PieceMove(piece: "N", fromRow: 9, fromColumn: 7, toRow: 7, toColumn: 6)
        #expect(PGNParser.pieceMoveToCoord(move) == "h9g7")
    }

    @Test func testGameResultToPgnResult() {
        #expect(PGNParser.gameResultToPgnResult(.redWin) == "1-0")
        #expect(PGNParser.gameResultToPgnResult(.blackWin) == "0-1")
        #expect(PGNParser.gameResultToPgnResult(.draw) == "1/2-1/2")
        #expect(PGNParser.gameResultToPgnResult(.notFinished) == "*")
        #expect(PGNParser.gameResultToPgnResult(.unknown) == "*")
    }

    @Test func testFenRoundTrip() {
        let originalAppFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let pgnFen = PGNParser.appFenToPgnFen(originalAppFen)
        let roundTrippedAppFen = PGNParser.pgnFenToAppFen(pgnFen)
        #expect(roundTrippedAppFen == originalAppFen)
    }

    // MARK: - Export: Empty Database

    @Test func testExportEmptyDatabase() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)
        let exported = PGNExportService.exportPGN(databaseView: databaseView, rootFenId: 1)
        #expect(exported.isEmpty)
    }

    // MARK: - Export: Linear Path (root → A → B)

    @Test func testExportLinearPath() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)

        let pgn = """
        [Game "1"]
        [Red "A"]
        [Black "B"]
        [Result "*"]

        1. h2e2 h9g7 *
        """
        let result = PGNImportService.importPGN(content: pgn, username: "", databaseView: databaseView)
        #expect(result.imported == 1)

        let exported = PGNExportService.exportPGN(databaseView: databaseView, rootFenId: 1)
        #expect(!exported.isEmpty)

        // Verify minimal headers (no player names, no date)
        #expect(exported.contains("[Game \"1\"]"))
        #expect(exported.contains("[Result \"*\"]"))
        #expect(!exported.contains("[Red"))
        #expect(!exported.contains("[Black"))
        #expect(!exported.contains("[Date"))

        // Standard starting position: no FEN header
        #expect(!exported.contains("[FEN"))

        // Should contain movetext
        #expect(exported.contains("1."))
    }

    // MARK: - Export: Branching Tree (root → A → B, root → A → C)

    @Test func testExportBranchingTree() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)

        let pgn = """
        [Game "1"]
        [Red "A"]
        [Black "B"]
        [Result "*"]

        1. h2e2 h9g7 *

        [Game "2"]
        [Red "C"]
        [Black "D"]
        [Result "*"]

        1. h2e2 b9c7 *
        """
        let result = PGNImportService.importPGN(content: pgn, username: "", databaseView: databaseView)
        #expect(result.imported == 2)

        let exported = PGNExportService.exportPGN(databaseView: databaseView, rootFenId: 1)
        #expect(!exported.isEmpty)

        // Should produce 2 PGN games (2 distinct root-to-leaf paths)
        let games = exported.components(separatedBy: "\n\n")
        #expect(games.count == 2)

        #expect(exported.contains("[Game \"1\"]"))
        #expect(exported.contains("[Game \"2\"]"))
    }

    // MARK: - generateAllPaths Direct Tests

    @Test func testGenerateAllPathsEmpty() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)
        let paths = PGNExportService.generateAllPaths(databaseView: databaseView, rootFenId: 1)
        #expect(paths.isEmpty)
    }

    @Test func testGenerateAllPathsLinear() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)

        let pgn = """
        [Game "1"]
        [Result "*"]

        1. h2e2 h9g7 *
        """
        _ = PGNImportService.importPGN(content: pgn, username: "", databaseView: databaseView)

        let paths = PGNExportService.generateAllPaths(databaseView: databaseView, rootFenId: 1)
        #expect(paths.count == 1)
        #expect(paths[0].count == 3) // root + 2 moves = 3 fenIds
        #expect(paths[0].first == 1) // starts from root
    }

    @Test func testGenerateAllPathsBranching() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)

        let pgn = """
        [Game "1"]
        [Result "*"]

        1. h2e2 h9g7 *

        [Game "2"]
        [Result "*"]

        1. h2e2 b9c7 *
        """
        _ = PGNImportService.importPGN(content: pgn, username: "", databaseView: databaseView)

        let paths = PGNExportService.generateAllPaths(databaseView: databaseView, rootFenId: 1)
        #expect(paths.count == 2)
        #expect(paths[0][0] == paths[1][0]) // same root
        #expect(paths[0][1] == paths[1][1]) // same after first move
        #expect(paths[0][2] != paths[1][2]) // diverge at third
    }

    // MARK: - Red Opening View exports full tree

    @Test func testExportFromRedOpeningView() {
        let database = Database(testDatabaseData: DatabaseData())
        let fullView = DatabaseView.full(database: database)

        // Import a game to create tree structure
        let pgn = """
        [Game "1"]
        [Result "*"]

        1. h2e2 h9g7 *
        """
        let result = PGNImportService.importPGN(content: pgn, username: "", databaseView: fullView)
        #expect(result.imported == 1)

        // Find the root fenId (standard start)
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)
        guard let rootFenId = fullView.getIdForFen(startFen) else {
            #expect(Bool(false), "Standard start FEN should exist")
            return
        }

        // Mark b-turn positions (after red's move) as inRedOpening
        // so the red opening view tree is connected
        let allFenIds = fullView.getAllFenIds()
        for fenId in allFenIds {
            if let fenObj = fullView.getFenObject(fenId), fenObj.redJustPlayed {
                fenObj.setInRedOpening(true)
            }
        }

        let redView = DatabaseView.redOpening(database: database)
        let paths = PGNExportService.generateAllPaths(databaseView: redView, rootFenId: rootFenId)
        #expect(paths.count == 1)
        #expect(paths[0].count == 3)

        let exported = PGNExportService.exportPGN(databaseView: redView, rootFenId: rootFenId)
        #expect(!exported.isEmpty)
        #expect(exported.contains("1."))
    }

    // MARK: - Non-standard Starting FEN

    @Test func testExportWithCustomStartingFen() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)

        let customFen = normalizeFen("rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKAB1R r")
        let afterMoveFen = normalizeFen("rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABR1 b")

        let fenId1 = databaseView.ensureFenId(for: customFen)
        let fenId2 = databaseView.ensureFenId(for: afterMoveFen)
        let (move, _, _) = databaseView.ensureMove(from: fenId1, to: fenId2)
        if let fenObject = databaseView.getFenObject(fenId1) {
            _ = fenObject.addMoveIfNeeded(move: move)
        }

        // Export the path directly
        let pgn = PGNExportService.exportPath([fenId1, fenId2], gameNumber: 1, databaseView: databaseView)
        #expect(pgn != nil)
        #expect(pgn!.contains("[FEN"))
    }

    // MARK: - Single Node (root only, no moves)

    @Test func testExportSingleNodeReturnsEmpty() {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)
        let result = PGNExportService.exportPath([1], gameNumber: 1, databaseView: databaseView)
        #expect(result == nil)
    }

    // MARK: - Database without fenId=1

    @Test func testExportWithoutFenId1() {
        // Empty DatabaseData has no fenId=1
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)
        // DatabaseData() creates empty data with no fenObjects — fenId=1 doesn't exist
        // But DatabaseStorage.createEmptyDatabase() creates fenId=1
        // With empty DatabaseData, getFenObjectUnfiltered(1) returns nil → empty
        let exported = PGNExportService.exportPGN(databaseView: databaseView, rootFenId: 1)
        #expect(exported.isEmpty)
    }
}
