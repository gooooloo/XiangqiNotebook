import Foundation
import Combine

/// AI 问棋的对话状态机。
///
/// 驱动「发请求 → 模型要工具 → 本地执行 → 把结果喂回去」的循环，直到模型给出文字回答。
/// 对话不持久化：关掉界面就没了，要留下的东西通过「存为局面注释」进笔记本，
/// 走既有的笔记体系，不新增存储层。
@MainActor
final class ChatViewModel: ObservableObject {

    // MARK: - 展示模型

    /// 界面上的一条消息。不含工具调用的中间态——那些走 `traces`
    struct DisplayMessage: Identifiable {
        enum Kind { case user, assistant }

        let id = UUID()
        let kind: Kind
        let text: String
        /// 这条回答背后调了几次工具，显示在页脚
        var toolCallCount: Int = 0
        var elapsedSeconds: Int = 0
        /// 本轮全部请求的 token 合计。工具循环每走一步都要把整段对话连同工具结果重发一遍，
        /// prompt tokens 会随步数快速累加——这正是值得摆到台面上的原因
        var usage: TokenUsage?
        /// 估算花费文案；设置里没填单价时为 nil
        var costText: String?
        /// 花费明细，展开时显示。存下来而不是渲染时现算：
        /// 这是「当时那次调用按当时单价」的账，用户中途改了价不该把旧账改掉
        var costLines: [CostLine] = []
        /// 已存进局面注释，按钮就地变灰
        var savedToComment: Bool = false
    }

    /// 一次已完成的工具调用，在进度区留痕
    struct ToolTrace: Identifiable {
        let id = UUID()
        let title: String
        let summary: String?
    }

    // MARK: - 状态

    @Published private(set) var messages: [DisplayMessage] = []
    /// 本轮已完成的工具调用；每次提问前清空
    @Published private(set) var traces: [ToolTrace] = []
    @Published private(set) var isRunning = false
    /// 当前正在做什么，nil 表示没有进行中的工具调用
    @Published private(set) var progressText: String?
    /// 已进行到第几步（1-based），配合 `maxIterations` 显示 n / 8
    @Published private(set) var progressStep = 0
    /// 模型思考的最新一段，显示在进度行下方。
    /// 只做「看得见它在动」用，不进对话记录，也不会被存进注释
    @Published private(set) var reasoningPreview: String?
    @Published private(set) var errorText: String?
    @Published private(set) var errorIsRetryable = false
    /// 达到步数上限时提示用户「以上是目前的结论」
    @Published private(set) var hitIterationLimit = false
    @Published var input = ""

    /// 工具循环上限，防止模型来回打转烧钱。
    /// 一轮完整的评点（读局面 → 看候选 → 评实战着 → 走几手验证 → 再评）实测要六七步，
    /// 8 步太紧，撞上限就只能给个半截结论
    static let maxIterations = 12

    var isConfigured: Bool { config.isConfigured }

    /// 顶栏常驻的局面提要，让人一眼知道在问哪个局面。
    /// 直接读那两个字段而不是走 `currentPositionSnapshot()`——后者要遍历着法列表，
    /// 而这是每次重绘都会调的
    var positionSummary: String {
        guard let viewModel else { return "" }
        let side = AnalysisToolbox.sideToMove(fen: viewModel.currentFen) == "black" ? "黑方" : "红方"
        return "第 \(viewModel.currentGameStepDisplay) 步 · 轮\(side)走"
    }

    // MARK: - 依赖

    /// weak：主界面先于问棋窗口销毁时不应崩溃，只是从此存不了注释
    private weak var viewModel: ViewModel?
    private let toolbox: AnalysisToolbox
    private var config: AIConfig
    private let clientFactory: (AIConfig) -> LLMSending

    /// 完整对话（含工具中间态），供追问时保持上下文
    private var wireMessages: [LLMMessage] = [.system(AIChatPrompt.system)]
    private var runningTask: Task<Void, Never>?
    /// 重试用：记住上一次没成功的提问
    private var lastFailedInput: String?

    init(viewModel: ViewModel,
         config: AIConfig = .load(),
         clientFactory: @escaping (AIConfig) -> LLMSending = { LLMClient(config: $0) }) {
        self.viewModel = viewModel
        self.toolbox = AnalysisToolbox(host: viewModel)
        self.config = config
        self.clientFactory = clientFactory
    }

    /// 设置页改完配置后调用，让下一次提问用新配置
    func reloadConfig() {
        config = .load()
        if config.isConfigured, errorText != nil, !errorIsRetryable {
            // 配置问题（未配置 / key 无效）已经处理了，把红字撤掉
            clearError()
        }
    }

    // MARK: - 提问

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        start(question: text)
    }

    /// 快捷入口用：直接问一个现成的问题。
    /// 正在跑的时候不打断，把问题放进输入框——问题不能被悄悄吞掉
    func ask(_ question: String) {
        guard !isRunning else {
            input = question
            return
        }
        input = question
        send()
    }

    /// 重试上一次失败的提问
    func retry() {
        guard let question = lastFailedInput else { return }
        start(question: question)
    }

    private func start(question: String) {
        guard !isRunning else { return }
        guard config.isConfigured else {
            lastFailedInput = question
            setError(LLMError.notConfigured)
            return
        }

        clearError()
        traces = []
        progressStep = 0
        clearProgress()
        messages.append(DisplayMessage(kind: .user, text: question))
        wireMessages.append(.user(question))

        isRunning = true
        runningTask = Task { [weak self] in
            await self?.runToolLoop(question: question)
            self?.isRunning = false
            self?.clearProgress()
            self?.runningTask = nil
            // 本轮问棋算出的引擎分析统一在这里落盘。放在收尾处而不是每次分析后，
            // 理由见 flushAnalysisCache。取消也会走到这里——已经算出来的结果照样值得留下
            self?.viewModel?.flushAnalysisCache()
        }
    }

    /// 进度行与思考预览必须一起收——只清前者会把思考文本残留在界面上
    private func clearProgress() {
        progressText = nil
        reasoningPreview = nil
    }

    func cancel() {
        runningTask?.cancel()
        runningTask = nil
        isRunning = false
        clearProgress()
        // 光取消 Task 不会让引擎停下——它会把剩下的 movetime 跑完。
        // evaluate_move 一次跑两轮分析，不停的话点了停止还要空转十几秒
        viewModel?.stopRemoteEngineAnalyze()
        // 取消后 wireMessages 可能停在「assistant 要了工具但没给结果」的半截状态，
        // 下一轮请求会因 tool_call 没有配对的 tool 结果被服务端拒绝。回滚到上一个干净点。
        rollbackToLastUserMessage()
    }

    // MARK: - 工具循环

    private func runToolLoop(question: String) async {
        let client = clientFactory(config)
        let startedAt = Date()
        var toolCallCount = 0
        var usage = TokenUsage.zero

        for step in 1...Self.maxIterations {
            if Task.isCancelled { return }

            // 等模型回复的这段也要有提示。推理型模型在拿到工具结果后可能思考一两分钟，
            // 界面若空着，用户只能干等到超时才知道发生过什么
            progressStep = step
            progressText = traces.isEmpty ? "正在等模型回复…" : "模型正在读取分析结果…"
            reasoningPreview = nil

            let response: LLMResponse
            do {
                response = try await client.send(
                    messages: wireMessages,
                    tools: AnalysisToolbox.toolSpecs,
                    onReasoning: { [weak self] chunk in
                        Task { @MainActor in self?.appendReasoning(chunk) }
                    })
            } catch {
                lastFailedInput = question
                rollbackToLastUserMessage()
                setError(error)
                return
            }

            if Task.isCancelled { return }
            if let step = response.usage { usage = usage + step }

            guard !response.toolCalls.isEmpty else {
                finish(text: response.content, toolCallCount: toolCallCount,
                       startedAt: startedAt, usage: usage)
                return
            }

            // 先把 assistant 的工具请求入档，再逐个执行：两者必须成对出现，
            // 否则下一轮请求会因 tool_call 无对应结果被服务端拒绝
            wireMessages.append(.assistant(response.content, toolCalls: response.toolCalls))

            for call in response.toolCalls {
                if Task.isCancelled { return }
                toolCallCount += 1
                progressStep = step
                let arguments = AnalysisToolbox.parseArgumentsJSON(call.argumentsJSON)
                let title = AnalysisToolbox.progressDescription(toolName: call.name, arguments: arguments)
                progressText = title

                let result = await toolbox.execute(toolName: call.name, argumentsJSON: call.argumentsJSON)
                wireMessages.append(.toolResult(callId: call.id, content: result))
                traces.append(ToolTrace(
                    title: title,
                    summary: AnalysisToolbox.resultSummary(toolName: call.name, resultJSON: result)))
            }
            // 不在这里清空——下一轮开头会立刻改写成「模型正在读取分析结果…」，
            // 清了反而在两者之间闪一下空白。循环退出时由外层统一收尾
        }

        // 到顶还没收敛：把最后说过的话拿出来，别让用户一无所获。
        // recordInWire: false —— 这段话本就在对话记录里，不能再入档一遍
        hitIterationLimit = true
        finish(text: lastAssistantText(), toolCallCount: toolCallCount,
               startedAt: startedAt, usage: usage, recordInWire: false)
    }

    private func finish(text: String?, toolCallCount: Int, startedAt: Date,
                        usage: TokenUsage, recordInWire: Bool = true) {
        let body = (text?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        }
        guard let body else {
            setError(LLMError.malformedResponse("模型没有给出文字回答"))
            return
        }
        if recordInWire {
            wireMessages.append(LLMMessage(role: .assistant, content: body))
        }
        // 一次用量都没回报（服务端不认 stream_options）就别显示 0 tokens——
        // 那看起来像「没花钱」，其实是「不知道」
        let reported: TokenUsage? = usage.totalTokens > 0 ? usage : nil
        messages.append(DisplayMessage(
            kind: .assistant,
            text: body,
            toolCallCount: toolCallCount,
            elapsedSeconds: max(1, Int(Date().timeIntervalSince(startedAt).rounded())),
            usage: reported,
            costText: reported.flatMap {
                config.pricing.formattedCost(promptTokens: $0.promptTokens,
                                             cachedTokens: $0.cachedTokens,
                                             completionTokens: $0.completionTokens)
            },
            costLines: reported.map {
                config.pricing.breakdown(promptTokens: $0.promptTokens,
                                         cachedTokens: $0.cachedTokens,
                                         completionTokens: $0.completionTokens)
            } ?? []))
        traces = []
        lastFailedInput = nil
    }

    /// 思考只留尾巴一小段。推理模型能吐好几千字，全量显示会把界面撑爆，
    /// 而用户真正需要的信息只有「它还在动、在想什么方向」
    private func appendReasoning(_ chunk: String) {
        guard isRunning else { return }
        let merged = (reasoningPreview ?? "") + chunk
        let flattened = merged.replacingOccurrences(of: "\n", with: " ")
        reasoningPreview = String(flattened.suffix(Self.reasoningPreviewLimit))
    }

    private static let reasoningPreviewLimit = 160

    /// 达到步数上限时，模型最近一次说过的正文
    private func lastAssistantText() -> String? {
        wireMessages.last { $0.role == .assistant && $0.content?.isEmpty == false }?.content
    }

    /// 回滚到最后一条 user 消息，丢掉半截的工具往返。
    /// 失败或取消后必须做，否则残留的 tool_call 会毒化后续每一轮请求。
    private func rollbackToLastUserMessage() {
        guard let index = wireMessages.lastIndex(where: { $0.role == .user }) else { return }
        wireMessages.removeSubrange((index + 1)...)
    }

    // MARK: - 存为局面注释

    /// 把回答追加到当前局面的注释末尾（不覆盖既有内容）
    func saveAnswerAsComment(_ message: DisplayMessage) {
        guard let viewModel,
              message.kind == .assistant,
              let index = messages.firstIndex(where: { $0.id == message.id }),
              !messages[index].savedToComment else { return }

        // 注释区是纯文本，`**` 和 `- ` 进去只是噪音，落盘前剥干净
        let answer = AnswerMarkdown.plainText(message.text)
        let existing = viewModel.currentFenComment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let merged = existing.isEmpty ? answer : existing + "\n\n" + answer
        viewModel.updateCurrentFenComment(merged)
        messages[index].savedToComment = true
    }

    // MARK: - 错误

    private func setError(_ error: Error) {
        let llmError = error as? LLMError
        errorText = llmError?.errorDescription ?? error.localizedDescription
        errorIsRetryable = llmError?.isRetryable ?? true
    }

    func clearError() {
        errorText = nil
        errorIsRetryable = false
        hitIterationLimit = false
    }
}
