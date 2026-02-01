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
    
    var body: some View {
        VStack {
            HStack {
                Text("分数: \(viewModel.displayScore)")
                    .font(fontStyle)
                    .foregroundColor(viewModel.isCurrentMoveBad ? .red : (viewModel.isCurrentMoveRecommended ? .green : .primary))
                Spacer()
                Text("步数: \(viewModel.currentGameStepDisplay) / \(viewModel.maxGameStepDisplay) / \(viewModel.gameStepLimitation?.description ?? "")")
                    .font(fontStyle)
                Spacer()
                Text("本变: \(viewModel.currentVariationIndex + 1) / \(viewModel.totalVariationsCount)")
                    .font(fontStyle)
                Spacer()
                if viewModel.session.sessionData.currentMode == .practice {
                    Text("局数: \(viewModel.totalPathsCountFromCurrentFen.map { String($0) } ?? "?")")
                        .font(fontStyle)
                } else {
                    Text("路径: \(viewModel.currentPathIndexDisplay.map { String($0 + 1) } ?? "?") / \(viewModel.totalPathsCount.map { String($0) } ?? "?")")
                        .font(fontStyle)
                }
                Spacer()
                Text("数据版本: \(viewModel.currentDataVersion)\(viewModel.currentDatabaseDirty ? "*" : " ")")
                    .font(fontStyle)
            }
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)
            .border(Color.gray)
            // 确保文本在空间不足时能够适当缩小
            .lineLimit(1)
            // .minimumScaleFactor(0.75)

            HStack {
                Text("执红实战: 总 \(viewModel.currentFenInRealRedGameTotalCount) / 胜 \(viewModel.currentFenInRealRedGameWinCount) / 和 \(viewModel.currentFenInRealRedGameDrawCount) / 负 \(viewModel.currentFenInRealRedGameLossCount)")
                    .font(fontStyle)
                Spacer()
                Text("执黑实战: 总 \(viewModel.currentFenInRealBlackGameTotalCount) / 胜 \(viewModel.currentFenInRealBlackGameWinCount) / 和 \(viewModel.currentFenInRealBlackGameDrawCount) / 负 \(viewModel.currentFenInRealBlackGameLossCount)")
                    .font(fontStyle)
                Spacer()
                Text("练习次数: \(viewModel.currentFenPracticeCount)")
                    .font(fontStyle)
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
