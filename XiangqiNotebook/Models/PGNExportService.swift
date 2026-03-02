import Foundation

enum PGNExportService {

    /// Export all root-to-leaf paths in the DatabaseView tree as PGN games
    static func exportPGN(databaseView: DatabaseView, rootFenId: Int) -> String {
        let paths = generateAllPaths(databaseView: databaseView, rootFenId: rootFenId)
        var pgnStrings: [String] = []
        for (index, path) in paths.enumerated() {
            if let pgn = exportPath(path, gameNumber: index + 1, databaseView: databaseView) {
                pgnStrings.append(pgn)
            }
        }
        return pgnStrings.joined(separator: "\n\n")
    }

    /// DFS traversal of the DatabaseView tree, collecting all root-to-leaf paths as [[Int]]
    ///
    /// Uses `databaseView.moves(from:)` which enforces scope filtering (both source and target
    /// must be in scope). For opening views, this means only positions explicitly marked as
    /// belonging to the opening are traversed, keeping the export bounded.
    static func generateAllPaths(databaseView: DatabaseView, rootFenId: Int) -> [[Int]] {
        guard databaseView.containsFenId(rootFenId) else { return [] }

        var result: [[Int]] = []
        var stack: [(fenId: Int, path: [Int])] = [(rootFenId, [rootFenId])]

        while !stack.isEmpty {
            let (currentFenId, currentPath) = stack.removeLast()
            let moves = databaseView.moves(from: currentFenId)
            let validNextIds = moves.compactMap { move -> Int? in
                guard let targetFenId = move.targetFenId else { return nil }
                guard !currentPath.contains(targetFenId) else { return nil }
                return targetFenId
            }

            if validNextIds.isEmpty {
                if currentPath.count >= 2 {
                    result.append(currentPath)
                }
            } else {
                for nextFenId in validNextIds {
                    stack.append((nextFenId, currentPath + [nextFenId]))
                }
            }
        }

        return result
    }

    /// Convert a fenId path to a PGN string
    static func exportPath(_ path: [Int], gameNumber: Int, databaseView: DatabaseView) -> String? {
        guard path.count >= 2 else { return nil }

        // Convert consecutive FEN pairs to coordinate moves
        // Use getFenObjectUnfiltered since the path may include positions not in scope
        // (e.g., intermediate positions in opening views)
        var coordMoves: [String] = []
        for i in 0..<(path.count - 1) {
            guard let fenObj1 = databaseView.getFenObjectUnfiltered(path[i]),
                  let fenObj2 = databaseView.getFenObjectUnfiltered(path[i + 1]) else {
                return nil
            }
            guard let pieceMove = extractPieceMoveFromFens(fen1: fenObj1.fen, fen2: fenObj2.fen) else {
                return nil
            }
            coordMoves.append(PGNParser.pieceMoveToCoord(pieceMove))
        }

        // Build minimal headers
        var headers: [String] = []
        headers.append("[Game \"\(gameNumber)\"]")
        headers.append("[Result \"*\"]")

        // Add FEN header if starting position is non-standard
        if let startFenObj = databaseView.getFenObjectUnfiltered(path[0]) {
            let standardStartFen = normalizeFen(XiangqiBoardUtils.startFEN)
            if startFenObj.fen != standardStartFen {
                let pgnFen = PGNParser.appFenToPgnFen(startFenObj.fen)
                headers.append("[FEN \"\(pgnFen)\"]")
            }
        }

        // Build movetext
        var movetext = ""
        for i in 0..<coordMoves.count {
            if i % 2 == 0 {
                movetext += "\(i / 2 + 1). "
            }
            movetext += coordMoves[i]
            if i < coordMoves.count - 1 {
                movetext += " "
            }
        }
        movetext += " *"

        return headers.joined(separator: "\n") + "\n" + movetext
    }

    // MARK: - Private Helpers

    /// Extract PieceMove by comparing two FEN strings directly
    private static func extractPieceMoveFromFens(fen1: String, fen2: String) -> PieceMove? {
        let fenObj1 = FenObject(fen: fen1, fenId: 0)
        let fenObj2 = FenObject(fen: fen2, fenId: 1)
        let tempFenObjects: [Int: FenObject] = [0: fenObj1, 1: fenObj2]
        return Move.extractPieceMove(fenObjects2: tempFenObjects, from: 0, to: 1)
    }
}
