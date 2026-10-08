#if os(iOS)
import SwiftUI
import SafariServices

struct ChatGPTSubscriptionProbeView: View {
    @StateObject private var probe = ChatGPTSubscriptionProbe()
    @Binding var effort: CodexReasoningEffort
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("手机订阅问棋") {
                    Text("使用自己的 ChatGPT 订阅授权；手机直接连接 OpenAI，无需 Mac 或另外安装应用。登录后，在 AI 设置中选择 ChatGPT（订阅）并点击完成，即可使用订阅问棋。")
                    Text("模型：gpt-6.1-sol").font(.system(.body, design: .monospaced))
                    Picker("Reasoning effort", selection: $effort) {
                        ForEach(CodexReasoningEffort.allCases) { Text($0.displayName).tag($0) }
                    }.disabled(probe.busy)
                    Text("实际请求：gpt-6.1-sol；reasoning effort = \(effort.rawValue)")
                }
                Section("ChatGPT 登录") {
                    Button(probe.loggedIn ? "已登录 ChatGPT" : "Continue with ChatGPT") { probe.login() }
                        .disabled(probe.busy || probe.loggedIn)
                    if probe.loggedIn {
                        Button("重新授权") { probe.reauthorize() }.disabled(probe.busy)
                    }
                    Text(probe.message).textSelection(.enabled)
                    if probe.busy {
                        ProgressView()
                        Button("取消等待", role: .cancel) { probe.cancel() }
                    }
                }
                Section("连接测试") {
                    Button("获取一句回答") { probe.test(effort: effort) }
                        .disabled(probe.busy || !probe.loggedIn)
                    if !probe.answer.isEmpty { Text(probe.answer).textSelection(.enabled) }
                    Text("收到完整回答后即可返回问棋。可用额度以你的 ChatGPT 账号为准。")
                        .font(.footnote)
                }
            }
            .navigationTitle("ChatGPT 订阅")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { probe.cancel(); dismiss() } } }
            .sheet(item: $probe.browserURL, onDismiss: {
                // 收到回调时会自动关闭浏览器；只有仍在等待回调时才属于用户取消。
                if probe.busy && probe.awaitingCallback { probe.cancel() }
            }) { browser in
                SubscriptionSafari(url: browser.url).ignoresSafeArea()
            }

        }
    }
}
private struct SubscriptionSafari: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#endif
