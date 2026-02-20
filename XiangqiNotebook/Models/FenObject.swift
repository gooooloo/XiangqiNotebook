import Foundation

class FenObject: Codable {
    
    // MARK: - Properties
    let fen: String
    var fenId: Int?
    var moves: [Move]
    var score: Int?
    var comment: String?
    var lastMoveFenId: Int?
    var inBlackOpening: Bool?
    var inRedOpening: Bool?
    var pathGroups: [PathGroup]?
    var _practiceCount: Int?

    // MARK: - Coding Keys
    enum CodingKeys: String, CodingKey {
        // case fenId is not encoded
        // case moves is not encoded
        case fen
        case score
        case comment
        case lastMoveFenId = "last_move_fen_id"
        case inBlackOpening = "in_black_opening"
        case inRedOpening = "in_red_opening"
        case pathGroups = "path_groups"
        case _practiceCount = "practice_count"
    }
    
    // MARK: - Initialization
    init(fen: String, fenId: Int) {
        self.fen = fen
        self.fenId = fenId
        self.moves = []
        self.pathGroups = nil
        self._practiceCount = nil
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
        self.fen = try container.decode(String.self, forKey: .fen)
        self.inBlackOpening = try container.decodeIfPresent(Bool.self, forKey: .inBlackOpening)
        self.inRedOpening = try container.decodeIfPresent(Bool.self, forKey: .inRedOpening)
        self.lastMoveFenId = try container.decodeIfPresent(Int.self, forKey: .lastMoveFenId)
        self.score = try container.decodeIfPresent(Int.self, forKey: .score)
        self.pathGroups = try container.decodeIfPresent([PathGroup].self, forKey: .pathGroups)
        self._practiceCount = try container.decodeIfPresent(Int.self, forKey: ._practiceCount)
        // we don't have fenId in JSON
        // we don't have moves in JSON
        self.moves = []
    }
  
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(fen, forKey: .fen)
        try container.encodeIfPresent(inBlackOpening, forKey: .inBlackOpening)
        try container.encodeIfPresent(inRedOpening, forKey: .inRedOpening)
        try container.encodeIfPresent(lastMoveFenId, forKey: .lastMoveFenId)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encodeIfPresent(pathGroups, forKey: .pathGroups)
        try container.encodeIfPresent(_practiceCount, forKey: ._practiceCount)
        // we don't have fenId in JSON
        // we don't have moves in JSON
    }

    // MARK: - Computed Properties
    var blackJustPlayed: Bool {
        fen.split(separator: " ").count > 1 && fen.split(separator: " ")[1] == "r"
    }
    
    var redJustPlayed: Bool {
        fen.split(separator: " ").count > 1 && fen.split(separator: " ")[1] == "b"
    }
    
    // 黑方开局需要知道如何应对红方
    var isAutoInBlackOpening: Bool {
        redJustPlayed
    }
    
    // 红方开局需要知道如何应对黑方
    var isAutoInRedOpening: Bool {
        blackJustPlayed
    }
    
    var canChangeInRedOpening: Bool {
        !isAutoInRedOpening
    }
    
    var canChangeInBlackOpening: Bool {
        !isAutoInBlackOpening
    }
    
    var isInRedOpening: Bool {
        isAutoInRedOpening || inRedOpening == true
    }
    
    var isInBlackOpening: Bool {
        isAutoInBlackOpening || inBlackOpening == true
    }

    var practiceCount: Int {
        _practiceCount ?? 0
    }
    
    // MARK: - Methods
    func setFenId(_ fenId: Int) {
      self.fenId = fenId
    }
  
    func setInRedOpening(_ value: Bool) {
        inRedOpening = value
    }
    
    func setInBlackOpening(_ value: Bool) {
        inBlackOpening = value
    }

    func incrementPracticeCount() {
        _practiceCount = (_practiceCount ?? 0) + 1
    }
    
    func findFirstMove(fenIdFilter: ((Int) -> Bool)? = nil) -> Move? {
        let filter = fenIdFilter ?? { _ in true }
        return moves.first { move in
            guard let targetFenId = move.targetFenId else { return false }
            return filter(targetFenId)
        }
    }
    
    func findLastMove(fenIdFilter: ((Int) -> Bool)? = nil) -> Move? {
        let filter = fenIdFilter ?? { _ in true }
        return moves.last { move in
            guard let targetFenId = move.targetFenId else { return false }
            return filter(targetFenId)
        }
    }
    
    func findPreviousMove(fenId: Int, fenIdFilter: ((Int) -> Bool)? = nil) -> Move? {
        let filter = fenIdFilter ?? { _ in true }
        guard let currentIndex = moves.firstIndex(where: { $0.targetFenId == fenId }) else {
            return nil
        }
        
        for index in (0..<currentIndex).reversed() {
            if let targetFenId = moves[index].targetFenId, filter(targetFenId) {
                return moves[index]
            }
        }
        return nil
    }
    
    func findNextMove(fenId: Int, fenIdFilter: ((Int) -> Bool)? = nil) -> Move? {
        let filter = fenIdFilter ?? { _ in true }
        guard let currentIndex = moves.firstIndex(where: { $0.targetFenId == fenId }) else {
            return nil
        }
        
        for index in (currentIndex + 1)..<moves.count {
            if let targetFenId = moves[index].targetFenId, filter(targetFenId) {
                return moves[index]
            }
        }
        return nil
    }
    
    func getMoves(fenIdFilter: ((Int) -> Bool)? = nil) -> [Move] {
        let filter = fenIdFilter ?? { _ in true }
        return moves.compactMap { move in
            guard move.targetFenId != nil else {
                return nil
            }
            return filter(move.targetFenId!) ? move : nil
        }
    }
    
    func findMove(targetFenId: Int, fenIdFilter: ((Int) -> Bool)) -> Move? {
        return moves.compactMap { $0 }.first { move in
            move.targetFenId != nil &&
            move.targetFenId == targetFenId &&
            fenIdFilter(move.targetFenId!)
        }
    }
    
    func removeMove(targetFenId: Int) {
        if let move = findMove(targetFenId: targetFenId, fenIdFilter: { _ in true}){
            move.markAsRemoved()
        }
        
        if lastMoveFenId == targetFenId {
            lastMoveFenId = nil
        }
    }
    
    func addMoveIfNeeded(move: Move) -> Bool {
        if move.sourceFenId == self.fenId,
            let targetFenId = move.targetFenId,
            findMove(targetFenId: targetFenId, fenIdFilter: { _ in true}) == nil {
                moves.append(move)
                return true
        }
        return false
    }
    
    func markLastMove(fenId: Int?) {
        self.lastMoveFenId = fenId
    }

    // MARK: - Path Methods
    func setPathGroups(_ groups: [PathGroup]?) {
        self.pathGroups = groups
    }
    
    func getPathGroups() -> [PathGroup] {
        return pathGroups ?? []
    }
}
