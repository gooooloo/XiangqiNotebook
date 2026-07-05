#if os(iOS)
import SwiftUI

/// 「错误统计」页：练习模式里走错次数最多的局面。
struct iPhoneMistakeListView: View {
    @ObservedObject var viewModel: ViewModel
    let onBack: () -> Void

    private struct Row: Identifiable {
        let fenId: Int
        let count: Int
        let lastWrongAt: Date
        var id: Int { fenId }
    }

    private var rows: [Row] {
        viewModel.practiceMistakesInScope.map { fenId, records in
            Row(
                fenId: fenId,
                count: records.reduce(0) { $0 + $1.count },
                lastWrongAt: records.map(\.lastWrongAt).max() ?? Date.distantPast
            )
        }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Text("‹").font(.system(size: 22)).foregroundColor(XiangqiTheme.accent)
                }
                Text("错误统计")
                    .font(XiangqiTheme.XFont.sans(18, weight: .bold))
                    .foregroundColor(XiangqiTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            if rows.isEmpty {
                Text("暂无练习错误记录")
                    .font(.system(size: 14))
                    .foregroundColor(XiangqiTheme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("易错局面")
                            .font(.system(size: 12.5))
                            .foregroundColor(XiangqiTheme.sub)
                        Text("\(rows.count) 个")
                            .font(XiangqiTheme.XFont.serif(26, weight: .black))
                            .foregroundColor(XiangqiTheme.ink)
                    }
                    Spacer()
                }
                .padding(17)
                .xqCard()
                .padding(.horizontal, 18)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        HStack(spacing: 12) {
                            Text("\(row.count)")
                                .font(XiangqiTheme.XFont.serif(21, weight: .black))
                                .foregroundColor(row.count >= 3 ? XiangqiTheme.bad : XiangqiTheme.sub)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(viewModel.reviewItemDescription(fenId: row.fenId))
                                    .font(XiangqiTheme.XFont.sans(14.5, weight: .semibold))
                                    .foregroundColor(XiangqiTheme.ink)
                                    .lineLimit(1)
                                Text("上次 \(relativeTime(row.lastWrongAt))")
                                    .font(.system(size: 12))
                                    .foregroundColor(XiangqiTheme.sub)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 13)
                        .padding(.horizontal, 16)
                        if i < rows.count - 1 {
                            Divider().overlay(XiangqiTheme.hair).padding(.leading, 60)
                        }
                    }
                }
                .xqCard()
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Button(action: { viewModel.resetPracticeMistakes() }) {
                    Text("清空错误记录")
                        .font(XiangqiTheme.XFont.sans(15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
        }
        .padding(.bottom, 20)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
#endif
