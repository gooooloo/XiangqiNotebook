import SwiftUI

/// 功能使用统计视图：按触发次数从多到少展示已记录的动作
struct ShortcutUsageStatsView: View {
    @ObservedObject var viewModel: ViewModel
    @ObservedObject private var stats = ShortcutUsageStats.shared
    @State private var showingResetConfirmation = false

    /// (动作名, 快捷键文本, 总次数, 快捷键次数, 按钮次数)
    private var rows: [(name: String, shortcut: String, total: Int, keyboard: Int, button: Int)] {
        let ad = viewModel.actionDefinitions
        return stats.countsBySource
            .map { (rawKey, sources) -> (name: String, shortcut: String, total: Int, keyboard: Int, button: Int) in
                let total = sources.values.reduce(0, +)
                let keyboard = sources["keyboard"] ?? 0
                let button = sources["button"] ?? 0
                if let actionKey = ActionDefinitions.ActionKey(rawValue: rawKey) {
                    if let info = ad.getActionInfo(actionKey) {
                        return (name: info.text, shortcut: info.shortcutsDisplayText ?? "-", total: total, keyboard: keyboard, button: button)
                    }
                    if let info = ad.getToggleActionInfo(actionKey) {
                        return (name: info.text, shortcut: info.shortcutsDisplayText ?? "-", total: total, keyboard: keyboard, button: button)
                    }
                }
                return (name: rawKey, shortcut: "-", total: total, keyboard: keyboard, button: button)
            }
            .sorted { $0.total > $1.total }
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
            Text("此操作将清空所有功能使用统计，且无法撤销。")
        }
        #else
        NavigationView {
            content
                .navigationTitle("功能统计")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("重置") { showingResetConfirmation = true }
                            .disabled(stats.countsBySource.isEmpty)
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
            Text("此操作将清空所有功能使用统计，且无法撤销。")
        }
        #endif
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("功能使用统计").font(.headline)
            Spacer()
            Text("共 \(stats.countsBySource.count) 个动作").foregroundColor(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack {
                Spacer()
                Text("尚无功能使用记录").foregroundColor(.secondary)
                Spacer()
            }
        } else {
            List {
                HStack {
                    Text("动作").bold()
                    Spacer()
                    Text("快捷键").bold().frame(width: 100, alignment: .leading)
                    Text("总次数").bold().frame(width: 60, alignment: .trailing)
                }
                ForEach(rows, id: \.name) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(row.shortcut)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(row.total)")
                                .font(.system(.body, design: .monospaced))
                            if row.keyboard > 0 || row.button > 0 {
                                HStack(spacing: 8) {
                                    if row.keyboard > 0 {
                                        Text("⌨️\(row.keyboard)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    if row.button > 0 {
                                        Text("🖱️\(row.button)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
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
                .disabled(stats.countsBySource.isEmpty)
            Spacer()
            Button("关闭") { viewModel.showingShortcutUsageStatsView = false }
        }
        .padding()
    }
}
