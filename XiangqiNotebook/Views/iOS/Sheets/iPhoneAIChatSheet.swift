#if os(iOS)
import SwiftUI

/// 「AI 问棋」Sheet（iPhone / iPad）。
///
/// 不复用 `iPhoneSheetShell`：那个外层套了 ScrollView 且默认 medium 档位，
/// 而对话界面自己要滚动、底部还要钉住输入框，需要占满全屏。
struct iPhoneAIChatSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chat: ChatViewModel

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
        _chat = StateObject(wrappedValue: ChatViewModel(viewModel: viewModel))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            AIChatView(chat: chat)
        }
        .background(XiangqiTheme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear {
            // 走「问 AI」快捷入口进来的，sheet 一起来就把问题发出去
            if let question = viewModel.pendingAIQuestion {
                viewModel.pendingAIQuestion = nil
                chat.ask(question)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("问棋")
                .font(XiangqiTheme.XFont.sans(18, weight: .heavy))
                .foregroundColor(XiangqiTheme.ink)
            Spacer()
            Button(action: { dismiss() }) {
                Text("✕")
                    .font(.system(size: 15))
                    .foregroundColor(XiangqiTheme.sub)
                    .frame(width: 30, height: 30)
                    .xqInset(radius: 15)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(XiangqiTheme.panel)
    }
}
#endif
