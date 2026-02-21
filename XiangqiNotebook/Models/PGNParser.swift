import Foundation

// MARK: - Data Structures

struct PGNGame {
    var headers: [String: String] = [:]
    var coordinateMoves: [String] = []  // e.g., ["h2e2", "h9g7", ...]
    var startingFen: String?
}

struct PGNImportResult {
    var totalParsed: Int = 0
    var imported: Int = 0
    var skippedDuplicate: Int = 0
    var skippedError: Int = 0
    var redGameCount: Int = 0
    var blackGameCount: Int = 0
    var errors: [String] = []
}

// MARK: - PGN Parser

enum PGNParser {

    // MARK: - File Parsing

    /// Parse a PGN file containing one or more games
    static func parseFile(_ content: String) -> [PGNGame] {
        var games: [PGNGame] = []
        var currentGame: PGNGame? = nil

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                // Header line
                if let (key, value) = parseHeader(trimmed) {
                    if key == "Game" || key == "Event" {
                        // Start of a new game — save previous if exists
                        if let game = currentGame {
                            games.append(game)
                        }
                        currentGame = PGNGame()
                    }
                    if currentGame == nil {
                        currentGame = PGNGame()
                    }
                    if key == "FEN" {
                        currentGame?.startingFen = value
                    }
                    currentGame?.headers[key] = value
                }
            } else {
                // Move line
                if currentGame == nil {
                    currentGame = PGNGame()
                }
                let moves = parseMoves(trimmed)
                currentGame?.coordinateMoves.append(contentsOf: moves)
            }
        }

        // Don't forget the last game
        if let game = currentGame {
            games.append(game)
        }

        return games
    }

    /// Parse a header line like `[Red "gooooloo"]`
    private static func parseHeader(_ line: String) -> (String, String)? {
        // Remove [ and ]
        let inner = String(line.dropFirst().dropLast())
        // Find the first space
        guard let spaceIndex = inner.firstIndex(of: " ") else { return nil }
        let key = String(inner[inner.startIndex..<spaceIndex])
        var value = String(inner[inner.index(after: spaceIndex)...])
        // Remove quotes
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (key, value)
    }

    /// Parse moves from a line like "1. h7e7 h0g2 2. h9g7 i0h0 ... 0-1"
    private static func parseMoves(_ line: String) -> [String] {
        var moves: [String] = []
        let tokens = line.split(separator: " ")

        for token in tokens {
            let t = String(token)
            // Skip move numbers (e.g., "1.", "23.")
            if t.hasSuffix(".") { continue }
            // Skip result indicators
            if t == "1-0" || t == "0-1" || t == "1/2-1/2" || t == "*" { continue }
            // A valid coordinate move is 4 characters: column+row+column+row
            if t.count == 4, isCoordinateMove(t) {
                moves.append(t)
            }
        }

        return moves
    }

    /// Check if a string looks like a coordinate move (e.g., "h7e7")
    private static func isCoordinateMove(_ s: String) -> Bool {
        let chars = Array(s)
        guard chars.count == 4 else { return false }
        let validCols: Set<Character> = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
        return validCols.contains(chars[0]) && chars[1].isNumber
            && validCols.contains(chars[2]) && chars[3].isNumber
    }

    // MARK: - Coordinate Conversion

    /// Convert PGN coordinate to app coordinate
    /// PGN: row 0 = top (black side), App: row 0 = bottom (red side)
    /// Conversion: app_row = 9 - pgn_row
    static func pgnCoordToAppCoord(_ coord: String) -> String {
        let chars = Array(coord)
        guard chars.count == 4,
              let fromRow = Int(String(chars[1])),
              let toRow = Int(String(chars[3])) else {
            return coord
        }
        let fromCol = chars[0]
        let toCol = chars[2]
        let appFromRow = 9 - fromRow
        let appToRow = 9 - toRow
        return "\(fromCol)\(appFromRow)\(toCol)\(appToRow)"
    }

    // MARK: - FEN Conversion

    /// Convert PGN FEN to app FEN format
    /// PGN uses "w" for red's turn, app uses "r"
    static func pgnFenToAppFen(_ fen: String) -> String {
        let parts = fen.split(separator: " ", maxSplits: 1)
        guard parts.count >= 1 else { return fen }
        let boardPart = String(parts[0])
        var turnPart = parts.count > 1 ? String(parts[1]) : "r"

        // Convert "w" to "r" for red's turn
        if turnPart.hasPrefix("w") {
            turnPart = "r" + turnPart.dropFirst()
        }

        let rawFen = boardPart + " " + turnPart
        return normalizeFen(rawFen)
    }

    // MARK: - FEN Sequence Generation

    /// Generate a sequence of FEN strings from a PGN game
    /// Returns nil if any move is invalid
    static func generateFenSequence(_ game: PGNGame) -> [String]? {
        let startingFen: String
        if let pgnFen = game.startingFen {
            startingFen = pgnFenToAppFen(pgnFen)
        } else {
            startingFen = normalizeFen(XiangqiBoardUtils.startFEN)
        }

        var fenSequence = [startingFen]
        var currentPieces = XiangqiBoardUtils.fenToPiecesBySquare(startingFen)

        for pgnMove in game.coordinateMoves {
            let appMove = pgnCoordToAppCoord(pgnMove)
            let fromSquare = String(appMove.prefix(2))
            let toSquare = String(appMove.suffix(2))

            guard let newFen = XiangqiBoardUtils.getNewFenAfterMove(
                from: fromSquare, to: toSquare, currentPieces: currentPieces
            ) else {
                return nil
            }

            let normalizedFen = normalizeFen(newFen)
            fenSequence.append(normalizedFen)
            currentPieces = XiangqiBoardUtils.fenToPiecesBySquare(normalizedFen)
        }

        return fenSequence
    }

    // MARK: - Mirror / Normalization

    /// Mirror a FEN string left-right (column a↔i, b↔h, c↔g, d↔f, e stays)
    static func mirrorFen(_ fen: String) -> String {
        let pieces = XiangqiBoardUtils.fenToPiecesBySquare(fen)
        let columnMirror: [Character: Character] = [
            "a": "i", "b": "h", "c": "g", "d": "f", "e": "e",
            "f": "d", "g": "c", "h": "b", "i": "a"
        ]

        var mirroredPieces: [String: String] = [:]
        for (square, piece) in pieces {
            let chars = Array(square)
            guard chars.count == 2,
                  let mirroredCol = columnMirror[chars[0]] else { continue }
            let mirroredSquare = String(mirroredCol) + String(chars[1])
            mirroredPieces[mirroredSquare] = piece
        }

        // Determine current turn from FEN
        let parts = fen.split(separator: " ")
        let turn = parts.count > 1 ? String(parts[1]) : "r"

        let mirroredFenRaw = XiangqiBoardUtils.piecesBySquareToFen(mirroredPieces, currentTurn: turn)
        return normalizeFen(mirroredFenRaw)
    }

    /// Normalize game orientation based on red's first move.
    ///
    /// Standard convention (no mirror needed):
    /// - 车(R), 炮(C), 相(B), 仕(A): first move from right side (columns e-i, 一二三四五路)
    /// - 马(N): standard is 八路马 (column b), so first move from left side (a-d)
    /// - 兵(P): standard is 七路兵 (column c), so first move from left side (a-d)
    ///
    /// Non-standard (needs mirror):
    /// - 车(R), 炮(C), 相(B), 仕(A): first move from left side (columns a-d, 六七八九路)
    /// - 马(N): first move from right side (columns e-i, 二路马)
    /// - 兵(P): first move from right side (columns e-i, 三路兵)
    static func normalizeGameOrientation(_ fenSequence: [String], firstMoveCoord: String?) -> (fens: [String], wasMirrored: Bool) {
        guard let firstMove = firstMoveCoord, !firstMove.isEmpty,
              let startingFen = fenSequence.first else {
            return (fenSequence, false)
        }

        // Determine the from-square in app coordinates
        let appMove = pgnCoordToAppCoord(firstMove)
        let fromSquare = String(appMove.prefix(2))

        // Find what piece is on that square
        let pieces = XiangqiBoardUtils.fenToPiecesBySquare(startingFen)
        guard let piece = pieces[fromSquare] else {
            return (fenSequence, false)
        }

        let fromColumn = firstMove.first!  // Column letters are the same in PGN and app
        let leftSideColumns: Set<Character> = ["a", "b", "c", "d"]
        let isFromLeftSide = leftSideColumns.contains(fromColumn)

        // Piece type is the second character (e.g., "rN" → "N", "rP" → "P")
        let pieceType = piece.last!

        let needsMirror: Bool
        if pieceType == "N" || pieceType == "P" {
            // 马 and 兵: standard is on the LEFT side (八路马 at b, 七路兵 at c)
            // Non-standard (needs mirror) is on the RIGHT side
            needsMirror = !isFromLeftSide
        } else {
            // 车, 炮, 相, 仕: standard is on the RIGHT side
            // Non-standard (needs mirror) is on the LEFT side
            needsMirror = isFromLeftSide
        }

        if needsMirror {
            let mirroredFens = fenSequence.map { mirrorFen($0) }
            return (mirroredFens, true)
        }

        return (fenSequence, false)
    }

    // MARK: - Result Parsing

    /// Parse PGN result string to GameResult
    static func parseResult(_ result: String?) -> GameResult {
        switch result {
        case "1-0": return .redWin
        case "0-1": return .blackWin
        case "1/2-1/2": return .draw
        default: return .unknown
        }
    }

    /// Parse PGN date string "2026.02.21" to Date
    static func parseDate(_ dateString: String?) -> Date {
        guard let dateString = dateString else { return Date() }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.date(from: dateString) ?? Date()
    }
}
