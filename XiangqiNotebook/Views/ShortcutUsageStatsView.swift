import SwiftUI

/// 快捷键使用统计视图：按触发次数从多到少展示已记录的动作
struct ShortcutUsageStatsView: View {
    @ObservedObject var viewModel: ViewModel
    @ObservedObject private var stats = ShortcutUsageStats.shared
    @State private var showingResetConfirmation = false

    /// (动作名, 快捷键文本, 次数)
    private var rows: [(name: String, shortcut: String, count: Int)] {
        let ad = viewModel.actionDefinitions
        return stats.counts
            .map { (rawKey, count) -> (name: String, shortcut: String, count: Int) in
                if let actionKey = ActionDefinitions.ActionKey(rawValue: rawKey) {
                    if let info = ad.getActionInfo(actionKey) {
                        return (name: info.text, shortcut: info.shortcutsDisplayText ?? "-", count: count)
                    }
                    if let info = ad.getToggleActionInfo(actionKey) {
                        return (name: info.text, shortcut: info.shortcutsDisplayText ?? "-", count: count)
                    }
                }
                return (name: rawKey, shortcut: "-", count: count)
            }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 360)
        .alert("重置统计？", isPresented: $showingResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { stats.reset() }
        } message: {
            Text("此操作将清空所有快捷键使用统计，且无法撤销。")
        }
        #else
        NavigationView {
            content
                .navigationTitle("快捷键统计")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("重置") { showingResetConfirmation = true }
                            .disabled(stats.counts.isEmpty)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("关闭") { viewModel.showingShortcutUsageStatsView = false }
                    }
                }
        }
        .alert("重置统计？", isPresented: $showingResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { stats.reset() }
        } message: {
            Text("此操作将清空所有快捷键使用统计，且无法撤销。")
        }
        #endif
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("快捷键使用统计").font(.headline)
            Spacer()
            Text("共 \(stats.counts.count) 个动作").foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack {
                Spacer()
                Text("尚无快捷键使用记录").foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                HStack {
                    Text("动作").bold()
                    Spacer()
                    Text("快捷键").bold().frame(width: 100, alignment: .leading)
                    Text("次数").bold().frame(width: 60, alignment: .trailing)
                }
                ForEach(rows, id: \.name) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(row.shortcut)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text("\(row.count)")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            Button("重置") { showingResetConfirmation = true }
                .disabled(stats.counts.isEmpty)
            Spacer()
            Button("关闭") { viewModel.showingShortcutUsageStatsView = false }
        }
        .padding()
    }
}
