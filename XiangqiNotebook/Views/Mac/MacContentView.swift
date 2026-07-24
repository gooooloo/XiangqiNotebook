#if os(macOS)
import SwiftUI
import Foundation
import AppKit

struct MacContentView: View {
    @StateObject private var viewModel: ViewModel
    @FocusState private var isViewFocused: Bool
    @State private var keyMonitor: Any?
    // 本地分析服务在 Release 也启用（只读接口供 MCP 使用；驱动 app 的
    // /action、/actions 仍限 DEBUG，切分在 RemoteControlServer 内部）
    @State private var remoteControlServer: RemoteControlServer?
    
    init() {
        _viewModel = StateObject(wrappedValue: ViewModel(
            platformService: MacOSPlatformService()
        ))
    }
    
    /// 清除 TextEditor 焦点并将焦点设置到主视图
    private func clearTextEditorFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        isViewFocused = true
    }
    
    /// 弹性列宽：clamp(min, 比例, max)
    private func clampWidth(_ total: CGFloat, ratio: CGFloat, min minW: CGFloat, max maxW: CGFloat) -> CGFloat {
        Swift.min(maxW, Swift.max(minW, total * ratio))
    }

    var body: some View {
        GeometryReader { geometry in
            // 侧栏 / 着法列 / 右栏：确定宽度且更高布局优先级，HStack 先把它们排满，
            // 棋盘栏拿剩余空间（最低优先级），因此列宽只随窗口宽度变化，既不会被
            // 评论区内容反向挤压而随局面漂移，也不会在窄窗口下被压成空白。
            // 各列 min/max 随字号缩放，避免放大字体后窄列装不下内容。
            let totalWidth = geometry.size.width
            let sidebarShown = viewModel.showGameBrowserSidebar
            let sidebarWidth = sidebarShown ? clampWidth(totalWidth, ratio: 0.15, min: Theme.fs(178), max: Theme.fs(238)) : 0
            let middleWidth = clampWidth(totalWidth, ratio: 0.17, min: Theme.fs(208), max: Theme.fs(272))
            let rightWidth = clampWidth(totalWidth, ratio: 0.18, min: Theme.fs(220), max: Theme.fs(288))

            // 本步 / 下步变招固定为约 4 行 item 的高度（多余交给滚动条），不再随窗口
            // 高度线性增长挤占上方招法列表。各项随字号缩放，放大字体时同步变高。
            //   行高 ≈ fs(20)（文字 fs 12.5 + 上下 padding 3 + 分隔线）
            //   再加 标题 fs(12) + VStack spacing 5 + 外层上下 padding(6) 共 12
            let variantListHeight = Theme.fs(20) * 4 + Theme.fs(12) + 5 + 12

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // 棋局浏览器侧栏（弹性宽度 clamp(178, 15%, 238)，可折叠）
                    if sidebarShown {
                        GameBrowserSidebarView(viewModel: viewModel)
                            .frame(width: sidebarWidth)
                            .layoutPriority(1)
                        Divider()
                    }

                    // 左侧区域：棋盘
                    VStack(spacing: 0) {
                        // 棋盘 - 按可用空间等比缩放并居中（内部 aspectRatio .fit），
                        // 多余的纵向空间留给它，而不是堆给评论区
                        XiangqiBoard(viewModel: $viewModel.boardViewModel, onMove: { newFen in
                            viewModel.handleBoardMove(newFen)
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // 状态栏 - 保持固定高度
                        StatusBarView(viewModel: viewModel)

                        // 评论区 - 限高，避免空评论框过高
                        CommentView(viewModel: viewModel)
                            .frame(maxHeight: geometry.size.height * 0.30)
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(Theme.centerBackground)

                    Divider()

                    // 中间区域：着法列 + 变招（弹性宽度 clamp(208, 17%, 272)）
                    // 着法列表 / 本步变招 / 下步变招 三段上下竖排，各占满整列宽度，
                    // 这样变招行能拿到完整列宽，分数不会因列太窄被截断或换行。
                    VStack(spacing: 0) {
                        MoveListView(viewModel: viewModel)
                            .frame(maxHeight: .infinity)
                        VariantListView(viewModel: viewModel)
                            .frame(height: variantListHeight)
                        NextMovesListView(viewModel: viewModel)
                            .frame(height: variantListHeight)
                    }
                    .frame(width: middleWidth)
                    .layoutPriority(1)
                    .background(Theme.sidebarBackground)

                    Divider()

                    // 右侧区域
                    if viewModel.isInVerificationMode {
                        // 检验模式：检验面板 + 单项列表 + 棋盘操作（底部）
                        VStack(spacing: 0) {
                            ModeSelectorView(viewModel: viewModel)
                            ReviewModeView(viewModel: viewModel)
                            ScrollView {
                                ReviewListView(viewModel: viewModel)
                            }
                            .border(Color.gray)
                            .frame(maxHeight: .infinity)
                            BoardOperationTogglesView(viewModel: viewModel)
                        }
                        .frame(width: rightWidth)
                    .layoutPriority(1)
                    .background(Theme.sidebarBackground)
                    } else if viewModel.isInReviewMode {
                        // 复习模式：复习面板 + 复习库列表（填满） + 棋盘操作（底部）
                        VStack(spacing: 0) {
                            ModeSelectorView(viewModel: viewModel)
                            ReviewModeView(viewModel: viewModel)
                            ScrollView {
                                ReviewListView(viewModel: viewModel)
                            }
                            .border(Color.gray)
                            .frame(maxHeight: .infinity)
                            BoardOperationTogglesView(viewModel: viewModel)
                        }
                        .frame(width: rightWidth)
                    .layoutPriority(1)
                    .background(Theme.sidebarBackground)
                    } else {
                        // 常规/练习模式：ScrollView 包裹
                        ScrollView {
                            VStack(spacing: 0) {
                                ModeSelectorView(viewModel: viewModel)
                                TogglesView(viewModel: viewModel)
                                BookmarkListView(viewModel: viewModel)
                                if viewModel.currentAppMode == .normal && viewModel.showRealGameList {
                                    RealGameListView(viewModel: viewModel)
                                }
                            }
                        }
                        .frame(width: rightWidth)
                    .layoutPriority(1)
                    .background(Theme.sidebarBackground)
                    }
                }

                // 按钮区 - 占据所有宽度
                MacActionButtonsView(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
            }
            .focused($isViewFocused)
        }
        .sheet(isPresented: $viewModel.showingBookmarkAlert) {
            BookmarkDialog(
                isPresented: $viewModel.showingBookmarkAlert,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $viewModel.showMarkPathView) {
            MarkPathView(viewModel: viewModel.boardViewModel) { updatedPathGroups in
                viewModel.updateCurrentFenPathGroups(updatedPathGroups)
            }
        }
        .sheet(isPresented: $viewModel.showingGameBrowserView) {
            GameBrowserView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingPGNImportSheet) {
            PGNImportView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingStepLimitationDialog) {
            StepLimitationDialog(isPresented: $viewModel.showingStepLimitationDialog, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingGameInputView) {
            GameInputView(
                viewModel: viewModel,
                onSave: { game in
                    return viewModel.addCurrentGameToMyRealGame(gameInfo: game)
                }
            )
        }
        .sheet(isPresented: $viewModel.showingReviewListView) {
            ReviewListView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(isPresented: $viewModel.showingBoardTextView) {
            BoardTextView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingShortcutUsageStatsView) {
            ShortcutUsageStatsView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingPracticeMistakeStatsView) {
            PracticeMistakeStatsView(viewModel: viewModel)
        }
        .onChange(of: viewModel.isCommentEditing) { oldValue, newValue in
            // 当评论编辑状态从 true 变为 false 时，清除焦点
            if oldValue && !newValue {
                DispatchQueue.main.async {
                    clearTextEditorFocus()
                }
            }
        }
        .focusedSceneObject(viewModel)
        .onAppear {
            updateWindowTitle()
            installKeyMonitor()
            startRemoteControlServer()
        }
        .onDisappear {
            removeKeyMonitor()
            remoteControlServer?.stop()
            remoteControlServer = nil
        }
        .onReceive(viewModel.objectWillChange) { _ in
            // 监听 ViewModel 的任何变化，及时更新窗口标题
            // 这样可以捕获 filter 切换、棋局加载等所有导致 windowTitle 变化的情况
            updateWindowTitle()
        }
    }

    /// 安装全局按键监控，不依赖 SwiftUI 焦点系统
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 如果有任何 sheet 显示，不处理快捷键
            if viewModel.isAnySheetPresented { return event }

            // 检查焦点是否在文本输入控件上
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                // NSTextField 的 first responder 实际是其 field editor（NSTextView, isFieldEditor=true），
                // 例如 NSAlert 中的输入框。和 NSTextField 一视同仁：直接放行。
                if let textView = firstResponder as? NSTextView, textView.isFieldEditor {
                    return event
                }

                // 如果焦点在 TextField 上，不处理快捷键
                if firstResponder is NSTextField { return event }

                // 如果焦点在 TextEditor (NSTextView, 非 field editor) 上
                if firstResponder is NSTextView {
                    if !viewModel.isCommentEditing {
                        // 评论编辑已关闭但焦点仍在 TextEditor，强制清除焦点
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        // 清除焦点后继续处理快捷键
                    } else {
                        // 在编辑模式中，只处理 Escape 键
                        if event.keyCode == 53 { // Escape
                            NSApp.keyWindow?.makeFirstResponder(nil)
                            return nil
                        }
                        return event
                    }
                }
            }

            // 提取字符和修饰键，分发到快捷键处理器
            guard let chars = event.characters, let character = chars.first else { return event }
            let flags = event.modifierFlags
            if viewModel.actionDefinitions.handleKeyDown(
                character: character,
                command: flags.contains(.command),
                control: flags.contains(.control),
                option: flags.contains(.option)
            ) {
                return nil // 已处理，消费事件
            }
            return event // 未处理，传递给系统
        }
    }

    /// 移除按键监控
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func startRemoteControlServer() {
        let server = RemoteControlServer()
        server.viewModel = viewModel
        do {
            try server.start()
            remoteControlServer = server
            print("RemoteControlServer started on port 9214")
        } catch {
            print("RemoteControlServer failed to start: \(error)")
        }
    }

    /// 更新窗口标题
    private func updateWindowTitle() {
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            window.title = viewModel.windowTitle
        }
    }
}

// MARK: - Menu Bar Commands

struct MacMenuCommands: Commands {
    @FocusedObject private var viewModel: ViewModel?

    var body: some Commands {
        // 文件 menu
        CommandGroup(after: .saveItem) {
            Divider()
            menuButton(.save)
            Divider()
            menuButton(.backup)
            menuButton(.restore)
            Divider()
            menuButton(.checkDataVersion)
            menuButton(.importPGN)
            menuButton(.exportPGNCurrentDatabaseView)
            menuButton(.exportPGNCurrentGame)
            menuButton(.inputGame)
            menuButton(.browseGames)
        }

        // 编辑 menu
        CommandGroup(after: .undoRedo) {
            Divider()
            menuButton(.deleteMove)
            menuButton(.removeMoveFromGame)
            menuButton(.deleteScore)
            Divider()
            menuButton(.fix)
            Divider()
            menuButton(.copyFEN)
            menuButton(.copyBoardText)
            menuButton(.copyBoardImage)
        }

        // 显示 menu
        CommandGroup(after: .toolbar) {
            Divider()
            menuToggle(.toggleGameBrowserSidebar)
            Divider()
            menuToggle(.flip)
            menuToggle(.flipHorizontal)
            Divider()
            menuToggle(.toggleShowPath)
            menuToggle(.toggleShowAllNextMoves)
            menuToggle(.toggleShowLastMove)
            Divider()
            menuToggle(.toggleIsCommentEditing)
            menuToggle(.toggleAllowAddingNewMoves)
            menuToggle(.toggleAutoExtendGameWhenPlayingBoardFen)
            Divider()
            menuToggle(.togglePracticeMode)
            menuToggle(.toggleLock)
            menuToggle(.toggleCanNavigateBeforeLockedStep)
        }

        // 筛选 menu
        CommandMenu("筛选") {
            menuToggle(.setFilterNone)
            Divider()
            menuToggle(.toggleFilterRedOpeningOnly)
            menuToggle(.toggleFilterBlackOpeningOnly)
            menuToggle(.toggleFilterRedRealGameOnly)
            menuToggle(.toggleFilterBlackRealGameOnly)
            Divider()
            menuToggle(.setFilterFocusedPractice)
            menuToggle(.toggleFilterSpecificGame)
            menuToggle(.toggleFilterSpecificBook)
            Divider()
            menuButton(.stepLimitation)
            Divider()
            menuToggle(.toggleBookmark)
            menuToggle(.inRedOpening)
            menuToggle(.inBlackOpening)
        }

        // 导航 menu
        CommandMenu("导航") {
            menuButton(.toStart)
            menuButton(.stepBack)
            menuButton(.stepForward)
            menuButton(.toEnd)
            Divider()
            menuButton(.nextVariant)
            menuButton(.previousPath)
            menuButton(.nextPath)
            Divider()
            menuButton(.random)
        }

        // 分析 menu
        CommandMenu("分析") {
            menuButton(.queryScore)
            menuButton(.openYunku)
            menuButton(.pikafishQuickMove)
            menuButton(.quickEngineScore)
            menuButton(.queryEngineScore)
            menuButton(.quickAllEngineScores)
            menuButton(.queryAllEngineScores)
            Divider()
            menuButton(.referenceBoard)
            menuButton(.searchCurrentMove)
            Divider()
            menuButton(.markPath)
            Divider()
            menuButton(.autoAddToOpening)
            menuButton(.jumpToNextOpeningGap)
        }

        // 帮助/诊断 menu 项
        CommandGroup(after: .help) {
            menuButton(.showShortcutUsageStats)
        }

        // 练习 menu
        CommandMenu("练习") {
            menuButton(.playRandomNextMove)
            menuButton(.hintNextMove)
            Divider()
            menuButton(.practiceNewGame)
            menuButton(.reviewThisGame)
            menuButton(.focusedPractice)
            Divider()
            menuButton(.practiceRedOpening)
            menuButton(.practiceBlackOpening)
            Divider()
            menuButton(.addToReview)
            menuButton(.showReviewList)
            Divider()
            menuButton(.showPracticeMistakeStats)
        }
    }

    private func menuLabel(_ text: String, shortcut: String?) -> String {
        guard let shortcut = shortcut else { return text }
        return "\(text)  [\(shortcut)]"
    }

    @ViewBuilder
    private func menuButton(_ key: ActionDefinitions.ActionKey) -> some View {
        if let vm = viewModel, let info = vm.actionDefinitions.getActionInfo(key) {
            Button(menuLabel(info.text, shortcut: info.shortcutsDisplayText)) {
                ShortcutUsageStats.shared.recordFromButton(key)
                info.action()
            }
                .disabled(!vm.isActionVisible(key))
        }
    }

    @ViewBuilder
    private func menuToggle(_ key: ActionDefinitions.ActionKey) -> some View {
        if let vm = viewModel, let info = vm.actionDefinitions.getToggleActionInfo(key) {
            Toggle(menuLabel(info.text, shortcut: info.shortcutsDisplayText), isOn: Binding(
                get: { info.isOn() },
                set: {
                    ShortcutUsageStats.shared.recordFromButton(key)
                    info.action($0)
                }
            ))
            .disabled(!vm.isActionVisible(key) || !info.isEnabled())
        }
    }
}

#Preview {
    MacContentView()
}
#endif
