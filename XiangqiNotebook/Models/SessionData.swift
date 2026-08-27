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
    var showLastMove: Bool = true
    var showRedAttackPoints: Bool = false
    var showBlackAttackPoints: Bool = false
    var attackPointsRedPalaceOnly: Bool = false
    var attackPointsBlackPalaceOnly: Bool = false
    var showRealGameList: Bool = false
    var autoExtendGameWhenPlayingBoardFen: Bool = true
    var isCommentEditing: Bool = false
    var focusedPracticeGamePath: [Int]? = nil
    var specificGameId: UUID? = nil
    var specificBookId: UUID? = nil
    var allowAddingNewMoves: Bool = true
    var showGameBrowserSidebar: Bool = false
    var gameBrowserExpandedBookIds: Set<UUID>? = nil
    var gameBrowserSelectedBookId: UUID? = nil
    var gameBrowserSelectedGameId: UUID? = nil

    init() {
        // 所有属性都已在声明时设置了默认值
    }

    // 缓存数据 - 不编码
    var totalGamePathsCount: Int? = nil
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
        case showLastMove = "show_last_move"
        case showRedAttackPoints = "show_red_attack_points"
        case showBlackAttackPoints = "show_black_attack_points"
        case attackPointsRedPalaceOnly = "attack_points_red_palace_only"
        case attackPointsBlackPalaceOnly = "attack_points_black_palace_only"
        case showRealGameList = "show_real_game_list"
        case autoExtendGameWhenPlayingBoardFen = "auto_extend_game_when_playing_board_fen"
        case isCommentEditing = "is_comment_editing"
        case focusedPracticeGamePath = "focused_practice_game_path"
        case specificGameId = "specific_game_id"
        case specificBookId = "specific_book_id"
        case allowAddingNewMoves = "allow_adding_new_moves"
        case showGameBrowserSidebar = "show_game_browser_sidebar"
        case gameBrowserExpandedBookIds = "game_browser_expanded_book_ids"
        case gameBrowserSelectedBookId = "game_browser_selected_book_id"
        case gameBrowserSelectedGameId = "game_browser_selected_game_id"
    }

    /// 所有字段都用 decodeIfPresent + 默认值：会话文件是可丢弃的 UI 状态，
    /// schema 演进（新增/删除字段）时任一字段缺失都不应导致整体解码失败而重置全部会话
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        currentGame2 = try container.decodeIfPresent([Int].self, forKey: .currentGame2) ?? [1]
        currentGameStep = try container.decodeIfPresent(Int.self, forKey: .currentGameStep) ?? 0
        lockedStep = try container.decodeIfPresent(Int.self, forKey: .lockedStep)
        filters = try container.decodeIfPresent([String].self, forKey: .filters) ?? []
        isBlackOrientation = try container.decodeIfPresent(Bool.self, forKey: .isBlackOrientation) ?? false
        isHorizontalFlipped = try container.decodeIfPresent(Bool.self, forKey: .isHorizontalFlipped) ?? false
        gameHistory = try container.decodeIfPresent([[Int]].self, forKey: .gameHistory)
        gameStepLimitation = try container.decodeIfPresent(Int.self, forKey: .gameStepLimitation)
        canNavigateBeforeLockedStep = try container.decodeIfPresent(Bool.self, forKey: .canNavigateBeforeLockedStep) ?? false
        showPath = try container.decodeIfPresent(Bool.self, forKey: .showPath) ?? true
        showAllNextMoves = try container.decodeIfPresent(Bool.self, forKey: .showAllNextMoves) ?? false
        showLastMove = try container.decodeIfPresent(Bool.self, forKey: .showLastMove) ?? true
        showRedAttackPoints = try container.decodeIfPresent(Bool.self, forKey: .showRedAttackPoints) ?? false
        showBlackAttackPoints = try container.decodeIfPresent(Bool.self, forKey: .showBlackAttackPoints) ?? false
        attackPointsRedPalaceOnly = try container.decodeIfPresent(Bool.self, forKey: .attackPointsRedPalaceOnly) ?? false
        attackPointsBlackPalaceOnly = try container.decodeIfPresent(Bool.self, forKey: .attackPointsBlackPalaceOnly) ?? false
        showRealGameList = try container.decodeIfPresent(Bool.self, forKey: .showRealGameList) ?? false
        autoExtendGameWhenPlayingBoardFen = try container.decodeIfPresent(Bool.self, forKey: .autoExtendGameWhenPlayingBoardFen) ?? true
        isCommentEditing = try container.decodeIfPresent(Bool.self, forKey: .isCommentEditing) ?? false
        focusedPracticeGamePath = try container.decodeIfPresent([Int].self, forKey: .focusedPracticeGamePath)
        specificGameId = try container.decodeIfPresent(UUID.self, forKey: .specificGameId)
        specificBookId = try container.decodeIfPresent(UUID.self, forKey: .specificBookId)
        // 兼容已持久化的 "review" 值：回退为 .normal
        let modeString = try container.decodeIfPresent(String.self, forKey: .currentMode) ?? AppMode.normal.rawValue
        if modeString == "review" {
            currentMode = .normal
        } else {
            currentMode = AppMode(rawValue: modeString) ?? .normal
        }
        allowAddingNewMoves = try container.decodeIfPresent(Bool.self, forKey: .allowAddingNewMoves) ?? true
        showGameBrowserSidebar = try container.decodeIfPresent(Bool.self, forKey: .showGameBrowserSidebar) ?? false
        gameBrowserExpandedBookIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .gameBrowserExpandedBookIds)
        gameBrowserSelectedBookId = try container.decodeIfPresent(UUID.self, forKey: .gameBrowserSelectedBookId)
        gameBrowserSelectedGameId = try container.decodeIfPresent(UUID.self, forKey: .gameBrowserSelectedGameId)
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
        try container.encode(showLastMove, forKey: .showLastMove)
        try container.encode(showRedAttackPoints, forKey: .showRedAttackPoints)
        try container.encode(showBlackAttackPoints, forKey: .showBlackAttackPoints)
        try container.encode(attackPointsRedPalaceOnly, forKey: .attackPointsRedPalaceOnly)
        try container.encode(attackPointsBlackPalaceOnly, forKey: .attackPointsBlackPalaceOnly)
        try container.encode(showRealGameList, forKey: .showRealGameList)
        try container.encode(autoExtendGameWhenPlayingBoardFen, forKey: .autoExtendGameWhenPlayingBoardFen)
        try container.encode(isCommentEditing, forKey: .isCommentEditing)
        try container.encodeIfPresent(focusedPracticeGamePath, forKey: .focusedPracticeGamePath)
        try container.encodeIfPresent(specificGameId, forKey: .specificGameId)
        try container.encodeIfPresent(specificBookId, forKey: .specificBookId)
        try container.encode(currentMode, forKey: .currentMode)
        try container.encode(allowAddingNewMoves, forKey: .allowAddingNewMoves)
        try container.encode(showGameBrowserSidebar, forKey: .showGameBrowserSidebar)
        try container.encodeIfPresent(gameBrowserExpandedBookIds, forKey: .gameBrowserExpandedBookIds)
        try container.encodeIfPresent(gameBrowserSelectedBookId, forKey: .gameBrowserSelectedBookId)
        try container.encodeIfPresent(gameBrowserSelectedGameId, forKey: .gameBrowserSelectedGameId)
    }
}
