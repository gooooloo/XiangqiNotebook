import SwiftUI

/// 着法列表组件
struct MoveListView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.currentGameMoveListDisplay.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 8) {
                            // 第一列：序号（右对齐，紧凑固定宽度）
                            Text(item.number)
                                .frame(width: 32, alignment: .trailing)
                                .monospacedDigit()

                            // 第二列：招法（左对齐，固定宽度容纳4个字符）
                            Text(item.notation)
                                .frame(width: 52, alignment: .leading)

                            // 第三列：红方开局库标识（居中对齐，固定宽度）
                            Text(item.redOpeningMarker)
                                .frame(width: 8, alignment: .center)
                                .foregroundColor(.secondary)

                            // 第四列：黑方开局库标识（居中对齐，固定宽度）
                            Text(item.blackOpeningMarker)
                                .frame(width: 8, alignment: .center)
                                .foregroundColor(.secondary)

                            // 第五列：复习库标识（居中对齐，固定宽度）
                            Text(item.reviewMarker)
                                .frame(width: 8, alignment: .center)
                                .foregroundColor(.secondary)

                            // 第六列：变着标记（左对齐，获得剩余空间）
                            Text(item.markers)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .background(
                            Group {
                                if viewModel.currentGameStepDisplay == index {
                                    Color.blue.opacity(0.2)
                                } else if viewModel.isMoveLocked(index) {
                                    Color.gray.opacity(0.2)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .foregroundColor(item.move.map { move in
                            if viewModel.isBadMove(move) {
                                return .red
                            } else if viewModel.isRecommendedMove(move) {
                                return .green
                            }
                            return .primary
                        } ?? .primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.toStepIndex(index)
                        }
                        Divider()  // 添加分隔线
                    }
                }
            }
        }
        .scrollPosition(id: .constant(viewModel.currentGameStepDisplay))
        .padding() // 添加内边距，让内容不贴边
        .border(Color.gray)
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