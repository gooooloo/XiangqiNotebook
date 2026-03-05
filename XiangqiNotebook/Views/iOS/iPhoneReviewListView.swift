#if os(iOS)
import SwiftUI

/// iPhone版本的复习库列表视图
struct iPhoneReviewListView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool
    @State private var selectedFenId: Int?
    @State private var renamingFenId: Int?
    @State private var renameText: String = ""

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
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(item.fenId == selectedFenId ? Color.blue.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedFenId = item.fenId
                                    if let gamePath = item.srsData.gamePath {
                                        viewModel.loadReviewItem(gamePath)
                                        isPresented = false
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        selectedFenId = item.fenId
                                        renameText = viewModel.reviewItemDescription(fenId: item.fenId)
                                        renamingFenId = item.fenId
                                    } label: {
                                        Label("重命名", systemImage: "pencil")
                                    }
                                    Button {
                                        selectedFenId = item.fenId
                                        viewModel.reviewAgain(fenId: item.fenId)
                                    } label: {
                                        Label("再次复习", systemImage: "arrow.counterclockwise")
                                    }
                                    if let gamePath = item.srsData.gamePath {
                                        Button {
                                            selectedFenId = item.fenId
                                            viewModel.enterVerificationMode(fenId: item.fenId, srsData: item.srsData, gamePath: gamePath)
                                            isPresented = false
                                        } label: {
                                            Label("核对答案", systemImage: "checkmark.circle")
                                        }
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        selectedFenId = item.fenId
                                        viewModel.removeReviewItem(fenId: item.fenId)
                                    } label: {
                                        Label("删除", systemImage: "trash")
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
            .alert("重命名复习项", isPresented: Binding(
                get: { renamingFenId != nil },
                set: { if !$0 { renamingFenId = nil } }
            )) {
                TextField("名称", text: $renameText)
                Button("确定") {
                    if let fenId = renamingFenId {
                        viewModel.renameReviewItem(fenId: fenId, name: renameText)
                    }
                    renamingFenId = nil
                }
                Button("取消", role: .cancel) {
                    renamingFenId = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { selectedFenId = viewModel.lockedFenId ?? viewModel.reviewItemList.first?.fenId }
        .onChange(of: viewModel.lockedFenId) { _, newValue in
            if let newValue { selectedFenId = newValue }
        }
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
