#if os(macOS)
import SwiftUI
import Foundation
import AppKit

struct MacContentView: View {
    @StateObject private var viewModel: ViewModel
    @FocusState private var isViewFocused: Bool
    @State private var keyMonitor: Any?
    
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
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // 左侧区域：棋盘
                    VStack(spacing: 0) {
                        // 棋盘 - 设置为屏幕高度的一半
                        XiangqiBoard(viewModel: $viewModel.boardViewModel, onMove: { newFen in
                            viewModel.handleBoardMove(newFen)
                        })
                        .frame(height: geometry.size.height * 0.5)  // 设置为屏幕高度的50%

                        // 状态栏 - 保持固定高度
                        StatusBarView(viewModel: viewModel)

                        // 评论区 - 分配剩余空间
                        CommentView(viewModel: viewModel)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                    // 中间区域：开局库和书签
                    VStack(spacing: 0) {
                        MoveListView(viewModel: viewModel)
                            .frame(width: geometry.size.width * 0.2)

                        // 变着列表 + 下一步招法列表（左右并排）
                        HStack(spacing: 0) {
                            VariantListView(viewModel: viewModel)
                            NextMovesListView(viewModel: viewModel)
                        }
                        .frame(height: geometry.size.height * 0.25)
                    }
                    .frame(width: geometry.size.width * 0.2)

                    // 右侧区域
                    if viewModel.isInReviewMode {
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
                        .frame(width: geometry.size.width * 0.2)
                    } else {
                        // 常规/练习模式：ScrollView 包裹
                        ScrollView {
                            VStack(spacing: 0) {
                                ModeSelectorView(viewModel: viewModel)
                                TogglesView(viewModel: viewModel)
                                BookmarkListView(viewModel: viewModel)
                                if viewModel.currentAppMode == .normal {
                                    RealGameListView(viewModel: viewModel)
                                }
                            }
                        }
                        .frame(width: geometry.size.width * 0.2)
                    }
                }

                // 按钮区 - 占据所有宽度
                MacActionButtonsView(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
            }
            .focused($isViewFocused)
        }
        .overlay {
            if let progress = viewModel.batchEvalProgress {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                BatchEvalProgressView(progress: progress, onCancel: {
                    viewModel.cancelBatchEval()
                }, onDismiss: {
                    viewModel.dismissBatchEvalProgress()
                })
            }
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
        }
        .onDisappear {
            removeKeyMonitor()
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
                // 如果焦点在 TextField 上，不处理快捷键
                if firstResponder is NSTextField { return event }

                // 如果焦点在 TextEditor (NSTextView) 上
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
        }

        // 显示 menu
        CommandGroup(after: .toolbar) {
            Divider()
            menuToggle(.flip)
            menuToggle(.flipHorizontal)
            Divider()
            menuToggle(.toggleShowPath)
            menuToggle(.toggleShowAllNextMoves)
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
            menuButton(.queryEngineScore)
            menuButton(.queryAllEngineScores)
            Divider()
            menuButton(.referenceBoard)
            menuButton(.openYunku)
            menuButton(.searchCurrentMove)
            Divider()
            menuButton(.markPath)
            Divider()
            menuButton(.autoAddToOpening)
            menuButton(.jumpToNextOpeningGap)
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
        }
    }

    private func menuLabel(_ text: String, shortcut: String?) -> String {
        guard let shortcut = shortcut else { return text }
        return "\(text)  [\(shortcut)]"
    }

    @ViewBuilder
    private func menuButton(_ key: ActionDefinitions.ActionKey) -> some View {
        if let vm = viewModel, let info = vm.actionDefinitions.getActionInfo(key) {
            Button(menuLabel(info.text, shortcut: info.shortcutsDisplayText)) { info.action() }
                .disabled(!vm.isActionVisible(key))
        }
    }

    @ViewBuilder
    private func menuToggle(_ key: ActionDefinitions.ActionKey) -> some View {
        if let vm = viewModel, let info = vm.actionDefinitions.getToggleActionInfo(key) {
            Toggle(menuLabel(info.text, shortcut: info.shortcutsDisplayText), isOn: Binding(
                get: { info.isOn() },
                set: { info.action($0) }
            ))
            .disabled(!vm.isActionVisible(key) || !info.isEnabled())
        }
    }
}

#Preview {
    MacContentView()
}
#endif
