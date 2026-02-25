#if os(macOS)
import SwiftUI
import AppKit

/// 按钮区域组件
struct MacActionButtonsView: View {
    @ObservedObject var viewModel: ViewModel

    private var isPractice: Bool {
        viewModel.currentAppMode == .practice
    }

    private var isNormal: Bool {
        viewModel.currentAppMode == .normal
    }

    /// 第一行按钮定义
    private var row1Keys: [ActionDefinitions.ActionKey?] {
        [
            .toStart,
            .stepBack,
            .stepForward,
            .toEnd,
            .nextVariant,
            (isPractice && viewModel.isMyTurn) ? .hintNextMove : .playRandomNextMove,
            .random,
            .practiceNewGame,
            .reviewThisGame,
            .focusedPractice,
            isNormal ? .practiceRedOpening : nil,
            isNormal ? .practiceBlackOpening : nil,
            !isNormal ? .save : nil,
        ]
    }

    /// 第二行按钮定义（仅普通模式可见）
    private var row2Keys: [ActionDefinitions.ActionKey?] {
        [
            .queryScore,
            .queryEngineScore,
            .queryAllEngineScores,
            .openYunku,
            .markPath,
            .referenceBoard,
            .browseGames,
            .importPGN,
            isNormal ? .save : nil,
        ]
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
        max(visibleKeys(for: row1Keys).count, visibleKeys(for: row2Keys).count)
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
            if !visibleKeys(for: row2Keys).isEmpty {
                buttonRow(keys: row2Keys)
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
