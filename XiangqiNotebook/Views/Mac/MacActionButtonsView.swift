#if os(macOS)
import SwiftUI
import AppKit

/// 按钮区域组件
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
                ],
                [
                    .queryScore, .queryEngineScore, .queryAllEngineScores,
                    .openYunku, .markPath, .referenceBoard, .browseGames, .importPGN,
                    .addToReview, .save,
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

    /// 最大可见按钮数量
    private var maxVisibleCount: Int {
        buttonRows.map { visibleKeys(for: $0).count }.max() ?? 0
    }

    /// 渲染一行按钮
    @ViewBuilder
    private func buttonRow(keys: [ActionDefinitions.ActionKey?]) -> some View {
        let visible = visibleKeys(for: keys)
        let padding = maxVisibleCount - visible.count

        HStack {
            // 只渲染可见的按钮
            ForEach(Array(visible.enumerated()), id: \.offset) { _, key in
                LargeButton(viewModel: viewModel, actionKey: key)
                    .frame(maxWidth: .infinity)
            }
            // 补齐空占位符
            ForEach(0..<padding, id: \.self) { _ in
                LargeButton(viewModel: viewModel, actionKey: nil)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(Array(buttonRows.enumerated()), id: \.offset) { _, rowKeys in
                let visible = visibleKeys(for: rowKeys)
                if !visible.isEmpty {
                    buttonRow(keys: rowKeys)
                }
            }
        }
        .padding(8)
        .border(Color.gray)
    }
}

#Preview {
    MacActionButtonsView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
} 

#endif
