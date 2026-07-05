#if os(iOS)
import SwiftUI

/// 「开局库」Sheet：工程暂无按开局体系打标的数据，静态列表，点击跳转「棋谱」标签的课程分类。
struct iPhoneOpeningsSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedTab: IPhoneTab
    @Binding var isMorePresented: Bool
    @Environment(\.dismiss) private var dismiss

    private let openings = ["中炮", "屏风马", "仙人指路", "飞相局", "过宫炮", "顺炮"]

    var body: some View {
        iPhoneSheetShell(title: "开局库") {
            VStack(spacing: 10) {
                ForEach(openings, id: \.self) { name in
                    Button(action: {
                        selectedTab = .library
                        isMorePresented = false
                    }) {
                        HStack(spacing: 12) {
                            Text("炮")
                                .font(XiangqiTheme.XFont.serif(17, weight: .heavy))
                                .foregroundColor(XiangqiTheme.accent)
                                .frame(width: 38, height: 42)
                                .background(Color(hex: 0xE5D3A8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xD0B885), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(name)
                                .font(XiangqiTheme.XFont.sans(15, weight: .bold))
                                .foregroundColor(XiangqiTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(XiangqiTheme.faint)
                        }
                        .padding(14)
                        .xqCard()
                    }
                }
            }
        }
    }
}
#endif
