import SwiftUI

/// 变着列表组件
struct VariantListView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack() {
                Text("本步变招")
                Spacer()
            }
            if viewModel.currentGameVariantListDisplay.count > 1 {
                ScrollView(showsIndicators: true) {
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
                            Divider()
                        }
                    }
                    // scrollPosition(id:) 必须配套 scrollTargetLayout 才能定位条目
                    .scrollTargetLayout()
                }
                .scrollPosition(id: .constant(viewModel.currentGameVariantListDisplay.firstIndex(where: {
                    $0.move.targetFenId == viewModel.currentFenId
                })))
                .opacity(viewModel.currentAppMode == .practice || (viewModel.currentAppMode == .review && !viewModel.showAllNextMoves) ? 0 : 1)
            }
            Spacer()
        }
        .padding()
        .border(Color.gray)
    }
}

/// 下一步招法列表组件
struct NextMovesListView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack() {
                Text("下步变招")
                Spacer()
            }
            if viewModel.currentNextMovesListDisplay.count > 1 {
                ScrollView(showsIndicators: true) {
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
                            Divider()
                        }
                    }
                }
                .opacity(viewModel.currentAppMode == .practice || (viewModel.currentAppMode == .review && !viewModel.showAllNextMoves) ? 0 : 1)
            }
            Spacer()
        }
        .padding()
        .border(Color.gray)
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
        HStack {
            Text(displayText)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Group {
                        if isSelected {
                            Color.blue.opacity(0.2)
                        } else if isLocked {
                            Color.gray.opacity(0.2)
                        } else {
                            Color.clear
                        }
                    }
                )
                .foregroundColor(foregroundColor)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        }
    }
    
    private var displayText: String {
        if !score.isEmpty {
            return "\(text)（\(score)）"
        }
        return text
    }
    
    private var foregroundColor: Color {
        if isBadMove {
            return .red
        } else if isRecommendedMove {
            return .green
        }
        return .primary
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
