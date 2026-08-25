import SwiftUI

/// AI 问棋的对话界面，三端共用。
/// Mac 装在独立窗口里（可与主窗口并排，边走边问），iPhone / iPad 装在全屏 sheet 里。
struct AIChatView: View {

    @ObservedObject var chat: ChatViewModel
    /// 打开设置页。Mac 上是另一个 sheet，iOS 上由外层导航承接
    @State private var showingSettings = false
    /// 展开了花费明细的回答。默认收起——账目是给想核对的时候看的，不该每条都占地方
    @State private var expandedCostIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            contextBar
            Divider()
            transcript
            errorBanner
            inputBar
        }
        .background(AIChatPalette.background)
        .aiChatLightAppearance()
        .sheet(isPresented: $showingSettings, onDismiss: chat.reloadConfig) {
            AISettingsView(isPresented: $showingSettings)
        }
    }

    // MARK: - 顶栏

    /// 常驻当前局面提要，免得问到一半忘了在讨论哪个局面
    private var contextBar: some View {
        HStack(spacing: 6) {
            Text("正在讨论：")
                .foregroundColor(AIChatPalette.textSecondary)
            Text(chat.positionSummary)
                .foregroundColor(AIChatPalette.textPrimary)
                .fontWeight(.semibold)
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundColor(AIChatPalette.textSecondary)
            .help("AI 设置")
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(AIChatPalette.insetBackground)
    }

    // MARK: - 消息区

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty && !chat.isRunning {
                        emptyState
                    }
                    ForEach(chat.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }
                    ForEach(chat.traces) { trace in
                        traceRow(trace)
                    }
                    if let progressText = chat.progressText {
                        progressRow(progressText)
                    }
                    if chat.hitIterationLimit {
                        Text("分析步数已达上限（\(ChatViewModel.maxIterations) 步），以上是目前的结论。")
                            .font(.system(size: 11.5))
                            .foregroundColor(AIChatPalette.textFaint)
                    }
                    // 滚到底的锚点
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: chat.messages.count) { _ in scrollToBottom(proxy) }
            .onChange(of: chat.traces.count) { _ in scrollToBottom(proxy) }
        }
    }

    private static let bottomAnchor = "aiChatBottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            if chat.isConfigured {
                Text("问问这个局面")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AIChatPalette.textSecondary)
                Text("比如「为什么走车二进五不好」「红方最好走什么」「这步亏在哪」")
                    .font(.system(size: 11.5))
                    .foregroundColor(AIChatPalette.textFaint)
                    .multilineTextAlignment(.center)
            } else {
                Text("尚未配置 AI 服务")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AIChatPalette.textSecondary)
                Button("去设置") { showingSettings = true }
                    .font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatViewModel.DisplayMessage) -> some View {
        switch message.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(AIChatPalette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: AIChatPalette.bubbleRadius))
            }
        case .assistant:
            HStack {
                VStack(alignment: .leading, spacing: 9) {
                    MarkdownText(markdown: message.text)
                        .font(.system(size: 13))
                        .foregroundColor(AIChatPalette.textPrimary)
                        .textSelection(.enabled)
                    answerFooter(message)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(AIChatPalette.bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AIChatPalette.bubbleRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AIChatPalette.bubbleRadius)
                        .stroke(AIChatPalette.border, lineWidth: 0.5)
                )
                Spacer(minLength: 40)
            }
        }
    }

    private func answerFooter(_ message: ChatViewModel.DisplayMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if message.savedToComment {
                    Label("已存入注释", systemImage: "checkmark")
                        .font(.system(size: 11))
                        .foregroundColor(AIChatPalette.textFaint)
                } else {
                    Button("存为局面注释") { chat.saveAnswerAsComment(message) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(AIChatPalette.accent)
                }
                Spacer()
                statsLabel(message)
            }
            if expandedCostIDs.contains(message.id) {
                costBreakdown(message)
            }
        }
        .padding(.top, 2)
        .overlay(alignment: .top) {
            Divider().foregroundColor(AIChatPalette.hairline)
        }
    }

    /// 有用量数据时可点开看账，没有就是一行静态文字
    @ViewBuilder
    private func statsLabel(_ message: ChatViewModel.DisplayMessage) -> some View {
        let text = Self.statsText(message)
        if message.costLines.isEmpty {
            Text(text)
                .font(.system(size: 10.5))
                .foregroundColor(AIChatPalette.textFaint)
        } else {
            let isExpanded = expandedCostIDs.contains(message.id)
            Button {
                if isExpanded {
                    expandedCostIDs.remove(message.id)
                } else {
                    expandedCostIDs.insert(message.id)
                }
            } label: {
                HStack(spacing: 3) {
                    Text(text)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7.5))
                }
                .font(.system(size: 10.5))
                .foregroundColor(AIChatPalette.textFaint)
            }
            .buttonStyle(.plain)
            .help("展开花费明细")
        }
    }

    /// 花费明细。等宽字体 + 右对齐，让几行数字能竖着对上，便于自己核账
    private func costBreakdown(_ message: ChatViewModel.DisplayMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(message.costLines, id: \.label) { line in
                HStack(spacing: 8) {
                    Text(line.label)
                        .frame(width: 30, alignment: .leading)
                    Text(line.tokensText)
                        .frame(width: 62, alignment: .trailing)
                    if let unitPriceText = line.unitPriceText {
                        Text("×")
                        Text(unitPriceText)
                    }
                    Spacer(minLength: 6)
                    if let amountText = line.amountText {
                        Text(amountText)
                    }
                }
            }
            if let costText = message.costText {
                HStack(spacing: 8) {
                    Text("合计")
                        .frame(width: 30, alignment: .leading)
                    Spacer(minLength: 6)
                    // 页脚与明细同一个格式化口径，各行相加正好等于这个数
                    Text("≈\(costText)")
                }
                .foregroundColor(AIChatPalette.textSecondary)
            } else {
                Text(message.costFootnote ?? "未填单价，只统计用量")
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(AIChatPalette.textFaint)
        .padding(.top, 1)
    }

    /// 页脚右侧的用量统计。花费带「≈」——单价是用户自填的，缓存策略也未必对得上账单
    private static func statsText(_ message: ChatViewModel.DisplayMessage) -> String {
        var parts: [String] = []
        if message.toolCallCount > 0 {
            parts.append("调用工具 \(message.toolCallCount) 次")
        }
        parts.append("\(message.elapsedSeconds) 秒")
        if let usage = message.usage {
            parts.append(usage.compactDescription)
        }
        if let costText = message.costText {
            parts.append("≈\(costText)")
        }
        return parts.joined(separator: " · ")
    }

    /// 已完成的工具调用留痕，让人看得见 AI 到底算了什么
    private func traceRow(_ trace: ChatViewModel.ToolTrace) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("✓")
                .foregroundColor(AIChatPalette.textFaint)
            Text(trace.title)
                .foregroundColor(AIChatPalette.textSecondary)
            if let summary = trace.summary {
                Text("— \(summary)")
                    .foregroundColor(AIChatPalette.textFaint)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func progressRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(AIChatPalette.textSecondary)
                Spacer()
                Text("\(chat.progressStep) / \(ChatViewModel.maxIterations)")
                    .font(.system(size: 11))
                    .foregroundColor(AIChatPalette.textFaint)
            }
            // 推理模型可以想上一两分钟，把思考的尾巴露出来，让人看得见它在动
            if let reasoning = chat.reasoningPreview, !reasoning.isEmpty {
                Text(reasoning)
                    .font(.system(size: 10.5))
                    .foregroundColor(AIChatPalette.textFaint)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AIChatPalette.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: AIChatPalette.controlRadius))
    }

    // MARK: - 错误

    @ViewBuilder
    private var errorBanner: some View {
        if let errorText = chat.errorText {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(AIChatPalette.bad)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if chat.errorIsRetryable {
                    Button("重试") { chat.retry() }
                        .font(.system(size: 12))
                } else if !chat.isConfigured {
                    Button("去设置") { showingSettings = true }
                        .font(.system(size: 12))
                }
                Button {
                    chat.clearError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(AIChatPalette.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AIChatPalette.bad.opacity(0.08))
        }
    }

    // MARK: - 输入区

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField(inputPlaceholder, text: $chat.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                // 底色是硬编码浅色，文字色必须一并固定（见 AIChatPalette.LightAppearance）
                .foregroundColor(AIChatPalette.textPrimary)
                .lineLimit(1...5)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(AIChatPalette.bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AIChatPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AIChatPalette.controlRadius)
                        .stroke(AIChatPalette.border, lineWidth: 0.5)
                )
                .disabled(chat.isRunning || !chat.isConfigured)
                .onSubmit(chat.send)

            if chat.isRunning {
                Button("停止") { chat.cancel() }
                    .font(.system(size: 12.5, weight: .semibold))
            } else {
                Button("发送") { chat.send() }
                    .font(.system(size: 12.5, weight: .semibold))
                    .disabled(!chat.isConfigured
                              || chat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AIChatPalette.barBackground)
        .overlay(alignment: .top) { Divider() }
    }

    private var inputPlaceholder: String {
        if !chat.isConfigured { return "请先在设置里配置 AI 服务" }
        if chat.isRunning { return "分析中…" }
        return chat.messages.isEmpty ? "问点什么，比如「这步棋怎么样」" : "继续追问…"
    }
}

// MARK: - Markdown 渲染

/// `AnswerMarkdown` 拆出的块的排版。
/// 字号与颜色由外部通过环境注入（`.font` / `.foregroundColor`），这里只管结构。
private struct MarkdownText: View {

    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 块本身没有稳定 id，用下标——这个列表不会增删，只整块重建
            ForEach(Array(AnswerMarkdown.blocks(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: AnswerMarkdown.Block) -> some View {
        switch block {
        case .heading(let text):
            inlineText(text)
                .fontWeight(.semibold)
                .padding(.top, 3)
        case .bullet(let text):
            listRow(marker: "·", text: text)
        case .ordered(let number, let text):
            listRow(marker: "\(number).", text: text)
        case .paragraph(let text):
            inlineText(text)
        }
    }

    /// 悬挂缩进：标记与正文分列，正文换行后不会绕到标记底下
    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(marker)
                .foregroundColor(AIChatPalette.textFaint)
            inlineText(text)
        }
        .padding(.leading, 2)
    }

    private func inlineText(_ text: String) -> some View {
        Text(AnswerMarkdown.inline(text))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
