#if os(macOS)
import SwiftUI
import AppKit

/// 按钮区域组件
struct MacActionButtonsView: View {
    @ObservedObject var viewModel: ViewModel

    /// 第一行按钮定义
    private var row1Keys: [ActionDefinitions.ActionKey?] {
        [
            .toStart,
            .stepBack,
            .stepForward,
            .toEnd,
            .nextVariant,
            (viewModel.session.sessionData.currentMode == .practice && viewModel.isMyTurn) ? .hintNextMove : .playRandomNextMove,
            .practiceNewGame,
            .reviewThisGame,
            .focusedPractice,
            .removeMoveFromGame,
        ]
    }

    /// 第二行按钮定义
    private let row2Keys: [ActionDefinitions.ActionKey?] = [
        .queryScore,
        .queryEngineScore,
        .queryAllEngineScores,
        .openYunku,
        .fix,
        .markPath,
        .referenceBoard,
        .previousPath,
        .nextPath,
        .random,
        .stepLimitation,
        .jumpToNextOpeningGap,
    ]

    /// 第三行按钮定义
    private let row3Keys: [ActionDefinitions.ActionKey?] = [
        .checkDataVersion,
        .save,
        .backup,
        .restore,
        .deleteMove,
        .deleteScore,
        .inputGame,
        .browseGames,
        .searchCurrentMove,
        .autoAddToOpening,
    ]

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
        max(visibleKeys(for: row1Keys).count, visibleKeys(for: row2Keys).count, visibleKeys(for: row3Keys).count)
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
            buttonRow(keys: row1Keys)
            buttonRow(keys: row2Keys)
            buttonRow(keys: row3Keys)
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
