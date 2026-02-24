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
    
    private func gameStatRow(_ label: String, total: Int, wins: Int, draws: Int, losses: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
            Text("总")
            Text("\(total)").frame(minWidth: 14, alignment: .leading)
            Text("胜")
            Text("\(wins)").frame(minWidth: 14, alignment: .leading)
            Text("和")
            Text("\(draws)").frame(minWidth: 14, alignment: .leading)
            Text("负")
            Text("\(losses)").frame(minWidth: 14, alignment: .leading)
        }
        .font(fontStyle)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("分数: \(viewModel.displayScore)")
                    .font(fontStyle)
                    .foregroundColor(viewModel.isCurrentMoveBad ? .red : (viewModel.isCurrentMoveRecommended ? .green : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("皮卡鱼: \(viewModel.displayEngineScore)")
                    .font(fontStyle)
                    .foregroundColor(viewModel.isCurrentMoveBad ? .red : (viewModel.isCurrentMoveRecommended ? .green : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("步数: \(viewModel.currentGameStepDisplay) / \(viewModel.maxGameStepDisplay)")
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)

            Divider()
            .background(Color.gray)

            HStack {
                Text("练习次数: \(viewModel.currentFenPracticeCount)")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("锁定: \(viewModel.isAnyMoveLocked ? "是" : "否")")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("红开局库: \(viewModel.currentFenIsInRedOpening ? "是" : "否")")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("黑开局库: \(viewModel.currentFenIsInBlackOpening ? "是" : "否")")
                    .font(fontStyle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal)

            Divider()
            .background(Color.gray)

            HStack(spacing: 0) {
                gameStatRow("实战执红:", total: viewModel.currentFenInRealRedGameTotalCount, wins: viewModel.currentFenInRealRedGameWinCount, draws: viewModel.currentFenInRealRedGameDrawCount, losses: viewModel.currentFenInRealRedGameLossCount)
                    .frame(maxWidth: .infinity, alignment: .leading)
                gameStatRow("执黑:", total: viewModel.currentFenInRealBlackGameTotalCount, wins: viewModel.currentFenInRealBlackGameWinCount, draws: viewModel.currentFenInRealBlackGameDrawCount, losses: viewModel.currentFenInRealBlackGameLossCount)
                    .frame(maxWidth: .infinity, alignment: .leading)
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