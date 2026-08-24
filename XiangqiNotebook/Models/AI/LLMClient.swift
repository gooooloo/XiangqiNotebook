import Foundation

// MARK: - 消息模型

/// 模型请求 / 返回的一次工具调用
struct LLMToolCall: Equatable, Identifiable {
    let id: String
    let name: String
    /// 参数原文（JSON 字符串），交给 `AnalysisToolbox.parseArgumentsJSON` 解析
    let argumentsJSON: String
}

/// 对话中的一条消息。
/// 形状对齐 OpenAI Chat Completions：assistant 可带 tool_calls，
/// tool 角色的消息必须带 tool_call_id 与之配对。
struct LLMMessage: Equatable {
    enum Role: String {
        case system, user, assistant, tool
    }

    let role: Role
    let content: String?
    let toolCalls: [LLMToolCall]
    let toolCallId: String?

    init(role: Role, content: String?, toolCalls: [LLMToolCall] = [], toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    static func system(_ text: String) -> LLMMessage { LLMMessage(role: .system, content: text) }
    static func user(_ text: String) -> LLMMessage { LLMMessage(role: .user, content: text) }

    static func assistant(_ text: String?, toolCalls: [LLMToolCall]) -> LLMMessage {
        LLMMessage(role: .assistant, content: text, toolCalls: toolCalls)
    }

    static func toolResult(callId: String, content: String) -> LLMMessage {
        LLMMessage(role: .tool, content: content, toolCallId: callId)
    }

    /// 序列化成请求体里的一条消息（纯函数，便于单测）
    func wireDictionary() -> [String: Any] {
        var dict: [String: Any] = ["role": role.rawValue]

        // assistant 带 tool_calls 时 content 可以为 null，但字段本身不能缺——
        // 部分兼容实现会因缺字段报 400
        dict["content"] = content as Any? ?? NSNull()

        if !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.argumentsJSON],
                ] as [String: Any]
            }
        }
        if let toolCallId {
            dict["tool_call_id"] = toolCallId
        }
        return dict
    }
}

/// 一轮请求消耗的 token。数值由服务端回报，不本地估算——
/// 各家分词器不同，自己数出来的与账单对不上，还不如不显示
struct TokenUsage: Equatable {
    let promptTokens: Int
    /// promptTokens 中命中缓存的部分（含在 promptTokens 里，不另算）。
    /// 工具循环每一步都要重发整段 system prompt 与工具 schema，缓存命中率很高，
    /// 而各家缓存读取价常只有输入价的几分之一——不单列出来，估价会明显偏高
    let cachedTokens: Int
    let completionTokens: Int

    var totalTokens: Int { promptTokens + completionTokens }

    static let zero = TokenUsage(promptTokens: 0, completionTokens: 0)

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(promptTokens: lhs.promptTokens + rhs.promptTokens,
                   cachedTokens: lhs.cachedTokens + rhs.cachedTokens,
                   completionTokens: lhs.completionTokens + rhs.completionTokens)
    }

    init(promptTokens: Int, cachedTokens: Int = 0, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.cachedTokens = cachedTokens
        self.completionTokens = completionTokens
    }

    /// 从响应里的 `usage` 字段解析；字段缺失或形状不对返回 nil。
    /// 缓存命中数在 `prompt_tokens_details.cached_tokens`，不报就当 0
    init?(json: [String: Any]) {
        guard let prompt = json["prompt_tokens"] as? Int,
              let completion = json["completion_tokens"] as? Int else { return nil }
        let details = json["prompt_tokens_details"] as? [String: Any]
        self.init(promptTokens: prompt,
                  cachedTokens: (details?["cached_tokens"] as? Int) ?? 0,
                  completionTokens: completion)
    }

    /// 页脚空间有限，上千就折成「24.1k」
    var compactDescription: String {
        totalTokens < 1000
            ? "\(totalTokens) tokens"
            : String(format: "%.1fk tokens", Double(totalTokens) / 1000)
    }
}

/// 一轮请求的结果
struct LLMResponse: Equatable {
    let content: String?
    let toolCalls: [LLMToolCall]
    /// 服务端回报的用量；没开或不支持 `stream_options` 时为 nil
    let usage: TokenUsage?

    init(content: String?, toolCalls: [LLMToolCall], usage: TokenUsage? = nil) {
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

// MARK: - 错误

/// 面向用户的错误分类。文案直接显示在对话界面上，所以说人话、给下一步动作。
enum LLMError: Error, LocalizedError, Equatable {
    case notConfigured
    case invalidBaseURL
    case unauthorized
    case rateLimited
    case toolsUnsupported
    case badRequest(String)
    case serverError(Int)
    case timeout(seconds: Int)
    case network(String)
    case malformedResponse(String)
    // Claude Code（订阅）线路专用
    case bridgeUnreachable
    case claudeNotLoggedIn
    case claudeNotFound

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未配置 AI 服务，请先在设置里填写服务地址、模型与 API key。"
        case .invalidBaseURL:
            return "服务地址无效，应形如 https://api.deepseek.com/v1。"
        case .unauthorized:
            return "API key 无效或已过期。"
        case .rateLimited:
            return "请求过于频繁，稍后再试。"
        case .toolsUnsupported:
            return "该模型不支持工具调用，无法使用引擎分析。请换一个支持 function calling 的模型。"
        case .badRequest(let detail):
            return "请求被拒绝：\(detail)"
        case .serverError(let code):
            return "服务端出错（HTTP \(code)），稍后再试。"
        case .timeout(let seconds):
            // 不要笼统说「连不上」——那会让人去查网络，而网络多半是通的
            return "等模型回复超过 \(seconds) 秒。推理型模型拿到局面后思考较久，可以再试一次；"
                + "若反复超时，换一个响应更快的模型。"
        case .network(let detail):
            return "连不上服务：\(detail)"
        case .malformedResponse(let detail):
            return "返回内容看不懂：\(detail)"
        case .bridgeUnreachable:
            return "连不上 Claude 桥接服务（127.0.0.1:9216）。请先启动它："
                + "在仓库目录运行 node mcp/claude-bridge.mjs，"
                + "或按 mcp/README.md 安装 launchd 常驻服务。"
        case .claudeNotLoggedIn:
            return "本机 claude 尚未登录。在终端运行 claude 完成订阅登录后再试。"
        case .claudeNotFound:
            return "本机没找到 claude 命令。安装 Claude Code 并登录后，重启桥接服务再试。"
        }
    }

    /// 换个 key 或换个模型才有用的错误，重试按钮没有意义
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .timeout, .network,
             // 起桥接 / 登录之后重试就能过，按钮留着
             .bridgeUnreachable, .claudeNotLoggedIn: return true
        case .notConfigured, .invalidBaseURL, .unauthorized,
             .toolsUnsupported, .badRequest, .malformedResponse, .claudeNotFound: return false
        }
    }
}

// MARK: - 客户端

/// Claude Code 线路上工具在 claude 进程内部执行、app 的循环看不见，
/// 客户端把过程透传出来，供界面生成与其他线路一致的工具轨迹。
/// `name` 已剥掉 MCP 前缀（evaluate 而非 mcp__xiangqi-notebook__evaluate），
/// `AnalysisToolbox.progressDescription` / `resultSummary` 可直接用。
enum LLMToolEvent: Equatable {
    case started(name: String, argumentsJSON: String)
    case finished(name: String, argumentsJSON: String, resultJSON: String)
}

/// 发一轮对话请求的能力。
/// 抽成协议只为一件事：让 `ChatViewModel` 的工具循环能在单测里被脚本化驱动，
/// 不必发真网络也不必配真 key。
protocol LLMSending {
    /// - Parameter onReasoning: 收到思考片段时回调，供界面显示模型正在想什么。
    ///   在流式请求的读取循环里调用，实现方应假设它可能被调用很多次。
    func send(messages: [LLMMessage],
              tools: [[String: Any]],
              onReasoning: @escaping (String) -> Void) async throws -> LLMResponse

    /// 带工具事件回调的版本。工具在客户端内部执行的线路（Claude Code）必须实现它；
    /// 其余线路的工具由调用方执行，用协议扩展里的默认实现（忽略回调）即可。
    /// 必须是协议 requirement 而不能只放扩展——否则经 existential 调用时
    /// 静态派发到默认实现，真正的实现永远不会被调到。
    func send(messages: [LLMMessage],
              tools: [[String: Any]],
              onReasoning: @escaping (String) -> Void,
              onToolEvent: @escaping (LLMToolEvent) -> Void) async throws -> LLMResponse
}

extension LLMSending {
    func send(messages: [LLMMessage], tools: [[String: Any]]) async throws -> LLMResponse {
        try await send(messages: messages, tools: tools, onReasoning: { _ in })
    }

    /// 默认忽略工具事件，转调三参版——`LLMClient` 与既有测试替身零改动
    func send(messages: [LLMMessage],
              tools: [[String: Any]],
              onReasoning: @escaping (String) -> Void,
              onToolEvent: @escaping (LLMToolEvent) -> Void) async throws -> LLMResponse {
        try await send(messages: messages, tools: tools, onReasoning: onReasoning)
    }
}

/// 按线路格式挑客户端。单点分派：新增一种格式时只有这里要改，调用处不必知道有几种
enum LLMClientFactory {
    static func make(config: AIConfig, session: URLSession = .shared) -> LLMSending {
        switch config.wireFormat {
        case .openAICompatible:
            return LLMClient(config: config, session: session)
        case .claudeCode:
            return ClaudeCodeClient(config: config, session: session)
        }
    }
}

/// OpenAI 兼容的 Chat Completions 客户端。
///
/// 只做这一种格式：DeepSeek、Kimi、智谱、通义、豆包、OpenAI、本机 Ollama
/// 都提供兼容端点，一套 adapter 通吃。
///
/// **走流式（SSE）**。最初做的是非流式，理由是「问棋的时间大头在引擎思考、不在文字生成」——
/// 那话对输出长度成立，对推理模型的思考时间不成立。`timeoutInterval` 计的是「等待下一段
/// 数据」的间隔，非流式下服务端要整段生成完才回传，模型思考一两分钟就会直接超时（实测撞到）。
/// 流式下数据持续到达，超时窗口不断刷新，顺带还能把思考进度显示给用户。
struct LLMClient: LLMSending {

    let config: AIConfig
    let session: URLSession

    /// 两段数据之间的最大间隔。流式下每来一片就重新计时，
    /// 所以这是「模型卡住多久算失败」而不是「整轮最多跑多久」
    static let requestTimeout: TimeInterval = 180

    init(config: AIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// 发一轮请求。工具调用循环由调用方驱动（见 `ChatViewModel`）。
    func send(messages: [LLMMessage],
              tools: [[String: Any]],
              onReasoning: @escaping (String) -> Void) async throws -> LLMResponse {
        guard config.isConfigured else { throw LLMError.notConfigured }
        guard let url = config.chatCompletionsURL else { throw LLMError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Self.requestBody(
            model: config.model, messages: messages, tools: tools, stream: true)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw Self.transportError(from: error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // 错误响应是普通 JSON 而非 SSE，整段读出来再分类
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.error(forStatus: status, body: body)
        }

        var accumulator = LLMStreamAccumulator()
        do {
            for try await line in bytes.lines {
                guard let payload = Self.sseDataPayload(from: line) else { continue }
                let shouldContinue = accumulator.consume(dataPayload: payload)
                if let chunk = accumulator.latestReasoningChunk { onReasoning(chunk) }
                if !shouldContinue { break }
            }
        } catch {
            throw Self.transportError(from: error)
        }
        return try accumulator.finish()
    }

    /// 从一行 SSE 里取出 `data:` 后面的负载；注释行、事件名行与空行返回 nil
    static func sseDataPayload(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }

    /// 传输层错误分类。注意：不要把 request 或其 header 带进错误信息，
    /// Authorization 会跟着泄漏进日志
    static func transportError(from error: Error) -> LLMError {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return .network(nsError.localizedDescription)
        }
        return nsError.code == NSURLErrorTimedOut
            ? .timeout(seconds: Int(requestTimeout))
            : .network(nsError.localizedDescription)
    }

    // MARK: 请求构造（纯函数，便于单测）

    static func requestBody(model: String, messages: [LLMMessage],
                            tools: [[String: Any]], stream: Bool = false) throws -> Data {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.wireDictionary() },
            "stream": stream,
        ]
        if stream {
            // 流式默认不回报用量，要显式索取，否则估不出这次问答花了多少钱。
            // 这是 OpenAI 兼容规范里的标准字段，不认的实现一般会忽略而非报错
            body["stream_options"] = ["include_usage": true]
        }
        if !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw LLMError.malformedResponse("请求体序列化失败")
        }
    }

    // MARK: 错误分类（纯函数，便于单测）

    static func error(forStatus status: Int, body: Data) -> LLMError {
        let message = errorMessage(from: body)

        switch status {
        case 401, 403:
            return .unauthorized
        case 429:
            return .rateLimited
        case 400..<500:
            // 不支持工具的模型多半在这里报错，措辞各家不同，抓关键词
            let lowered = message.lowercased()
            let mentionsTools = ["tool", "function call", "function_call", "tools"]
                .contains { lowered.contains($0) }
            if mentionsTools {
                return .toolsUnsupported
            }
            return .badRequest(message.isEmpty ? "HTTP \(status)" : message)
        default:
            return .serverError(status)
        }
    }

    /// 从错误响应体里挖出人能读的说明；挖不到就返回空串
    static func errorMessage(from body: Data) -> String {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return String(data: body, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if let error = root["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let message = error["msg"] as? String { return message }
        }
        if let message = root["message"] as? String { return message }
        if let message = root["msg"] as? String { return message }
        return ""
    }
}
