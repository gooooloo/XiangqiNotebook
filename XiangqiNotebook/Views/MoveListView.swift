import SwiftUI

/// 着法列表组件
struct MoveListView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.currentGameMoveListDisplay.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 6) {
                            // 第一列：序号（右对齐，紧凑固定宽度；宽度随字号缩放）
                            Text(item.number)
                                .frame(width: Theme.fs(32), alignment: .trailing)
                                .monospacedDigit()
                                .lineLimit(1)
                                .foregroundColor(Theme.textSecondary)

                            // 第二列：招法（左对齐，全角数字等宽，固定宽度容纳4个字符）
                            Text(item.notation.fullwidthDigits)
                                .frame(width: Theme.fs(58), alignment: .leading)
                                .lineLimit(1)

                            // 第三列：红方开局库标识（居中对齐，固定宽度）
                            Text(item.redOpeningMarker)
                                .frame(width: Theme.fs(9), alignment: .center)
                                .foregroundColor(Theme.textSecondary)

                            // 第四列：黑方开局库标识（居中对齐，固定宽度）
                            Text(item.blackOpeningMarker)
                                .frame(width: Theme.fs(9), alignment: .center)
                                .foregroundColor(Theme.textSecondary)

                            // 第五列：复习库标识（居中对齐，固定宽度）
                            Text(item.reviewMarker)
                                .frame(width: Theme.fs(9), alignment: .center)
                                .foregroundColor(Theme.textSecondary)

                            // 第六列：变着标记（左对齐，获得剩余空间）
                            Text(item.markers)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .foregroundColor(Theme.placeholder)
                        }
                        .font(.system(size: Theme.fs(12.5)))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            Group {
                                if viewModel.currentGameStepDisplay == index {
                                    Theme.accent.opacity(0.12)
                                } else if viewModel.isMoveLocked(index) {
                                    Color.black.opacity(0.05)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .foregroundColor(item.move.map { move in
                            if viewModel.isBadMove(move) {
                                return Theme.bad
                            } else if viewModel.isRecommendedMove(move) {
                                return Theme.good
                            }
                            return Theme.textPrimary
                        } ?? Theme.textPrimary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toStepIndex(index)
                        }
                        Divider().overlay(Theme.hairline)  // 添加分隔线
                    }
                }
                // scrollPosition(id:) 必须配套 scrollTargetLayout 才能定位条目
                .scrollTargetLayout()
            }
            // scrollPosition 必须挂在 ScrollView 上（原先挂在外层 VStack 上无效）
            .scrollPosition(id: .constant(viewModel.currentGameStepDisplay))
        }
        .padding(6) // 添加内边距，让内容不贴边
        .sectionCard()
        .padding(6)
    }
}

#Preview {
    #if os(macOS)
    MoveListView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    MoveListView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 