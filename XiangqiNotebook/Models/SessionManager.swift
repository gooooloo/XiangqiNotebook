import Foundation
import Combine

/// SessionManager 负责管理多个 Session 实例的切换
class SessionManager: ObservableObject {
    @Published private(set) var mainSession: Session
    @Published private(set) var practiceSession: Session?
    private(set) var database: Database

    /// 当前活跃的 Session（practiceSession 优先，否则 mainSession）
    var currentSession: Session {
        practiceSession ?? mainSession
    }

    /// 是否处于专注练习模式
    var isInFocusedPractice: Bool {
        practiceSession != nil
    }

    // MARK: - 初始化

    init(mainSession: Session, database: Database = .shared) {
        self.mainSession = mainSession
        self.database = database
    }

    /// 从 SessionData 创建 SessionManager 实例
    /// - Parameters:
    ///   - sessionData: 会话数据
    ///   - database: 数据库实例（默认为共享实例）
    /// - Returns: 创建的 SessionManager 实例（保证成功）
    static func create(from sessionData: SessionData, database: Database = .shared) -> SessionManager {
        do {
            // 1. 创建 DatabaseView
            let databaseView = createDatabaseView(
                for: sessionData.filters,
                focusedPath: sessionData.focusedPracticeGamePath,
                specificGameId: sessionData.specificGameId,
                specificBookId: sessionData.specificBookId,
                database: database
            )

            // 2. 使用主构造器创建 Session
            let mainSession = try Session(sessionData: sessionData, databaseView: databaseView)

            // 3. 返回 SessionManager
            return SessionManager(mainSession: mainSession, database: database)

        } catch {
            // Fallback: 创建默认的 SessionManager
            print("❌ Session 初始化失败，使用默认 Session: \(error)")

            let fallbackSessionData = SessionData()
            let fallbackDatabaseView = DatabaseView.full(database: database)
            let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"

            // 使用 DatabaseView 确保起始局面存在
            let startFenId = fallbackDatabaseView.ensureFenId(for: startFen)
            fallbackSessionData.currentGame2 = [startFenId]
            fallbackSessionData.currentGameStep = 0

            let fallbackSession = try! Session(sessionData: fallbackSessionData, databaseView: fallbackDatabaseView)
            return SessionManager(mainSession: fallbackSession)
        }
    }

    // MARK: - 过滤切换

    /// 设置过滤器（创建新 Session 并迁移状态）
    /// - Parameters:
    ///   - filters: 目标过滤器数组（空数组表示 Full 视图）
    ///   - focusedPath: 专注练习模式的路径（仅当 filters 包含 filterFocusedPractice 时使用）
    ///   - specificGameId: 特定棋局ID（仅当 filters 包含 filterSpecificGame 时使用）
    ///   - specificBookId: 特定棋谱ID（仅当 filters 包含 filterSpecificBook 时使用）
    func setFilters(_ filters: [String], focusedPath: [Int]? = nil, specificGameId: UUID? = nil, specificBookId: UUID? = nil) {
        // 注意：即使目标 filters 与当前 filters 相同，也不能快速退出。
        // 因为底层数据可能已变化（如用户将当前位置移出开局库），需要重新构建 DatabaseView 并裁剪游戏。

        // 0. 如果当前在 focusedPractice 模式，先退出
        if isInFocusedPractice {
            exitFocusedPractice()
        }

        // 1. 从当前 mainSession 复制状态到新的 SessionData
        let newSessionData = SessionData()
        newSessionData.currentGame2 = mainSession.sessionData.currentGame2
        newSessionData.currentGameStep = mainSession.sessionData.currentGameStep
        newSessionData.lockedStep = mainSession.sessionData.lockedStep
        newSessionData.filters = filters
        newSessionData.isBlackOrientation = mainSession.sessionData.isBlackOrientation
        newSessionData.isHorizontalFlipped = mainSession.sessionData.isHorizontalFlipped
        newSessionData.gameStepLimitation = mainSession.sessionData.gameStepLimitation
        newSessionData.canNavigateBeforeLockedStep = mainSession.sessionData.canNavigateBeforeLockedStep
        newSessionData.currentMode = mainSession.sessionData.currentMode
        // 复习/练习模式下保持当前设置，其他情况默认打开路径和下一步
        if mainSession.sessionData.currentMode == .review || mainSession.sessionData.currentMode == .practice {
            newSessionData.showPath = mainSession.sessionData.showPath
            newSessionData.showAllNextMoves = mainSession.sessionData.showAllNextMoves
        } else {
            newSessionData.showPath = mainSession.sessionData.showPath
            newSessionData.showAllNextMoves = true
        }
        newSessionData.autoExtendGameWhenPlayingBoardFen = mainSession.sessionData.autoExtendGameWhenPlayingBoardFen
        newSessionData.isCommentEditing = mainSession.sessionData.isCommentEditing
        newSessionData.focusedPracticeGamePath = focusedPath
        // 保留上一次的 specificGameId/specificBookId，除非明确传入了新值
        newSessionData.specificGameId = specificGameId ?? mainSession.sessionData.specificGameId
        newSessionData.specificBookId = specificBookId ?? mainSession.sessionData.specificBookId

        // 根据 filters 类型设置 allowAddingNewMoves
        if filters.isEmpty {
            // 无过滤（Full视图）：保持原有设置
            newSessionData.allowAddingNewMoves = mainSession.sessionData.allowAddingNewMoves
        } else if filters.contains(Session.filterSpecificGame) {
            // 特定棋局：根据 isFullyRecorded 决定
            let fullView = DatabaseView.full(database: database)
            if let gameId = specificGameId,
               let game = fullView.getGameObject(gameId),
               game.isFullyRecorded {
                newSessionData.allowAddingNewMoves = false
            } else {
                newSessionData.allowAddingNewMoves = mainSession.sessionData.allowAddingNewMoves
            }
        } else if filters.contains(Session.filterSpecificBook) {
            // 特定棋谱：始终只读（棋谱是参考资料）
            newSessionData.allowAddingNewMoves = false
        } else {
            // 开局、实战、专注练习等：强制设为 false（这些模式下不允许增加新走法）
            newSessionData.allowAddingNewMoves = false
        }

        // 2. 根据 filters 构造相应的 DatabaseView
        let databaseView = Self.createDatabaseView(for: filters, focusedPath: focusedPath, specificGameId: specificGameId, specificBookId: specificBookId, database: database)

        // 3. 按视图裁剪 currentGame2/currentGameStep（移除不在视图范围的 fenId）
        let oldGame = Array(newSessionData.currentGame2[0...newSessionData.currentGameStep])
        let lockedFens = newSessionData.lockedStep.map { Array(newSessionData.currentGame2[0...$0]) }

        // 裁剪：如果有步骤不符合条件则截断
        for i in 1..<newSessionData.currentGame2.count {
            let fenId = newSessionData.currentGame2[i]
            if !databaseView.containsFenId(fenId) {
                newSessionData.currentGame2 = Array(newSessionData.currentGame2[0..<i])
                break
            }
        }

        // 自动延伸对局（尽可能拓展更多符合 filter 的走法）
        // 注意：此处使用 scope-only 的 databaseView（不含步数限制），
        // 步数限制会在 Session 初始化时通过 rebuildDatabaseView 应用
        newSessionData.currentGame2 = GameOperations.autoExtendGame(
            game: newSessionData.currentGame2,
            nextFenIds: nil,
            databaseView: databaseView,
            allowExtend: true
        )

        // 尝试恢复到原来的步骤
        newSessionData.currentGameStep = min(newSessionData.currentGame2.count - 1, oldGame.count - 1)
        for i in 0..<min(newSessionData.currentGame2.count, oldGame.count) {
            if newSessionData.currentGame2[i] == oldGame[i] {
                newSessionData.currentGameStep = i
            }
        }

        // 尝试恢复锁定步骤
        newSessionData.lockedStep = nil
        if let lockedFens = lockedFens {
            for i in 0..<min(lockedFens.count, newSessionData.currentGame2.count) {
                if newSessionData.currentGame2[i] == lockedFens[i] {
                    newSessionData.lockedStep = i
                } else {
                    break
                }
            }
        }

        // 4. 设定朝向（黑开/黑实→黑朝向；红开/红实→红朝向；其他不改）
        if filters.contains(Session.filterBlackOpeningOnly) || filters.contains(Session.filterBlackRealGameOnly) {
            newSessionData.isBlackOrientation = true
        } else if filters.contains(Session.filterRedOpeningOnly) || filters.contains(Session.filterRedRealGameOnly) {
            newSessionData.isBlackOrientation = false
        }
        // 其他过滤器不改变方向

        // 5. 构造新的 Session 并替换 mainSession
        do {
            let newSession = try Session(sessionData: newSessionData, databaseView: databaseView)
            self.mainSession = newSession

            // 触发 objectWillChange，通知 ViewModel 重新订阅
            objectWillChange.send()
        } catch {
            print("❌ 切换过滤器失败: \(error)")
        }
    }

    /// 根据 filters 数组创建对应的 DatabaseView（静态方法，供全局使用）
    static func createDatabaseView(for filters: [String], focusedPath: [Int]?, specificGameId: UUID?, specificBookId: UUID?, database: Database = .shared) -> DatabaseView {
        return .combined(
            database: database,
            filters: filters,
            specificGameId: specificGameId,
            specificBookId: specificBookId,
            focusedPracticePath: focusedPath
        )
    }

    // MARK: - 加载操作

    /// 加载棋局（切换到特定棋局视图再执行）
    /// - Parameter gameId: 要加载的棋局 ID
    func loadGame(_ gameId: UUID) {
        // 切换到特定棋局视图
        setFilters([Session.filterSpecificGame], specificGameId: gameId)

        // 调用 mainSession 的 loadGame
        mainSession.loadGame(gameId)
    }

    /// 加载棋谱（切换到特定棋谱视图再执行）
    /// - Parameter bookId: 要加载的棋谱 ID
    func loadBook(_ bookId: UUID) {
        // 切换到特定棋谱视图
        setFilters([Session.filterSpecificBook], specificBookId: bookId)

        // 调用 mainSession 的 loadBook
        mainSession.loadBook(bookId)
    }

    /// 加载书签（总是先切换到 Full 视图再执行）
    /// - Parameter game: 书签对应的棋局路径
    func loadBookmark(_ game: [Int]) {
        // 总是先切换到 Full 视图
        setFilters([])

        // 调用 mainSession 的 loadBookmark（内部会调用 playNewGame）
        mainSession.loadBookmark(game)
    }

    // MARK: - Session 切换

    /// 进入专注练习模式
    func startFocusedPractice() {
        // 创建临时 session，复制当前 UI 状态
        let practiceSessionData = createPracticeSession(from: mainSession.sessionData)

        // 创建专注练习的 DatabaseView
        let databaseView = Self.createDatabaseView(
            for: [Session.filterFocusedPractice],
            focusedPath: practiceSessionData.focusedPracticeGamePath,
            specificGameId: nil,
            specificBookId: nil,
            database: database
        )

        // 使用主构造器创建 practiceSession
        do {
            self.practiceSession = try Session(
                sessionData: practiceSessionData,
                databaseView: databaseView
            )
        } catch {
            print("❌ 创建 practiceSession 失败: \(error)")
            return
        }

        // 触发 objectWillChange，通知 ViewModel 重新订阅
        objectWillChange.send()
    }

    /// 退出专注练习模式
    func exitFocusedPractice() {
        guard practiceSession != nil else { return }

        // 清除临时 session
        practiceSession = nil

        // 触发 objectWillChange
        objectWillChange.send()
    }

    // MARK: - 私有辅助方法

    /// 创建练习模式的 session（从 mainSession 复制状态）
    private func createPracticeSession(from main: SessionData) -> SessionData {
        let temp = SessionData()

        // 复制当前游戏状态
        temp.currentGame2 = main.currentGame2
        temp.currentGameStep = main.currentGameStep
        temp.lockedStep = main.lockedStep
        temp.canNavigateBeforeLockedStep = main.canNavigateBeforeLockedStep

        // 复制视图状态
        temp.isBlackOrientation = main.isBlackOrientation
        temp.isHorizontalFlipped = main.isHorizontalFlipped
        temp.gameStepLimitation = main.gameStepLimitation

        // 设置专注练习特有状态
        temp.focusedPracticeGamePath = main.currentGame2  // 保存当前完整路径
        temp.filters = [Session.filterFocusedPractice]
        temp.currentMode = .practice
        temp.showPath = false
        temp.autoExtendGameWhenPlayingBoardFen = false

        // 在练习模式下，只保留从锁定步骤到当前的路径
        let startStep = temp.lockedStep ?? 0
        temp.currentGame2 = Array(temp.currentGame2.prefix(startStep + 1))
        temp.currentGameStep = startStep

        return temp
    }
}

// MARK: - 便捷访问 mainSession.sessionData
extension SessionManager {
    /// 便捷访问 mainSession 的 sessionData（用于数据持久化）
    var mainSessionData: SessionData {
        mainSession.sessionData
    }

    /// 保存当前 mainSession 的 sessionData 到默认位置
    func saveCurrentSession() throws {
        try SessionStorage.saveSessionToDefault(session: mainSessionData)
    }
}
