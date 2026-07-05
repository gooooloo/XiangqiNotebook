#if os(iOS)
import SwiftUI

/// 「引擎与云库」Sheet。iPhone 端无本地皮卡鱼引擎（`PikafishService` 仅 macOS 实现），
/// 只接云库（ChessDB）评估；皮卡鱼开关展示但禁用，注明仅 Mac 支持。
struct iPhoneEngineSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        iPhoneSheetShell(title: "引擎与云库") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("皮卡鱼引擎")
                                .font(XiangqiTheme.XFont.sans(15, weight: .semibold))
                                .foregroundColor(XiangqiTheme.ink)
                            Text("仅 Mac 支持")
                                .font(.system(size: 11.5))
                                .foregroundColor(XiangqiTheme.faint)
                        }
                        Spacer()
                        Toggle("", isOn: .constant(false))
                            .labelsHidden()
                            .disabled(true)
                    }
                    .padding(.vertical, 12)
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
