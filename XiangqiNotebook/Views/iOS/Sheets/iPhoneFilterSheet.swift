#if os(iOS)
import SwiftUI

/// 「筛选棋谱」Sheet。原型里三组筛选本身就是纯演示（应用后仅提示，不真正过滤），
/// 工程里也暂无「开局体系 / 复习状态」打标数据，故这里保持同等的 UI 展示，不接真实过滤。
struct iPhoneFilterSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var result = "全部"
    @State private var openings: Set<String> = ["中炮", "屏风马"]
    @State private var reviewState = "全部"

    var body: some View {
        iPhoneSheetShell(title: "筛选棋谱") {
            VStack(alignment: .leading, spacing: 16) {
                group(title: "棋局结果", options: ["全部", "我胜", "我负", "和棋"], selected: [result]) { result = $0 }
                group(title: "开局体系", options: ["中炮", "屏风马", "仙人指路", "飞相局", "过宫炮"], selected: Array(openings), multi: true) { opt in
                    if openings.contains(opt) { openings.remove(opt) } else { openings.insert(opt) }
                }
                group(title: "复习状态", options: ["全部", "已到期", "学习中", "未加入"], selected: [reviewState]) { reviewState = $0 }

                Button(action: { dismiss() }) {
                    Text("应用筛选")
                        .font(XiangqiTheme.XFont.sans(16.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
                .padding(.top, 4)
            }
        }
    }

    private func group(title: String, options: [String], selected: [String], multi: Bool = false, onTap: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(XiangqiTheme.XFont.sans(11.5, weight: .bold))
                .tracking(1.5)
                .foregroundColor(XiangqiTheme.faint)
            iPhoneFlowChips(options: options, selected: selected, onTap: onTap)
        }
    }
}

/// 简单流式换行 Pill 组，用于筛选维度；复用工程既有的 `FlowLayout`（见 `Views/FlowLayout.swift`）。
struct iPhoneFlowChips: View {
    private struct Chip: Identifiable { let id: String }
    let options: [String]
    let selected: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(items: options.map(Chip.init)) { chip in
            let on = selected.contains(chip.id)
            Button(action: { onTap(chip.id) }) {
                Text(chip.id)
                    .font(XiangqiTheme.XFont.sans(13.5, weight: .semibold))
                    .foregroundColor(on ? .white : XiangqiTheme.sub)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(on ? XiangqiTheme.accent : XiangqiTheme.inset, in: Capsule())
            }
        }
    }
}
#endif
