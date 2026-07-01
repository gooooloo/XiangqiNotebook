import SwiftUI

/// 模式选择器组件
/// 显示当前模式，支持模式切换；视觉改版为单选（radio）样式。
struct ModeSelectorView: View {
    @ObservedObject var viewModel: ViewModel

    private static let modeActionKeys: [ActionDefinitions.ActionKey] = [
        .setNormalMode,
        .setPracticeMode,
        .setReviewMode,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupHeader("应用模式")
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.modeActionKeys, id: \.self) { key in
                    ModeRadioRow(viewModel: viewModel, actionKey: key)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .sectionCard()
        }
        .padding(8)
    }
}

/// 单选行：蓝心圆 radio + 标签 + 右端快捷键键帽。
struct ModeRadioRow: View {
    @ObservedObject var viewModel: ViewModel

    let toggleActionInfo: ActionDefinitions.ToggleActionInfo
    let actionKey: ActionDefinitions.ActionKey

    init(viewModel: ViewModel, actionKey: ActionDefinitions.ActionKey) {
        self.viewModel = viewModel
        self.actionKey = actionKey
        self.toggleActionInfo = viewModel.actionDefinitions.getToggleActionInfo(actionKey)!
    }

    private var isOn: Bool { toggleActionInfo.isOn() }
    private var isDisabled: Bool {
        !viewModel.isActionVisible(actionKey) || !toggleActionInfo.isEnabled()
    }

    var body: some View {
        Button(action: {
            ShortcutUsageStats.shared.recordFromButton(actionKey)
            toggleActionInfo.action(true)
        }) {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: Theme.fs(13)))
                    .foregroundColor(isOn ? Theme.accent : Theme.placeholder)
                Text(toggleActionInfo.text)
                    .font(.system(size: Theme.fs(12.5)))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
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
    }
}

#Preview {
    #if os(macOS)
    ModeSelectorView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    ModeSelectorView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
}
