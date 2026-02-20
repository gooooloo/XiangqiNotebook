#if os(iOS)
import SwiftUI

/// 状态栏组件
struct iPhoneStatusBarView: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let fontStyle: Font = .caption
    
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
        VStack(spacing: 0) {
            HStack {
                Text("分数: \(viewModel.displayScore)")
                    .font(fontStyle)
                    .foregroundColor(viewModel.isCurrentMoveBad ? .red : (viewModel.isCurrentMoveRecommended ? .green : .primary))
                Spacer()
                Text("皮: \(viewModel.displayEngineScore)")
                    .font(fontStyle)
                Spacer()
                Text("步数: \(viewModel.currentGameStepDisplay) / \(viewModel.maxGameStepDisplay)")
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)

            Divider()
            .background(Color.gray)

            HStack {
                Text("练习次数: \(viewModel.currentFenPracticeCount)")
                    .font(fontStyle)
                Spacer()
                Text("锁定: \(viewModel.isAnyMoveLocked ? "是" : "否")")
                    .font(fontStyle)
                Spacer()
                Text("红开局库: \(viewModel.currentFenIsInRedOpening ? "是" : "否")")
                    .font(fontStyle)
                Spacer()
                Text("黑开局库: \(viewModel.currentFenIsInBlackOpening ? "是" : "否")")
                    .font(fontStyle)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)

            Divider()
            .background(Color.gray)

            HStack {
                Text("实战执红: 总 \(viewModel.currentFenInRealRedGameTotalCount) / 胜 \(viewModel.currentFenInRealRedGameWinCount) / 和 \(viewModel.currentFenInRealRedGameDrawCount) / 负 \(viewModel.currentFenInRealRedGameLossCount)")
                    .font(fontStyle)
                Spacer()
                Text("执黑: 总 \(viewModel.currentFenInRealBlackGameTotalCount) / 胜 \(viewModel.currentFenInRealBlackGameWinCount) / 和 \(viewModel.currentFenInRealBlackGameDrawCount) / 负 \(viewModel.currentFenInRealBlackGameLossCount)")
                    .font(fontStyle)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)

            Divider()
            .background(Color.gray)

            iPhoneCommentView(viewModel: viewModel)
        }
        .border(Color.gray)
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
#endif