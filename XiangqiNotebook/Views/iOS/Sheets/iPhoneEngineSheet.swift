#if os(iOS)
import SwiftUI

/// 「引擎与云库」Sheet。iPhone/iPad 端皮卡鱼引擎内嵌运行（进程内调用，非 Mac 版子进程方案），
/// 出于耗电考虑固定 3 秒限时评估、仅手动触发，不做批量/自动评估；分数单独存一个 engineKey，
/// 与 Mac 深评互不干扰。另外仍保留云库（ChessDB）评估。
struct iPhoneEngineSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    private var lightScoreText: String {
        let text = viewModel.displayDeepEngineScore
        return text.isEmpty ? "暂无评分" : text
    }

    var body: some View {
        iPhoneSheetShell(title: "引擎与云库") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("皮卡鱼引擎（轻评）")
                                .font(XiangqiTheme.XFont.sans(15, weight: .semibold))
                                .foregroundColor(XiangqiTheme.ink)
                            Text("手动触发 · 固定 3 秒限时")
                                .font(.system(size: 11.5))
                                .foregroundColor(XiangqiTheme.faint)
                        }
                        Spacer()
                        Text(lightScoreText)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(XiangqiTheme.ink)
                    }
                    .padding(.vertical, 12)
                    Divider().overlay(XiangqiTheme.hair)
                    Button(action: {
                        Task { await viewModel.aiRespondIOS() }
                    }) {
                        HStack {
                            if viewModel.isEvaluatingIOS {
                                ProgressView()
                                    .controlSize(.small)
                                Text("AI应招中…")
                            } else {
                                Text("AI应招")
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(XiangqiTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .disabled(viewModel.isEvaluatingIOS)
                    Divider().overlay(XiangqiTheme.hair)
                    HStack {
                        Text("云库评估")
                            .font(XiangqiTheme.XFont.sans(15, weight: .semibold))
                            .foregroundColor(XiangqiTheme.ink)
                        Spacer()
                        Text("ChessDB · 已启用")
                            .font(.system(size: 12.5))
                            .foregroundColor(XiangqiTheme.good)
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 15)
                .xqCard()

                Button(action: { dismiss() }) {
                    Text("完成")
                        .font(XiangqiTheme.XFont.sans(16.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
            }
        }
    }
}
#endif
