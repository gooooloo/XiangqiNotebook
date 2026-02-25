#if os(iOS)
import SwiftUI

/// iPhone版本的复习库列表视图
struct iPhoneReviewListView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                if viewModel.reviewItemList.isEmpty {
                    Text("暂无复习项")
                        .foregroundColor(.secondary)
                        .padding()
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
                                    Button(action: {
                                        viewModel.removeReviewItem(fenId: item.fenId)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(item.fenId == viewModel.currentFenId ? Color.blue.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let gamePath = item.srsData.gamePath {
                                        viewModel.loadReviewItem(gamePath)
                                        isPresented = false
                                    }
                                }
                                Divider()
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("复习库")
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
    iPhoneReviewListView(
        viewModel: ViewModel(
            platformService: IOSPlatformService(presentingViewController: UIViewController())
        ),
        isPresented: .constant(true)
    )
}
#endif
