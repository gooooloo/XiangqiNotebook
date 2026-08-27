import SwiftUI

/// 棋局筛选组件
struct TogglesView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(spacing: 10) {
            // 棋局筛选
            ToggleGroup(title: "棋局筛选") {
                MyToggle(viewModel: viewModel, actionKey: .setFilterNone)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterRedOpeningOnly)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterBlackOpeningOnly)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterRedRealGameOnly)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterBlackRealGameOnly)
                MyToggle(viewModel: viewModel, actionKey: .setFilterFocusedPractice)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterSpecificGame)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterSpecificBook)
                MyToggle(viewModel: viewModel, actionKey: .toggleStepLimitation)
                MyToggle(viewModel: viewModel, actionKey: .toggleLock)
            }

            // 开局库 / 书签
            ToggleGroup(title: "开局库 / 书签") {
                MyToggle(viewModel: viewModel, actionKey: .inRedOpening)
                MyToggle(viewModel: viewModel, actionKey: .inBlackOpening)
                MyToggle(viewModel: viewModel, actionKey: .toggleBookmark)
            }

            BoardOperationTogglesView(viewModel: viewModel)
        }
        .padding(8)
    }
}

/// 右栏分组容器：大写灰小标题 + 白色圆角卡（行间细分隔线由各行自身留白体现）。
struct ToggleGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupHeader(title)
                .padding(.horizontal, 2)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .sectionCard()
        }
    }
}

/// 棋盘操作区域（独立组件，复习模式下也显示）
struct BoardOperationTogglesView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        ToggleGroup(title: "棋盘操作") {
            MyToggle(viewModel: viewModel, actionKey: .flip)
            MyToggle(viewModel: viewModel, actionKey: .flipHorizontal)
            MyToggle(viewModel: viewModel, actionKey: .toggleAutoExtendGameWhenPlayingBoardFen)
            MyToggle(viewModel: viewModel, actionKey: .toggleCanNavigateBeforeLockedStep)
            MyToggle(viewModel: viewModel, actionKey: .toggleShowPath)
            MyToggle(viewModel: viewModel, actionKey: .toggleShowAllNextMoves)
            MyToggle(viewModel: viewModel, actionKey: .toggleShowLastMove)
            MyToggle(viewModel: viewModel, actionKey: .toggleShowRedAttackPoints)
            MyToggle(viewModel: viewModel, actionKey: .toggleShowBlackAttackPoints)
            MyToggle(viewModel: viewModel, actionKey: .toggleAttackPointsRedPalaceOnly)
            MyToggle(viewModel: viewModel, actionKey: .toggleAttackPointsBlackPalaceOnly)
            MyToggle(viewModel: viewModel, actionKey: .toggleShowRealGameList)
            MyToggle(viewModel: viewModel, actionKey: .togglePracticeMode)
            MyToggle(viewModel: viewModel, actionKey: .toggleIsCommentEditing)
            MyToggle(viewModel: viewModel, actionKey: .toggleAllowAddingNewMoves)
        }
    }
}

struct MyToggle: View {
    // 没有这个，就不会自动更新
    @ObservedObject var viewModel: ViewModel

    let toggleActionInfo: ActionDefinitions.ToggleActionInfo
    let actionKey: ActionDefinitions.ActionKey

    init(viewModel: ViewModel, actionKey: ActionDefinitions.ActionKey) {
        self.viewModel = viewModel
        self.actionKey = actionKey
        self.toggleActionInfo = viewModel.actionDefinitions.getToggleActionInfo(actionKey)!
    }

    /// 标签文本（含特定棋局/棋书名称、步数/锁定步数，但不含快捷键）
    var displayText: String {
        var text = toggleActionInfo.text

        // 为特定棋局/棋书筛选添加名称，为步数限制显示当前值
        if actionKey == .toggleFilterSpecificGame,
           let gameName = viewModel.lastSpecificGameName, !gameName.isEmpty {
            text += ": \(gameName)"
        } else if actionKey == .toggleFilterSpecificBook,
                  let bookName = viewModel.lastSpecificBookName, !bookName.isEmpty {
            text += ": \(bookName)"
        } else if actionKey == .toggleStepLimitation,
                  let limit = viewModel.gameStepLimitation {
            text += ": \(limit)"
        } else if actionKey == .toggleLock,
                  let lockedStep = viewModel.currentLockedStep {
            text += ": \(lockedStep)"
        }

        return text
    }

    private var isDisabled: Bool {
        !viewModel.isActionVisible(actionKey) || !toggleActionInfo.isEnabled()
    }

    private var isOn: Bool { toggleActionInfo.isOn() }

    private func toggle() {
        ShortcutUsageStats.shared.recordFromButton(actionKey)
        toggleActionInfo.action(!isOn)
    }

    var body: some View {
        #if os(macOS)
        // macOS：自绘复选框（蓝底白勾）+ 标签 + 右端键帽。
        // 不用原生 Toggle(.checkbox)，因为它与 Spacer 同处 HStack 时
        // 其 AppKit 标题会被压成 0 宽而“消失”。
        Button(action: toggle) {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: Theme.fs(13)))
                    .foregroundColor(isOn ? Theme.accent : Theme.placeholder)
                Text(displayText)
                    .font(.system(size: Theme.fs(12.5)))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if let shortcut = toggleActionInfo.shortcutsDisplayText {
                    Keycap(text: shortcut)
                        .opacity(isDisabled ? 0.4 : 1)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        #else
        HStack(spacing: 6) {
            Toggle(isOn: Binding(
                get: { toggleActionInfo.isOn() },
                set: { _ in toggle() }
            )) {
                Text(displayText)
                    .font(.system(size: Theme.fs(12.5)))
                    .lineLimit(1)
            }
            .disabled(isDisabled)
            Spacer(minLength: 6)
            if let shortcut = toggleActionInfo.shortcutsDisplayText {
                Keycap(text: shortcut)
                    .opacity(isDisabled ? 0.4 : 1)
            }
        }
        .padding(.vertical, 3)
        #endif
    }
}

#Preview {
    #if os(macOS)
    TogglesView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    TogglesView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 