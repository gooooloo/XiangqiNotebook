import Foundation

enum GameResult: String, Codable, CaseIterable {
    case redWin = "红胜"
    case blackWin = "黑胜"
    case draw = "和棋"
    case notFinished = "未完"
    case unknown = "不知"
}

class GameObject: Identifiable, Codable {
    let id: UUID
    var name: String?
    var creationDate: Date?
    var gameDate: Date?
    var redPlayerName: String = ""
    var blackPlayerName: String = ""
    var iAmRed: Bool = false
    var iAmBlack: Bool = false
    var gameResult: GameResult = .unknown
    var startingFenId: Int?
    var moveIds: [Int] = []
    var isFullyRecorded: Bool = false

    // MARK: - Performance Optimization: Cached Set for O(1) lookup

    /// Cached Set for O(1) moveId lookup (not serialized, lazily initialized)
    private var moveIdSet: Set<Int>?

    /// Cached Set for O(1) fenId lookup (not serialized, lazily initialized)
    private var fenIdSet: Set<Int>?

    /// Check if a moveId exists in the game (O(1) lookup)
    func containsMoveId(_ moveId: Int) -> Bool {
        if moveIdSet == nil {
            moveIdSet = Set(moveIds)
        }
        return moveIdSet!.contains(moveId)
    }

    /// Check if a fenId exists in the game (O(1) lookup after initial build)
    /// This includes the starting position and all positions in moves
    func containsFenId(_ fenId: Int, moveObjects: [Int: Move]) -> Bool {
        // Check starting position first
        if startingFenId == fenId {
            return true
        }

        // Build fenIdSet lazily if needed
        if fenIdSet == nil {
            var fens = Set<Int>()
            for moveId in moveIds {
                if let move = moveObjects[moveId] {
                    fens.insert(move.sourceFenId)
                    if let targetFenId = move.targetFenId {
                        fens.insert(targetFenId)
                    }
                }
            }
            fenIdSet = fens
        }

        return fenIdSet!.contains(fenId)
    }

    /// Append a moveId to both the array and the cached Sets
    /// - Parameters:
    ///   - moveId: The move ID to append
    ///   - move: The move object for incremental fenIdSet update
    func appendMoveId(_ moveId: Int, move: Move) {
        moveIds.append(moveId)

        // Update moveIdSet if already initialized
        if moveIdSet != nil {
            moveIdSet!.insert(moveId)
        }

        // Incrementally update fenIdSet if already initialized
        if fenIdSet != nil {
            fenIdSet!.insert(move.sourceFenId)
            if let targetFenId = move.targetFenId {
                fenIdSet!.insert(targetFenId)
            }
        }
    }

    /// Remove a moveId from both the array and the cached Sets
    func removeMoveId(_ moveId: Int) {
        moveIds.removeAll { $0 == moveId }

        // Update moveIdSet if already initialized
        if moveIdSet != nil {
            moveIdSet!.remove(moveId)
        }

        // Invalidate fenIdSet as it needs full rebuild
        // (we can't safely remove fenIds as they might be referenced by other moves)
        fenIdSet = nil
    }

    /// 生成显示标题，用于棋局列表和窗口标题
    /// 如果有自定义名称则使用名称，否则根据对局双方和结果生成
    var displayTitle: String {
        if let name = name, !name.isEmpty {
            return name
        }
        let redName = iAmRed ? "我" : (redPlayerName.isEmpty ? "红方" : redPlayerName)
        let blackName = iAmBlack ? "我" : (blackPlayerName.isEmpty ? "黑方" : blackPlayerName)
        let separator: String
        if iAmRed || iAmBlack {
            switch gameResult {
            case .redWin:
                separator = "胜"
            case .blackWin:
                separator = "负"
            case .draw:
                separator = "和"
            case .notFinished, .unknown:
                separator = "vs"
            }
        } else {
            separator = "vs"
        }
        return "\(redName) \(separator) \(blackName)"
    }

    init(id: UUID) {
        self.id = id
    }

    // Custom Codable implementation for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, name, creationDate, gameDate
        case redPlayerName, blackPlayerName
        case iAmRed, iAmBlack
        case gameResult, startingFenId, moveIds
        case isFullyRecorded
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        gameDate = try container.decodeIfPresent(Date.self, forKey: .gameDate)
        redPlayerName = try container.decodeIfPresent(String.self, forKey: .redPlayerName) ?? ""
        blackPlayerName = try container.decodeIfPresent(String.self, forKey: .blackPlayerName) ?? ""
        iAmRed = try container.decodeIfPresent(Bool.self, forKey: .iAmRed) ?? false
        iAmBlack = try container.decodeIfPresent(Bool.self, forKey: .iAmBlack) ?? false
        gameResult = try container.decodeIfPresent(GameResult.self, forKey: .gameResult) ?? .unknown
        startingFenId = try container.decodeIfPresent(Int.self, forKey: .startingFenId)
        moveIds = try container.decodeIfPresent([Int].self, forKey: .moveIds) ?? []
        // Provide default value for backward compatibility
        isFullyRecorded = try container.decodeIfPresent(Bool.self, forKey: .isFullyRecorded) ?? false
    }
}

class BookObject: Identifiable, Codable {
    let id: UUID
    var name: String = ""
    var gameIds: [UUID] = []
    var subBookIds: [UUID] = []
    var author: String = ""
    
    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

class GameResultStatistics: Codable {
    var redWin: Int = 0
    var blackWin: Int = 0
    var draw: Int = 0
    var notFinished: Int = 0
    var unknown: Int = 0
}