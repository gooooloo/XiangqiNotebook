import SwiftUI
import Foundation
import Combine

#if os(macOS)
struct BatchEvalProgress {
    let current: Int
    let total: Int
    let evaluatedCount: Int
    let lastDetail: String?
    let elapsedSeconds: Double?
    let isCompleted: Bool
}
#endif

/// 定义平台服务接口，用于处理平台特定的功能
protocol PlatformService {
    func openURL(_ url: URL)
    func showAlert(title: String, message: String)
    func showWarningAlert(title: String, message: String)
    func showConfirmAlert(title: String, message: String, completion: @escaping (Bool) throws -> Void)
    func saveFile(defaultName: String, completion: @escaping (URL?) -> Void)
    func openFile(completion: @escaping (URL?) -> Void)
    
    // 备份和恢复方法
    func backupData(_ data: Data, defaultName: String, completion: @escaping (Bool) -> Void)
    func recoverData(completion: @escaping (Data?) -> Void)
}

/// ViewModel 负责处理象棋应用的业务逻辑
/// 它作为 View 和 Model(Session) 之间的中介
class ViewModel: ObservableObject {
    @Published private(set) var sessionManager: SessionManager

    // 计算属性：向 Views 暴露当前活跃的 Session（向后兼容）
    var session: Session {
        sessionManager.currentSession
    }

    // 棋盘配置
    @Published var boardViewModel: BoardViewModel
    
    // UI 状态
    @Published var showingBookmarkAlert = false
    @Published var showingStepLimitationDialog = false
    @Published var showingGameInputView = false
    @Published var showingGameBrowserView = false
    @Published var showingPGNImportSheet = false
    @Published var showMarkPathView = false
    @Published var showIOSBookMarkListView = false
    @Published var showIOSMoreActionsView = false
    @Published var showEditCommentIOS = false

    // 检查是否有任何 sheet 正在显示（用于禁用快捷键）
    var isAnySheetPresented: Bool {
        return showingBookmarkAlert ||
               showingStepLimitationDialog ||
               showingGameInputView ||
               showingGameBrowserView ||
               showingPGNImportSheet ||
               showMarkPathView
    }

    // Global alert state
    @Published var showingGlobalAlert = false
    @Published var globalAlertTitle = ""
    @Published var globalAlertMessage = ""

    #if os(macOS)
    private var referenceBoardWindowController: ReferenceBoardWindowController?
    #endif

    // 用于存储订阅
    private var cancellables = Set<AnyCancellable>()

    // 操作定义
    let actionDefinitions = ActionDefinitions()

    // 平台服务
    private let platformService: PlatformService

    // 引擎评估（仅 macOS）
    #if os(macOS)
    private var pikafishService: PikafishService?
    private var isBatchEvaluating: Bool = false
    private var batchEvalCancelled: Bool = false
    @Published var batchEvalProgress: BatchEvalProgress?
    #endif

    // 初始化方法
    init(platformService: PlatformService) {
        // 1. 加载 SessionData
        let sessionData: SessionData
        if let loadedSessionData = SessionStorage.loadSessionFromDefault() {
            sessionData = loadedSessionData
        } else {
            sessionData = SessionData()
            print("⚠️ 创建新的 SessionData")
        }

        // 2. 创建 SessionManager（内部处理所有错误）
        let createdSessionManager = SessionManager.create(from: sessionData)
        self.sessionManager = createdSessionManager
        self.platformService = platformService

        // 3. 初始化 boardViewModel（使用局部变量避免 self 访问）
        let currentSession = createdSessionManager.currentSession
        self.boardViewModel = BoardViewModel(
            fen: currentSession.currentFen,
            orientation: currentSession.isCurrentBlackOrientation ? "black" : "red",
            isHorizontalFlipped: currentSession.isCurrentHorizontalFlipped,
            showPath: currentSession.showPath,
            showAllNextMoves: currentSession.showAllNextMoves,
            shouldAnimate: true,
            currentFenPathGroups: currentSession.getCurrentFenPathGroups()
        )

        // 4. 监听 sessionManager 和 session 的变化
        setupSessionObservers()

        // 5. 注册所有操作
        registerActions()

        // 6. 设置引擎分数的 activeEngineKey（确保加载的分数文件能立即显示）
        #if os(macOS)
        Database.shared.activeEngineKey = PikafishService.engineKey

        // 7. App 退出时关闭引擎子进程，防止孤儿进程残留
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.pikafishService?.stop()
        }
        #endif
    }
    
    // 当前 Session 的订阅（需要在 Session 切换时重新创建）
    private var currentSessionSubscription: AnyCancellable?

    private func setupSessionObservers() {
        // 1. 监听 SessionManager 的变化（Session 切换时触发）
        sessionManager.objectWillChange
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("[ViewModel] SessionManager changed, re-subscribing to current session")
                self.setupCurrentSessionObserver()

                // 防御性检查：如果 currentFenId 不在 DatabaseView 范围内，跳过更新
                // 这可能发生在过滤器切换的过渡期间
                guard self.session.databaseView.containsFenId(self.session.currentFenId) else {
                    return
                }
                self.updateBoardView()
            }
            .store(in: &cancellables)

        // 2. 初始化当前 Session 的监听
        setupCurrentSessionObserver()

        // 3. 监听 iCloud 文件变更（使用单例）
        iCloudFileCoordinator.shared.$databaseFileChanged
            .filter { $0 == true } // 只处理变为 true 的情况
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.handleRemoteFileChange()
            }
            .store(in: &cancellables)
    }

    /// 设置当前 Session 的观察者（Session 切换时需要重新调用）
    private func setupCurrentSessionObserver() {
        // 取消旧的订阅
        currentSessionSubscription?.cancel()

        // 订阅当前活跃的 Session
        currentSessionSubscription = session.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 防御性检查：
                // 1. currentGame2 可能在数据库恢复等场景下变得不一致
                // 2. currentFenId 对应的 FenObject 可能不存在（数据库已替换）
                let fenId = self.session.currentFenId
                guard self.session.databaseView.containsFenId(fenId),
                      self.session.databaseView.getFenObject(fenId) != nil else {
                    return
                }
                self.updateBoardView()
            }
    }

    /// 更新棋盘视图（数据变化时调用）
    private func updateBoardView() {
        boardViewModel.updatePieceViews(fen: session.currentFen)
        boardViewModel.updateOrientation(orientation: session.isCurrentBlackOrientation ? "black" : "red")
        boardViewModel.updateHorizontalFlipped(flipped: session.isCurrentHorizontalFlipped)
        boardViewModel.updateCurrentFenPathGroups(currentFenPathGroups: currentFenPathGroups)
        boardViewModel.updateNextMovesPathGroups(nextMovesPathGroups: session.getNextMovesPathGroups())
        boardViewModel.updateShowPath(showPath: showPath)
        boardViewModel.updateShowAllNextMoves(showAllNextMoves: showAllNextMoves)


        // 通知 ViewModel 的观察者（View）
        objectWillChange.send()
    }
    
    /// 注册所有操作和快捷键
    private func registerActions() {
        actionDefinitions.registerAction(.toStart, text: "开局", shortcuts: [.single("^")], supportedModes: ActionDefinitions.allModes) { self.toStart() }

        #if os(macOS)
        actionDefinitions.registerAction(.stepBack, text: "后退", shortcuts: [.single("h"), .single(KeyEquivalent.leftArrow.character)], supportedModes: ActionDefinitions.allModes) { self.stepBackward() }
        actionDefinitions.registerAction(.stepForward, text: "前进", shortcuts: [.single("l"), .single(KeyEquivalent.rightArrow.character)], supportedModes: ActionDefinitions.allModes) { self.stepForward() }
        #else
        actionDefinitions.registerAction(.stepBack, text: "后退", shortcuts: [.single("h")], supportedModes: ActionDefinitions.allModes) { self.stepBackward() }
        actionDefinitions.registerAction(.stepForward, text: "前进", shortcuts: [.single("l")], supportedModes: ActionDefinitions.allModes) { self.stepForward() }
        #endif

        actionDefinitions.registerAction(.toEnd, text: "终局", shortcuts: [.single("$")], supportedModes: ActionDefinitions.allModes) { self.toEnd() }
        actionDefinitions.registerAction(.nextVariant, text: "下一变", textIPhone: "下变", shortcuts: [.single(" ")], supportedModes: [.normal, .review]) { self.playNextVariant() }

        actionDefinitions.registerAction(.previousPath, text: "复习上局", textIPhone: "上局", shortcuts: [.single("p")], supportedModes: [.review]) { self.goToPreviousPath() }
        actionDefinitions.registerAction(.nextPath, text: "复习下局", textIPhone: "下局", shortcuts: [.single("n")], supportedModes: [.review]) { self.goToNextPath() }
        actionDefinitions.registerAction(.random, text: "随机一局", shortcuts: [.sequence(",g")], supportedModes: [.review]) { _ = self.makeRandomGame() }
        actionDefinitions.registerAction(.reviewThisGame, text: "回顾本局", textIPhone: "回顾", shortcuts: [.single("R")], supportedModes: [.practice]) { self.reviewThisGame() }
        actionDefinitions.registerAction(.searchCurrentMove, text: "搜索此步", shortcuts: [.sequence(",/")], supportedModes: [.normal, .review]) { self.showSearchResultsWindow() }
        actionDefinitions.registerAction(.referenceBoard, text: "参考棋谱", shortcuts: [.modified([.command], "x")], supportedModes: [.normal, .review]) { self.showReferenceBoard() }

        actionDefinitions.registerAction(.practiceNewGame, text: "练习新局", textIPhone: "练习", shortcuts: [.single("P")], supportedModes: ActionDefinitions.allModes) { self.practiceNewGame() }
        actionDefinitions.registerAction(.focusedPractice, text: "练习本局", textIPhone: "专练", shortcuts: [.single("Z")], supportedModes: ActionDefinitions.allModes) { self.startFocusedPractice() }
        actionDefinitions.registerAction(.practiceRedOpening, text: "练习红方开局", supportedModes: ActionDefinitions.allModes) { self.practiceRedOpening() }
        actionDefinitions.registerAction(.practiceBlackOpening, text: "练习黑方开局", supportedModes: ActionDefinitions.allModes) { self.practiceBlackOpening() }
        actionDefinitions.registerAction(.playRandomNextMove, text: "随机走子", textIPhone: "随机", shortcuts: [.sequence(",r")], supportedModes: [.practice]) { self.playRandomNextMove() }
        actionDefinitions.registerAction(.hintNextMove, text: "提示", textIPhone: "提示", supportedModes: [.practice]) { self.playRandomNextMove() }

        actionDefinitions.registerAction(.queryScore, text: "查分", shortcuts: [.single("s")], supportedModes: [.normal, .review]) { Task { await self.queryFenScore() } }
        #if os(macOS) && arch(arm64)
        actionDefinitions.registerAction(.queryEngineScore, text: "皮卡鱼查分", supportedModes: [.normal, .review]) { Task { await self.queryEngineScore() } }
        actionDefinitions.registerAction(.queryAllEngineScores, text: "本局查皮卡鱼", supportedModes: [.normal, .review]) { Task { await self.queryAllEngineScores() } }
        #endif
        actionDefinitions.registerAction(.deleteScore, text: "删分", shortcuts: [.sequence(",D")], supportedModes: [.normal, .review]) { self.updateFenScore(self.currentFenId, score: nil) }
        actionDefinitions.registerAction(.openYunku, text: "云库", shortcuts: [.single("y")], supportedModes: [.normal, .review]) { self.openYunku() }
        actionDefinitions.registerAction(.deleteMove, text: "删招", shortcuts: [.sequence(",d")], supportedModes: [.normal, .review]) { self.removeCurrentStep() }
        actionDefinitions.registerAction(.removeMoveFromGame, text: "从局中删除此招", supportedModes: [.normal, .review]) { self.removeMoveFromGame() }
        actionDefinitions.registerAction(.markPath, text: "标记路径", shortcuts: [.single("a")], supportedModes: [.normal, .review]) { self.showMarkPathView = true }

        actionDefinitions.registerAction(.save, text: "保存", shortcuts: [.single("w")], supportedModes: ActionDefinitions.allModes) { self.saveToDefault() }
        actionDefinitions.registerAction(.checkDataVersion, text: "更新数据", textIPhone: "更新", shortcuts: [.sequence(",u")], supportedModes: ActionDefinitions.allModes) { self.checkDataVersion() }
        actionDefinitions.registerAction(.backup, text: "备份", shortcuts: [.sequence(",b")], supportedModes: [.normal]) { self.backup() }
        actionDefinitions.registerAction(.restore, text: "恢复", shortcuts: [.sequence(",R")], supportedModes: [.normal]) { Task { await self.recoverFromUserChoice() } }

        actionDefinitions.registerAction(.stepLimitation, text: "步数限制", supportedModes: [.normal]) { self.showingStepLimitationDialog = true }
        actionDefinitions.registerAction(.inputGame, text: "录入棋局", shortcuts: [.sequence(",i")], supportedModes: [.normal]) { self.showingGameInputView = true }
        actionDefinitions.registerAction(.browseGames, text: "棋局浏览器", shortcuts: [.sequence(",fff")], supportedModes: [.normal]) { self.showingGameBrowserView = true }
        actionDefinitions.registerAction(.importPGN, text: "导入PGN", shortcuts: [.sequence(",p")], supportedModes: [.normal]) { self.showingPGNImportSheet = true }

        actionDefinitions.registerAction(.fix, text: "修复", shortcuts: [.sequence(",fix")], supportedModes: [.normal]) { /* TODO */ }
        actionDefinitions.registerAction(.autoAddToOpening, text: "自动完善开局库", supportedModes: [.normal]) { self.performAutoAddToOpening() }
        actionDefinitions.registerAction(.jumpToNextOpeningGap, text: "跳转开局缺口", shortcuts: [.sequence(",o")], supportedModes: [.normal]) { self.jumpToNextOpeningGap() }

        actionDefinitions.registerAction(.showEditCommentIOS, text: "编辑评论", shortcuts: [.sequence(",e")], supportedModes: [.normal, .review]) { self.showEditCommentIOS = true }
        actionDefinitions.registerAction(.showBookmarkListIOS, text: "书签", shortcuts: [.sequence(",m")]) { self.showIOSBookMarkListView = true }
        actionDefinitions.registerAction(.showMoreActionsIOS, text: "更多", shortcuts: [.sequence(",a")]) { self.showIOSMoreActionsView = true }
      
        actionDefinitions.registerToggleAction(
          .setFilterNone,
          text: "不筛选",
          shortcuts: [.single("0")],
          isEnabled: { true },
          isOn:  {
            return self.session.currentFilters.isEmpty
          },
          action: { _ in self.setFilterNone() }
        )
        
        actionDefinitions.registerToggleAction(
          .toggleFilterRedOpeningOnly,
          text: "只筛选红方开局",
          shortcuts: [.single("1")],
          isEnabled: { true },
          isOn: { self.currentFilters.contains(Session.filterRedOpeningOnly) },
          action: { _ in self.toggleFilterRedOpeningOnly() }
        )

        actionDefinitions.registerToggleAction(
          .toggleFilterBlackOpeningOnly,
          text: "只筛选黑方开局",
          shortcuts: [.single("2")],
          isEnabled: { true },
          isOn: { self.currentFilters.contains(Session.filterBlackOpeningOnly) },
          action: { _ in self.toggleFilterBlackOpeningOnly() }
        )

        actionDefinitions.registerToggleAction(
          .toggleFilterRedRealGameOnly,
          text: "只筛选红方实战",
          shortcuts: [.single("3")],
          isEnabled: { true },
          isOn: { self.currentFilters.contains(Session.filterRedRealGameOnly) },
          action: { _ in self.toggleFilterRedRealGameOnly() }
        )

        actionDefinitions.registerToggleAction(
          .toggleFilterBlackRealGameOnly,
          text: "只筛选黑方实战",
          shortcuts: [.single("4")],
          isEnabled: { true },
          isOn: { self.currentFilters.contains(Session.filterBlackRealGameOnly) },
          action: { _ in self.toggleFilterBlackRealGameOnly()
          }
        )

        actionDefinitions.registerToggleAction(
          .setFilterFocusedPractice,
          text: "专注练习筛选",
          isEnabled: { false },
          isOn: { self.currentFilters.contains(Session.filterFocusedPractice) },
          action: { _ in }
        )

        actionDefinitions.registerToggleAction(
          .toggleFilterSpecificGame,
          text: "只筛选特定棋局",
          isEnabled: { self.session.sessionData.specificGameId != nil },
          isOn: { self.currentFilters.contains(Session.filterSpecificGame) },
          action: { _ in self.toggleFilterSpecificGame() }
        )

        actionDefinitions.registerToggleAction(
          .toggleFilterSpecificBook,
          text: "只筛选特定棋书",
          isEnabled: { self.session.sessionData.specificBookId != nil },
          isOn: { self.currentFilters.contains(Session.filterSpecificBook) },
          action: { _ in self.toggleFilterSpecificBook() }
        )

        actionDefinitions.registerToggleAction(
          .toggleStepLimitation,
          text: "步数限制",
          shortcuts: [.sequence(",l")],
          isEnabled: { true },
          isOn: { self.gameStepLimitation != nil },
          action: { newValue in
            if newValue {
                self.showingStepLimitationDialog = true
            } else {
                self.setGameStepLimitation(nil)
            }
          }
        )

        actionDefinitions.registerToggleAction(
          .inRedOpening,
          text: "列入红方开局库",
          shortcuts: [.single("r")],
          isEnabled: { self.currentFenCanChangeInRedOpening },
          isOn: { self.currentFenIsInRedOpening },
          action: { newValue in
            if (self.currentFenCanChangeInRedOpening) {
              self.setCurrentFenInRedOpening(newValue)
            }
          }
        )
        
        actionDefinitions.registerToggleAction(
          .inBlackOpening,
          text: "列入黑方开局库",
          shortcuts: [.single("b")],
          isEnabled: { self.currentFenCanChangeInBlackOpening },
          isOn: { self.currentFenIsInBlackOpening },
          action: { newValue in
            if (self.currentFenCanChangeInBlackOpening) {
              self.setCurrentFenInBlackOpening(newValue)
            }
          }
        )

        actionDefinitions.registerToggleAction(
          .toggleLock,
          text: "锁定",
          shortcuts: [.single("L")],
          isEnabled: { true },
          isOn: { self.isAnyMoveLocked },
          action: { newValue in
            self.toggleLock()
          }
        )

        actionDefinitions.registerToggleAction(
          .toggleCanNavigateBeforeLockedStep,
          text: "锁定区域可以前进后退",
          shortcuts: [.sequence(",n")],
          isEnabled: { self.isAnyMoveLocked },
          isOn: { self.canNavigateBeforeLockedStep },
          action: { newValue in
            self.toggleCanNavigateBeforeLockedStep()
          }
        )

        // 棋盘操作 - 练习、复习和常规模式都需要
        actionDefinitions.registerToggleAction(
          .flip,
          text: "黑方视角",
          shortcuts: [.single("f")],
          supportedModes: [.practice, .review, .normal],
          isEnabled: { self.session.sessionData.currentMode != .practice },
          isOn: { self.isCurrentBlackOrientation },
          action: { newValue in
            self.flipOrientation()
          }
        )

        actionDefinitions.registerToggleAction(
          .flipHorizontal,
          text: "左右翻转",
          shortcuts: [.single("z")],
          supportedModes: [.practice, .review, .normal],
          isEnabled: { self.session.sessionData.currentMode != .practice },
          isOn: { self.isCurrentHorizontalFlipped },
          action: { newValue in
            self.flipHorizontal()
          }
        )

        actionDefinitions.registerToggleAction(
          .toggleAutoExtendGameWhenPlayingBoardFen,
          text: "棋盘走子时自动往后拓展",
          shortcuts: [.sequence(",x")],
          isEnabled: { self.session.sessionData.currentMode != .practice },
          isOn: { self.autoExtendGameWhenPlayingBoardFen },
          action: { newValue in
            self.toggleAutoExtendGameWhenPlayingBoardFen()
          }
        )

        // 模式切换 - 练习、复习和常规模式都需要
        actionDefinitions.registerToggleAction(
          .togglePracticeMode,
          text: "练习模式",
          shortcuts: [.sequence(",p")],
          supportedModes: [.practice, .review, .normal],
          isEnabled: { true },
          isOn: { self.session.sessionData.currentMode == .practice },
          action: { newValue in
            self.togglePracticeMode()
          }
        )

        // 路径相关 - 只在复习和常规模式可用
        actionDefinitions.registerToggleAction(
          .toggleShowPath,
          text: "显示路径",
          shortcuts: [.sequence(",s")],
          supportedModes: [.review, .normal],
          isEnabled: { self.session.sessionData.currentMode != .practice },
          isOn: { self.showPath },
          action: { newValue in
            self.toggleShowPath()
          }
        )

        // 显示所有下一步 - 只在复习和常规模式可用
        actionDefinitions.registerToggleAction(
          .toggleShowAllNextMoves,
          text: "显示所有下一步",
          shortcuts: [.sequence(",n")],
          supportedModes: [.review, .normal],
          isEnabled: { self.session.sessionData.currentMode != .practice },
          isOn: { self.showAllNextMoves },
          action: { newValue in
            self.toggleShowAllNextMoves()
          }
        )

        // 书签功能 - 只在复习和常规模式可用
        actionDefinitions.registerToggleAction(
          .toggleBookmark,
          text: "加入书签",
          shortcuts: [.single("m")],
          supportedModes: [.review, .normal],
          isEnabled: { true },
          isOn: { self.isBookmarked },
          action: { newValue in
            if newValue {
              self.showingBookmarkAlert = true
            } else {
              _ = self.removeBookmark()
            }
          }
        )

        // 评论功能 - 只在复习和常规模式可用
        actionDefinitions.registerToggleAction(
          .toggleIsCommentEditing,
          text: "编辑评论区",
          shortcuts: [.single("c")],
          supportedModes: [.review, .normal],
          isEnabled: { true },
          isOn: { self.isCommentEditing },
          action: { newValue in
            self.session.toggleIsCommentEditing()
          }
        )

        // 允许增加新走法 - 只在无过滤或特定棋局模式下可用
        actionDefinitions.registerToggleAction(
          .toggleAllowAddingNewMoves,
          text: "允许增加新走法",
          isEnabled: { self.session.canToggleAllowAddingNewMoves },
          isOn: { self.session.allowAddingNewMoves },
          action: { _ in self.session.toggleAllowAddingNewMoves() }
        )
    }
    
    // MARK: - 棋盘操作
    
    /// 处理棋盘移动
    func handleBoardMove(_ newFen: String) {
        if self.session.sessionData.currentMode == .practice {
            if !session.hasNextMove {
                platformService.showWarningAlert(
                    title: "棋谱结束",
                    message: "棋谱结束"
                )
            } else if !session.checkBoardFenInNextMoveList(newFen) {
                platformService.showWarningAlert(
                    title: "没有着法",
                    message: "没有着法，请检查棋谱是否正确。"
                )
            } else {
                session.playNewBoardFen(newFen)
                queryFenScoreSilentlyIfNeeded()
                if !session.hasNextMove {
                    platformService.showWarningAlert(
                        title: "棋谱结束",
                        message: "棋谱结束"
                    )
                } else {
                    playRandomIfYourTurn(delay: 1.0)
                }
            }
        } else {
            let success = session.playNewBoardFen(newFen)
            if success {
                queryFenScoreSilentlyIfNeeded()
            } else {
                // 操作失败，检查是否因为不允许添加新走法
                if !session.allowAddingNewMoves {
                    platformService.showWarningAlert(
                        title: "不允许增加新走法",
                        message: "当前【允许增加新走法】选项已关闭。\n如果您想添加这个走法，请先打开此选项。"
                    )
                }
            }
        }
    }
    
    // MARK: - 导航操作
    
    func toStart() {
        session.toStart()
        queryFenScoreSilentlyIfNeeded()
    }
    
    func stepBackward() {
        session.stepBackward()
        queryFenScoreSilentlyIfNeeded()
    }
    
    func stepForward() {
        session.stepForward()
        queryFenScoreSilentlyIfNeeded()
    }
    
    func toEnd() {
        session.toEnd()
        queryFenScoreSilentlyIfNeeded()
    }
    
    func playNextVariant() {
        session.playNextVariant()
        queryFenScoreSilentlyIfNeeded()
    }
    
    func toStepIndex(_ index: Int) {
        session.toStepIndex(index)
        queryFenScoreSilentlyIfNeeded()
    }
    
    func playVariantIndex(_ index: Int) {
        session.playVariantIndex(index)
        queryFenScoreSilentlyIfNeeded()
    }

    func playVariantMove(_ move: Move) {
        session.playVariantMove(move)
        queryFenScoreSilentlyIfNeeded()
    }

    func goToPreviousPath() {
        session.goToPreviousPath()
        queryFenScoreSilentlyIfNeeded()
    }
    
    func goToNextPath() {
        session.goToNextPath()
        queryFenScoreSilentlyIfNeeded()
    }
    
    // MARK: - 棋局操作
    
    func toggleLock() {
        session.toggleLock()
    }
    
    func toggleCanNavigateBeforeLockedStep() {
        session.toggleCanNavigateBeforeLockedStep()
    }
    
    func flipOrientation() {
        session.flipOrientation()
    }
    
    func flipHorizontal() {
        session.flipHorizontal()
    }
    
    func removeCurrentStep() {
        session.removeCurrentStep()
    }

    /// 从特定棋局中删除当前招法
    func removeMoveFromGame() {
        session.removeMoveFromGame()
    }

    // MARK: - 开局库操作（过滤切换）

    /// 切换筛选器：添加或移除单个 filter
    private func toggleFilter(_ filter: String) {
        var newFilters = session.currentFilters

        if newFilters.contains(filter) {
            // 如果已存在，移除它
            newFilters.removeAll { $0 == filter }
        } else {
            // 如果不存在，添加它
            newFilters.append(filter)
        }

        // 显式传递当前的 specificGameId 和 specificBookId，避免依赖隐式保留逻辑
        sessionManager.setFilters(
            newFilters,
            focusedPath: session.sessionData.focusedPracticeGamePath,
            specificGameId: session.sessionData.specificGameId,
            specificBookId: session.sessionData.specificBookId
        )
    }

    /// 切换到无过滤（Full 视图）
    func setFilterNone() {
        // "不筛选" 是特殊的：清空所有 filters
        sessionManager.setFilters([])
    }

    /// 切换红方开局筛选
    func toggleFilterRedOpeningOnly() {
        toggleFilter(Session.filterRedOpeningOnly)
    }

    /// 切换黑方开局筛选
    func toggleFilterBlackOpeningOnly() {
        toggleFilter(Session.filterBlackOpeningOnly)
    }

    /// 切换红方实战筛选
    func toggleFilterRedRealGameOnly() {
        toggleFilter(Session.filterRedRealGameOnly)
    }

    /// 切换黑方实战筛选
    func toggleFilterBlackRealGameOnly() {
        toggleFilter(Session.filterBlackRealGameOnly)
    }

    /// 切换特定棋局筛选
    func toggleFilterSpecificGame() {
        var newFilters = session.currentFilters

        if newFilters.contains(Session.filterSpecificGame) {
            newFilters.removeAll { $0 == Session.filterSpecificGame }
            // 关闭时显式清除 specificGameId
            sessionManager.setFilters(newFilters, specificGameId: nil)
        } else {
            if let gameId = session.sessionData.specificGameId {
                // 互斥：选中"特定棋局"时，取消"特定棋书"
                newFilters.removeAll { $0 == Session.filterSpecificBook }
                newFilters.append(Session.filterSpecificGame)
                sessionManager.setFilters(newFilters, specificGameId: gameId)
            }
        }
    }

    /// 切换特定棋书筛选
    func toggleFilterSpecificBook() {
        var newFilters = session.currentFilters

        if newFilters.contains(Session.filterSpecificBook) {
            newFilters.removeAll { $0 == Session.filterSpecificBook }
            // 关闭时显式清除 specificBookId
            sessionManager.setFilters(newFilters, specificBookId: nil)
        } else {
            if let bookId = session.sessionData.specificBookId {
                // 互斥：选中"特定棋书"时，取消"特定棋局"
                newFilters.removeAll { $0 == Session.filterSpecificGame }
                newFilters.append(Session.filterSpecificBook)
                sessionManager.setFilters(newFilters, specificBookId: bookId)
            }
        }
    }

    func setCurrentFenInRedOpening(_ value: Bool) {
        if session.currentFenCanChangeInRedOpening {
            session.setCurrentFenInRedOpening(value)

            // 如果在红方开局过滤模式下，且将当前位置移出开局库，则刷新视图
            // 使用双重异步调用确保在下一个 runloop 周期执行，避免与 Session.notifyDataChanged 的 async 竞态
            if session.currentFilters.contains(Session.filterRedOpeningOnly) && !value {
                let currentFilters = session.currentFilters
                DispatchQueue.main.async {
                    DispatchQueue.main.async { [weak self] in
                        self?.sessionManager.setFilters(currentFilters)
                    }
                }
            }
        }
    }
    
    func setCurrentFenInBlackOpening(_ value: Bool) {
        if session.currentFenCanChangeInBlackOpening {
            session.setCurrentFenInBlackOpening(value)

            // 如果在黑方开局过滤模式下，且将当前位置移出开局库，则刷新视图
            // 使用双重异步调用确保在下一个 runloop 周期执行，避免与 Session.notifyDataChanged 的 async 竞态
            if session.currentFilters.contains(Session.filterBlackOpeningOnly) && !value {
                let currentFilters = session.currentFilters
                DispatchQueue.main.async {
                    DispatchQueue.main.async { [weak self] in
                        self?.sessionManager.setFilters(currentFilters)
                    }
                }
            }
        }
    }
    
    // MARK: - 书签和棋局加载操作

    /// 加载书签（总是先切换到 Full 视图）
    func loadBookmark(_ game: [Int]) {
        sessionManager.loadBookmark(game)
    }

    /// 加载棋局（总是先切换到 Full 视图）
    func loadGame(_ gameId: UUID) {
        sessionManager.loadGame(gameId)
    }

    func loadBook(_ bookId: UUID) {
        sessionManager.loadBook(bookId)
    }

    func addBookmark(_ name: String) -> Bool {
        return session.toggleBookmark { name }
    }

    func removeBookmark() -> Bool {
        return session.toggleBookmark { nil }
    }
    
    // MARK: - 评论操作
    
    func updateCurrentFenComment(_ comment: String) {
        session.updateCurrentFenComment(comment)
    }
    
    func updateCurrentMoveComment(_ comment: String) {
        session.updateCurrentMoveComment(comment)
    }

    func updateCurrentMoveBadReason(_ badReason: String?) {
        session.updateCurrentMoveBadReason(badReason)
    }

    func getRandomNextMove() -> Move? {
        session.getRandomNextMove()
    }
    
    // MARK: - 分数操作
    
    func updateFenScore(_ fenId: Int, score: Int?) {
        session.updateFenScore(fenId, score: score)
    }
    
    // MARK: - 存储操作

    func checkDataVersion() {
        // 检查远程数据库版本
        if let dataVersion = DatabaseStorage.loadDataVersionFromDefault(),
            dataVersion != session.currentCheckpointDataVersion {
                platformService.showConfirmAlert(
                    title: "存档文件版本不对",
                    message: "检测到存档文件中的版本号不对。应该是\(session.currentCheckpointDataVersion)，实际是 \(dataVersion)。 可能存档文件在别处被修改过。请问是否要重新加载存档？",
                    completion: { result in
                        if result {
                            do {
                                // 重新加载数据库（通过 DatabaseView）
                                try self.session.databaseView.reload()
                                // session 保持不变（每个窗口独立）
                                self.platformService.showAlert(
                                    title: "数据已更新",
                                    message: "已从远程同步最新数据"
                                )
                            } catch {
                                self.platformService.showAlert(
                                    title: "读取存档失败",
                                    message: "读取存档失败：\(error.localizedDescription)"
                                )
                            }
                        }
                    }
                )
        } else {
            platformService.showAlert(
                title: "存档文件版本号一致",
                message: "存档文件版本号与当前版本号一致，无需更新。"
            )
        }
    }
    
    func saveToDefault() {
        let session = self.session

        // 检查远程版本（database）
        if let remoteVersion = DatabaseStorage.loadDataVersionFromDefault(),
           remoteVersion > session.currentCheckpointDataVersion {
            platformService.showConfirmAlert(
                title: "存档文件可能在别处被修改过",
                message: "检测到存档文件中的版本号大于当前版本号，可能存档文件在别处被修改过。请问是否要覆盖存档文件，强行保存？",
                completion: { result in
                    if result {
                        self.saveToDefaultWithResultNotification(session: session)
                    } else {
                        self.showWarningAlert( message: "保存取消", info: "保存取消")
                    }
                }
            )
        } else {
            self.saveToDefaultWithResultNotification(session: session)
        }
    }

    func saveToDefaultWithResultNotification(session: Session) {
        do {
            // 1. 保存 database（通过 DatabaseView）
            try session.databaseView.save()

            // 2. 保存引擎分数文件
            try session.databaseView.saveEngineScores()

            // 3. 保存 mainSession（通过 SessionStorage）
            // 注意：只保存 mainSession，practiceSession 是临时的
            try SessionStorage.saveSessionToDefault(session: sessionManager.mainSessionData)

            self.setDataClean()
            self.showAlert(
                message: "保存成功",
                info: "数据已成功保存"
            )
        } catch {
            self.showWarningAlert(
                message: "保存失败",
                info: "无法保存数据：\(error.localizedDescription)"
            )
        }
    }

    /// 处理远程文件变更（其他设备修改了 database.json）
    private func handleRemoteFileChange() {
        print("[ViewModel] 检测到远程文件变更")

        // 重置 coordinator 的变更标志
        iCloudFileCoordinator.shared.resetFileChangeFlag()

        // 检查是否有未保存的本地修改
        if session.databaseDirty {
            // 本地有未保存修改，需要进一步判断是否真的冲突
            // 只读取远程版本号（高效，不加载整个数据库）
            guard let remoteVersion = DatabaseStorage.loadDataVersionFromDefault() else {
                print("[ViewModel] 无法读取远程版本号，忽略此次文件变更通知")
                return
            }

            let localCheckpointVersion = session.currentCheckpointDataVersion

            print("[ViewModel] 版本比较: 本地checkpoint=\(localCheckpointVersion), 远程=\(remoteVersion)")

            if remoteVersion > localCheckpointVersion {
                // 真实冲突：远程有新修改，本地也有新修改
                print("[ViewModel] 检测到真实冲突：远程版本更新")
                showConflictAlert()
            } else {
                // 不是冲突：远程数据就是本地的base版本（或更旧）
                print("[ViewModel] 远程数据是本地base版本，无需处理")
            }
        } else {
            // 无冲突：本地无修改，直接加载远程数据
            reloadFromRemote()
        }
    }

    /// 从远程重新加载数据
    private func reloadFromRemote() {
        print("[ViewModel] 从远程重新加载数据")

        // 检查版本号：只有远程版本更新时才加载
        let currentVersion = session.currentCheckpointDataVersion
        guard let remoteVersion = DatabaseStorage.loadDataVersionFromDefault() else {
            platformService.showWarningAlert(
                title: "加载失败",
                message: "无法从远程加载最新数据"
            )
            return
        }

        if remoteVersion <= currentVersion {
            print("[ViewModel] 远程版本(\(remoteVersion))未变化或更旧，忽略加载（当前版本: \(currentVersion)）")
            return
        }

        print("[ViewModel] 远程版本(\(remoteVersion))更新，加载数据（当前版本: \(currentVersion)）")

        do {
            // 重新加载数据库（数据库是全局共享的，通过 DatabaseView）
            try session.databaseView.reload()

            // session 保持不变（每个窗口独立）

            // 通知用户
            platformService.showAlert(
                title: "数据已更新",
                message: "已从其他设备同步最新数据（版本 \(currentVersion) → \(remoteVersion)）"
            )
        } catch {
            platformService.showWarningAlert(
                title: "加载失败",
                message: "无法从远程加载最新数据：\(error.localizedDescription)"
            )
        }
    }

    /// 显示冲突解决对话框
    private func showConflictAlert() {
        print("[ViewModel] 检测到数据冲突：本地有未保存修改，远程也有更新")

        platformService.showConfirmAlert(
            title: "数据冲突",
            message: "检测到其他设备已更新数据，但您本地也有未保存的修改。\n\n选择「保留本地」将覆盖远程数据（其他设备的修改会丢失）\n选择「使用远程」将丢弃本地未保存的修改\n\n建议：先选择「保留本地」并保存，然后手动合并数据。",
            completion: { [weak self] useLocal in
                guard let self = self else { return }

                if useLocal {
                    // 用户选择保留本地修改
                    print("[ViewModel] 用户选择保留本地修改，将覆盖远程数据")

                    do {
                        // 强制保存本地数据到 iCloud（覆盖远程，通过 DatabaseView）
                        try self.session.databaseView.save()
                        // 注意：只保存 mainSession，practiceSession 是临时的
                        try SessionStorage.saveSessionToDefault(session: self.sessionManager.mainSessionData)
                        self.setDataClean()

                        self.platformService.showAlert(
                            title: "已保存",
                            message: "本地修改已保存并同步到 iCloud"
                        )
                    } catch {
                        self.platformService.showWarningAlert(
                            title: "保存失败",
                            message: "无法保存本地修改：\(error.localizedDescription)"
                        )
                    }
                } else {
                    // 用户选择使用远程数据
                    print("[ViewModel] 用户选择使用远程数据，将丢弃本地修改")
                    self.reloadFromRemote()

                    // 清除 dirty 标志（因为已经放弃本地修改）
                    self.setDataClean()
                }
            }
        )
    }
    
    /// 生成包含数据版本号和日期的备份文件名
    /// - Returns: 格式为 "store_backup_v{dataVersion}_{date}.json" 的文件名
    private func generateBackupFileName() -> String {
        let version = session.databaseView.dataVersion
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())
        return "store_backup_v\(version)_\(dateString).json"
    }

    /// 备份数据库到用户选择的位置
    func backup() {
        platformService.saveFile(defaultName: generateBackupFileName()) { [weak self] url in
            guard let self = self else { return }
            if let url = url {
                do {
                    // 委托给 DatabaseStorage 执行备份（通过 DatabaseView）
                    try DatabaseStorage.saveDatabaseBackup(self.session.databaseView.databaseDataForBackup, to: url)
                    print("✅ 备份成功")
                } catch {
                    print("❌ 备份失败：\(error)")
                }
            }
        }
    }

    /// 通过用户选择文件方式恢复数据库
    /// - Note: 此方法会通过 DatabaseView 恢复数据库，影响所有窗口
    func recoverFromUserChoice() async {
        let service = platformService
        let success = await withCheckedContinuation { continuation in
            service.openFile { [weak self] url in
                guard let self = self else {
                    continuation.resume(returning: false)
                    return
                }

                if let url = url {
                    do {
                        // 1. 通过 DatabaseStorage 加载备份
                        let database = try DatabaseStorage.loadDatabaseBackup(from: url)
                        print("✅ 成功加载备份文件")

                        // 2. 恢复数据库到全局 Database（影响所有窗口，通过 DatabaseView）
                        self.session.databaseView.restoreFromBackup(database)
                        print("✅ 数据库已恢复")

                        continuation.resume(returning: true)
                    } catch {
                        print("❌ 从选定文件恢复失败：\(error)")
                        continuation.resume(returning: false)
                    }
                } else {
                    print("⚠️ 用户取消了文件选择")
                    continuation.resume(returning: false)
                }
            }
        }

        if success {
            // 恢复备份后，currentGame2 中的 fenId 可能在新数据库中不存在
            // 强制清空游戏状态并重置到起始局面
            await MainActor.run {
                self.session.resetGameStateForDatabaseRestore()
                self.session.objectWillChange.send()
            }

            // 通知用户恢复成功
            platformService.showAlert(
                title: "恢复成功",
                message: "数据库已从备份文件恢复"
            )
        }
    }
    
    func performAutoAddToOpening() {
        let result = session.autoAddMovesToOpening()
        let message = "已自动添加：\n红方开局库：\(result.redAdded) 个招法\n黑方开局库：\(result.blackAdded) 个招法"
        platformService.showAlert(title: "自动完善开局库", message: message)
    }
    
    func jumpToNextOpeningGap() {
        // 先查找下一个开局缺口
        if let stepIndex = session.findNextOpeningGap() {
            // 只有找到缺口时才清除过滤和锁定

            // 如果有锁定，先解锁
            if session.isAnyMoveLocked {
                session.toggleLock()
            }

            // 如果在过滤模式，切换到无过滤
            if !session.currentFilters.isEmpty {
                setFilterNone()
            }

            // 跳转到找到的位置
            session.toStepIndex(stepIndex)
        } else {
            // 没找到缺口，保持当前状态不变
            platformService.showAlert(
                title: "完成",
                message: "没有需要手工完善的开局库局面了"
            )
        }
    }
    
    // MARK: - 网络操作
    
    func queryFenScore() async {
        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else {return}
        let yunKuFen = String(fen.split(separator: " - ")[0])
        
        do {
            if let score = try await IO.queryFenScore(yunKuFen, silentMode: false) {
                await MainActor.run {
                    session.updateFenScore(fenId, score: score)
                }
            } else {
                platformService.showWarningAlert(
                    title: "查询失败",
                    message: "网络连接错误，无法从云库获取分数"
                )
            }
        } catch {
            platformService.showWarningAlert(
                title: "查询失败2",
                message: "网络连接错误，无法从云库获取分数"
            )
        }
    }

    func queryFenScoreSilentlyIfNeeded() {
        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else {return}
        if session.getScoreByFenId(fenId) != nil { return }

        let yunKuFen = String(fen.split(separator: " - ")[0])
        
        Task.detached {
            do {
                if let score = try await IO.queryFenScore(yunKuFen, silentMode: true) {
                    await MainActor.run {
                        self.updateFenScore(fenId, score: score)
                    }
                }
            } catch {
                // 在后台默默地跑，所以忽略错误
            }
        }
    }
    
    // MARK: - 引擎评估（macOS）

    #if os(macOS)
    /// 确保 PikafishService 已创建
    private func ensurePikafishService() -> PikafishService? {
        #if arch(arm64)
        if pikafishService == nil {
            pikafishService = PikafishService()
        }
        return pikafishService
        #else
        return nil
        #endif
    }

    func queryEngineScore() async {
        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else { return }
        guard let service = ensurePikafishService() else { return }

        isBatchEvaluating = true
        batchEvalCancelled = false
        defer { isBatchEvaluating = false }

        let startTime = Date()
        await MainActor.run {
            self.batchEvalProgress = BatchEvalProgress(current: 0, total: 1, evaluatedCount: 0, lastDetail: nil, elapsedSeconds: nil, isCompleted: false)
        }

        do {
            if batchEvalCancelled { return }

            if let result = try await service.evaluatePosition(fen: fen) {
                if batchEvalCancelled { return }
                let detail = Self.formatEvalDetail(result)
                let elapsed = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    session.updateEngineScore(fenId, score: result.score, engineKey: PikafishService.engineKey)
                    self.batchEvalProgress = BatchEvalProgress(current: 1, total: 1, evaluatedCount: 1, lastDetail: detail, elapsedSeconds: elapsed, isCompleted: true)
                }
            } else {
                await MainActor.run {
                    self.batchEvalProgress = nil
                }
            }
        } catch {
            await MainActor.run { self.batchEvalProgress = nil }
            platformService.showWarningAlert(
                title: "皮卡鱼评估失败",
                message: error.localizedDescription
            )
        }
    }


    private static func formatEvalDetail(_ result: PikafishService.EvaluationResult) -> String {
        var parts: [String] = []
        if let depth = result.depth {
            parts.append("深度\(depth)")
        }
        if let ms = result.timeMs {
            parts.append("耗时\(String(format: "%.1f", Double(ms) / 1000.0))s")
        }
        if let h = result.hashfull {
            parts.append("Hash\(h * 100 / 1000)%")
        }
        if result.timedOut {
            parts.append("超时")
        }
        return parts.joined(separator: " ")
    }

    func cancelBatchEval() {
        batchEvalCancelled = true
        batchEvalProgress = nil
    }

    func dismissBatchEvalProgress() {
        batchEvalProgress = nil
    }

    func queryAllEngineScores() async {
        guard let service = ensurePikafishService() else { return }

        isBatchEvaluating = true
        batchEvalCancelled = false
        defer { isBatchEvaluating = false }

        let game = session.sessionData.currentGame2
        let totalSteps = game.count
        var evaluatedCount = 0
        var lastDetail: String?
        let startTime = Date()

        await MainActor.run {
            self.batchEvalProgress = BatchEvalProgress(current: 0, total: totalSteps, evaluatedCount: 0, lastDetail: nil, elapsedSeconds: nil, isCompleted: false)
        }

        // 从前往后搜索，利用 Hash 表复用加速后续局面
        for i in 0..<totalSteps {
            if batchEvalCancelled { break }

            let fenId = game[i]

            // 跳过已有引擎分数的局面
            if Database.shared.getEngineScore(fenId: fenId, engineKey: PikafishService.engineKey) != nil {
                let elapsed = Date().timeIntervalSince(startTime)
                let count = evaluatedCount
                let detail = lastDetail
                await MainActor.run {
                    self.batchEvalProgress = BatchEvalProgress(current: i + 1, total: totalSteps, evaluatedCount: count, lastDetail: detail, elapsedSeconds: elapsed, isCompleted: false)
                }
                continue
            }

            guard let fen = session.getFenForId(fenId) else { continue }

            let elapsed = Date().timeIntervalSince(startTime)
            let countBefore = evaluatedCount
            let detailBefore = lastDetail
            await MainActor.run {
                self.batchEvalProgress = BatchEvalProgress(current: i, total: totalSteps, evaluatedCount: countBefore, lastDetail: detailBefore, elapsedSeconds: elapsed, isCompleted: false)
            }

            do {
                // evaluatePosition 用 try() 获取锁，如果被占用返回 nil
                // 等待当前评估完成后重试一次
                var result = try await service.evaluatePosition(fen: fen)
                if result == nil {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    result = try await service.evaluatePosition(fen: fen)
                }

                if batchEvalCancelled { break }

                if let result = result {
                    lastDetail = Self.formatEvalDetail(result)
                    await MainActor.run {
                        self.session.updateEngineScore(fenId, score: result.score, engineKey: PikafishService.engineKey)
                    }
                    evaluatedCount += 1
                }
            } catch {
                print("[Pikafish] 全局评估 \(i)/\(totalSteps - 1) fenId=\(fenId) 失败: \(error.localizedDescription)")
                break
            }

            let elapsedAfter = Date().timeIntervalSince(startTime)
            let countAfter = evaluatedCount
            let detailAfter = lastDetail
            await MainActor.run {
                self.batchEvalProgress = BatchEvalProgress(current: i + 1, total: totalSteps, evaluatedCount: countAfter, lastDetail: detailAfter, elapsedSeconds: elapsedAfter, isCompleted: false)
            }
        }

        // 完成后显示最终结果
        let finalElapsed = Date().timeIntervalSince(startTime)
        let finalCount = evaluatedCount
        let finalDetail = lastDetail
        await MainActor.run {
            self.batchEvalProgress = BatchEvalProgress(current: totalSteps, total: totalSteps, evaluatedCount: finalCount, lastDetail: finalDetail, elapsedSeconds: finalElapsed, isCompleted: true)
        }
    }

    #endif

    func openYunku() {
        let fen = session.currentFen
        let yunkuFen = fen.split(separator: " - ")[0]
        if let url = URL(string: "http://www.qqzze.com/yunku/?" + yunkuFen) {
            platformService.openURL(url)
        }
    }
    
    // MARK: - 随机游戏
    
    func makeRandomGame() -> Int? {
        // 如果没有锁定的着法，随机设置过滤器
        if !isAnyMoveLocked {
            if Bool.random() {
                toggleFilterRedOpeningOnly()
            } else {
                toggleFilterBlackOpeningOnly()
            }
        }

        // 生成随机游戏
        return session.playRandomGame()
    }
    
    // MARK: - 辅助方法
    
    func showGlobalAlert(title: String, message: String) {
        globalAlertTitle = title
        globalAlertMessage = message
        showingGlobalAlert = true
    }
    
    func showWarningAlert(message: String, info: String) {
        platformService.showWarningAlert(title: message, message: info)
    }
    
    func showAlert(message: String, info: String) {
        platformService.showAlert(title: message, message: info)
    }
    
    func showReferenceBoard() {
        #if os(macOS)
        let item = ReferenceBoardItem(
            fen: session.currentFen,
            orientation: session.isCurrentBlackOrientation ? "black" : "red",
            isHorizontalFlipped: session.isCurrentHorizontalFlipped,
            showPath: showPath,
            currentFenPathGroups: session.getCurrentFenPathGroups(),
            score: displayScore,
            scoreDelta: "",
            comments: session.currentCombinedComment ?? ""
        )

        if let controller = referenceBoardWindowController, controller.window?.isVisible == true {
            controller.update(item)
        } else {
            let controller = ReferenceBoardWindowController(item: item)
            referenceBoardWindowController = controller
            controller.showWindow(nil)
        }
        #endif
    }
    
    func showSearchResultsWindow() {
        #if os(macOS)
        let searchResults = session.searchCurrentMove()

        let items = searchResults.map { move in
            let pathGroups = session.getPathGroups(fenId: move.targetFenId!)
            let comments = session.getCombinedComment(fenObject: nil, move: move)
            let fen = session.getFenForId(move.targetFenId!)!
            let orientation = session.isCurrentBlackOrientation ? "black" : "red"
            let isHorizontalFlipped = session.isCurrentHorizontalFlipped
            let showPath = session.showPath
            let score = session.getDisplayScoreForMove(move)
            let scoreDelta = session.getDisplayScoreDeltaForMove(move)
            let text = session.getMoveString(move: move)

            return SearchResultItem(
                text: text,
                fen: fen,
                orientation: orientation,
                isHorizontalFlipped: isHorizontalFlipped,
                showPath: showPath,
                currentFenPathGroups: pathGroups,
                score: score,
                scoreDelta: scoreDelta,
                comments: comments ?? ""
            )
        }
        
        let windowController = SearchResultsWindowController(items: items)
        windowController.showWindow(nil)
        #endif
    }
    
    // MARK: - 计算属性
    
    // 从 Session 转发的计算属性
    var currentFenId: Int { session.currentFenId }
    var displayScore: String { session.displayScore }
    var displayEngineScore: String { session.displayEngineScore }
    var currentGameStepDisplay: Int { session.currentGameStepDisplay }
    var maxGameStepDisplay: Int { session.maxGameStepDisplay }
    var currentFenComment: String? { session.currentFenComment }
    var currentMoveComment: String? { session.currentMoveComment }
    var currentMoveBadReason: String? { session.currentMoveBadReason }
    var currentCombinedComment: String? { session.currentCombinedComment }
    var bookmarkList: [(game: [Int], name: String)] { session.bookmarkList }
    var currentGameMoveListDisplay: [MoveListItem] { session.currentGameMoveList }
    var currentGameVariantListDisplay: [(moveString: String, move: Move)] {
        session.currentGameVariantList.sorted { $0.moveString < $1.moveString }
    }
    
    // 路径相关的属性
    var currentPathIndexDisplay: Int? { session.currentPathIndexDisplay }
    var totalPathsCount: Int? { session.totalPathsCount }
    var totalPathsCountFromCurrentFen: Int? { session.totalPathsCountFromCurrentFen }
    
    // 路径相关的属性和方法
    var currentFenPathGroups: [PathGroup] {
        session.getCurrentFenPathGroups()
    }

    var nextMovesPathGroups: [PathGroup] {
        showAllNextMoves ? session.getNextMovesPathGroups() : []
    }
    
    // 当前着法是否是坏棋
    var isCurrentMoveBad: Bool {
        if let currentMove = session.currentMove {
            return session.isBadMove(currentMove)
        }
        return false
    }

    // 当前着法是否是推荐棋
    var isCurrentMoveRecommended: Bool {
        if let currentMove = session.currentMove {
            return session.isRecommendedMove(currentMove)
        }
        return false
    }
    
    func updateCurrentFenPathGroups(_ pathGroups: [PathGroup]) {
        session.updateCurrentFenPathGroups(pathGroups)
    }
    
    // 状态属性
    var isAnyMoveLocked: Bool { session.isAnyMoveLocked }
    var canNavigateBeforeLockedStep: Bool { session.canNavigateBeforeLockedStep }
    var isBookmarked: Bool { session.isBookmarked }
    var isCurrentBlackOrientation: Bool { session.isCurrentBlackOrientation }
    var isCurrentHorizontalFlipped: Bool { session.isCurrentHorizontalFlipped }
    var isMyTurn: Bool {
        let iamBlack = session.isCurrentBlackOrientation
        let blackJustPlayed = session.blackJustPlayed
        // 我是黑方且该黑方走，或我是红方且该红方走
        return (iamBlack && !blackJustPlayed) || (!iamBlack && blackJustPlayed)
    }
    var currentFilters: [String] { session.currentFilters }

    /// 获取上一次选择的特定棋局名称
    var lastSpecificGameName: String? {
        guard let gameId = session.sessionData.specificGameId,
              let game = getGameObjectUnfiltered(gameId) else {
            return nil
        }
        return game.displayTitle
    }

    /// 获取上一次选择的特定棋书名称
    var lastSpecificBookName: String? {
        guard let bookId = session.sessionData.specificBookId,
              let book = getBookObjectUnfiltered(bookId) else {
            return nil
        }
        return book.name
    }

    var currentFenCanChangeInRedOpening: Bool { session.currentFenCanChangeInRedOpening }
    var currentFenCanChangeInBlackOpening: Bool { session.currentFenCanChangeInBlackOpening }
    var currentFenIsInRedOpening: Bool { session.currentFenIsInRedOpening }
    var currentFenIsInBlackOpening: Bool { session.currentFenIsInBlackOpening }
    var currentFenInRealRedGameTotalCount: Int { session.currentFenInRealRedGameTotalCount }
    var currentFenInRealRedGameWinCount: Int { session.currentFenInRealRedGameWinCount }
    var currentFenInRealRedGameLossCount: Int { session.currentFenInRealRedGameLossCount }
    var currentFenInRealRedGameDrawCount: Int { session.currentFenInRealRedGameDrawCount }
    var currentFenInRealBlackGameTotalCount: Int { session.currentFenInRealBlackGameTotalCount }
    var currentFenInRealBlackGameWinCount: Int { session.currentFenInRealBlackGameWinCount }
    var currentFenInRealBlackGameLossCount: Int { session.currentFenInRealBlackGameLossCount }
    var currentFenInRealBlackGameDrawCount: Int { session.currentFenInRealBlackGameDrawCount }
    var currentFenPracticeCount: Int { session.currentFenPracticeCount }
    var autoExtendGameWhenPlayingBoardFen: Bool { session.autoExtendGameWhenPlayingBoardFen }
    var gameStepLimitation: Int? { session.gameStepLimitation }
    func setGameStepLimitation(_ limit: Int?) { session.setGameStepLimitation(limit) }

    func isBadMove(_ move: Move) -> Bool { session.isBadMove(move) }
    func isRecommendedMove(_ move: Move) -> Bool { session.isRecommendedMove(move) }
    func isMoveLocked(_ stepIndex: Int) -> Bool { session.isMoveLocked(stepIndex) }

    var currentAppMode: AppMode { session.currentAppMode }
    var showPath: Bool { session.showPath }
    var showAllNextMoves: Bool { session.showAllNextMoves }
    var isCommentEditing: Bool { session.isCommentEditing }
    var currentDataVersion: Int { session.currentDataVersion }
    var currentDataDirty: Bool { session.currentDataDirty }
    var currentDatabaseDirty: Bool { session.databaseDirty }

    // 变着相关属性
    var currentVariationIndex: Int {
        guard let currentMove = session.currentMove else { return 0 }
        let variants = session.currentGameVariantMoves
        if variants.isEmpty { return 0 }
        return variants.firstIndex(where: { $0.targetFenId == currentMove.targetFenId }) ?? 0
    }
    
    var totalVariationsCount: Int {
        let variants = session.currentGameVariantMoves
        return variants.isEmpty ? 1 : variants.count
    }
    
    func isBookmarkInCurrentGame(_ game: [Int]) -> Bool {
        return session.isBookmarkInCurrentGame(game)
    }
  
    func getMoveString(move: Move) -> String {
      return session.getMoveString(move: move)
    }

    func getDisplayScoreDeltaForMove(_ move: Move) -> String {
        return session.getDisplayScoreDeltaForMove(move)
    }

    func getDisplayScoreForMove(_ move: Move) -> String {
        return session.getDisplayScoreForMove(move)
    }

    var allTopLevelBookObjects: [BookObject] {
        session.allTopLevelBookObjects
    }

    var allBookObjects: [BookObject] {
        session.allBookObjects
    }

    var currentSpecificGameId: UUID? {
        session.currentSpecificGameId
    }

    var currentGamePositionFenId: Int {
        session.sessionData.currentGame2[session.sessionData.currentGameStep]
    }

    func getGamesInBook(_ bookId: UUID) -> [GameObject] {
        session.getGamesInBook(bookId)
    }

    func addCurrentGameToMyRealGame(gameInfo: GameObject) -> Bool {
        return session.addCurrentGameToMyRealGame(gameInfo: gameInfo)
    }

    // MARK: - 棋谱和棋局管理

    func addBook(name: String, parentBookId: UUID? = nil) -> UUID {
        return session.addBook(name: name, parentBookId: parentBookId)
    }

    func updateBook(_ bookId: UUID, name: String) {
        session.updateBook(bookId, name: name)
    }

    func deleteBook(_ bookId: UUID) {
        session.deleteBook(bookId)
    }

    func getBookObjectUnfiltered(_ bookId: UUID) -> BookObject? {
        return session.databaseView.getBookObjectUnfiltered(bookId)
    }

    func addGame(to bookId: UUID, name: String?, redPlayerName: String, blackPlayerName: String, gameDate: Date, gameResult: GameResult, iAmRed: Bool, iAmBlack: Bool, startingFenId: Int?, isFullyRecorded: Bool) -> UUID {
        return session.addGame(to: bookId, name: name, redPlayerName: redPlayerName, blackPlayerName: blackPlayerName, gameDate: gameDate, gameResult: gameResult, iAmRed: iAmRed, iAmBlack: iAmBlack, startingFenId: startingFenId, isFullyRecorded: isFullyRecorded)
    }

    func updateGame(_ gameId: UUID, name: String?, redPlayerName: String, blackPlayerName: String, gameDate: Date, gameResult: GameResult, iAmRed: Bool, iAmBlack: Bool, startingFenId: Int?, isFullyRecorded: Bool) {
        session.updateGame(gameId, name: name, redPlayerName: redPlayerName, blackPlayerName: blackPlayerName, gameDate: gameDate, gameResult: gameResult, iAmRed: iAmRed, iAmBlack: iAmBlack, startingFenId: startingFenId, isFullyRecorded: isFullyRecorded)
    }

    func deleteGame(_ gameId: UUID) {
        // 如果当前正在查看被删除的棋局，先切换到全库视图，避免 DatabaseView 筛选失效导致崩溃
        if currentFilters.contains(Session.filterSpecificGame),
           session.sessionData.specificGameId == gameId {
            sessionManager.setFilters([], specificGameId: nil)
        }
        session.deleteGame(gameId)
    }

    func importPGNFile(content: String, username: String) -> PGNImportResult {
        session.setupDefaultBooksIfNeeded()
        let databaseView = DatabaseView.full(database: Database.shared)
        let result = PGNImportService.importPGN(content: content, username: username, databaseView: databaseView)
        if result.imported > 0 {
            // Database is already marked dirty by PGNImportService operations.
            // Toggle dataChanged to trigger UI updates.
            session.dataChanged.toggle()
        }
        return result
    }

    func getGameObjectUnfiltered(_ gameId: UUID) -> GameObject? {
        return session.getGameObjectUnfiltered(gameId)
    }

    func toggleAutoExtendGameWhenPlayingBoardFen() {
        session.toggleAutoExtendGameWhenPlayingBoardFen()
    }

    func togglePracticeMode() {
        session.togglePracticeMode()
    }

    func setMode(_ mode: AppMode) {
        session.setMode(mode)
    }

    /// 查询指定 ActionKey 在当前模式下是否可见
    func isActionVisible(_ actionKey: ActionDefinitions.ActionKey) -> Bool {
        // removeMoveFromGame 按钮只在特定棋局模式下显示
        if actionKey == .removeMoveFromGame {
            return currentFilters.contains(Session.filterSpecificGame) && actionDefinitions.isActionVisible(actionKey, in: currentAppMode)
        }
        return actionDefinitions.isActionVisible(actionKey, in: currentAppMode)
    }

    func toggleShowPath() {
        session.toggleShowPath()
    }

    func toggleShowAllNextMoves() {
        session.toggleShowAllNextMoves()
    }

    func setDataClean() {
        session.setDataClean()
    }

    func checkBoardFenInNextMoveList(_ boardFen: String) -> Bool {
        session.checkBoardFenInNextMoveList(boardFen)
    }

    func playRandomNextMove(delay: Double = 0) {
        session.playRandomNextMove(delay: delay)
    }

    func reviewThisGame() {
        // 如果在focusedPractice中，先退出（使用 SessionManager）
        if sessionManager.isInFocusedPractice {
            sessionManager.exitFocusedPractice()
        }

        if session.sessionData.currentMode == .practice {
            session.togglePracticeMode()
        }
        session.toStart()
    }

    func practiceNewGame() {
        // 如果在focusedPractice中，先退出（使用 SessionManager）
        if sessionManager.isInFocusedPractice {
            sessionManager.exitFocusedPractice()
        }

        if !self.isAnyMoveLocked {
            self.toggleLock()
        }
        if session.sessionData.currentMode != .practice {
            session.togglePracticeMode()
        }
        session.toStart()

        playRandomIfYourTurn(delay: 1.0)
    }

    func startFocusedPractice() {
        // 使用 SessionManager 的方法进入 focusedPractice（v3.0 架构）
        sessionManager.startFocusedPractice()

        // Auto-play if it's opponent's turn
        playRandomIfYourTurn(delay: 1.0)
    }

    func practiceRedOpening() {
        // 退出 focusedPractice（如果正在进行）
        if sessionManager.isInFocusedPractice {
            sessionManager.exitFocusedPractice()
        }

        // 切换到红方开局范围
        sessionManager.setFilters([Session.filterRedOpeningOnly])

        // 先跳到起点，再锁定在开始局面
        session.toStart()
        if self.isAnyMoveLocked {
            self.toggleLock()
        }
        self.toggleLock()
        if session.sessionData.currentMode != .practice {
            session.togglePracticeMode()
        }

        playRandomIfYourTurn(delay: 1.0)
    }

    func practiceBlackOpening() {
        // 退出 focusedPractice（如果正在进行）
        if sessionManager.isInFocusedPractice {
            sessionManager.exitFocusedPractice()
        }

        // 切换到黑方开局范围
        sessionManager.setFilters([Session.filterBlackOpeningOnly])

        // 先跳到起点，再锁定在开始局面
        session.toStart()
        if self.isAnyMoveLocked {
            self.toggleLock()
        }
        self.toggleLock()
        if session.sessionData.currentMode != .practice {
            session.togglePracticeMode()
        }

        playRandomIfYourTurn(delay: 1.0)
    }

    func playRandomIfYourTurn(delay: Double) {
        let IamBlackButYourTurn = session.isCurrentBlackOrientation && session.blackJustPlayed
        let IamRedButYourTurn = !session.isCurrentBlackOrientation && !session.blackJustPlayed
        if IamBlackButYourTurn || IamRedButYourTurn {
            session.playRandomNextMove(delay: delay)

            let delay2 = delay + 1.0 // wait for animation
            DispatchQueue.main.asyncAfter(deadline: .now() + delay2) {
                if !self.session.hasNextMove {
                    self.platformService.showWarningAlert(
                        title: "棋谱结束",
                        message: "棋谱结束"
                    )
                }
            }
        }
    }

    // MARK: - Window Title

    /// 计算窗口标题
    /// 在 GameObject filter 模式下显示棋局名称，BookObject filter 模式下显示棋书名称，其他模式显示默认标题
    var windowTitle: String {
        if currentFilters.contains(Session.filterSpecificGame),
           let gameId = session.sessionData.specificGameId,
           let gameObject = session.databaseView.getGameObject(gameId) {
            // GameObject filter 模式：显示棋局名称
            return "XiangqiNotebook - \(gameObject.displayTitle)"
        } else if currentFilters.contains(Session.filterSpecificBook),
                  let bookId = session.sessionData.specificBookId,
                  let bookObject = session.databaseView.getBookObjectUnfiltered(bookId) {
            // BookObject filter 模式：显示棋书名称
            if !bookObject.name.isEmpty {
                return "XiangqiNotebook - \(bookObject.name)"
            } else {
                return "XiangqiNotebook - 棋书"
            }
        } else {
            // 其他模式：显示默认标题
            return "XiangqiNotebook"
        }
    }

    // MARK: - Related Courses

    /// 获取与当前局面相关的课程（转发到 Session）
    var relatedCoursesForCurrentFen: [GameObject] {
        session.relatedCoursesForCurrentFen
    }
}
