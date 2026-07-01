#if os(macOS)
import SwiftUI
import AppKit

/// 底部按钮区组件
///
/// 视觉改版：两行等宽对齐网格（行 1 不足处留空位补齐）；每个按钮单行「文字 + 键帽」，
/// 高约 30；所有按钮统一为普通样式（不做单独高亮，避免被误读成激活态）。
/// 整条工具栏用渐变底 + 顶部细分隔线。
struct MacActionButtonsView: View {
    @ObservedObject var viewModel: ViewModel

    /// 按钮行布局，根据模式穷举配置
    /// 新增 AppMode 时编译器会强制要求处理
    private var buttonRows: [[ActionDefinitions.ActionKey?]] {
        switch viewModel.currentAppMode {
        case .normal:
            return [
                [
                    .toStart, .stepBack, .stepForward, .toEnd,
                    .nextVariant, .playRandomNextMove, .random,
                    .practiceNewGame, .reviewThisGame, .focusedPractice,
                    .practiceRedOpening, .practiceBlackOpening,
                    .addToReview,
                ],
                [
                    .queryScore, .openYunku, .pikafishQuickMove, .quickEngineScore, .queryEngineScore, .quickAllEngineScores, .queryAllEngineScores,
                    .markPath, .referenceBoard, .browseGames, .importPGN,
                    .save,
                ],
            ]
        case .practice:
            return [
                [
                    .toStart, .stepBack, .stepForward, .toEnd,
                    viewModel.isMyTurn ? .hintNextMove : .playRandomNextMove,
                    .practiceNewGame, .reviewThisGame, .focusedPractice,
                    .addToReview, .save,
                ],
            ]
        case .review:
            return [
                [
                    .toStart, .stepBack, .stepForward, .toEnd,
                    .practiceNewGame, .reviewThisGame, .focusedPractice,
                    .save,
                ],
            ]
        }
    }

    /// 检查按钮是否可见
    private func isVisible(_ key: ActionDefinitions.ActionKey?) -> Bool {
        guard let key = key else { return false }
        return viewModel.isActionVisible(key) && viewModel.actionDefinitions.getActionInfo(key) != nil
    }

    /// 获取某行可见的按钮
    private func visibleKeys(for keys: [ActionDefinitions.ActionKey?]) -> [ActionDefinitions.ActionKey] {
        keys.compactMap { key in
            guard let key = key, isVisible(key) else { return nil }
            return key
        }
    }

    /// 最大可见按钮数量（决定网格列数，保证两行对齐）
    private var maxVisibleCount: Int {
        buttonRows.map { visibleKeys(for: $0).count }.max() ?? 0
    }

    /// 渲染一行按钮
    @ViewBuilder
    private func buttonRow(keys: [ActionDefinitions.ActionKey?]) -> some View {
        let visible = visibleKeys(for: keys)
        let padding = maxVisibleCount - visible.count

        HStack(spacing: 5) {
            // 只渲染可见的按钮
            ForEach(Array(visible.enumerated()), id: \.offset) { _, key in
                MacToolbarButton(viewModel: viewModel, actionKey: key)
                    .frame(maxWidth: .infinity)
            }
            // 补齐空占位符
            ForEach(0..<padding, id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(buttonRows.enumerated()), id: \.offset) { _, rowKeys in
                let visible = visibleKeys(for: rowKeys)
                if !visible.isEmpty {
                    buttonRow(keys: rowKeys)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xF8F8FA), Color(hex: 0xEEEEF1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

/// 底部工具栏的单个按钮：文字 + 键帽，单行。
private struct MacToolbarButton: View {
    @ObservedObject var viewModel: ViewModel
    let actionKey: ActionDefinitions.ActionKey

    var body: some View {
        let info: ActionDefinitions.ActionInfo? = viewModel.isActionVisible(actionKey)
            ? viewModel.actionDefinitions.getActionInfo(actionKey)
            : nil

        Button(action: {
            ShortcutUsageStats.shared.recordFromButton(actionKey)
            info?.action()
        }) {
            HStack(spacing: 5) {
                Text(info?.text ?? "")
                    .font(.system(size: Theme.fs(12.5), weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let shortcut = info?.shortcutsDisplayText {
                    Keycap(text: shortcut)
                }
            }
            .foregroundColor(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .padding(.horizontal, 6)
        }
        .buttonStyle(MacToolbarButtonStyle())
        .disabled(info == nil)
    }
}

/// 工具栏按钮样式：圆角浅底细边 + 轻投影，所有按钮统一。
private struct MacToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row)
                    .fill(configuration.isPressed ? Color.black.opacity(0.06) : Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row)
                    .stroke(Color.black.opacity(0.14), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 0.75, y: 1)
    }
}

#Preview {
    MacActionButtonsView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
}

#endif
