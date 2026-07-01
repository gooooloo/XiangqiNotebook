import SwiftUI

/// 变着列表组件
struct VariantListView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GroupHeader("本步变招")
            ScrollView(showsIndicators: true) {
                if viewModel.currentGameVariantListDisplay.count > 1 {
                    VStack(alignment: .leading, spacing: 0) {
                        // 用 enumerated 的 offset 作为身份，与下方 scrollPosition
                        // 的 Int 索引保持同一身份类型，否则定位无法匹配
                        ForEach(Array(viewModel.currentGameVariantListDisplay.enumerated()), id: \.offset) { _, item in
                            MoveItemView(
                                text: viewModel.getMoveString(move: item.move),
                                score: viewModel.getDisplayScoreForMove(item.move),
                                isSelected: item.move.targetFenId == viewModel.currentFenId,
                                isBadMove: viewModel.isBadMove(item.move),
                                isRecommendedMove: viewModel.isRecommendedMove(item.move),
                                isLocked: viewModel.isMoveLocked(viewModel.currentGameStepDisplay),
                                onTap: {
                                    viewModel.playVariantMove(item.move)
                                }
                            )
                            Divider().overlay(Theme.hairline)
                        }
                    }
                    // scrollPosition(id:) 必须配套 scrollTargetLayout 才能定位条目
                    .scrollTargetLayout()
                }
            }
            .scrollPosition(id: .constant(viewModel.currentGameVariantListDisplay.firstIndex(where: {
                $0.move.targetFenId == viewModel.currentFenId
            })))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .insetBox()
            .opacity(viewModel.currentAppMode == .practice || (viewModel.currentAppMode == .review && !viewModel.showAllNextMoves) ? 0 : 1)
        }
        // 两列（本步/下步变招）永远等宽等高，空的一侧也保留同样大小的框
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(6)
    }
}

/// 下一步招法列表组件
struct NextMovesListView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GroupHeader("下步变招")
            ScrollView(showsIndicators: true) {
                if viewModel.currentNextMovesListDisplay.count > 1 {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.currentNextMovesListDisplay, id: \.move) { item in
                            MoveItemView(
                                text: viewModel.getMoveString(move: item.move),
                                score: viewModel.getDisplayScoreForMove(item.move),
                                isSelected: false,
                                isBadMove: viewModel.isBadMove(item.move),
                                isRecommendedMove: viewModel.isRecommendedMove(item.move),
                                isLocked: false,
                                onTap: {
                                    viewModel.playNextMove(item.move)
                                }
                            )
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .insetBox()
            .opacity(viewModel.currentAppMode == .practice || (viewModel.currentAppMode == .review && !viewModel.showAllNextMoves) ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(6)
    }
}

/// 单个变着项视图
struct MoveItemView: View {
    let text: String
    let score: String
    let isSelected: Bool
    let isBadMove: Bool
    let isRecommendedMove: Bool
    let isLocked: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            // 招法（变招列较窄，用半角数字更紧凑，优先保证招法完整不被截断）
            Text(text)
                .lineLimit(1)
                .layoutPriority(1)
                .foregroundColor(foregroundColor)
            Spacer(minLength: 4)
            // 分数右对齐，按好坏着色
            if !score.isEmpty {
                Text(score)
                    .monospacedDigit()
                    .foregroundColor(scoreColor)
            }
        }
        .font(.system(size: Theme.fs(12.5)))
        .padding(.vertical, 3)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isSelected {
                    Theme.accent.opacity(0.12)
                } else if isLocked {
                    Color.black.opacity(0.05)
                } else {
                    Color.clear
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var foregroundColor: Color {
        if isBadMove {
            return Theme.bad
        } else if isRecommendedMove {
            return Theme.good
        }
        return Theme.textPrimary
    }

    private var scoreColor: Color {
        if isBadMove {
            return Theme.bad
        } else if isRecommendedMove {
            return Theme.good
        }
        return Theme.textSecondary
    }
}

#Preview {
    #if os(macOS)
    VariantListView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    VariantListView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 
