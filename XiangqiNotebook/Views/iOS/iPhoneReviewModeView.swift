#if os(iOS)
import SwiftUI

/// iPhone 版复习模式面板
/// 以 sheet 形式呈现复习流程
struct iPhoneReviewModeView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool
    @State private var selectedFenId: Int?

    private var displayItems: [(fenId: Int, srsData: SRSData)] {
        if let item = viewModel.verificationItem {
            return [(fenId: item.fenId, srsData: item.srsData)]
        }
        return viewModel.reviewItemList
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isInVerificationMode {
                    verificationView
                } else if viewModel.isReviewingInProgress {
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

                if displayItems.isEmpty {
                    Text("暂无复习项")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    Spacer()
                } else {
                    ScrollView(showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(displayItems, id: \.fenId) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(viewModel.reviewItemDescription(fenId: item.fenId))
                                            .lineLimit(1)
                                        HStack(spacing: 8) {
                                            Text(item.srsData.dueStatusText)
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
                                .background(item.fenId == selectedFenId ? Color.blue.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedFenId = item.fenId
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
            .navigationTitle(viewModel.isInVerificationMode ? "检验模式" : "复习模式")
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
        .onAppear { selectedFenId = viewModel.lockedFenId ?? displayItems.first?.fenId }
        .onChange(of: viewModel.lockedFenId) { _, newValue in
            if let newValue { selectedFenId = newValue }
        }
    }

    // MARK: - 检验中

    private var verificationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = viewModel.verificationItem {
                Text(viewModel.reviewItemDescription(fenId: item.fenId))
                    .lineLimit(2)
                    .padding(.horizontal)
            }
            Button("隐藏答案") {
                viewModel.exitVerificationMode()
                isPresented = false
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 复习进行中

    private var reviewInProgressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 评最后一项后索引可能短暂越界，安全取值
            if let item = viewModel.currentReviewItem {
                Text(viewModel.reviewItemDescription(fenId: item.fenId))
                    .lineLimit(2)
                    .padding(.horizontal)
            }

            Text("进度: \(viewModel.reviewProgress)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            // 自评按钮
            ReviewRatingButtons(viewModel: viewModel, spacing: 8)
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
