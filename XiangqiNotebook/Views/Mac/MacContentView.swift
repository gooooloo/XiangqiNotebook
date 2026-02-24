#if os(macOS)
import SwiftUI
import Foundation
import AppKit

struct MacContentView: View {
    @StateObject private var viewModel: ViewModel
    @FocusState private var isViewFocused: Bool
    
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

                        // 变着列表
                        VariantListView(viewModel: viewModel)
                            .frame(height: geometry.size.height * 0.2)
                    }
                    .frame(width: geometry.size.width * 0.2)

                    // 右侧区域：着法列表 - 添加 ScrollView 使内容可滚动
                    ScrollView {
                        VStack(spacing: 0) {
                            // 模式选择器
                            ModeSelectorView(viewModel: viewModel)

                            // 棋局筛选
                            TogglesView(viewModel: viewModel)

                            // 书签区域
                            BookmarkListView(viewModel: viewModel)
                        }
                    }
                    .frame(width: geometry.size.width * 0.2)
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
        .onKeyPress { press in
            // 如果有任何 sheet 显示，禁用所有快捷键
            if viewModel.isAnySheetPresented {
                return .ignored
            }

            // 检查焦点是否在文本输入控件上
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                // 如果焦点在 TextField 上，禁用所有快捷键
                if firstResponder is NSTextField {
                    return .ignored
                }

                // 如果焦点在 TextEditor (NSTextView) 上
                if firstResponder is NSTextView {
                    if !viewModel.isCommentEditing {
                        // 评论编辑已关闭但焦点仍在 TextEditor，强制清除焦点
                        clearTextEditorFocus()
                        // 清除焦点后继续处理快捷键
                    } else {
                        // 在编辑模式中，只处理 Escape 键
                        if press.key == .escape {
                            clearTextEditorFocus()
                            return .handled
                        }
                        return .ignored
                    }
                }
            }

            let handled = viewModel.actionDefinitions.handleSwiftUIKeyPress(press)
            return handled ? .handled : .ignored
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
        }
        .onReceive(viewModel.objectWillChange) { _ in
            // 监听 ViewModel 的任何变化，及时更新窗口标题
            // 这样可以捕获 filter 切换、棋局加载等所有导致 windowTitle 变化的情况
            updateWindowTitle()
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
        CommandMenu("操作") {
            menuButton(.toStart)
            menuButton(.stepBack)
            menuButton(.stepForward)
            menuButton(.toEnd)
            Divider()
            menuButton(.nextVariant)
            menuButton(.previousPath)
            menuButton(.nextPath)
            Divider()
            menuButton(.deleteMove)
            menuButton(.removeMoveFromGame)
            menuButton(.deleteScore)
            Divider()
            menuButton(.queryScore)
            menuButton(.queryEngineScore)
            menuButton(.queryAllEngineScores)
            Divider()
            menuButton(.markPath)
            menuButton(.referenceBoard)
            menuButton(.openYunku)
            menuButton(.searchCurrentMove)
            Divider()
            menuButton(.playRandomNextMove)
            menuButton(.hintNextMove)
            menuButton(.practiceNewGame)
            menuButton(.reviewThisGame)
            menuButton(.focusedPractice)
            menuButton(.stepLimitation)
            Divider()
            menuButton(.autoAddToOpening)
            menuButton(.jumpToNextOpeningGap)
            Divider()
            menuButton(.save)
            menuButton(.backup)
            menuButton(.restore)
            menuButton(.checkDataVersion)
            menuButton(.importPGN)
            menuButton(.inputGame)
            menuButton(.browseGames)
            Divider()
            menuButton(.fix)
            menuButton(.random)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            menuToggle(.flip)
            menuToggle(.flipHorizontal)
            Divider()
            menuToggle(.toggleShowPath)
            menuToggle(.toggleShowAllNextMoves)
            Divider()
            menuToggle(.togglePracticeMode)
            menuToggle(.toggleLock)
            menuToggle(.toggleCanNavigateBeforeLockedStep)
            Divider()
            menuToggle(.toggleIsCommentEditing)
            menuToggle(.toggleAllowAddingNewMoves)
            menuToggle(.toggleAutoExtendGameWhenPlayingBoardFen)
            Divider()
            menuToggle(.toggleBookmark)
            menuToggle(.inRedOpening)
            menuToggle(.inBlackOpening)
            Divider()
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
