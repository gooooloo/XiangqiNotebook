#if os(iOS)
import SwiftUI

/// 「棋盘与棋子」Sheet：工程当前棋盘/棋子渲染为固定图片资源，暂无换肤能力，
/// 与原型本身（应用后仅 toast、并无真实换肤）保持同等的纯展示 UI。
struct iPhoneBoardAppearanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pieceStyleIndex = 0
    @State private var boardColorIndex = 0
    @State private var toast: String?

    private let pieceStyles = ["传统红黑", "立体木纹", "极简线条"]
    private let boardColors: [Color] = [Color(hex: 0xE5D3A8), Color(hex: 0xD8C49A), Color(hex: 0xEDE4CE), Color(hex: 0xC9B896)]

    var body: some View {
        iPhoneSheetShell(title: "棋盘与棋子") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("棋子风格")
                    HStack(spacing: 10) {
                        ForEach(Array(pieceStyles.enumerated()), id: \.offset) { i, name in
                            let on = i == pieceStyleIndex
                            Button(action: { pieceStyleIndex = i }) {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: 0xF4E6C4))
                                        .frame(width: 34, height: 34)
                                        .overlay(Circle().stroke(on ? XiangqiTheme.accent : XiangqiTheme.line, lineWidth: 1.5))
                                        .overlay(
                                            Text("車")
                                                .font(XiangqiTheme.XFont.serif(14, weight: .heavy))
                                                .foregroundColor(XiangqiTheme.accent)
                                        )
                                    Text(name)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundColor(on ? XiangqiTheme.accent : XiangqiTheme.sub)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .xqCard()
                                .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card).stroke(on ? XiangqiTheme.accent : XiangqiTheme.line, lineWidth: on ? 1.5 : 1))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("棋盘底色")
                    HStack(spacing: 10) {
                        ForEach(Array(boardColors.enumerated()), id: \.offset) { i, color in
                            Button(action: { boardColorIndex = i }) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(color)
                                    .frame(height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(i == boardColorIndex ? XiangqiTheme.accent : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                    }
                }

                if let toast {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(XiangqiTheme.good)
                }

                Button(action: { toast = "已更新棋盘外观" }) {
                    Text("应用")
                        .font(XiangqiTheme.XFont.sans(16.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(XiangqiTheme.XFont.sans(11.5, weight: .bold))
            .tracking(1.5)
            .foregroundColor(XiangqiTheme.faint)
    }
}
#endif
