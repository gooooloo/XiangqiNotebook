import Testing
import Foundation
@testable import XiangqiNotebook

/// 工具循环的测试：用脚本化的假客户端驱动，不发网络、不配 key。
///
/// 工具那侧用的是真 `AnalysisToolbox` + 真 `ViewModel`：`get_position` 会返回真实局面，
/// `evaluate` 因测试环境没有引擎而返回错误 JSON——这两种都是线上会发生的情形，
/// 正好一并覆盖。
@MainActor
struct ChatViewModelTests {

    // MARK: - 脚手架

    private final class StubPlatformService: PlatformService {
        func openURL(_ url: URL) {}
        func showAlert(title: String, message: String) {}
        func showWarningAlert(title: String, message: String) {}
        func showConfirmAlert(title: String, message: String,
                              completion: @escaping (Bool) throws -> Void) { try? completion(false) }
        func saveFile(defaultName: String, completion: @escaping (URL?) -> Void) { completion(nil) }
        func openFile(completion: @escaping (URL?) -> Void) { completion(nil) }
        func backupData(_ data: Data, defaultName: String,
                        completion: @escaping (Bool) -> Void) { completion(false) }
        func recoverData(completion: @escaping (Data?) -> Void) { completion(nil) }
    }

    /// 按脚本逐轮返回预设响应；脚本用完就抛错，避免测试因意外多轮而挂住
    private final class ScriptedClient: LLMSending, @unchecked Sendable {
        private var script: [Result<LLMResponse, LLMError>]
        private(set) var sentMessageLog: [[LLMMessage]] = []

        init(_ script: [Result<LLMResponse, LLMError>]) {
            self.script = script
        }

        func send(messages: [LLMMessage], tools: [[String: Any]],
                  onReasoning: @escaping (String) -> Void) async throws -> LLMResponse {
            sentMessageLog.append(messages)
            guard !script.isEmpty else { throw LLMError.serverError(599) }
            return try script.removeFirst().get()
        }
    }

    private static let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"

    private func makeViewModel() -> ViewModel {
        let database = TestDatabaseBuilder()
            .addFen(1, fen: Self.startFen, inRedOpening: true, inBlackOpening: true)
            .build()
        let sessionData = SessionData()
        let databaseView = DatabaseView.full(database: database)
        sessionData.currentGame2 = [databaseView.ensureFenId(for: Self.startFen)]
        sessionData.currentGameStep = 0
        let session = try! Session(sessionData: sessionData, databaseView: databaseView)
        let sessionManager = SessionManager(mainSession: session, database: database)
        return ViewModel(sessionManager: sessionManager, platformService: StubPlatformService())
    }

    private let configured = AIConfig(baseURL: "https://example.com/v1", model: "m", apiKey: "k")

    private func makeChat(script: [Result<LLMResponse, LLMError>])
    -> (ChatViewModel, ScriptedClient, ViewModel) {
        let viewModel = makeViewModel()
        let client = ScriptedClient(script)
        let chat = ChatViewModel(viewModel: viewModel, config: configured, clientFactory: { _ in client })
        return (chat, client, viewModel)
    }

    /// 循环跑在 Task 里，等它落地
    private func waitUntilIdle(_ chat: ChatViewModel) async {
        for _ in 0..<200 {
            if !chat.isRunning { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func ask(_ chat: ChatViewModel, _ question: String) async {
        chat.input = question
        chat.send()
        await waitUntilIdle(chat)
    }

    private func text(_ body: String) -> Result<LLMResponse, LLMError> {
        .success(LLMResponse(content: body, toolCalls: []))
    }

    private func toolCall(_ name: String, id: String = "c1",
                          arguments: String = "{}") -> Result<LLMResponse, LLMError> {
        .success(LLMResponse(content: nil,
                             toolCalls: [LLMToolCall(id: id, name: name, argumentsJSON: arguments)]))
    }

    // MARK: - 直接回答

    @Test func testSend_plainAnswerAppearsAsAssistantMessage() async {
        let (chat, _, _) = makeChat(script: [text("车二进五是失着。")])
        await ask(chat, "为什么走车二进五不好")

        #expect(chat.messages.count == 2)
        #expect(chat.messages[0].kind == .user)
        #expect(chat.messages[0].text == "为什么走车二进五不好")
        #expect(chat.messages[1].kind == .assistant)
        #expect(chat.messages[1].text == "车二进五是失着。")
        #expect(chat.messages[1].toolCallCount == 0)
        #expect(chat.errorText == nil)
        #expect(!chat.isRunning)
    }

    @Test func testSend_trimsAndClearsInput() async {
        let (chat, _, _) = makeChat(script: [text("好。")])
        await ask(chat, "  这步怎么样  ")
        #expect(chat.messages.first?.text == "这步怎么样")
        #expect(chat.input.isEmpty)
    }

    @Test func testSend_ignoresBlankInput() async {
        let (chat, client, _) = makeChat(script: [text("不该被用到")])
        await ask(chat, "   ")
        #expect(chat.messages.isEmpty)
        #expect(client.sentMessageLog.isEmpty)
    }

    // MARK: - 工具循环

    @Test func testToolLoop_executesToolThenAnswers() async {
        let (chat, client, _) = makeChat(script: [
            toolCall("get_position"),
            text("现在轮红方走。"),
        ])
        await ask(chat, "现在什么局面")

        #expect(chat.messages.last?.text == "现在轮红方走。")
        #expect(chat.messages.last?.toolCallCount == 1)
        #expect(client.sentMessageLog.count == 2)

        // 第二轮请求必须带上 assistant 的工具请求与配对的 tool 结果，
        // 少任何一半服务端都会拒
        let secondRound = client.sentMessageLog[1]
        #expect(secondRound.contains { $0.role == .assistant && !$0.toolCalls.isEmpty })
        let toolResult = secondRound.last { $0.role == .tool }
        #expect(toolResult?.toolCallId == "c1")
        #expect(toolResult?.content?.contains("sideToMove") == true)
    }

    @Test func testToolLoop_recordsTraceWithSummary() async {
        let (chat, _, _) = makeChat(script: [
            toolCall("get_position"),
            text("讲解。"),
        ])
        await ask(chat, "问")
        // 回答落地后本轮痕迹清空，进度提示也该收起来
        #expect(chat.traces.isEmpty)
        #expect(chat.progressText == nil)
    }

    @Test func testToolLoop_handlesMultipleToolCallsInOneTurn() async {
        let response = LLMResponse(content: nil, toolCalls: [
            LLMToolCall(id: "c1", name: "get_position", argumentsJSON: "{}"),
            LLMToolCall(id: "c2", name: "get_position", argumentsJSON: "{}"),
        ])
        let (chat, client, _) = makeChat(script: [.success(response), text("好了。")])
        await ask(chat, "问")

        #expect(chat.messages.last?.toolCallCount == 2)
        // 两个工具结果都要回传，且 id 各自对上
        let ids = client.sentMessageLog[1].filter { $0.role == .tool }.compactMap(\.toolCallId)
        #expect(ids == ["c1", "c2"])
    }

    @Test func testToolLoop_failingToolStillFeedsResultBack() async {
        // 工具失败要作为 tool 结果喂回模型，让它改参数重试或如实说明，
        // 而不是中断整轮问答。
        // 用非法 FEN 而非 evaluate 制造失败：后者要看测试机上真引擎跑不跑得起来，
        // 结果不确定
        let (chat, client, _) = makeChat(script: [
            toolCall("apply_moves", arguments: #"{"fen":"乱码","moves":["h2e2"]}"#),
            text("局面串有问题，我重新读一次。"),
        ])
        await ask(chat, "分析一下")

        #expect(chat.errorText == nil)
        #expect(chat.messages.last?.text == "局面串有问题，我重新读一次。")
        let toolResult = client.sentMessageLog[1].last { $0.role == .tool }
        // 错误码是给模型分支用的：FEN_INVALID 就该重新 get_position
        #expect(toolResult?.content?.contains("FEN_INVALID") == true)
        #expect(toolResult?.content?.contains("\"ok\":false") == true)
    }

    @Test func testToolLoop_successResultsCarryOkTrue() async {
        let (chat, client, _) = makeChat(script: [
            toolCall("get_position"),
            text("好。"),
        ])
        await ask(chat, "问")
        let toolResult = client.sentMessageLog[1].last { $0.role == .tool }
        // 成功也带 ok，模型只看一个字段就能分支
        #expect(toolResult?.content?.contains("\"ok\":true") == true)
    }

    @Test func testToolLoop_evaluateMoveRejectsMissingMoveArgument() async {
        // move 是必填，缺了要报 BAD_ARGUMENTS 让模型补上，而不是拿当前局面瞎评
        let (chat, client, _) = makeChat(script: [
            toolCall("evaluate_move", arguments: "{}"),
            text("我需要知道具体评哪一步。"),
        ])
        await ask(chat, "这步怎么样")

        let toolResult = client.sentMessageLog[1].last { $0.role == .tool }
        #expect(toolResult?.content?.contains("BAD_ARGUMENTS") == true)
        #expect(chat.errorText == nil)
    }

    @Test func testToolLoop_evaluateMoveRejectsUnplayableMove() async {
        // 起点无子的着法要报 ILLEGAL_MOVE，模型据此换一步而不是继续往下算
        let arguments = """
        {"fen":"\(Self.startFen)","move":"e5e4"}
        """
        let (chat, client, _) = makeChat(script: [
            toolCall("evaluate_move", arguments: arguments),
            text("那步走不了。"),
        ])
        await ask(chat, "评一下 e5e4")

        let toolResult = client.sentMessageLog[1].last { $0.role == .tool }
        #expect(toolResult?.content?.contains("ILLEGAL_MOVE") == true)
    }

    @Test func testToolLoop_reportsUnapplicableMoveWithItsPosition() async {
        // 第二步起点无子，错误里要指明是第几步，模型才知道从哪改
        let arguments = """
        {"fen":"\(Self.startFen)","moves":["h2e2","e5e4"]}
        """
        let (chat, client, _) = makeChat(script: [
            toolCall("apply_moves", arguments: arguments),
            text("那步走不了。"),
        ])
        await ask(chat, "走这两步看看")

        let toolResult = client.sentMessageLog[1].last { $0.role == .tool }
        #expect(toolResult?.content?.contains("第 2 步") == true)
    }

    @Test func testToolLoop_unknownToolReportsErrorToModel() async {
        let (chat, client, _) = makeChat(script: [
            toolCall("nonexistent_tool"),
            text("我换个思路。"),
        ])
        await ask(chat, "问")
        let toolResult = client.sentMessageLog[1].last { $0.role == .tool }
        #expect(toolResult?.content?.contains("未知工具") == true)
        #expect(chat.errorText == nil)
    }

    @Test func testToolLoop_stopsAtIterationLimit() async {
        // 模型一直要工具不给结论，必须在上限处刹车
        let script = Array(repeating: toolCall("get_position"), count: ChatViewModel.maxIterations + 3)
        let (chat, client, _) = makeChat(script: script)
        await ask(chat, "问")

        #expect(chat.hitIterationLimit)
        #expect(client.sentMessageLog.count == ChatViewModel.maxIterations)
        #expect(!chat.isRunning)
    }

    // MARK: - Claude Code 线路（工具在客户端内部执行，经事件透传）

    /// 模拟 ClaudeCodeClient：只实现四参 send，工具过程经 onToolEvent 透传，
    /// 一次返回终稿、toolCalls 恒空。三参版抛错——若循环走到它，
    /// 说明 existential 派发掉进了默认实现，那是协议接错了。
    private final class ClaudeStyleClient: LLMSending, @unchecked Sendable {
        private(set) var sentMessageLog: [[LLMMessage]] = []

        func send(messages: [LLMMessage], tools: [[String: Any]],
                  onReasoning: @escaping (String) -> Void) async throws -> LLMResponse {
            throw LLMError.serverError(598)
        }

        func send(messages: [LLMMessage], tools: [[String: Any]],
                  onReasoning: @escaping (String) -> Void,
                  onToolEvent: @escaping (LLMToolEvent) -> Void) async throws -> LLMResponse {
            sentMessageLog.append(messages)
            onReasoning("先看引擎候选")
            onToolEvent(.started(name: "get_position", argumentsJSON: "{}"))
            onToolEvent(.finished(name: "get_position", argumentsJSON: "{}",
                                  resultJSON: #"{"ok":true,"step":3,"sideToMove":"red","nextMoves":[]}"#))
            onToolEvent(.started(name: "evaluate", argumentsJSON: #"{"multipv":5}"#))
            onToolEvent(.finished(name: "evaluate", argumentsJSON: #"{"multipv":5}"#,
                                  resultJSON: #"{"ok":true,"lines":[{"scoreCp":32,"pvChinese":["炮二平五"]}]}"#))
            return LLMResponse(content: "红方略优。", toolCalls: [],
                               usage: TokenUsage(promptTokens: 900, cachedTokens: 200,
                                                 completionTokens: 150))
        }
    }

    @Test func testClaudeRoute_dispatchesToFourParameterSend() async {
        // ClaudeStyleClient 的三参版抛 598：本测试通过本身就证明
        // 循环调的是带 onToolEvent 的协议方法，而不是默认实现
        let viewModel = makeViewModel()
        let client = ClaudeStyleClient()
        let chat = ChatViewModel(viewModel: viewModel, config: configured,
                                 clientFactory: { _ in client })
        await ask(chat, "现在局面怎么样")

        #expect(chat.errorText == nil)
        #expect(chat.messages.last?.text == "红方略优。")
    }

    @Test func testClaudeRoute_toolEventsCountIntoTheAnswer() async {
        // 工具跑在 claude 进程内部，次数只能靠事件计——页脚的「调了 N 次工具」
        // 必须与其他线路同一口径
        let viewModel = makeViewModel()
        let client = ClaudeStyleClient()
        let chat = ChatViewModel(viewModel: viewModel, config: configured,
                                 clientFactory: { _ in client })
        await ask(chat, "问")

        #expect(chat.messages.last?.toolCallCount == 2)
        #expect(chat.messages.last?.usage?.promptTokens == 900)
        // 一次返回终稿 → 只有一轮请求
        #expect(client.sentMessageLog.count == 1)
        // 回答落地后轨迹清空，与其他线路一致
        #expect(chat.traces.isEmpty)
    }

    @Test func testClaudeRoute_followUpCarriesHistoryOnly() async {
        // 追问要带上此前的问答，且不能混进工具中间态（本线路一轮收敛，本就没有）
        let viewModel = makeViewModel()
        let client = ClaudeStyleClient()
        let chat = ChatViewModel(viewModel: viewModel, config: configured,
                                 clientFactory: { _ in client })
        await ask(chat, "第一问")
        await ask(chat, "第二问")

        let second = client.sentMessageLog[1]
        #expect(second.first?.role == .system)
        #expect(second.contains { $0.role == .user && $0.content == "第一问" })
        #expect(second.contains { $0.role == .assistant && $0.content == "红方略优。" })
        #expect(second.last?.content == "第二问")
        #expect(!second.contains { $0.role == .tool })
        #expect(!second.contains { !$0.toolCalls.isEmpty })
    }

    // MARK: - 追问保持上下文

    @Test func testFollowUp_carriesPriorTurns() async {
        let (chat, client, _) = makeChat(script: [text("第一答。"), text("第二答。")])
        await ask(chat, "第一问")
        await ask(chat, "第二问")

        #expect(chat.messages.count == 4)
        let second = client.sentMessageLog[1]
        #expect(second.first?.role == .system)
        #expect(second.contains { $0.role == .user && $0.content == "第一问" })
        #expect(second.contains { $0.role == .assistant && $0.content == "第一答。" })
        #expect(second.last?.content == "第二问")
    }

    // MARK: - 错误处理

    @Test func testError_surfacesMessageAndRetryability() async {
        let (chat, _, _) = makeChat(script: [.failure(.unauthorized)])
        await ask(chat, "问")

        #expect(chat.errorText == LLMError.unauthorized.errorDescription)
        #expect(!chat.errorIsRetryable)
        // 失败时不该留下半截 assistant 消息
        #expect(chat.messages.count == 1)
    }

    @Test func testError_rateLimitIsRetryable() async {
        let (chat, _, _) = makeChat(script: [.failure(.rateLimited)])
        await ask(chat, "问")
        #expect(chat.errorIsRetryable)
    }

    @Test func testRetry_resendsLastQuestionWithCleanHistory() async {
        // 关键点：失败发生在工具往返中途时，残留的 tool_call 不能带进重试请求，
        // 否则服务端会因「有 tool_call 没有配对结果」直接拒绝
        let (chat, client, _) = makeChat(script: [
            toolCall("get_position"),
            .failure(.serverError(500)),
            text("重试成功。"),
        ])
        await ask(chat, "问")
        #expect(chat.errorText != nil)

        chat.retry()
        await waitUntilIdle(chat)

        #expect(chat.messages.last?.text == "重试成功。")
        let retryRound = client.sentMessageLog[2]
        #expect(!retryRound.contains { !$0.toolCalls.isEmpty }, "重试请求里不该残留工具调用")
        #expect(!retryRound.contains { $0.role == .tool }, "重试请求里不该残留工具结果")
    }

    @Test func testSend_withoutConfigurationReportsAndDoesNotCallClient() async {
        let viewModel = makeViewModel()
        let client = ScriptedClient([text("不该被用到")])
        let chat = ChatViewModel(viewModel: viewModel, config: .empty, clientFactory: { _ in client })
        await ask(chat, "问")

        #expect(chat.errorText == LLMError.notConfigured.errorDescription)
        #expect(client.sentMessageLog.isEmpty)
        #expect(!chat.isConfigured)
    }

    // MARK: - 存为局面注释

    @Test func testSaveAnswerAsComment_appendsAndMarksSaved() async {
        let (chat, _, viewModel) = makeChat(script: [text("这是讲解。")])
        await ask(chat, "问")

        viewModel.updateCurrentFenComment("原有笔记")
        let answer = try! #require(chat.messages.last)
        chat.saveAnswerAsComment(answer)

        // 追加而不是覆盖——用户自己写的笔记不能被冲掉
        #expect(viewModel.currentFenComment == "原有笔记\n\n这是讲解。")
        #expect(chat.messages.last?.savedToComment == true)
    }

    @Test func testSaveAnswerAsComment_intoEmptyCommentHasNoLeadingBlankLines() async {
        let (chat, _, viewModel) = makeChat(script: [text("这是讲解。")])
        await ask(chat, "问")

        chat.saveAnswerAsComment(try! #require(chat.messages.last))
        #expect(viewModel.currentFenComment == "这是讲解。")
    }

    @Test func testSaveAnswerAsComment_isIdempotent() async {
        let (chat, _, viewModel) = makeChat(script: [text("这是讲解。")])
        await ask(chat, "问")

        let answer = try! #require(chat.messages.last)
        chat.saveAnswerAsComment(answer)
        chat.saveAnswerAsComment(answer)
        #expect(viewModel.currentFenComment == "这是讲解。", "重复点击不该存两遍")
    }

    @Test func testSaveAnswerAsComment_ignoresUserMessages() async {
        let (chat, _, viewModel) = makeChat(script: [text("这是讲解。")])
        await ask(chat, "问")

        chat.saveAnswerAsComment(try! #require(chat.messages.first))
        #expect(viewModel.currentFenComment == nil)
    }

    @Test func testSaveAnswerAsComment_stripsMarkdown() async {
        // 界面渲染 markdown，但注释区是纯文本，落盘前必须剥干净——
        // 这是持久化数据，脏了要用户手工改
        let (chat, _, viewModel) = makeChat(script: [
            text("## 结论\n\n**炮8进5** 是失着。\n\n- 没有强制手\n- 交出了先手"),
        ])
        await ask(chat, "问")
        chat.saveAnswerAsComment(try! #require(chat.messages.last))

        let comment = try! #require(viewModel.currentFenComment)
        #expect(!comment.contains("**"))
        #expect(!comment.contains("##"))
        #expect(comment.contains("炮8进5 是失着。"))
        #expect(comment.contains("· 没有强制手"))
    }

    // MARK: - 快捷提问

    @Test func testAsk_sendsImmediately() async {
        let (chat, _, _) = makeChat(script: [text("这个局面黑方略优。")])
        chat.ask(ViewModel.AIQuickQuestion.analyzePosition)
        await waitUntilIdle(chat)

        #expect(chat.messages.first?.text == ViewModel.AIQuickQuestion.analyzePosition)
        #expect(chat.messages.last?.text == "这个局面黑方略优。")
        #expect(chat.input.isEmpty)
    }

    @Test func testAsk_whileRunningParksTheQuestionInsteadOfDroppingIt() async {
        // 跑着的时候再点「问 AI」不能把问题吞掉——用户看不到任何反应会以为按钮坏了
        let (chat, _, _) = makeChat(script: [toolCall("get_position"), text("好。")])
        chat.input = "第一个问题"
        chat.send()
        chat.ask("第二个问题")
        #expect(chat.input == "第二个问题")
        await waitUntilIdle(chat)
        // 只发出去一轮，第二个问题留在输入框里等用户自己决定
        #expect(chat.messages.filter { $0.kind == .user }.map(\.text) == ["第一个问题"])
    }

    // MARK: - 上一步（问「这一步为什么不好」靠它）

    /// 走了一步之后的会话：currentGame2 有两个局面，停在第 1 步
    private func makeViewModelAfterOneMove() -> ViewModel {
        let afterFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C4/9/RNBAKABNR b"
        let database = TestDatabaseBuilder()
            .addFen(1, fen: Self.startFen, inRedOpening: true)
            .addFen(2, fen: afterFen, inRedOpening: true)
            .addMove(from: 1, to: 2)
            .build()
        let sessionData = SessionData()
        let databaseView = DatabaseView.full(database: database)
        sessionData.currentGame2 = [1, 2]
        sessionData.currentGameStep = 1
        let session = try! Session(sessionData: sessionData, databaseView: databaseView)
        let sessionManager = SessionManager(mainSession: session, database: database)
        return ViewModel(sessionManager: sessionManager, platformService: StubPlatformService())
    }

    @Test func testSnapshot_lastMoveCarriesTheMoveAndThePositionBeforeIt() throws {
        // 这是「为什么这一步不好」能答对的前提：fenBefore 必须是走之前的局面，
        // 拿当前局面去评估就变成在评对方的下一手了
        let snapshot = makeViewModelAfterOneMove().currentPositionSnapshot()
        let lastMove = try #require(snapshot.lastMove)
        #expect(lastMove.fenBefore.hasPrefix("rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1"))
        #expect(lastMove.fenBefore != snapshot.fen)
        // 着法名按未翻转棋盘生成，与工具层其他地方口径一致
        #expect(lastMove.chinese == "炮二平五")
    }

    @Test func testSnapshot_lastMoveIsNilAtStartingPosition() {
        // 停在起始局面时没有「上一步」，不能给个假的让模型去评估
        #expect(makeViewModel().currentPositionSnapshot().lastMove == nil)
    }

    // MARK: - 分析缓存的定位

    @Test func testNotebookFenId_matchesRegardlessOfMoveCounters() throws {
        // 缓存全靠这一步定位。fen 的着数后缀形式不统一（工具返回的、
        // apply_moves 生成的、库里存的各不相同），不归一化就会永远查不中——
        // 而且是静默的：功能照常，只是每次都重算，看不出坏在哪
        let viewModel = makeViewModel()
        let stored = try #require(viewModel.notebookFenId(for: Self.startFen))

        let bare = String(Self.startFen.split(separator: "-")[0])
            .trimmingCharacters(in: .whitespaces)
        #expect(viewModel.notebookFenId(for: bare) == stored, "不带着数后缀的写法应指向同一个局面")
        #expect(viewModel.notebookFenId(for: bare + " - - 0 1") == stored)
    }

    @Test func testNotebookFenId_isNilForPositionsOutsideTheNotebook() {
        // 探索性变着不入库，也就不缓存——这正是缓存规模被笔记本封顶的原因
        let afterFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C4/9/RNBAKABNR b"
        #expect(makeViewModel().notebookFenId(for: afterFen) == nil)
    }

    // MARK: - Token 用量与花费

    private func text(_ body: String, usage: TokenUsage) -> Result<LLMResponse, LLMError> {
        .success(LLMResponse(content: body, toolCalls: [], usage: usage))
    }

    private func toolCall(_ name: String, usage: TokenUsage) -> Result<LLMResponse, LLMError> {
        .success(LLMResponse(content: nil,
                             toolCalls: [LLMToolCall(id: "c1", name: name, argumentsJSON: "{}")],
                             usage: usage))
    }

    @Test func testUsage_accumulatesAcrossToolLoopSteps() async {
        // 循环每走一步都要把整段对话重发一遍，用量必须累加成一条回答的总账，
        // 只记最后一次会严重低报
        let (chat, _, _) = makeChat(script: [
            toolCall("get_position", usage: TokenUsage(promptTokens: 4000, cachedTokens: 0,
                                                      completionTokens: 120)),
            text("现在轮红方走。", usage: TokenUsage(promptTokens: 4500, cachedTokens: 3900,
                                                 completionTokens: 380)),
        ])
        await ask(chat, "问")

        let usage = try! #require(chat.messages.last?.usage)
        #expect(usage.promptTokens == 8500)
        #expect(usage.cachedTokens == 3900)
        #expect(usage.completionTokens == 500)
    }

    @Test func testUsage_isNilWhenServerNeverReportsIt() async {
        // 显示 0 tokens 看起来像「没花钱」，实际是「不知道」——宁可不显示
        let (chat, _, _) = makeChat(script: [text("好。")])
        await ask(chat, "问")
        #expect(chat.messages.last?.usage == nil)
        #expect(chat.messages.last?.costText == nil)
    }

    @Test func testCostText_isNilWithoutConfiguredPricing() async {
        let (chat, _, _) = makeChat(script: [
            text("好。", usage: TokenUsage(promptTokens: 4000, completionTokens: 200)),
        ])
        await ask(chat, "问")
        #expect(chat.messages.last?.usage != nil)
        #expect(chat.messages.last?.costText == nil, "没填单价就不该报金额")
    }

    @Test func testCostText_usesConfiguredPricing() async {
        let viewModel = makeViewModel()
        var config = configured
        config.pricing = AIPricing(currency: "$", inputPerMillion: 0.3,
                                   outputPerMillion: 1.2, cachedPerMillion: 0.06)
        let client = ScriptedClient([
            // 100 万非缓存输入 + 100 万输出 = 0.3 + 1.2
            text("好。", usage: TokenUsage(promptTokens: 1_000_000, cachedTokens: 0,
                                          completionTokens: 1_000_000)),
        ])
        let chat = ChatViewModel(viewModel: viewModel, config: config,
                                 clientFactory: { _ in client })
        await ask(chat, "问")

        #expect(chat.messages.last?.costText == "$1.5000")
    }
}
