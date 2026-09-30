import Testing
import Foundation
@testable import XiangqiNotebook

struct SessionDataTests {

    // MARK: - Default Initialization Tests

    @Test func testDefaultInitialization() {
        let sessionData = SessionData()

        #expect(sessionData.currentGame2 == [1])
        #expect(sessionData.currentGameStep == 0)
        #expect(sessionData.lockedStep == nil)
        #expect(sessionData.filters.isEmpty)
        #expect(sessionData.isBlackOrientation == false)
        #expect(sessionData.isHorizontalFlipped == false)
        #expect(sessionData.gameHistory == nil)
        #expect(sessionData.gameStepLimitation == nil)
        #expect(sessionData.canNavigateBeforeLockedStep == false)
        #expect(sessionData.currentMode == .normal)
        #expect(sessionData.showPath == true)
        #expect(sessionData.showAllNextMoves == false)
        #expect(sessionData.autoExtendGameWhenPlayingBoardFen == true)
        #expect(sessionData.isCommentEditing == false)
        #expect(sessionData.focusedPracticeGamePath == nil)
        #expect(sessionData.specificGameId == nil)
        #expect(sessionData.specificBookId == nil)
        #expect(sessionData.allowAddingNewMoves == true)
    }

    // MARK: - Codable Tests

    @Test func testSessionDataEncodeDecodeRoundTrip() throws {
        let sessionData = SessionData()
        sessionData.currentGame2 = [1, 2, 3]
        sessionData.currentGameStep = 2
        sessionData.lockedStep = 1
        sessionData.filters = ["red_opening_only"]
        sessionData.isBlackOrientation = true
        sessionData.isHorizontalFlipped = true
        sessionData.showPath = false
        sessionData.showAllNextMoves = true
        sessionData.allowAddingNewMoves = false

        let encoder = JSONEncoder()
        let data = try encoder.encode(sessionData)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SessionData.self, from: data)

        #expect(decoded.currentGame2 == [1, 2, 3])
        #expect(decoded.currentGameStep == 2)
        #expect(decoded.lockedStep == 1)
        #expect(decoded.filters == ["red_opening_only"])
        #expect(decoded.isBlackOrientation == true)
        #expect(decoded.isHorizontalFlipped == true)
        #expect(decoded.showPath == false)
        #expect(decoded.showAllNextMoves == true)
        #expect(decoded.allowAddingNewMoves == false)
    }

    @Test func testSessionDataEncodeDecodeWithNilValues() throws {
        let sessionData = SessionData()
        // 保持所有 optional 为 nil

        let data = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        #expect(decoded.lockedStep == nil)
        #expect(decoded.gameHistory == nil)
        #expect(decoded.gameStepLimitation == nil)
        #expect(decoded.focusedPracticeGamePath == nil)
        #expect(decoded.specificGameId == nil)
        #expect(decoded.specificBookId == nil)
    }

    @Test func testSessionDataEncodeDecodeWithGameHistory() throws {
        let sessionData = SessionData()
        sessionData.gameHistory = [[1, 2, 3], [1, 4, 5], [1]]

        let data = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        #expect(decoded.gameHistory?.count == 3)
        #expect(decoded.gameHistory?[0] == [1, 2, 3])
        #expect(decoded.gameHistory?[1] == [1, 4, 5])
        #expect(decoded.gameHistory?[2] == [1])
    }

    @Test func testSessionDataEncodeDecodeWithSpecificIds() throws {
        let gameId = UUID()
        let bookId = UUID()
        let sessionData = SessionData()
        sessionData.specificGameId = gameId
        sessionData.specificBookId = bookId

        let data = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        #expect(decoded.specificGameId == gameId)
        #expect(decoded.specificBookId == bookId)
    }

    // MARK: - AppMode Backward Compatibility Tests

    @Test func testSessionData_OldReviewMode_FallsBackToNormal() throws {
        // 旧版本中 "review" 是一个 AppMode 值
        // 现在需要回退为 .normal
        let json = """
        {
            "current_game2": [1],
            "current_game_step": 0,
            "locked_step": null,
            "filters": [],
            "is_black_orientation": false,
            "is_horizontal_flipped": false,
            "can_navigate_before_locked_step": false,
            "current_mode": "review",
            "show_path": true,
            "show_all_next_moves": false,
            "auto_extend_game_when_playing_board_fen": true,
            "is_comment_editing": false
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        // "review" 应该回退为 .normal
        #expect(decoded.currentMode == .normal)
    }

    @Test func testSessionData_NormalMode() throws {
        let sessionData = SessionData()
        sessionData.currentMode = .normal

        let data = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        #expect(decoded.currentMode == .normal)
    }

    @Test func testSessionData_PracticeMode() throws {
        let sessionData = SessionData()
        sessionData.currentMode = .practice

        let data = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        #expect(decoded.currentMode == .practice)
    }

    // MARK: - Cache Fields Not Encoded Tests

    @Test func testCacheFields_NotEncoded() throws {
        let sessionData = SessionData()
        sessionData.totalGamePathsCount = 2
        sessionData.fenIdToGamePathCount = [1: 2, 2: 1]
        sessionData.currentPathIndex = 1

        let data = try JSONEncoder().encode(sessionData)
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        // 缓存字段不应该被编码，解码后应为 nil
        #expect(decoded.totalGamePathsCount == nil)
        #expect(decoded.fenIdToGamePathCount == nil)
        #expect(decoded.currentPathIndex == nil)
    }

    // MARK: - Optional Fields Backward Compatibility

    @Test func testSessionData_MissingOptionalFields_HasDefaults() throws {
        // 最小化 JSON（只包含必要字段）
        let json = """
        {
            "current_game2": [5],
            "current_game_step": 0,
            "is_black_orientation": false,
            "is_horizontal_flipped": false,
            "can_navigate_before_locked_step": false,
            "current_mode": "normal",
            "show_path": true,
            "auto_extend_game_when_playing_board_fen": true,
            "is_comment_editing": false
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SessionData.self, from: data)

        #expect(decoded.currentGame2 == [5])
        #expect(decoded.filters.isEmpty)           // 默认空数组
        #expect(decoded.showAllNextMoves == false)  // 默认 false
        #expect(decoded.allowAddingNewMoves == true) // 默认 true
        #expect(decoded.lockedStep == nil)
    }

    @Test func testSessionData_EmptyJSON_AllDefaults() throws {
        // schema 演进健壮性：任意字段缺失（极端情况：全部缺失）都不应整体解码失败
        let decoded = try JSONDecoder().decode(SessionData.self, from: Data("{}".utf8))

        #expect(decoded.currentGame2 == [1])
        #expect(decoded.currentGameStep == 0)
        #expect(decoded.isBlackOrientation == false)
        #expect(decoded.showPath == true)
        #expect(decoded.autoExtendGameWhenPlayingBoardFen == true)
        #expect(decoded.currentMode == .normal)
    }

    // MARK: - copy

    @Test func testCopy_preservesEveryStoredFieldIncludingReviewMode() {
        let original = SessionData()
        original.currentGame2 = [1, 5, 9]
        original.currentGameStep = 2
        original.lockedStep = 1
        original.filters = ["red_opening"]
        original.isBlackOrientation = true
        original.isHorizontalFlipped = true
        original.gameHistory = [[1, 2]]
        original.gameStepLimitation = 7
        original.canNavigateBeforeLockedStep = true
        original.currentMode = .review   // 持久化解码会把 review 回退为 normal，拷贝不能
        original.showPath = false
        original.showAllNextMoves = true
        original.showLastMove = false
        original.showRedAttackPoints = true
        original.showBlackAttackPoints = true
        original.attackPointsRedPalaceOnly = true
        original.attackPointsBlackPalaceOnly = true
        original.showRealGameList = true
        original.autoExtendGameWhenPlayingBoardFen = false
        original.isCommentEditing = true
        original.focusedPracticeGamePath = [1, 5]
        original.specificGameId = UUID()
        original.specificBookId = UUID()
        original.allowAddingNewMoves = false
        original.showGameBrowserSidebar = true
        original.gameBrowserExpandedBookIds = [UUID()]
        original.gameBrowserSelectedBookId = UUID()
        original.gameBrowserSelectedGameId = UUID()

        let copy = original.copy()

        #expect(copy !== original)
        #expect(copy.currentMode == .review)
        // 用反射逐个比对存储属性：新增字段若在 copy() 里丢失，这里会立刻暴露
        let originalFields = Mirror(reflecting: original).children.map { ($0.label ?? "", String(describing: $0.value)) }
        let copyFields = Mirror(reflecting: copy).children.map { ($0.label ?? "", String(describing: $0.value)) }
        for (o, c) in zip(originalFields, copyFields) where !o.0.hasPrefix("totalGamePathsCount") && !o.0.hasPrefix("fenIdToGamePathCount") && !o.0.hasPrefix("currentPathIndex") {
            #expect(o == c, "字段 \(o.0) 拷贝后不一致")
        }
    }
}
