import SwiftUI

/// 状态栏组件
struct StatusBarView: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // 根据平台确定字体样式
    private var fontStyle: Font {
        #if os(iOS)
        // 在 iOS 上使用 caption 字体，它会根据用户的设置自动调整大小
        return .caption
        #else
        // 在 macOS 上使用 body 字体
        return .body
        #endif
    }
    
    // 根据动态类型大小调整内边距
    private var verticalPadding: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return 6
        case .large, .xLarge:
            return 8
        default:
            return 10
        }
    }
    
    private func gameStatRow(_ label: String, total: Int, wins: Int, draws: Int, losses: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
            Text("总")
            Text("\(total)").frame(minWidth: 16, alignment: .leading)
            Text("胜")
            Text("\(wins)").frame(minWidth: 16, alignment: .leading)
            Text("和")
            Text("\(draws)").frame(minWidth: 16, alignment: .leading)
            Text("负")
            Text("\(losses)").frame(minWidth: 16, alignment: .leading)
        }
        .font(fontStyle)
    }

    var body: some View {
        VStack {
            HStack {
                Text("分数: \(viewModel.displayScore)")
                    .font(fontStyle)
                    .foregroundColor(viewModel.isCurrentMoveBad ? .red : (viewModel.isCurrentMoveRecommended ? .green : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("皮卡鱼: \(viewModel.displayEngineScore)")
                    .font(fontStyle)
                    .foregroundColor(viewModel.isCurrentMoveBad ? .red : (viewModel.isCurrentMoveRecommended ? .green : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("步数: \(viewModel.currentGameStepDisplay) / \(viewModel.maxGameStepDisplay) / \(viewModel.gameStepLimitation?.description ?? "")")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("本变: \(viewModel.currentVariationIndex + 1) / \(viewModel.totalVariationsCount)")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.currentAppMode == .practice {
                    Text("局数: \(viewModel.totalPathsCountFromCurrentFen.map { String($0) } ?? "?")")
                        .font(fontStyle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("路径: \(viewModel.currentPathIndexDisplay.map { String($0 + 1) } ?? "?") / \(viewModel.totalPathsCount.map { String($0) } ?? "?")")
                        .font(fontStyle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("数据: \(String(viewModel.currentDataVersion))\(viewModel.currentDatabaseDirty ? "*" : " ")")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)
            .border(Color.gray)
            // 确保文本在空间不足时能够适当缩小
            .lineLimit(1)
            // .minimumScaleFactor(0.75)

            HStack(spacing: 0) {
                gameStatRow("执红实战:", total: viewModel.currentFenInRealRedGameTotalCount, wins: viewModel.currentFenInRealRedGameWinCount, draws: viewModel.currentFenInRealRedGameDrawCount, losses: viewModel.currentFenInRealRedGameLossCount)
                    .frame(maxWidth: .infinity, alignment: .leading)
                gameStatRow("执黑实战:", total: viewModel.currentFenInRealBlackGameTotalCount, wins: viewModel.currentFenInRealBlackGameWinCount, draws: viewModel.currentFenInRealBlackGameDrawCount, losses: viewModel.currentFenInRealBlackGameLossCount)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("练习次数: \(viewModel.currentFenPracticeCount)")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)
            .border(Color.gray)
            // 确保文本在空间不足时能够适当缩小
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }
}

#Preview {
    #if os(macOS)
    StatusBarView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    StatusBarView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 
