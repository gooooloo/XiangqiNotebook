import Foundation

class SessionData: Codable {
    var currentGame2: [Int] = [1]
    var currentGameStep: Int = 0
    var lockedStep: Int? = nil
    var filters: [String] = []
    var isBlackOrientation: Bool = false
    var isHorizontalFlipped: Bool = false
    var gameHistory: [[Int]]? = nil
    var gameStepLimitation: Int? = nil
    var canNavigateBeforeLockedStep: Bool = false
    var currentMode: AppMode = .normal
    var showPath: Bool = true
    var showAllNextMoves: Bool = false
    var autoExtendGameWhenPlayingBoardFen: Bool = true
    var isCommentEditing: Bool = false
    var focusedPracticeGamePath: [Int]? = nil
    var specificGameId: UUID? = nil
    var specificBookId: UUID? = nil
    var allowAddingNewMoves: Bool = true

    init() {
        // 所有属性都已在声明时设置了默认值
    }

    // 缓存数据 - 不编码
    var allGamePaths: [[Int]]? = nil
    var fenIdToGamePathCount: [Int: Int]? = nil
    var currentPathIndex: Int? = nil

    enum CodingKeys: String, CodingKey {
        case currentGame2 = "current_game2"
        case currentGameStep = "current_game_step"
        case lockedStep = "locked_step"
        case filters
        case isBlackOrientation = "is_black_orientation"
        case isHorizontalFlipped = "is_horizontal_flipped"
        case gameHistory = "game_history"
        case gameStepLimitation = "game_step_limitation"
        case canNavigateBeforeLockedStep = "can_navigate_before_locked_step"
        case currentMode = "current_mode"
        case showPath = "show_path"
        case showAllNextMoves = "show_all_next_moves"
        case autoExtendGameWhenPlayingBoardFen = "auto_extend_game_when_playing_board_fen"
        case isCommentEditing = "is_comment_editing"
        case focusedPracticeGamePath = "focused_practice_game_path"
        case specificGameId = "specific_game_id"
        case specificBookId = "specific_book_id"
        case allowAddingNewMoves = "allow_adding_new_moves"
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        currentGame2 = try container.decode([Int].self, forKey: .currentGame2)
        currentGameStep = try container.decode(Int.self, forKey: .currentGameStep)
        lockedStep = try container.decodeIfPresent(Int.self, forKey: .lockedStep)
        filters = try container.decodeIfPresent([String].self, forKey: .filters) ?? []
        isBlackOrientation = try container.decode(Bool.self, forKey: .isBlackOrientation)
        isHorizontalFlipped = try container.decode(Bool.self, forKey: .isHorizontalFlipped)
        gameHistory = try container.decodeIfPresent([[Int]].self, forKey: .gameHistory)
        gameStepLimitation = try container.decodeIfPresent(Int.self, forKey: .gameStepLimitation)
        canNavigateBeforeLockedStep = try container.decode(Bool.self, forKey: .canNavigateBeforeLockedStep)
        showPath = try container.decode(Bool.self, forKey: .showPath)
        showAllNextMoves = try container.decodeIfPresent(Bool.self, forKey: .showAllNextMoves) ?? false
        autoExtendGameWhenPlayingBoardFen = try container.decode(Bool.self, forKey: .autoExtendGameWhenPlayingBoardFen)
        isCommentEditing = try container.decode(Bool.self, forKey: .isCommentEditing)
        focusedPracticeGamePath = try container.decodeIfPresent([Int].self, forKey: .focusedPracticeGamePath)
        specificGameId = try container.decodeIfPresent(UUID.self, forKey: .specificGameId)
        specificBookId = try container.decodeIfPresent(UUID.self, forKey: .specificBookId)
        // 兼容已持久化的 "review" 值：回退为 .normal
        let modeString = try container.decode(String.self, forKey: .currentMode)
        if modeString == "review" {
            currentMode = .normal
        } else {
            currentMode = AppMode(rawValue: modeString) ?? .normal
        }
        allowAddingNewMoves = try container.decodeIfPresent(Bool.self, forKey: .allowAddingNewMoves) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(currentGame2, forKey: .currentGame2)
        try container.encode(currentGameStep, forKey: .currentGameStep)
        try container.encodeIfPresent(lockedStep, forKey: .lockedStep)
        try container.encode(filters, forKey: .filters)
        try container.encode(isBlackOrientation, forKey: .isBlackOrientation)
        try container.encode(isHorizontalFlipped, forKey: .isHorizontalFlipped)
        try container.encodeIfPresent(gameHistory, forKey: .gameHistory)
        try container.encodeIfPresent(gameStepLimitation, forKey: .gameStepLimitation)
        try container.encode(canNavigateBeforeLockedStep, forKey: .canNavigateBeforeLockedStep)
        try container.encode(showPath, forKey: .showPath)
        try container.encode(showAllNextMoves, forKey: .showAllNextMoves)
        try container.encode(autoExtendGameWhenPlayingBoardFen, forKey: .autoExtendGameWhenPlayingBoardFen)
        try container.encode(isCommentEditing, forKey: .isCommentEditing)
        try container.encodeIfPresent(focusedPracticeGamePath, forKey: .focusedPracticeGamePath)
        try container.encodeIfPresent(specificGameId, forKey: .specificGameId)
        try container.encodeIfPresent(specificBookId, forKey: .specificBookId)
        try container.encode(currentMode, forKey: .currentMode)
        try container.encode(allowAddingNewMoves, forKey: .allowAddingNewMoves)
    }
}
