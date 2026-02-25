#if os(iOS)
import SwiftUI

/// iPhone 版复习模式面板
/// 以 sheet 形式呈现复习流程
struct iPhoneReviewModeView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isReviewingInProgress {
                    reviewInProgressView
                } else if viewModel.isReviewComplete {
                    reviewCompleteView
                } else {
                    noDueItemsView
                }

                Divider()

                // 复习库列表
                Text("复习库")
                    .font(.headline)
                    .padding(.horizontal)

                if viewModel.reviewItemList.isEmpty {
                    Text("暂无复习项")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.reviewItemList, id: \.fenId) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(viewModel.reviewItemDescription(fenId: item.fenId))
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            Text(dueStatusText(item.srsData))
                                                .font(.caption)
                                                .foregroundColor(item.srsData.isDue ? .red : .secondary)
                                            Text("已复习 \(item.srsData.repetitions) 次")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal)
                                .background(item.fenId == viewModel.currentFenId ? Color.blue.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let gamePath = item.srsData.gamePath {
                                        viewModel.loadReviewItem(gamePath)
                                    }
                                }
                                Divider()
                            }
                        }
                    }
                }
            }
            .navigationTitle("复习模式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 复习进行中

    private var reviewInProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            let item = viewModel.reviewQueue[viewModel.currentReviewIndex]
            Text(viewModel.reviewItemDescription(fenId: item.fenId))
                .lineLimit(2)
                .padding(.horizontal)

            Text("进度: \(viewModel.reviewProgress)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            // 自评按钮
            HStack(spacing: 8) {
                reviewButton("忘了", quality: .again, color: .red)
                reviewButton("困难", quality: .hard, color: .orange)
                reviewButton("良好", quality: .good, color: .blue)
                reviewButton("简单", quality: .easy, color: .green)
            }
            .padding(.horizontal)

            Button("跳过") {
                viewModel.skipCurrentReviewItem()
            }
            .foregroundColor(.secondary)
            .padding(.horizontal)
        }
    }

    // MARK: - 复习完成

    private var reviewCompleteView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("已完成 \(viewModel.reviewQueue.count) 项复习")
                .padding(.horizontal)
            Button("退出复习模式") {
                viewModel.exitReviewMode()
                isPresented = false
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 无到期项

    private var noDueItemsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("暂无到期复习项")
                .foregroundColor(.secondary)
                .padding(.horizontal)
            Button("退出复习模式") {
                viewModel.exitReviewMode()
                isPresented = false
            }
            .padding(.horizontal)
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

    private func dueStatusText(_ srsData: SRSData) -> String {
        if srsData.isDue {
            return "已到期"
        }
        let now = Date()
        let days = Calendar.current.dateComponents([.day], from: now, to: srsData.nextReviewDate).day ?? 0
        if days == 0 {
            return "今天到期"
        } else if days == 1 {
            return "明天到期"
        } else {
            return "\(days)天后"
        }
    }
}

#Preview {
    iPhoneReviewModeView(
        viewModel: ViewModel(
            platformService: IOSPlatformService(presentingViewController: UIViewController())
        ),
        isPresented: .constant(true)
    )
}
#endif
