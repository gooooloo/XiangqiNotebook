import SwiftUI

/// 练习模式走错统计视图
///
/// 按 fenId 分组展示当前 DatabaseView 筛选范围内的错误：
/// 顶层按"该局面累计走错总次数"从多到少排序；展开每个局面后可看到具体每个错招的次数和最近时间。
struct PracticeMistakeStatsView: View {
    @ObservedObject var viewModel: ViewModel
    @State private var showingResetConfirmation = false

    /// 触发重新计算的依赖：dataChanged 翻转时整个视图刷新
    private var dataVersion: Bool { viewModel.session.dataChanged }

    private struct Row: Identifiable {
        let id: Int             // fenId
        let fenId: Int
        let totalCount: Int
        let lastWrongAt: Date
        let mistakes: [PracticeMistakeRecord]   // 该局面下各错招记录，按 count 降序
        let fen: String          // 该局面的源 FEN（用于显示）
    }

    private var rows: [Row] {
        let view = viewModel.session.databaseView
        let mistakes = view.practiceMistakes
        return mistakes.compactMap { (fenId, records) -> Row? in
            guard !records.isEmpty else { return nil }
            let total = records.reduce(0) { $0 + $1.count }
            let last = records.map { $0.lastWrongAt }.max() ?? Date.distantPast
            let sorted = records.sorted { $0.count > $1.count }
            let fen = view.getFenObject(fenId)?.fen ?? "(unknown fen)"
            return Row(id: fenId, fenId: fenId, totalCount: total,
                       lastWrongAt: last, mistakes: sorted, fen: fen)
        }
        .sorted { lhs, rhs in
            if lhs.totalCount != rhs.totalCount { return lhs.totalCount > rhs.totalCount }
            return lhs.lastWrongAt > rhs.lastWrongAt
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        let _ = dataVersion
        #if os(macOS)
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 540, minHeight: 400)
        .alert("重置练习错误统计？", isPresented: $showingResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { viewModel.session.databaseView.resetPracticeMistakes(); viewModel.session.dataChanged.toggle() }
        } message: {
            Text("此操作将清空所有练习错误记录，且无法撤销。")
        }
        #else
        NavigationView {
            content
                .navigationTitle("练习错误统计")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("重置") { showingResetConfirmation = true }
                            .disabled(rows.isEmpty)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") { viewModel.showingPracticeMistakeStatsView = false }
                    }
                }
        }
        .alert("重置练习错误统计？", isPresented: $showingResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { viewModel.session.databaseView.resetPracticeMistakes(); viewModel.session.dataChanged.toggle() }
        } message: {
            Text("此操作将清空所有练习错误记录，且无法撤销。")
        }
        #endif
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("练习错误统计").font(.headline)
            Spacer()
            Text("当前筛选范围内 \(rows.count) 个局面").foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack {
                Spacer()
                Text("当前筛选范围内尚无错误记录").foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                ForEach(rows) { row in
                    DisclosureGroup {
                        ForEach(row.mistakes, id: \.wrongFen) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("错招").foregroundColor(.secondary)
                                    Text(record.wrongFen)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text("× \(record.count)")
                                        .font(.system(.body, design: .monospaced))
                                }
                                Text("最近：\(Self.dateFormatter.string(from: record.lastWrongAt))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("局面 #\(row.fenId)")
                                Text(row.fen)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text("\(row.totalCount)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("重置") { showingResetConfirmation = true }
                .disabled(rows.isEmpty)
            Spacer()
            Button("关闭") { viewModel.showingPracticeMistakeStatsView = false }
        }
        .padding()
    }
}
