import SwiftUI

/// 复习模式面板（macOS/iPad 共用）
/// 在复习模式下替换右侧栏的棋局筛选区域
struct ReviewModeView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isReviewingInProgress {
                reviewInProgressView
            } else if viewModel.isReviewComplete {
                reviewCompleteView
            } else {
                noDueItemsView
            }
        }
        .padding(8)
        .border(Color.gray)
    }

    // MARK: - 复习进行中

    private var reviewInProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("复习中")
                    .font(.headline)
                Spacer()
                Button("退出") {
                    viewModel.exitReviewMode()
                }
                .buttonStyle(.borderless)
            }

            // 当前复习项描述
            let item = viewModel.reviewQueue[viewModel.currentReviewIndex]
            Text(viewModel.reviewItemDescription(fenId: item.fenId))
                .lineLimit(2)
                .foregroundColor(.secondary)

            // 进度
            Text("进度: \(viewModel.reviewProgress)")
                .font(.caption)
                .foregroundColor(.secondary)

            // 自评按钮
            HStack(spacing: 6) {
                reviewButton("忘了", quality: .again, color: .red)
                reviewButton("困难", quality: .hard, color: .orange)
                reviewButton("良好", quality: .good, color: .blue)
                reviewButton("简单", quality: .easy, color: .green)
            }

            // 跳过按钮
            Button("跳过") {
                viewModel.skipCurrentReviewItem()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - 复习完成

    private var reviewCompleteView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("复习完成")
                    .font(.headline)
                Spacer()
            }
            Text("已完成 \(viewModel.reviewQueue.count) 项复习")
                .foregroundColor(.secondary)
            Button("退出复习模式") {
                viewModel.exitReviewMode()
            }
        }
    }

    // MARK: - 无到期项

    private var noDueItemsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("复习模式")
                    .font(.headline)
                Spacer()
            }
            Text("暂无到期复习项")
                .foregroundColor(.secondary)
            Button("退出复习模式") {
                viewModel.exitReviewMode()
            }
        }
    }

    // MARK: - Helper

    private func reviewButton(_ title: String, quality: ReviewQuality, color: Color) -> some View {
        Button(title) {
            viewModel.submitReviewRating(quality)
        }
        .foregroundColor(color)
        .buttonStyle(.bordered)
    }
}

#Preview {
    #if os(macOS)
    ReviewModeView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    ReviewModeView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
}
