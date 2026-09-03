import SwiftUI
import Foundation
import Combine


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

    /// 自定义按钮文案的确认对话框（如崩溃恢复用"恢复"/"丢弃"）
    func showConfirmAlert(title: String, message: String, confirmTitle: String, cancelTitle: String, completion: @escaping (Bool) -> Void)
}

extension PlatformService {
    /// 默认实现：复用基础确认对话框，忽略自定义按钮文案。
    /// 各平台服务可覆盖以提供真正的自定义按钮（Mac/iOS 已覆盖）
    func showConfirmAlert(title: String, message: String, confirmTitle: String, cancelTitle: String, completion: @escaping (Bool) -> Void) {
        showConfirmAlert(title: title, message: message) { result in completion(result) }
    }
}

/// ViewModel 负责处理象棋应用的业务逻辑
/// 它作为 View 和 Model(Session) 之间的中介
@MainActor
class ViewModel: ObservableObject {
    @Published private(set) var sessionManager: SessionManager

    // 当前活跃的 Session。private 以维持分层：Views 只能经 ViewModel 的转发接口
    // 访问数据（issue #164）；测试经 sessionManager.currentSession 访问
    private var session: Session {
        sessionManager.currentSession
    }

    // MARK: - Session 数据转发接口（供 Views 使用）

    /// 数据变更指示器（视图用作重新计算依赖）
    var dataChanged: Bool { session.dataChanged }

    /// 当前筛选范围内的练习走错统计
    var practiceMistakesInScope: [Int: [PracticeMistakeRecord]] {
        session.databaseView.practiceMistakes
    }

    /// 按 fenId 取局面 FEN（当前范围内；范围外返回 nil）
    func fenString(for fenId: Int) -> String? {
        session.databaseView.getFenObject(fenId)?.fen
    }

    /// 清空练习走错统计
    func resetPracticeMistakes() {
        session.databaseView.resetPracticeMistakes()
        session.dataChanged.toggle()
    }

    /// 棋局浏览器 UI 状态（选中棋书/棋局、展开集合），写入时标记会话脏
    var gameBrowserSelectedBookId: UUID? {
        get { session.sessionData.gameBrowserSelectedBookId }
        set {
            session.sessionData.gameBrowserSelectedBookId = newValue
            session.sessionDataDirty = true
        }
    }

    var gameBrowserSelectedGameId: UUID? {
        get { session.sessionData.gameBrowserSelectedGameId }
        set {
            session.sessionData.gameBrowserSelectedGameId = newValue
            session.sessionDataDirty = true
        }
    }

    var gameBrowserExpandedBookIds: Set<UUID>? {
        get { session.sessionData.gameBrowserExpandedBookIds }
        set {
            session.sessionData.gameBrowserExpandedBookIds = newValue
            session.sessionDataDirty = true
        }
    }

    // MARK: - 课程视频关联转发（维持 Views → ViewModel → Storage 分层）

    func courseVideoPath(for gameId: UUID) -> String? {
        CourseVideoStorage.shared.videoPath(for: gameId)
    }

    func setCourseVideoPath(_ path: String, for gameId: UUID) {
        CourseVideoStorage.shared.setVideoPath(path, for: gameId)
    }

    func removeCourseVideoPath(for gameId: UUID) {
        CourseVideoStorage.shared.removeVideoPath(for: gameId)
    }

    func courseVideoTimestamp(for gameId: UUID, fenId: Int) -> String? {
        CourseVideoStorage.shared.timestamp(for: gameId, fenId: fenId)
    }

    func setCourseVideoTimestamp(_ value: String, for gameId: UUID, fenId: Int) {
        CourseVideoStorage.shared.setTimestamp(value, for: gameId, fenId: fenId)
    }

    func removeCourseVideoTimestamp(for gameId: UUID, fenId: Int) {
        CourseVideoStorage.shared.removeTimestamp(for: gameId, fenId: fenId)
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
    @Published var showingReviewListView = false
    @Published var showRealGameListIOS = false
    @Published var showReviewListIOS = false
    @Published var showReviewModeIOS = false
    @Published var showingBoardTextView = false
    @Published var showingShortcutUsageStatsView = false
    @Published var showingPracticeMistakeStatsView = false
    /// AI 问棋（iOS/iPad 走 sheet；macOS 用独立窗口，不看这个标志）
    @Published var showingAIChat = false
    /// iOS 专用：等 sheet 起来之后自动发出的问题。取走即清空
    var pendingAIQuestion: String?

    // 复习模式状态
    @Published private(set) var reviewQueue: [(fenId: Int, srsData: SRSData)] = []
    @Published private(set) var currentReviewIndex = 0

    // 检验模式状态
    @Published private(set) var verificationItem: (fenId: Int, srsData: SRSData)?
    var isInVerificationMode: Bool { verificationItem != nil }

    // 检查是否有任何 sheet 正在显示（用于禁用快捷键）
    var isAnySheetPresented: Bool {
        return showingBookmarkAlert ||
               showingStepLimitationDialog ||
               showingGameInputView ||
               showingGameBrowserView ||
               showingPGNImportSheet ||
               showMarkPathView ||
               showingReviewListView ||
               showingBoardTextView ||
               showingShortcutUsageStatsView ||
               showingPracticeMistakeStatsView ||
               showingAIChat
    }

    // Global alert state
    @Published var showingGlobalAlert = false
    @Published var globalAlertTitle = ""
    @Published var globalAlertMessage = ""

    #if os(macOS)
    private var referenceBoardWindowController: ReferenceBoardWindowController?
    /// AI 问棋窗口。留引用是为了再次触发时把已有窗口带到前台而不是新开一个，
    /// 顺带保住窗口里那份对话上下文
    private var aiChatWindowController: AIChatWindowController?
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
    private(set) var evaluationQueue: EvaluationQueue?
    #endif

    // 引擎评估（仅 iOS/iPadOS，内嵌版 Pikafish）
    #if os(iOS)
    private var pikafishServiceIOS: PikafishServiceIOS?
    @Published private(set) var isEvaluatingIOS = false
    /// 用户在思考期间点了取消：结果到达后整个丢弃，不存分也不落子
    private var aiRespondCancelled = false
    #endif

    // 静默云库查分：在飞去重与退避状态（仅主线程访问）
    private var silentQueryTask: Task<Void, Never>?
    private var silentQueryFenId: Int?
    private var silentQueryBackoffUntil: Date = .distantPast
    private var silentQueryFailureCount = 0

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

        // 4. 练习模式一致性修复：如果加载的会话处于练习模式，强制隐藏路径
        if currentSession.sessionData.currentMode == .practice {
            currentSession.sessionData.showPath = false
            currentSession.sessionData.showAllNextMoves = false
        }

        // 5. 监听 sessionManager 和 session 的变化
        setupSessionObservers()

        // 6. 注册所有操作
        registerActions()

        // 7. 设置 actionDefinitions 的当前模式查询
        actionDefinitions.currentMode = { [weak self] in
            self?.currentAppMode ?? .normal
        }

        // 7b. 记录快捷键使用次数（按钮点击不会触发）
        actionDefinitions.usageRecorder = { ShortcutUsageStats.shared.recordFromKeyboard($0) }

        // 8. 异步构建实战反查表索引
        DispatchQueue.global(qos: .utility).async { [weak self] in
            Database.shared.buildRealGamesIndex()
            DispatchQueue.main.async {
                self?.session.dataChanged.toggle()
            }
        }

        // 9. 设置引擎分数的 activeEngineKey（确保加载的分数文件能立即显示）
        #if os(macOS)
        Database.shared.activeEngineKey = PikafishService.engineKey

        // 10. App 退出时：干净退出视为主动丢弃未保存改动（不自动写存档），
        //     清除崩溃恢复快照——只有崩溃/被杀（不触发此回调）才会留下快照。
        //     再关闭引擎子进程，防止孤儿进程残留
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            DatabaseStorage.clearRecoverySnapshot()
            Task { @MainActor [weak self] in
                self?.evaluationQueue?.cancelAll()
                self?.pikafishService?.stop()
            }
        }
        #endif

        #if os(iOS)
        // 9b. iOS 内嵌引擎评分单独存一个 engineKey，不与 Mac 的 "_d34" 共享
        Database.shared.activeEngineKey = PikafishServiceIOS.engineKey

        // 10. 进后台时强制写一次崩溃恢复快照（防系统在挂起期间杀掉进程）。
        //     iOS 无可靠的"干净退出"信号，恢复留待下次冷启动判断。
        //     同时释放内嵌引擎的置换表/线程池，避免后台常驻占用内存与耗电。
        //     大库的快照编码可能超过进后台的默认宽限期，用 background task 申请额外时间
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            let taskId = UIApplication.shared.beginBackgroundTask()
            let endTask = {
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { endTask(); return }
                self.pikafishServiceIOS?.releaseResources()
                // 快照写盘在后台队列完成后才结束 background task，防止编码中途被挂起
                self.writeRecoverySnapshotIfDirty(force: true, completion: endTask)
            }
        }
        #endif

        // 11. 崩溃恢复定时器（仅 macOS）：周期性把脏数据写入本地恢复快照（与正式存档分开）。
        //     编码写盘已在后台队列，但主线程仍要付一次值快照（深拷贝）的成本；
        //     iOS 不开定时器：iPhone 上深拷贝大库仍可能有可感知卡顿，
        //     且进后台的强制快照已覆盖挂起期间被杀这一主要风险场景
        #if os(macOS)
        startRecoveryTimer()
        #endif

        // 12. 启动后检查是否有上次未保存的恢复快照（崩溃/被杀残留）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.checkForCrashRecovery()
        }
    }

    // MARK: - 崩溃恢复

    private var recoveryTimer: Timer?
    /// 上次写入恢复快照时的修改计数，避免无新改动时重复写。
    /// 用 mutationCount 而非 dataVersion：dataVersion 每个脏周期只递增一次，
    /// 用它去重会让周期内的后续修改永远不再写入快照（快照只保护首次修改）
    private var lastSnapshotMutationCount: Int = -1
    /// 恢复快照后台写入是否在途（仅主线程读写）；在途时跳过本轮，下个周期再写
    private var recoverySnapshotInFlight = false
    /// 恢复快照后台写盘专用串行队列
    private let recoverySnapshotQueue = DispatchQueue(label: "com.gooooloo.XiangqiNotebook.recovery-snapshot", qos: .utility)

    /// 启动崩溃恢复定时器：每 30 秒检查一次，脏且有新改动时写入恢复快照
    private func startRecoveryTimer() {
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.writeRecoverySnapshotIfDirty()
            }
        }
    }

    /// 数据库脏且较上次快照有新改动时，写入本地崩溃恢复快照。
    /// 主线程只做值快照（拷贝，数十毫秒量级），JSON 编码与写盘在后台队列进行——
    /// 大库全量编码是秒级操作，放主线程会整体冻结界面。
    /// 这是与正式存档分开的"草稿"，不触碰 database.json，也不走 iCloud。
    /// - Parameters:
    ///   - force: 进后台等场景强制写一次（忽略修改计数去重）
    ///   - completion: 写盘完成（或本轮跳过）后的主线程回调，供进后台时结束 background task
    private func writeRecoverySnapshotIfDirty(force: Bool = false, completion: (() -> Void)? = nil) {
        guard session.databaseDirty else { completion?(); return }
        let count = session.databaseView.mutationCount
        guard force || count != lastSnapshotMutationCount else { completion?(); return }
        guard !recoverySnapshotInFlight else { completion?(); return }

        recoverySnapshotInFlight = true
        lastSnapshotMutationCount = count
        let snapshot = session.databaseView.databaseDataForBackup.snapshotCopy()
        recoverySnapshotQueue.async { [weak self] in
            DatabaseStorage.writeRecoverySnapshot(snapshot)
            DispatchQueue.main.async {
                self?.recoverySnapshotInFlight = false
                completion?()
            }
        }
    }

    /// 清除崩溃恢复快照（手动保存成功 或 干净退出 后调用）
    private func clearRecoverySnapshot() {
        DatabaseStorage.clearRecoverySnapshot()
        lastSnapshotMutationCount = -1
    }

    /// 启动时检查崩溃恢复快照：若上次会话因崩溃/被杀留下了未保存的更新，提示恢复。
    ///
    /// 只要快照存在就提示，不按版本号自动丢弃：快照版本 ≤ 存档版本并不代表它过时——
    /// 另一台设备在本机崩溃后保存过一次，存档版本就会追平甚至超过快照，
    /// 此时本机崩溃前的修改只剩这一份快照，静默清掉就是无提示的数据丢失。
    /// 由用户结合写入时间与两个版本号自行判断。
    private func checkForCrashRecovery() {
        guard let snapshotVersion = DatabaseStorage.loadRecoverySnapshotVersion() else { return }
        let canonicalVersion = session.databaseView.dataVersion
        let writtenAt = DatabaseStorage.loadRecoverySnapshotDate()
            .map { Self.recoveryDateFormatter.string(from: $0) } ?? "未知时间"
        var message = "上次可能因崩溃或被系统关闭，有一份未保存的修改未能写入存档"
            + "（快照写于 \(writtenAt)，快照版本 \(snapshotVersion)，当前存档版本 \(canonicalVersion)）。是否恢复？"
        if snapshotVersion <= canonicalVersion {
            message += "\n\n注意：存档在快照之后又被保存过（可能来自其他设备）。恢复会以快照内容替换当前数据，那次保存的改动需要之后再合并。"
        }
        message += "\n\n恢复后请记得手动保存（按 w 或保存按钮）。"
        platformService.showConfirmAlert(
            title: "检测到未保存的修改",
            message: message,
            confirmTitle: "恢复",
            cancelTitle: "丢弃",
            completion: { [weak self] restore in
                guard let self = self else { return }
                if restore, let snapshot = DatabaseStorage.loadRecoverySnapshot() {
                    self.session.databaseView.restoreFromBackup(
                        snapshot, remoteVersion: DatabaseStorage.loadDataVersionFromDefault())
                    self.session.resetGameStateForDatabaseRestore()
                    self.session.objectWillChange.send()
                    // 恢复的数据尚未写入存档，保持 dirty，待用户手动保存
                }
                self.clearRecoverySnapshot()
            }
        )
    }

    private static let recoveryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    deinit {
        recoveryTimer?.invalidate()
    }

    #if DEBUG
    /// 可测试的初始化器，允许直接注入 SessionManager，跳过文件加载和 iCloud 监听
    init(sessionManager: SessionManager, platformService: PlatformService) {
        self.sessionManager = sessionManager
        self.platformService = platformService
        let currentSession = sessionManager.currentSession
        self.boardViewModel = BoardViewModel(
            fen: currentSession.currentFen,
            orientation: currentSession.isCurrentBlackOrientation ? "black" : "red",
            isHorizontalFlipped: currentSession.isCurrentHorizontalFlipped,
            showPath: currentSession.showPath,
            showAllNextMoves: currentSession.showAllNextMoves,
            shouldAnimate: false,
            currentFenPathGroups: currentSession.getCurrentFenPathGroups()
        )
        registerActions()
        actionDefinitions.currentMode = { [weak self] in
            self?.currentAppMode ?? .normal
        }
    }
    #endif

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
        // 变更以单调递增计数发布，dropFirst 跳过订阅时的初始值
        iCloudFileCoordinator.shared.$databaseFileChangeCount
            .dropFirst()
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

        // 订阅当前活跃的 Session。
        // 不加 receive(on: main)：Session 的 dataChanged 只在主线程翻转，且翻转前数据变更已全部落地；
        // 多一次 main 队列跳变只会让每次操作的界面响应晚一帧
        currentSessionSubscription = session.objectWillChange
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

    private var currentMoveSquares: (from: String, to: String)? {
        guard let move = session.currentMove,
              let pieceMove = session.databaseView.parsePieceMove(move, isHorizontalFlipped: false)
        else { return nil }
        let fromSquare = MoveRules.coordinateToSquare(col: pieceMove.fromColumn, row: 9 - pieceMove.fromRow)
        let toSquare = MoveRules.coordinateToSquare(col: pieceMove.toColumn, row: 9 - pieceMove.toRow)
        return (from: fromSquare, to: toSquare)
    }

    /// 更新棋盘视图（数据变化时调用）
    private func updateBoardView() {
        boardViewModel.updatePieceViews(fen: session.currentFen)
        boardViewModel.updateOrientation(orientation: session.isCurrentBlackOrientation ? "black" : "red")
        boardViewModel.updateHorizontalFlipped(flipped: session.isCurrentHorizontalFlipped)
        boardViewModel.updateCurrentFenPathGroups(currentFenPathGroups: currentFenPathGroups)
        // 关闭「显示所有下一步」时不必计算路径组（棋盘也不会渲染它），每步走子都省一遍遍历
        boardViewModel.updateNextMovesPathGroups(nextMovesPathGroups: showAllNextMoves ? session.getNextMovesPathGroups() : [])
        boardViewModel.updateShowPath(showPath: showPath)
        boardViewModel.updateShowAllNextMoves(showAllNextMoves: showAllNextMoves)

        boardViewModel.updateLastMoveSquares(showLastMove ? currentMoveSquares : nil)

        boardViewModel.updateShowRedAttackPoints(showRedAttackPoints)
        boardViewModel.updateShowBlackAttackPoints(showBlackAttackPoints)
        boardViewModel.updateAttackPointsPalaceOnly(red: attackPointsRedPalaceOnly, black: attackPointsBlackPalaceOnly)

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
        actionDefinitions.registerAction(.nextVariant, text: "下一变", textIPhone: "下变", shortcuts: [.single(" ")], supportedModes: [.normal]) { self.playNextVariant() }

        actionDefinitions.registerAction(.previousPath, text: "上局", textIPhone: "上局", shortcuts: [.single("p")], supportedModes: [.normal]) { self.goToPreviousPath() }
        actionDefinitions.registerAction(.nextPath, text: "下局", textIPhone: "下局", shortcuts: [.single("n")], supportedModes: [.normal]) { self.goToNextPath() }
        #if os(macOS)
        actionDefinitions.registerAction(.random, text: "随机一局", shortcuts: [.sequence(",gr")], supportedModes: [.normal]) { _ = self.makeRandomGame() }
        #else
        actionDefinitions.registerAction(.random, text: "随机一局", supportedModes: [.normal]) { _ = self.makeRandomGame() }
        #endif
        actionDefinitions.registerAction(.reviewThisGame, text: "回顾本局", textIPhone: "回顾", shortcuts: [.sequence(",r")], supportedModes: [.practice]) { self.reviewThisGame() }
        actionDefinitions.registerAction(.searchCurrentMove, text: "搜索此步", shortcuts: [.sequence(",/")], supportedModes: [.normal]) { self.showSearchResultsWindow() }
        actionDefinitions.registerAction(.referenceBoard, text: "参考棋谱", shortcuts: [.modified([.command], "x")], supportedModes: [.normal]) { self.showReferenceBoard() }

        actionDefinitions.registerAction(.practiceNewGame, text: "练习新局", textIPhone: "练习", shortcuts: [.single("P")], supportedModes: [.normal, .practice]) { self.practiceNewGame() }
        actionDefinitions.registerAction(.focusedPractice, text: "练习本局", textIPhone: "专练", shortcuts: [.single("Z")], supportedModes: [.normal, .practice]) { self.startFocusedPractice() }
        actionDefinitions.registerAction(.practiceRedOpening, text: "练习红方开局", shortcuts: [.sequence(",1")], supportedModes: [.normal, .practice]) { self.practiceRedOpening() }
        actionDefinitions.registerAction(.practiceBlackOpening, text: "练习黑方开局", shortcuts: [.sequence(",2")], supportedModes: [.normal, .practice]) { self.practiceBlackOpening() }
        actionDefinitions.registerAction(.playRandomNextMove, text: "随机走子", textIPhone: "随机", supportedModes: [.practice]) { self.playRandomNextMove() }
        actionDefinitions.registerAction(.hintNextMove, text: "提示", textIPhone: "提示", shortcuts: [.single("?")], supportedModes: [.practice]) { self.playRandomNextMove() }

        actionDefinitions.registerAction(.queryScore, text: "云库查分", shortcuts: [.single("s")], supportedModes: [.normal]) { Task { await self.queryFenScore() } }
        #if os(macOS) && arch(arm64)
        actionDefinitions.registerAction(.quickEngineScore, text: "快速估分", shortcuts: [.sequence(",qs")], supportedModes: [.normal]) { self.quickEngineScore() }
        actionDefinitions.registerAction(.queryEngineScore, text: "深度评分", shortcuts: [.sequence(",Qs")], supportedModes: [.normal]) { self.queryEngineScore() }
        actionDefinitions.registerAction(.queryAllEngineScores, text: "深评本局", shortcuts: [.sequence(",Qa")], supportedModes: [.normal]) { self.queryAllEngineScores() }
        actionDefinitions.registerAction(.quickAllEngineScores, text: "快估本局", shortcuts: [.sequence(",qa")], supportedModes: [.normal]) { self.quickAllEngineScores() }
        actionDefinitions.registerAction(.pikafishQuickMove, text: "快速应招", shortcuts: [.single("m")], supportedModes: [.normal]) { Task { await self.pikafishQuickMove() } }
        #endif
        // 三端都注册：Mac 开独立窗口，iOS/iPad 弹全屏 sheet，分支在 showAIChat 里
        actionDefinitions.registerAction(.openAIChat, text: "AI 问棋", shortcuts: [.sequence(",ai")], supportedModes: [.normal]) { self.showAIChat() }
        actionDefinitions.registerAction(.deleteScore, text: "删分", shortcuts: [.sequence(",D")], supportedModes: [.normal]) { self.updateFenScore(self.currentFenId, score: nil) }
        actionDefinitions.registerAction(.openYunku, text: "打开云库", shortcuts: [.single("y")], supportedModes: [.normal]) { self.openYunku() }
        actionDefinitions.registerAction(.deleteMove, text: "删招", shortcuts: [.sequence(",d")], supportedModes: [.normal]) { self.removeCurrentStep() }
        actionDefinitions.registerAction(.removeMoveFromGame, text: "从局中删除此招", shortcuts: [.sequence(",k")], supportedModes: [.normal]) { self.removeMoveFromGame() }
        actionDefinitions.registerAction(.markPath, text: "标记路径", shortcuts: [.single("A")], supportedModes: [.normal]) { self.showMarkPathView = true }

        actionDefinitions.registerAction(.save, text: "保存", shortcuts: [.single("w")], supportedModes: ActionDefinitions.allModes) { self.saveToDefault() }
        actionDefinitions.registerAction(.checkDataVersion, text: "更新数据", textIPhone: "更新", shortcuts: [.sequence(",u")], supportedModes: ActionDefinitions.allModes) { self.checkDataVersion() }
        actionDefinitions.registerAction(.backup, text: "备份", shortcuts: [.sequence(",b")], supportedModes: [.normal]) { self.backup() }
        actionDefinitions.registerAction(.restore, text: "恢复", shortcuts: [.sequence(",br")], supportedModes: [.normal]) { Task { await self.recoverFromUserChoice() } }

        actionDefinitions.registerAction(.stepLimitation, text: "步数限制", supportedModes: [.normal]) { self.showingStepLimitationDialog = true }
        actionDefinitions.registerAction(.inputGame, text: "录入棋局", shortcuts: [.sequence(",i")], supportedModes: [.normal]) { self.showingGameInputView = true }
        actionDefinitions.registerAction(.browseGames, text: "棋局浏览器", shortcuts: [.sequence(",gB")], supportedModes: [.normal]) { self.showingGameBrowserView = true }
        actionDefinitions.registerAction(.importPGN, text: "导入PGN", shortcuts: [.sequence(",pi")], supportedModes: [.normal]) { self.showingPGNImportSheet = true }
        // 导出 PGN 的实现使用 NSSavePanel，仅 macOS 提供；不加守卫 iOS 编译失败
        #if os(macOS)
        actionDefinitions.registerAction(.exportPGNCurrentDatabaseView, text: "导出所有变着PGN...", shortcuts: [.sequence(",pa")], supportedModes: [.normal]) { self.exportPGNCurrentDatabaseView() }
        actionDefinitions.registerAction(.exportPGNCurrentGame, text: "导出当前棋局PGN...", shortcuts: [.sequence(",pc")], supportedModes: [.normal]) { self.exportPGNCurrentGame() }
        #endif

        actionDefinitions.registerAction(.copyFEN, text: "拷贝FEN", shortcuts: [.sequence(",f")]) { self.copyFenToClipboard() }
        actionDefinitions.registerAction(.copyBoardText, text: "生成详细局面文本", shortcuts: [.sequence(",c")]) { self.showingBoardTextView = true }
        actionDefinitions.registerAction(.copyBoardImage, text: "拷贝棋盘", shortcuts: [.sequence(",ci")]) { self.copyBoardImageToClipboard() }
        actionDefinitions.registerAction(.fix, text: "修复", shortcuts: [.sequence(",fix")], supportedModes: [.normal]) { self.session.recalculateGameStatistics() }
        actionDefinitions.registerAction(.autoAddToOpening, text: "自动完善开局库", shortcuts: [.sequence(",O")], supportedModes: [.normal]) { self.performAutoAddToOpening() }
        actionDefinitions.registerAction(.jumpToNextOpeningGap, text: "跳转开局缺口", shortcuts: [.sequence(",o")], supportedModes: [.normal]) { self.jumpToNextOpeningGap() }

        actionDefinitions.registerAction(.showEditCommentIOS, text: "编辑评论", shortcuts: [.sequence(",e")], supportedModes: [.normal]) { self.showEditCommentIOS = true }
        actionDefinitions.registerAction(.showBookmarkListIOS, text: "书签", shortcuts: [.sequence(",m")]) { self.showIOSBookMarkListView = true }
        actionDefinitions.registerAction(.showMoreActionsIOS, text: "更多", shortcuts: [.sequence(",a")]) { self.showIOSMoreActionsView = true }

        actionDefinitions.registerAction(.addToReview, text: "加入复习库", textIPhone: "复习+", shortcuts: [.single("v")]) {
            if self.session.isCurrentFenInReview {
                self.session.removeReviewItem(fenId: self.session.currentFenId)
            } else {
                self.session.addCurrentFenToReview()
            }
        }
        #if os(macOS)
        actionDefinitions.registerAction(.showReviewList, text: "复习库列表", shortcuts: [.sequence(",v")]) { self.showingReviewListView = true }
        actionDefinitions.registerAction(.showReviewListIOS, text: "复习库") { self.showReviewListIOS = true }
        actionDefinitions.registerAction(.showRealGameListIOS, text: "实战") { self.showRealGameListIOS = true }
        #else
        actionDefinitions.registerAction(.showReviewList, text: "复习库列表") { self.showingReviewListView = true }
        actionDefinitions.registerAction(.showReviewListIOS, text: "复习库", shortcuts: [.sequence(",v")]) { self.showReviewListIOS = true }
        actionDefinitions.registerAction(.showRealGameListIOS, text: "实战", shortcuts: [.sequence(",g")]) { self.showRealGameListIOS = true }
        #endif

        actionDefinitions.registerAction(.showShortcutUsageStats, text: "快捷键统计") { self.showingShortcutUsageStatsView = true }
        actionDefinitions.registerAction(.showPracticeMistakeStats, text: "练习错误统计", shortcuts: [.sequence(",ws")]) { self.showingPracticeMistakeStatsView = true }
      
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
          shortcuts: [.single("5")],
          isEnabled: { self.session.sessionData.specificGameId != nil },
          isOn: { self.currentFilters.contains(Session.filterSpecificGame) },
          action: { _ in self.toggleFilterSpecificGame() }
        )

        actionDefinitions.registerToggleAction(
          .toggleFilterSpecificBook,
          text: "只筛选特定棋书",
          shortcuts: [.single("6")],
          isEnabled: { self.session.sessionData.specificBookId != nil },
          isOn: { self.currentFilters.contains(Session.filterSpecificBook) },
          action: { _ in self.toggleFilterSpecificBook() }
        )

        actionDefinitions.registerToggleAction(
          .toggleStepLimitation,
          text: "步数限制",
          // ,l 已被 toggleShowLastMove 占用（同键注册时后注册者覆盖前者，
          // 本动作的快捷键会静默失效），故用 ,L
          shortcuts: [.sequence(",L")],
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
          shortcuts: [.sequence(",N")],
          isEnabled: { self.isAnyMoveLocked },
          isOn: { self.canNavigateBeforeLockedStep },
          action: { newValue in
            self.toggleCanNavigateBeforeLockedStep()
          }
        )

        // 棋盘操作
        actionDefinitions.registerToggleAction(
          .flip,
          text: "黑方视角",
          shortcuts: [.single("f")],
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

        // 模式切换
        actionDefinitions.registerToggleAction(
          .togglePracticeMode,
          text: "练习模式",
          shortcuts: [.sequence(",P")],
          isEnabled: { true },
          isOn: { self.session.sessionData.currentMode == .practice },
          action: { newValue in
            self.togglePracticeMode()
          }
        )

        // 直接切换到指定模式（radio-button 语义）
        actionDefinitions.registerToggleAction(
          .setNormalMode,
          text: "常规模式",
          shortcuts: [.sequence(",Mn")],
          isEnabled: { true },
          isOn: { self.currentAppMode == .normal },
          action: { newValue in
            if newValue { self.setMode(.normal) }
          }
        )

        actionDefinitions.registerToggleAction(
          .setPracticeMode,
          text: "练习模式",
          shortcuts: [.sequence(",Mp")],
          isEnabled: { true },
          isOn: { self.currentAppMode == .practice },
          action: { newValue in
            if newValue { self.setMode(.practice) }
          }
        )

        actionDefinitions.registerToggleAction(
          .setReviewMode,
          text: "复习模式",
          shortcuts: [.sequence(",Mr")],
          isEnabled: { true },
          isOn: { self.currentAppMode == .review },
          action: { newValue in
            if newValue { self.setMode(.review) }
          }
        )

        // 路径相关 - 常规模式和复习模式可用
        actionDefinitions.registerToggleAction(
          .toggleShowPath,
          text: "显示路径",
          shortcuts: [.sequence(",s")],
          supportedModes: [.normal, .review],
          isEnabled: { self.session.sessionData.currentMode != .practice },
          isOn: { self.showPath },
          action: { newValue in
            self.toggleShowPath()
          }
        )

        // 显示所有下一步 - 常规模式和复习模式可用
        actionDefinitions.registerToggleAction(
          .toggleShowAllNextMoves,
          text: "显示所有下一步",
          shortcuts: [.sequence(",n")],
          supportedModes: [.normal, .review],
          isEnabled: { self.session.sessionData.currentMode != .practice },
          isOn: { self.showAllNextMoves },
          action: { newValue in
            self.toggleShowAllNextMoves()
          }
        )

        // 显示来源招法 - 所有模式可用
        actionDefinitions.registerToggleAction(
          .toggleShowLastMove,
          text: "显示来源招法",
          shortcuts: [.sequence(",l")],
          supportedModes: ActionDefinitions.allModes,
          isEnabled: { true },
          isOn: { self.showLastMove },
          action: { newValue in
            self.toggleShowLastMove()
          }
        )

        // 攻击点位 - 只依赖当前局面、不泄露棋谱信息，所有模式可用
        actionDefinitions.registerToggleAction(
          .toggleShowRedAttackPoints,
          text: "红方攻击点位",
          shortcuts: [.sequence(",ar")],
          supportedModes: ActionDefinitions.allModes,
          isEnabled: { true },
          isOn: { self.showRedAttackPoints },
          // 尊重目标值而非无条件翻转：远程 /action 带 value 调用时保持幂等
          action: { newValue in
            if newValue != self.showRedAttackPoints {
              self.toggleShowRedAttackPoints()
            }
          }
        )

        actionDefinitions.registerToggleAction(
          .toggleShowBlackAttackPoints,
          text: "黑方攻击点位",
          shortcuts: [.sequence(",ab")],
          supportedModes: ActionDefinitions.allModes,
          isEnabled: { true },
          isOn: { self.showBlackAttackPoints },
          action: { newValue in
            if newValue != self.showBlackAttackPoints {
              self.toggleShowBlackAttackPoints()
            }
          }
        )

        // 攻击点位九宫过滤：按红/黑九宫分别收窄显示范围，构思杀法时聚焦某侧九宫。
        // 都开显示两宫，都关不过滤
        actionDefinitions.registerToggleAction(
          .toggleAttackPointsRedPalaceOnly,
          text: "只显示红方九宫",
          shortcuts: [.sequence(",agr")],
          supportedModes: ActionDefinitions.allModes,
          isEnabled: { self.showRedAttackPoints || self.showBlackAttackPoints },
          isOn: { self.attackPointsRedPalaceOnly },
          action: { newValue in
            if newValue != self.attackPointsRedPalaceOnly {
              self.toggleAttackPointsRedPalaceOnly()
            }
          }
        )

        actionDefinitions.registerToggleAction(
          .toggleAttackPointsBlackPalaceOnly,
          text: "只显示黑方九宫",
          shortcuts: [.sequence(",agb")],
          supportedModes: ActionDefinitions.allModes,
          isEnabled: { self.showRedAttackPoints || self.showBlackAttackPoints },
          isOn: { self.attackPointsBlackPalaceOnly },
          action: { newValue in
            if newValue != self.attackPointsBlackPalaceOnly {
              self.toggleAttackPointsBlackPalaceOnly()
            }
          }
        )

        // 显示实战列表 - 只在常规模式可用
        actionDefinitions.registerToggleAction(
          .toggleShowRealGameList,
          text: "显示实战列表",
          shortcuts: [.sequence(",t")],
          supportedModes: [.normal],
          isEnabled: { true },
          isOn: { self.showRealGameList },
          action: { newValue in
            self.toggleShowRealGameList()
          }
        )

        #if os(macOS)
        actionDefinitions.registerToggleAction(
          .toggleGameBrowserSidebar,
          text: "棋局浏览器侧栏",
          shortcuts: [.sequence(",gb")],
          supportedModes: [.normal],
          isEnabled: { true },
          isOn: { self.showGameBrowserSidebar },
          action: { _ in
            self.toggleShowGameBrowserSidebar()
          }
        )
        #endif

        // 书签功能 - 只在常规模式可用
        actionDefinitions.registerToggleAction(
          .toggleBookmark,
          text: "加入书签",
          shortcuts: [.single("M")],
          supportedModes: [.normal],
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

        // 评论功能 - 只在常规模式可用
        actionDefinitions.registerToggleAction(
          .toggleIsCommentEditing,
          text: "编辑评论区",
          shortcuts: [.single("c")],
          supportedModes: [.normal, .review],
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
          shortcuts: [.single("a")],
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
                session.recordPracticeMistakeAtCurrentFen(wrongBoardFen: newFen)
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

        sessionManager.setFilters(
            newFilters,
            focusedPath: session.sessionData.focusedPracticeGamePath,
            specificGameId: .keep,
            specificBookId: .keep
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
            sessionManager.setFilters(newFilters, specificGameId: .clear)
        } else {
            if let gameId = session.sessionData.specificGameId {
                // 互斥：选中"特定棋局"时，取消"特定棋书"
                newFilters.removeAll { $0 == Session.filterSpecificBook }
                newFilters.append(Session.filterSpecificGame)
                sessionManager.setFilters(newFilters, specificGameId: .set(gameId))
            }
        }
    }

    /// 切换特定棋书筛选
    func toggleFilterSpecificBook() {
        var newFilters = session.currentFilters

        if newFilters.contains(Session.filterSpecificBook) {
            newFilters.removeAll { $0 == Session.filterSpecificBook }
            // 关闭时显式清除 specificBookId
            sessionManager.setFilters(newFilters, specificBookId: .clear)
        } else {
            if let bookId = session.sessionData.specificBookId {
                // 互斥：选中"特定棋书"时，取消"特定棋局"
                newFilters.removeAll { $0 == Session.filterSpecificGame }
                newFilters.append(Session.filterSpecificBook)
                sessionManager.setFilters(newFilters, specificBookId: .set(bookId))
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

    /// 加载复习项（通过 gamePath 导航到对应局面，锁定已走步骤并隐藏后续）
    func loadReviewItem(_ gamePath: [Int]) {
        // 先清除上一次复习项的锁定，确保 loadBookmark 在完整视图上执行
        session.unlockIfNeeded()
        sessionManager.loadBookmark(gamePath)
        session.lockAndHideAfterCurrentStep()
        // 每次进入新条目时重置为隐藏，避免上一条目的手动开启影响下一条目
        session.sessionData.showPath = false
        session.sessionData.showAllNextMoves = false
        session.sessionData.allowAddingNewMoves = false
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
        let remoteVersion = DatabaseStorage.loadDataVersionFromDefault()

        if let remoteVersion = remoteVersion,
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
        } else if remoteVersion == nil && DatabaseStorage.databaseFileExists() {
            // 存档文件存在但读不出版本号（损坏/未下载/schema 不兼容）。
            // 此时内存数据可能是启动失败后的空库，静默保存会覆盖云端真实数据
            platformService.showConfirmAlert(
                title: "无法确认存档版本",
                message: "存档文件存在但无法读取其版本号（文件可能损坏或尚未从 iCloud 下载完成）。继续保存会覆盖现有存档。\n\n继续前会自动将原存档备份到本地。是否继续保存？",
                completion: { result in
                    if result {
                        if let backupURL = DatabaseStorage.backupExistingDatabaseFile() {
                            print("✅ 原存档已备份到 \(backupURL.path)")
                        } else {
                            print("⚠️ 原存档备份失败（文件可能不可读），继续保存")
                        }
                        self.saveToDefaultWithResultNotification(session: session)
                    } else {
                        self.showWarningAlert(message: "保存取消", info: "保存取消")
                    }
                }
            )
        } else {
            self.saveToDefaultWithResultNotification(session: session)
        }
    }

    func saveToDefaultWithResultNotification(session: Session) {
        do {
            // 1. 引擎分数与 mainSession 文件很小，主线程同步保存
            //   （只保存 mainSession，practiceSession 是临时的）
            try session.databaseView.saveEngineScores()
            try SessionStorage.saveSessionToDefault(session: sessionManager.mainSessionData)
        } catch {
            self.showWarningAlert(
                message: "保存失败",
                info: "无法保存数据：\(error.localizedDescription)"
            )
            return
        }

        // 2. database 是大文件：主线程值快照后异步编码写盘
        //   （主线程全量编码大库要秒级，会整体冻结界面）
        session.databaseView.saveAsync { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // 数据库脏标记已由 saveAsync 处理（保存期间无新修改才转干净）
                self.session.setSessionAndEngineScoreClean()
                self.clearRecoverySnapshot()  // 快照内容已进正式存档，不再需要
                if self.session.databaseDirty {
                    self.showAlert(
                        message: "保存成功",
                        info: "数据已成功保存（保存期间又有新改动，可稍后再次保存）"
                    )
                } else {
                    self.showAlert(
                        message: "保存成功",
                        info: "数据已成功保存"
                    )
                }
            case .failure(let error):
                self.showWarningAlert(
                    message: "保存失败",
                    info: "无法保存数据：\(error.localizedDescription)"
                )
            }
        }
    }

    /// 处理远程文件变更（其他设备修改了 database.json）
    private func handleRemoteFileChange() {
        print("[ViewModel] 检测到远程文件变更")

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
                        // 注意：只保存 mainSession，practiceSession 是临时的
                        try SessionStorage.saveSessionToDefault(session: self.sessionManager.mainSessionData)
                    } catch {
                        self.platformService.showWarningAlert(
                            title: "保存失败",
                            message: "无法保存本地修改：\(error.localizedDescription)"
                        )
                        return
                    }

                    // 强制保存本地数据到 iCloud（覆盖远程）：值快照后异步编码写盘
                    self.session.databaseView.saveAsync { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success:
                            // 数据库脏标记已由 saveAsync 处理（保存期间无新修改才转干净）
                            self.session.setSessionAndEngineScoreClean()
                            self.clearRecoverySnapshot()  // 已写入存档，恢复快照不再需要

                            self.platformService.showAlert(
                                title: "已保存",
                                message: "本地修改已保存并同步到 iCloud"
                            )
                        case .failure(let error):
                            self.platformService.showWarningAlert(
                                title: "保存失败",
                                message: "无法保存本地修改：\(error.localizedDescription)"
                            )
                        }
                    }
                } else {
                    // 用户选择使用远程数据
                    print("[ViewModel] 用户选择使用远程数据，将丢弃本地修改")
                    self.reloadFromRemote()

                    // 清除 dirty 标志与恢复快照（因为已经放弃本地修改）
                    self.setDataClean()
                    self.clearRecoverySnapshot()
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
                        self.session.databaseView.restoreFromBackup(
                            database, remoteVersion: DatabaseStorage.loadDataVersionFromDefault())
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
    
    /// @MainActor：从快捷键闭包经无结构 Task 调用时会落在全局执行器上，
    /// session 状态读写必须归位主线程；网络请求的 await 仍在后台挂起
    @MainActor
    func queryFenScore() async {
        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else {return}
        let yunKuFen = String(fen.split(separator: " - ")[0])

        do {
            if let score = try await IO.queryFenScore(yunKuFen, silentMode: false) {
                session.updateFenScore(fenId, score: score)
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

        // 退避期内不发起新请求（限流或网络故障后指数退避）
        guard Date() >= silentQueryBackoffUntil else { return }

        // 在飞去重：同一 fenId 已在查询则跳过；
        // 已导航到别的局面则取消旧请求，任何时刻至多一个在飞请求，
        // 避免按住方向键扫过未评分线路时发出几十个并发请求
        if silentQueryFenId == fenId, silentQueryTask != nil { return }
        silentQueryTask?.cancel()
        silentQueryFenId = fenId

        let yunKuFen = String(fen.split(separator: " - ")[0])

        silentQueryTask = Task { [weak self] in
            do {
                let score = try await IO.queryFenScore(yunKuFen, silentMode: true)
                await MainActor.run {
                    guard let self else { return }
                    if let score {
                        self.updateFenScore(fenId, score: score)
                    }
                    self.silentQueryFailureCount = 0
                    self.clearSilentQueryTask(for: fenId)
                }
            } catch {
                let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
                await MainActor.run {
                    guard let self else { return }
                    if !cancelled {
                        // 限流或网络故障：指数退避（5s、10s、20s…上限 60s）
                        self.silentQueryFailureCount += 1
                        let delay = min(60.0, 5.0 * pow(2.0, Double(self.silentQueryFailureCount - 1)))
                        self.silentQueryBackoffUntil = Date().addingTimeInterval(delay)
                    }
                    self.clearSilentQueryTask(for: fenId)
                }
            }
        }
    }

    /// 清理在飞记录（仅当仍指向本次请求时，避免误清后续请求的记录）
    private func clearSilentQueryTask(for fenId: Int) {
        if silentQueryFenId == fenId {
            silentQueryTask = nil
            silentQueryFenId = nil
        }
    }
    
    // MARK: - 引擎评估（macOS）

    #if os(macOS)
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

    private func ensureEvaluationQueue() -> EvaluationQueue? {
        if let queue = evaluationQueue { return queue }
        guard let service = ensurePikafishService() else { return nil }
        let queue = EvaluationQueue(pikafishService: service) { fenId, engineKey in
            Database.shared.getEngineScore(fenId: fenId, engineKey: engineKey) != nil
        }
        queue.onEvaluationCompleted = { [weak self] request, result in
            self?.session.updateEngineScore(request.fenId, score: result.score, engineKey: request.engineKey)
        }
        // 转发队列状态变化：视图经 viewModel.evaluationQueue.state 读取进度，
        // 但没有任何视图直接观察 EvaluationQueue，不转发则进度条与取消按钮
        // 不会即时刷新（如取消后进度条悬挂到下一次无关更新）
        queue.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        evaluationQueue = queue
        return queue
    }

    func queryEngineScore() {
        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else { return }
        guard let queue = ensureEvaluationQueue() else { return }
        queue.enqueue(EvaluationRequest(fenId: fenId, fen: fen, engineKey: PikafishService.engineKey, movetime: nil))
    }

    func quickEngineScore() {
        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else { return }
        guard let queue = ensureEvaluationQueue() else { return }
        queue.enqueue(EvaluationRequest(fenId: fenId, fen: fen, engineKey: PikafishService.quickEngineKey, movetime: 3000))
    }

    /// @MainActor：从快捷键闭包经无结构 Task 调用时会落在全局执行器上，
    /// 惰性创建 service/queue 的 ivar 写入、queue.isIdle 读取（MainActor 状态）
    /// 与 session 读写都必须归位主线程；引擎评估的 await 仍在后台挂起
    @MainActor
    func pikafishQuickMove() async {
        guard session.allowAddingNewMoves else {
            platformService.showWarningAlert(
                title: "不允许增加新走法",
                message: "请先打开【允许增加新走法】选项。"
            )
            return
        }
        guard let queue = ensureEvaluationQueue() else { return }
        guard queue.isIdle else {
            platformService.showWarningAlert(
                title: "引擎忙碌中",
                message: "请先等待当前评估完成或取消评估。"
            )
            return
        }

        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else { return }
        guard let service = ensurePikafishService() else { return }

        do {
            if let result = try await service.evaluatePosition(fen: fen, movetime: 3000) {
                // 函数为 @MainActor，await 恢复后数据修改自动回到主线程
                session.updateEngineScore(fenId, score: result.score, engineKey: PikafishService.quickEngineKey)

                // 评估这 3 秒期间用户可能已经切到别的局面：分数按 fenId 存，切到哪都不受影响，
                // 但应招落子必须只在用户仍停留在被评估的这个局面时才执行，
                // 否则会把用户从当前正在看的局面强行拽走到一个跟当前上下文无关的新局面
                if session.currentFenId == fenId,
                   let uciMove = result.bestMove,
                   let newFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: uciMove, fen: fen) {
                    _ = session.playNewBoardFen(newFen)
                    session.updateEngineScore(session.currentFenId, score: -result.score, engineKey: PikafishService.quickEngineKey)
                }
            }
        } catch {
            platformService.showWarningAlert(
                title: "皮卡鱼应招失败",
                message: error.localizedDescription
            )
        }
    }

    #endif

    // MARK: - 只读 MultiPV 分析（跨平台）
    //
    // 两个消费方：macOS 的远程 /eval 接口（供 MCP 桥接外部 Claude），以及三端的
    // app 内 AI 问棋（AnalysisToolbox 的 evaluate 工具）。两者都是只读分析，
    // 都要与 app 内的评估任务抢同一个引擎，所以共用下面这套忙碌互斥。

    /// 分析进行中标志：防止并发请求同时驱动同一个引擎。
    /// 供 Release 也启用的只读接口使用，故不限 DEBUG
    private var isRemoteAnalyzing = false

    enum RemoteAnalyzeError: Error, LocalizedError {
        case engineBusy
        case engineUnavailable

        var errorDescription: String? {
            switch self {
            case .engineBusy: return "引擎忙碌中（有评估任务在进行）"
            #if os(macOS)
            case .engineUnavailable: return "引擎不可用（仅支持 Apple Silicon Mac）"
            #else
            case .engineUnavailable: return "引擎不可用"
            #endif
            }
        }
    }

    /// 对指定局面做 MultiPV 引擎分析。
    /// 只读分析，不写入数据库；与 app 内评估共用引擎，忙碌时直接拒绝。
    /// @MainActor：忙碌标志与惰性创建的 service ivar 都是主线程状态；
    /// 引擎评估的 await 挂起期间不占用主线程
    @MainActor
    func remoteEngineAnalyze(fen: String, multiPV: Int, movetime: Int) async throws -> [EnginePVLine] {
        if isRemoteAnalyzing { throw RemoteAnalyzeError.engineBusy }
        isRemoteAnalyzing = true
        defer { isRemoteAnalyzing = false }

        #if os(macOS)
        if let queue = evaluationQueue, !queue.isIdle { throw RemoteAnalyzeError.engineBusy }
        guard let service = ensurePikafishService() else { throw RemoteAnalyzeError.engineUnavailable }
        return try await service.analyzePosition(fen: fen, multiPV: multiPV, movetime: movetime)
        #elseif os(iOS)
        // iOS 侧与「AI 应招」共用同一个内嵌引擎实例；互斥由 service 自己保证
        do {
            return try await ensurePikafishServiceIOS()
                .analyzePosition(fen: fen, multiPV: multiPV, movetime: movetime)
        } catch PikafishServiceIOS.EngineError.busy {
            throw RemoteAnalyzeError.engineBusy
        }
        #else
        throw RemoteAnalyzeError.engineUnavailable
        #endif
    }

    /// 中断正在进行的只读分析。
    ///
    /// 用户点「停止」时必须调——只取消 Swift Task 不会让引擎停下来，它会把剩下的
    /// movetime 跑完：Mac 上白烧 CPU，iPhone 上白烧电。
    /// 引擎收到 stop 会立刻发 bestmove，analyzePosition 因此提前返回已有结果。
    @MainActor
    func stopRemoteEngineAnalyze() {
        #if os(macOS)
        pikafishService?.stopCurrentSearch()
        #elseif os(iOS)
        pikafishServiceIOS?.stopCurrentSearch()
        #endif
    }

    #if os(macOS)
    func queryAllEngineScores() {
        guard let queue = ensureEvaluationQueue() else { return }
        let game = session.sessionData.currentGame2
        var requests: [EvaluationRequest] = []
        for fenId in game {
            if Database.shared.getEngineScore(fenId: fenId, engineKey: PikafishService.engineKey) != nil { continue }
            guard let fen = session.getFenForId(fenId) else { continue }
            requests.append(EvaluationRequest(fenId: fenId, fen: fen, engineKey: PikafishService.engineKey, movetime: nil))
        }
        queue.enqueueAll(requests)
    }

    func quickAllEngineScores() {
        guard let queue = ensureEvaluationQueue() else { return }
        let game = session.sessionData.currentGame2
        var requests: [EvaluationRequest] = []
        for fenId in game {
            // 只看快估分：与深评本局对称，各管各的 engineKey。
            // 即使已有深评分，也仍补算快估分（按用户需求，不再因深评存在而跳过）
            if Database.shared.getEngineScore(fenId: fenId, engineKey: PikafishService.quickEngineKey) != nil { continue }
            guard let fen = session.getFenForId(fenId) else { continue }
            requests.append(EvaluationRequest(fenId: fenId, fen: fen, engineKey: PikafishService.quickEngineKey, movetime: 3000))
        }
        queue.enqueueAll(requests)
    }

    func cancelEvaluation() {
        evaluationQueue?.cancelAll()
    }

    #endif

    #if os(iOS)
    private func ensurePikafishServiceIOS() -> PikafishServiceIOS {
        if let service = pikafishServiceIOS { return service }
        let service = PikafishServiceIOS()
        pikafishServiceIOS = service
        return service
    }

    /// AI 应招（iOS 专属，内嵌引擎，固定 3 秒限时的「轻评」参数）：
    /// 评估当前局面并落子最佳应招，原局面和应招后局面的分数都存到 PikafishServiceIOS.engineKey（轻评分数）下
    @MainActor
    func aiRespondIOS() async {
        guard !isEvaluatingIOS else { return }
        guard session.allowAddingNewMoves else {
            platformService.showWarningAlert(
                title: "不允许增加新走法",
                message: "请先打开【允许增加新走法】选项。"
            )
            return
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            platformService.showWarningAlert(
                title: "低电量模式",
                message: "当前设备处于低电量模式，暂不进行引擎评估。"
            )
            return
        }
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            platformService.showWarningAlert(
                title: "设备过热",
                message: "设备当前温度较高，暂不进行引擎评估，请稍后再试。"
            )
            return
        }

        let fenId = session.currentFenId
        guard let fen = session.getFenForId(fenId) else { return }

        isEvaluatingIOS = true
        aiRespondCancelled = false
        defer { isEvaluatingIOS = false }

        let service = ensurePikafishServiceIOS()
        let result: PikafishServiceIOS.EvaluationResult?
        do {
            result = try await service.evaluatePosition(fen: fen)
        } catch {
            // 只可能是 busy：问棋分析正占着引擎
            platformService.showWarningAlert(
                title: "引擎忙碌中",
                message: "AI 问棋正在分析，请稍后再试。"
            )
            return
        }
        guard let result else { return }

        // 用户思考期间点了取消：结果整个丢弃，不存分也不落子，就当没点过
        guard !aiRespondCancelled else { return }

        session.updateEngineScore(fenId, score: result.score, engineKey: PikafishServiceIOS.engineKey)

        // 评估这 3 秒期间用户可能已经切到别的局面：分数按 fenId 存，切到哪都不受影响，
        // 但应招落子必须只在用户仍停留在被评估的这个局面时才执行，
        // 否则会把用户从当前正在看的局面强行拽走到一个跟当前上下文无关的新局面
        guard session.currentFenId == fenId else { return }

        if let uciMove = result.bestMove,
           let newFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: uciMove, fen: fen) {
            _ = session.playNewBoardFen(newFen)
            session.updateEngineScore(session.currentFenId, score: -result.score, engineKey: PikafishServiceIOS.engineKey)
        }
    }

    /// 取消正在进行的 AI 应招：通知引擎提前结束搜索，结果到达后会被丢弃
    @MainActor
    func cancelAIRespondIOS() {
        guard isEvaluatingIOS else { return }
        aiRespondCancelled = true
        pikafishServiceIOS?.stopCurrentSearch()
    }
    #endif

    var currentFenQuickEvalStatus: FenEvalStatus {
        #if os(macOS)
        return evaluationQueue?.statusForFen(fenId: session.currentFenId, engineKey: PikafishService.quickEngineKey) ?? .idle
        #else
        return .idle
        #endif
    }

    var currentFenDeepEvalStatus: FenEvalStatus {
        #if os(macOS)
        return evaluationQueue?.statusForFen(fenId: session.currentFenId, engineKey: PikafishService.engineKey) ?? .idle
        #else
        return .idle
        #endif
    }

    func copyFenToClipboard() {
        let fen = displayFen
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fen, forType: .string)
        #else
        UIPasteboard.general.string = fen
        #endif
    }

    func generateBoardText() -> String {
        let fen = session.currentFen
        let parts = fen.split(separator: " ")
        let boardPart = parts.first ?? Substring(fen)
        let rows = boardPart.split(separator: "/")

        let sideToMove = parts.count > 1 && parts[1] == "b" ? "black" : "red"

        var lines: [String] = []
        lines.append("side_to_move: \(sideToMove)")
        lines.append("fen: \(boardPart)")
        lines.append("")
        lines.append("    a b c d e f g h i")

        for (index, row) in rows.enumerated() {
            let rowNum = 10 - index
            var cells: [String] = []
            for ch in row {
                if let digit = ch.wholeNumberValue {
                    for _ in 0..<digit {
                        cells.append(".")
                    }
                } else {
                    cells.append(String(ch))
                }
            }
            let rowLabel = String(format: "%2d", rowNum)
            lines.append("\(rowLabel)  \(cells.joined(separator: " "))")
        }

        return lines.joined(separator: "\n")
    }

    func copyBoardTextToClipboard() {
        let text = generateBoardText()
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// 构建一个与当前棋盘展示状态一致、脱离实时绑定的静态快照，供离屏渲染导出图片使用。
    /// 不能直接复用 `boardViewModel`：它是 class，会被 `updateBoardView()` 持续原地修改，
    /// 离屏渲染期间若发生变化会导致图片内容与截图瞬间不一致。
    func makeBoardSnapshotForImageExport() -> BoardViewModel {
        BoardViewModel(
            fen: boardViewModel.getFen(),
            orientation: boardViewModel.getOrientation(),
            isHorizontalFlipped: boardViewModel.getIsHorizontalFlipped(),
            showPath: boardViewModel.getShowPath(),
            showAllNextMoves: boardViewModel.getShowAllNextMoves(),
            shouldAnimate: false,
            currentFenPathGroups: boardViewModel.getCurrentFenPathGroups(),
            nextMovesPathGroups: boardViewModel.getNextMovesPathGroups(),
            lastMoveSquares: boardViewModel.getLastMoveSquares()
        )
    }

    func copyBoardImageToClipboard() {
        let snapshot = makeBoardSnapshotForImageExport()
        let boardSize: CGFloat = 640
        let boardView = XiangqiBoard(viewModel: .constant(snapshot), staticSnapshot: true)
            .frame(width: boardSize, height: boardSize)

        let renderer = ImageRenderer(content: boardView)
        renderer.scale = 3

        #if os(macOS)
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #else
        guard let image = renderer.uiImage else { return }
        UIPasteboard.general.image = image
        #endif
    }

    func openYunku() {
        let fen = session.currentFen
        let yunkuFen = fen.split(separator: " - ")[0]
        if let url = URL(string: "http://www.qqzze.com/yunku/?" + yunkuFen) {
            platformService.openURL(url)
        }
    }
    
    // MARK: - 随机游戏
    
    func makeRandomGame() -> Int? {
        // 如果没有锁定的着法，随机选择红方或黑方开局库筛选。
        // 必须显式 setFilters 而非 toggle：当前已在红方开局筛选时
        // 随机到红方，toggle 会把筛选关掉，在全库上随机
        if !isAnyMoveLocked {
            let filter = Bool.random() ? Session.filterRedOpeningOnly : Session.filterBlackOpeningOnly
            sessionManager.setFilters([filter])
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

    /// 打开 AI 问棋窗口。已开着就带到前台——对话上下文留在窗口里，
    /// 每次都新建会把追问的前情丢掉
    func showAIChat() {
        #if os(macOS)
        if let controller = aiChatWindowController, controller.window?.isVisible == true {
            controller.chat.reloadConfig()
            controller.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = AIChatWindowController(viewModel: self)
        aiChatWindowController = controller
        controller.showWindow(nil)
        #else
        showingAIChat = true
        #endif
    }

    /// 打开问棋并直接发出一个现成的问题（评论区的「问 AI」快捷入口用）
    func askAI(_ question: String) {
        showAIChat()
        #if os(macOS)
        aiChatWindowController?.chat.ask(question)
        #else
        // iOS 的 ChatViewModel 建在 sheet 里，这里够不着，
        // 挂起来等 sheet 起来自己取
        pendingAIQuestion = question
        #endif
    }

    /// 常用的两种问法。做成常量而不是散在视图里：三端要一致，
    /// 措辞也直接决定模型往哪个方向答
    enum AIQuickQuestion {
        static let analyzePosition = "分析一下这个局面。"
        static let whyLastMoveIsBad = "为什么这一步不好？"
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
    var currentFen: String { session.currentFen }
    /// 用于显示和拷贝的 FEN：`r` → `w`，尾部 `1 1` → `0 1`
    var displayFen: String {
        var fen = session.currentFen
        // r → w（红方用标准 FEN 的 w 表示）
        if let range = fen.range(of: " r ", options: .backwards) {
            fen.replaceSubrange(range, with: " w ")
        }
        // 尾部 - - 1 1 → - - 0 1
        if fen.hasSuffix(" - - 1 1") {
            fen = String(fen.dropLast(7)) + "- - 0 1"
        }
        return fen
    }
    var currentMoveUCCI: String {
        guard let move = session.currentMove,
              let pieceMove = session.databaseView.parsePieceMove(move, isHorizontalFlipped: false)
        else { return "" }
        return PGNParser.pieceMoveToCoord(pieceMove)
    }
    var currentFenId: Int { session.currentFenId }
    var displayScore: String { session.displayScore }
    var displayEngineScore: String { session.displayEngineScore }
    var displayDeepEngineScore: String { session.displayDeepEngineScore }
    var displayQuickEngineScore: String { session.displayQuickEngineScore }
    var currentGameStepDisplay: Int { session.currentGameStepDisplay }
    var maxGameStepDisplay: Int { session.maxGameStepDisplay }
    var currentFenComment: String? { session.currentFenComment }
    var currentMoveComment: String? { session.currentMoveComment }
    var hasCurrentMove: Bool { session.currentMove != nil }
    /// 走当前这一步之前的局面。问「这步为什么不好」时要以它为准评估
    var previousFen: String? { session.previousFenObject?.fen }
    /// 按 fen 找笔记本里的 fenId；不在库里返回 nil（不新建）。
    /// 必须先 normalizeFen：库里存的是归一化形式，直接查会因为着数计数不同而全部落空
    func notebookFenId(for fen: String) -> Int? {
        session.databaseView.getIdForFen(normalizeFen(fen))
    }
    /// 当前手的着法记谱文本（评论面板标题用）
    var currentMoveNotation: String? { session.currentMove.map { session.getMoveString(move: $0) } }
    var currentMoveBadReason: String? { session.currentMoveBadReason }
    var currentCombinedComment: String? { session.currentCombinedComment }
    var bookmarkList: [(game: [Int], name: String)] { session.bookmarkList }
    var isCurrentFenInReview: Bool { session.isCurrentFenInReview }
    var reviewItemList: [(fenId: Int, srsData: SRSData)] { session.reviewItemList }
    /// 当前到期待复习的局面数（今日首页 Hero 卡用）
    var dueReviewItemsCount: Int { session.dueReviewItems.count }
    func removeReviewItem(fenId: Int) { session.removeReviewItem(fenId: fenId) }
    func renameReviewItem(fenId: Int, name: String) { session.renameReviewItem(fenId: fenId, name: name) }
    func reviewAgain(fenId: Int) {
        session.reviewAgain(fenId: fenId)
        if isInReviewMode {
            startReview()
        }
    }
    func reviewItemDescription(fenId: Int) -> String {
        if let srsData = session.databaseView.reviewItems[fenId],
           let customName = srsData.customName, !customName.isEmpty {
            return customName
        }
        guard let fenObj = session.databaseView.getFenObjectUnfiltered(fenId) else {
            return "fenId: \(fenId)"
        }
        if let comment = fenObj.comment, !comment.isEmpty {
            return comment
        }
        return String(fenObj.fen.prefix(20))
    }

    // MARK: - 复习模式

    var isInReviewMode: Bool { currentAppMode == .review }

    /// 复习流程进行中（队列非空且未完成）
    var isReviewingInProgress: Bool {
        !reviewQueue.isEmpty && currentReviewIndex < reviewQueue.count
    }

    /// 复习全部完成
    var isReviewComplete: Bool {
        !reviewQueue.isEmpty && currentReviewIndex >= reviewQueue.count
    }

    /// 当前复习项；索引越界时返回 nil。
    /// 给最后一项评分后 currentReviewIndex 会等于 reviewQueue.count，
    /// SwiftUI 可能在父视图切换到完成态之前重算进行中视图的 body，
    /// 视图必须经由本属性安全取值，不可直接下标访问 reviewQueue
    var currentReviewItem: (fenId: Int, srsData: SRSData)? {
        guard currentReviewIndex >= 0, currentReviewIndex < reviewQueue.count else { return nil }
        return reviewQueue[currentReviewIndex]
    }

    /// 复习进度显示
    var reviewProgress: String {
        "\(min(currentReviewIndex + 1, reviewQueue.count))/\(reviewQueue.count)"
    }

    /// 启动复习：筛选到期项，构建队列，导航到第一项
    func startReview() {
        let dueItems = session.dueReviewItems
        reviewQueue = dueItems
        currentReviewIndex = 0
        if let first = dueItems.first, let gamePath = first.srsData.gamePath {
            loadReviewItem(gamePath)
        } else if let first = reviewItemList.first, let gamePath = first.srsData.gamePath {
            // 没有到期项时，加载第一个复习项以锁定
            loadReviewItem(gamePath)
        }
    }

    /// 提交复习评分，前进到下一项
    func submitReviewRating(_ quality: ReviewQuality) {
        if isInVerificationMode {
            // 核对答案模式：提交评分后退出核对，继续复习流程
            if let item = verificationItem {
                session.submitReviewRating(fenId: item.fenId, quality: quality)
            }
            exitVerificationMode()
            // 前进到下一项
            if isReviewingInProgress {
                currentReviewIndex += 1
                if isReviewingInProgress {
                    let nextItem = reviewQueue[currentReviewIndex]
                    if let gamePath = nextItem.srsData.gamePath {
                        loadReviewItem(gamePath)
                    }
                }
            }
            return
        }
        guard isReviewingInProgress else { return }
        let item = reviewQueue[currentReviewIndex]
        session.submitReviewRating(fenId: item.fenId, quality: quality)
        currentReviewIndex += 1
        if isReviewingInProgress {
            let nextItem = reviewQueue[currentReviewIndex]
            if let gamePath = nextItem.srsData.gamePath {
                loadReviewItem(gamePath)
            }
        }
    }

    /// 跳过当前复习项
    func skipCurrentReviewItem() {
        guard isReviewingInProgress else { return }
        currentReviewIndex += 1
        if isReviewingInProgress {
            let nextItem = reviewQueue[currentReviewIndex]
            if let gamePath = nextItem.srsData.gamePath {
                loadReviewItem(gamePath)
            }
        }
    }

    /// 退出复习模式，重置状态
    func exitReviewMode() {
        reviewQueue = []
        currentReviewIndex = 0
        setMode(.normal)
    }

    // MARK: - 检验模式

    /// 进入检验模式：导航到复习项，锁定但显示路径和着法，不更新 SRS 数据
    func enterVerificationMode(fenId: Int, srsData: SRSData, gamePath: [Int]) {
        verificationItem = (fenId: fenId, srsData: srsData)
        session.unlockIfNeeded()
        sessionManager.loadBookmark(gamePath)
        session.lockAndHideAfterCurrentStep()
        session.sessionData.showPath = true
        session.sessionData.showAllNextMoves = true
        session.sessionData.autoExtendGameWhenPlayingBoardFen = true
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            showReviewModeIOS = true
        }
        #endif
    }

    /// 退出检验模式
    func exitVerificationMode() {
        verificationItem = nil
        session.unlockIfNeeded()
    }

    var currentGameMoveListDisplay: [MoveListItem] { session.currentGameMoveList }
    var currentGameVariantListDisplay: [(moveString: String, move: Move)] {
        session.currentGameVariantList.sorted { $0.moveString < $1.moveString }
    }

    var currentNextMovesListDisplay: [(moveString: String, move: Move)] {
        session.currentNextMovesList.sorted { $0.moveString < $1.moveString }
    }

    func playNextMove(_ move: Move) {
        session.playNextMove(move)
        queryFenScoreSilentlyIfNeeded()
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
    var isRedTurn: Bool { session.blackJustPlayed }
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
    var currentLockedStep: Int? { session.sessionData.lockedStep }
    var lockedFenId: Int? {
        guard let step = session.sessionData.lockedStep,
              step < session.sessionData.currentGame2.count else { return nil }
        return session.sessionData.currentGame2[step]
    }
    func setGameStepLimitation(_ limit: Int?) { session.setGameStepLimitation(limit) }

    func isBadMove(_ move: Move) -> Bool { session.isBadMove(move) }
    func isRecommendedMove(_ move: Move) -> Bool { session.isRecommendedMove(move) }
    func isMoveLocked(_ stepIndex: Int) -> Bool { session.isMoveLocked(stepIndex) }

    /// 练习模式选择题：记录用户点选的错误候选着法（走该手后的局面 FEN 作为错误记录）
    func recordPracticeMistake(wrongMove: Move) {
        guard let targetFenId = wrongMove.targetFenId,
              let fenObj = session.databaseView.getFenObjectUnfiltered(targetFenId) else { return }
        session.recordPracticeMistakeAtCurrentFen(wrongBoardFen: fenObj.fen)
    }

    var currentAppMode: AppMode { session.currentAppMode }
    var showPath: Bool { session.showPath }
    var showAllNextMoves: Bool { session.showAllNextMoves }
    var showLastMove: Bool { session.showLastMove }
    var showRedAttackPoints: Bool { session.showRedAttackPoints }
    var showBlackAttackPoints: Bool { session.showBlackAttackPoints }
    var attackPointsRedPalaceOnly: Bool { session.attackPointsRedPalaceOnly }
    var attackPointsBlackPalaceOnly: Bool { session.attackPointsBlackPalaceOnly }
    var showRealGameList: Bool { session.showRealGameList }
    var showGameBrowserSidebar: Bool { session.showGameBrowserSidebar }
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
        session.allTopLevelBookObjects.sorted { b1, b2 in
            b1.name.localizedStandardCompare(b2.name) == .orderedAscending
        }
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

    /// 递归取某个棋书（含所有子棋书）下的全部棋局，用于「棋谱」标签的树形浏览
    func getGamesInBookRecursively(_ bookId: UUID) -> [GameObject] {
        session.databaseView.getGamesInBookRecursivelyUnfiltered(bookId: bookId)
    }

    func getSubBooksInBook(_ book: BookObject) -> [BookObject] {
        book.subBookIds.compactMap { id in
            session.allBookObjects.first { $0.id == id }
        }.sorted { b1, b2 in
            b1.name.localizedStandardCompare(b2.name) == .orderedAscending
        }
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
        // 如果当前正在查看被删除的棋书，先切换到全库视图，避免 DatabaseView 筛选失效
        if currentFilters.contains(Session.filterSpecificBook),
           session.sessionData.specificBookId == bookId {
            sessionManager.setFilters([], specificBookId: .clear)
        } else if session.sessionData.specificBookId == bookId {
            sessionManager.setFilters(currentFilters, specificBookId: .clear)
        }
        session.deleteBook(bookId)
        // 棋书删除会级联删除其下棋局，残留的 specificGameId 可能指向已删棋局
        if let gameId = session.sessionData.specificGameId,
           session.databaseView.getGameObjectUnfiltered(gameId) == nil {
            sessionManager.setFilters(currentFilters, specificGameId: .clear)
        }
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
            sessionManager.setFilters([], specificGameId: .clear)
        } else if session.sessionData.specificGameId == gameId {
            // 不在特定棋局视图但残留的 id 指向被删棋局：清除，避免之后 toggle 回已删棋局
            sessionManager.setFilters(currentFilters, specificGameId: .clear)
        }
        session.deleteGame(gameId)
    }

    func importPGNFile(content: String, username: String) -> PGNImportResult {
        session.setupDefaultBooksIfNeeded()
        let databaseView = DatabaseView.full(database: sessionManager.database)
        let result = PGNImportService.importPGN(content: content, username: username, databaseView: databaseView)
        if result.imported > 0 {
            // Database is already marked dirty by PGNImportService operations.
            // Toggle dataChanged to trigger UI updates.
            session.dataChanged.toggle()
        }
        return result
    }

    /// 导入一节课程视频的棋谱：多条线路合并为目标课程棋书中的一个棋局，
    /// 并关联视频文件路径与各局面的视频时间戳（mm:ss）
    func importCourseGame(
        bookPath: [String],
        name: String,
        lines: [CourseImportService.LineInput],
        videoPath: String?
    ) throws -> CourseImportService.ImportResult {
        session.setupDefaultBooksIfNeeded()
        let databaseView = DatabaseView.full(database: sessionManager.database)
        let bookId = try CourseImportService.resolveCourseBook(path: bookPath, databaseView: databaseView)
        let result = try CourseImportService.importCourseGame(
            bookId: bookId, name: name, lines: lines, databaseView: databaseView)
        if let videoPath {
            setCourseVideoPath(videoPath, for: result.gameId)
            for (fenId, seconds) in result.fenTimestamps {
                let total = Int(seconds.rounded())
                let timestamp = String(format: "%02d:%02d", total / 60, total % 60)
                setCourseVideoTimestamp(timestamp, for: result.gameId, fenId: fenId)
            }
        }
        session.dataChanged.toggle()
        return result
    }

    func exportPGNCurrentDatabaseViewContent() -> String {
        let rootFenId = session.sessionData.currentGame2[0]
        return PGNExportService.exportCurrentDatabaseView(databaseView: session.databaseView, rootFenId: rootFenId)
    }

    func exportPGNCurrentGameContent() -> String {
        let path = session.sessionData.currentGame2
        return PGNExportService.exportCurrentGame(path: path, databaseView: session.databaseView)
    }

    #if os(macOS)
    func exportPGNCurrentDatabaseView() {
        let content = exportPGNCurrentDatabaseViewContent()
        guard !content.isEmpty else {
            showGlobalAlert(title: "导出PGN", message: "当前范围内没有可导出的路径")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "export.pgn"
        savePanel.title = "导出所有变着PGN"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showGlobalAlert(title: "导出失败", message: error.localizedDescription)
        }
    }

    func exportPGNCurrentGame() {
        let content = exportPGNCurrentGameContent()
        guard !content.isEmpty else {
            showGlobalAlert(title: "导出PGN", message: "当前棋局没有可导出的着法")
            return
        }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "export.pgn"
        savePanel.title = "导出当前棋局PGN"

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showGlobalAlert(title: "导出失败", message: error.localizedDescription)
        }
    }
    #endif

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
        if isInVerificationMode {
            exitVerificationMode()
        }
        session.setMode(mode)
        if mode == .review {
            startReview()
            #if os(iOS)
            // iPhone 上以 sheet 形式展示复习面板
            if UIDevice.current.userInterfaceIdiom == .phone {
                showReviewModeIOS = true
            }
            #endif
        } else {
            // 退出复习模式时重置队列
            reviewQueue = []
            currentReviewIndex = 0
        }
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

    func toggleShowLastMove() {
        session.toggleShowLastMove()
    }

    func toggleShowRedAttackPoints() {
        session.toggleShowRedAttackPoints()
    }

    func toggleShowBlackAttackPoints() {
        session.toggleShowBlackAttackPoints()
    }

    func toggleAttackPointsRedPalaceOnly() {
        session.toggleAttackPointsRedPalaceOnly()
    }

    func toggleAttackPointsBlackPalaceOnly() {
        session.toggleAttackPointsBlackPalaceOnly()
    }

    func toggleShowRealGameList() {
        session.toggleShowRealGameList()
    }

    /// 「记录变招」：是否允许在棋盘上走出新着法时把它写入棋谱
    var allowAddingNewMoves: Bool { session.allowAddingNewMoves }
    func toggleAllowAddingNewMoves() { session.toggleAllowAddingNewMoves() }

    func toggleShowGameBrowserSidebar() {
        session.toggleShowGameBrowserSidebar()
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

    /// 是否存在正在进行的专项练习（今日/练习首页「继续练习」卡用）
    var isInFocusedPractice: Bool { sessionManager.isInFocusedPractice }

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

    /// 获取包含当前局面的实战对局列表（转发到 Session）
    var relatedRealGamesForCurrentFen: [GameObject] {
        session.relatedRealGamesForCurrentFen
    }

    /// 是否有更多相关实战（超过5个）
    var hasMoreRelatedRealGames: Bool {
        session.hasMoreRelatedRealGames
    }
}
