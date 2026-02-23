import Foundation

enum PGNImportService {

    /// Main entry point for PGN import
    static func importPGN(content: String, username: String, databaseView: DatabaseView) -> PGNImportResult {
        let games = PGNParser.parseFile(content)
        var result = PGNImportResult()
        result.totalParsed = games.count

        for game in games {
            let importResult = importSingleGame(game, username: username, databaseView: databaseView)
            switch importResult {
            case .importedMyRed:
                result.imported += 1
                result.redGameCount += 1
            case .importedMyBlack:
                result.imported += 1
                result.blackGameCount += 1
            case .importedOthers:
                result.imported += 1
                result.othersGameCount += 1
            case .duplicate:
                result.skippedDuplicate += 1
            case .error(let message):
                result.skippedError += 1
                result.errors.append(message)
            }
        }

        return result
    }

    private enum SingleImportResult {
        case importedMyRed
        case importedMyBlack
        case importedOthers
        case duplicate
        case error(String)
    }

    private static func importSingleGame(_ game: PGNGame, username: String, databaseView: DatabaseView) -> SingleImportResult {
        // Skip games with no moves
        if game.coordinateMoves.isEmpty {
            return .error("棋局无着法记录")
        }

        // Generate FEN sequence
        guard let fenSequence = PGNParser.generateFenSequence(game) else {
            let red = game.headers["Red"] ?? "?"
            let black = game.headers["Black"] ?? "?"
            return .error("\(red) vs \(black): 着法解析失败")
        }

        // Normalize orientation (mirror if needed based on red's first move column)
        let (normalizedFens, _) = PGNParser.normalizeGameOrientation(fenSequence, firstMoveCoord: game.coordinateMoves.first)

        // Determine if user played red or black
        let redPlayer = game.headers["Red"] ?? ""
        let blackPlayer = game.headers["Black"] ?? ""
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        let iAmRed = !trimmedUsername.isEmpty && redPlayer.caseInsensitiveCompare(trimmedUsername) == .orderedSame
        let iAmBlack = !trimmedUsername.isEmpty && blackPlayer.caseInsensitiveCompare(trimmedUsername) == .orderedSame

        let targetBookId: UUID
        if iAmRed {
            targetBookId = Session.myRealRedGameBookId
        } else if iAmBlack {
            targetBookId = Session.myRealBlackGameBookId
        } else {
            targetBookId = Session.othersRealGameBookId
        }

        // Check for duplicate
        if isDuplicate(fenSequence: normalizedFens, bookId: targetBookId, databaseView: databaseView) {
            return .duplicate
        }

        // Create FEN objects and moves
        var fenIds: [Int] = []
        for fen in normalizedFens {
            let fenId = databaseView.ensureFenId(for: fen)
            fenIds.append(fenId)
        }

        // Create moves and wire up FenObjects
        var moveIds: [Int] = []
        for i in 1..<fenIds.count {
            let (move, moveId, _) = databaseView.ensureMove(from: fenIds[i - 1], to: fenIds[i])
            moveIds.append(moveId)
            // Wire up the move to the source FenObject
            if let fenObject = databaseView.getFenObject(fenIds[i - 1]) {
                _ = fenObject.addMoveIfNeeded(move: move)
            }
        }

        // Create the game object
        let gameResult = PGNParser.parseResult(game.headers["Result"])
        let gameDate = PGNParser.parseDate(game.headers["Date"], time: game.headers["Time"])

        let gameId = databaseView.addGame(
            to: targetBookId,
            name: nil,
            redPlayerName: redPlayer,
            blackPlayerName: blackPlayer,
            gameDate: gameDate,
            gameResult: gameResult,
            iAmRed: iAmRed,
            iAmBlack: iAmBlack,
            startingFenId: fenIds.first,
            isFullyRecorded: true
        )

        // Set moveIds on the game object
        if let gameObject = databaseView.getGameObjectUnfiltered(gameId) {
            for moveId in moveIds {
                if let move = databaseView.move(id: moveId) {
                    gameObject.appendMoveId(moveId, move: move)
                }
            }
            databaseView.updateGameObject(gameId, gameObject: gameObject)
        }

        // Update statistics for each FEN position (only for my games)
        if iAmRed || iAmBlack {
            for fenId in fenIds {
                updateGameStatistics(fenId: fenId, iAmRed: iAmRed, gameResult: gameResult, databaseView: databaseView)
            }
        }

        if iAmRed {
            return .importedMyRed
        } else if iAmBlack {
            return .importedMyBlack
        } else {
            return .importedOthers
        }
    }

    /// Check if a game with identical FEN sequence already exists in the target book
    static func isDuplicate(fenSequence: [String], bookId: UUID, databaseView: DatabaseView) -> Bool {
        let existingGames = databaseView.getGamesInBookUnfiltered(bookId)

        for existingGame in existingGames {
            let existingFenSequence = reconstructFenSequence(game: existingGame, databaseView: databaseView)
            if existingFenSequence == fenSequence {
                return true
            }
        }
        return false
    }

    /// Reconstruct FEN sequence from a GameObject's startingFenId and moveIds
    static func reconstructFenSequence(game: GameObject, databaseView: DatabaseView) -> [String] {
        guard let startFenId = game.startingFenId,
              let startFenObj = databaseView.getFenObject(startFenId) else {
            return []
        }

        var fenSequence = [startFenObj.fen]

        for moveId in game.moveIds {
            guard let move = databaseView.move(id: moveId),
                  let targetFenId = move.targetFenId,
                  let targetFenObj = databaseView.getFenObject(targetFenId) else {
                break
            }
            fenSequence.append(targetFenObj.fen)
        }

        return fenSequence
    }

    /// Update game statistics for a FEN position (mirrors Session.updateMyRealGameStatistics)
    private static func updateGameStatistics(fenId: Int, iAmRed: Bool, gameResult: GameResult, databaseView: DatabaseView) {
        let dictionary = iAmRed ? databaseView.myRealRedGameStatisticsByFenId : databaseView.myRealBlackGameStatisticsByFenId

        let gameStatistics: GameResultStatistics = dictionary[fenId] ?? GameResultStatistics()

        switch gameResult {
        case .redWin:
            gameStatistics.redWin += 1
        case .blackWin:
            gameStatistics.blackWin += 1
        case .draw:
            gameStatistics.draw += 1
        case .notFinished:
            gameStatistics.notFinished += 1
        default:
            gameStatistics.unknown += 1
        }

        if iAmRed {
            databaseView.updateRedGameStatistics(for: fenId, statistics: gameStatistics)
        } else {
            databaseView.updateBlackGameStatistics(for: fenId, statistics: gameStatistics)
        }
    }
}
