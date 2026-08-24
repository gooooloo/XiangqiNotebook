import Foundation

/// 「Claude Code（订阅）」线路客户端。
///
/// 不直连任何 LLM 服务：请求发给本机桥接进程（mcp/claude-bridge.mjs，127.0.0.1:9216），
/// 由它在沙盒外 spawn `claude -p` 用本机 Claude Code 的订阅登录跑——沙盒内的 app
/// 自己 spawn 不了 claude（子进程继承沙盒，读不了 ~/.claude 与钥匙串凭据）。
///
/// 工具循环在 claude 进程内部（经 MCP → localhost:9214），app 的循环看不见——
/// 本客户端把过程透传成 `LLMToolEvent` 供界面留痕；`send` 一次返回终稿、
/// `toolCalls` 恒空，`ChatViewModel` 的循环第一轮即收敛。
///
/// 多轮对话走无状态重放：把历史渲染成 transcript 随每次请求发出，由桥接拼进 prompt。
/// 刻意不用 claude 的 --resume：app 侧 wireMessages 是唯一真相源，取消/失败后
/// 剪本地数组即可回滚；有状态 session 会与它漂移。
struct ClaudeCodeClient: LLMSending {

    let config: AIConfig
    let session: URLSession

    static let chatURL = URL(string: "http://127.0.0.1:9216/chat")!
    static let healthURL = URL(string: "http://127.0.0.1:9216/health")!
    static let tokenHeaderName = "X-ClaudeBridge-Token"
    /// 片间超时，语义同 `LLMClient.requestTimeout`。桥接每 15 秒发一次 ping 心跳，
    /// 真超时说明桥接或 claude 卡死了
    static let requestTimeout: TimeInterval = 180

    init(config: AIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - 发送

    func send(messages: [LLMMessage],
              tools: [[String: Any]],
              onReasoning: @escaping (String) -> Void) async throws -> LLMResponse {
        try await send(messages: messages, tools: tools,
                       onReasoning: onReasoning, onToolEvent: { _ in })
    }

    /// `tools` 参数整个忽略：工具 schema 由 MCP server 提供给 claude，这里用不上
    func send(messages: [LLMMessage],
              tools: [[String: Any]],
              onReasoning: @escaping (String) -> Void,
              onToolEvent: @escaping (LLMToolEvent) -> Void) async throws -> LLMResponse {
        guard let token = Self.readBridgeToken() else {
            // token 文件是桥接启动时写的，读不到 = 桥接没跑过
            throw LLMError.bridgeUnreachable
        }

        var request = URLRequest(url: Self.chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: Self.tokenHeaderName)
        request.httpBody = try Self.requestBody(messages: messages, model: config.claudeModel)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw Self.transportError(from: error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.error(forStatus: status, body: body)
        }

        // tool_result 事件只带 id，短名与参数从对应的 tool_use 里记下来配对
        var pendingTools: [String: (name: String, argumentsJSON: String)] = [:]
        var final: LLMResponse?
        do {
            for try await line in bytes.lines {
                guard let event = Self.parseEvent(line: line) else { continue }
                switch event {
                case .text, .ping:
                    break // 只当活性信号（刷新片间超时）；终稿以 done.result 为准
                case .thinking(let delta):
                    onReasoning(delta)
                case .toolUse(let id, let name, let argumentsJSON):
                    let short = Self.shortToolName(name)
                    pendingTools[id] = (short, argumentsJSON)
                    onToolEvent(.started(name: short, argumentsJSON: argumentsJSON))
                case .toolResult(let id, let content, _):
                    let pending = pendingTools.removeValue(forKey: id) ?? ("", "")
                    onToolEvent(.finished(name: pending.name,
                                          argumentsJSON: pending.argumentsJSON,
                                          resultJSON: content))
                case .done(let result, let usage):
                    final = LLMResponse(content: result, toolCalls: [], usage: usage)
                case .error(let code, let message):
                    throw Self.error(forBridgeCode: code, message: message)
                }
                if final != nil { break }
            }
        } catch let error as LLMError {
            throw error
        } catch {
            throw Self.transportError(from: error)
        }

        guard let final else {
            throw LLMError.malformedResponse("桥接流在给出结果前就结束了")
        }
        return final
    }

    // MARK: - 健康检查（设置页「测试连接」用）

    struct BridgeHealth: Equatable {
        /// "max" / "pro"，桥接读不出来时为 nil
        let subscriptionType: String?
    }

    static func health(session: URLSession = .shared) async throws -> BridgeHealth {
        guard let token = readBridgeToken() else { throw LLMError.bridgeUnreachable }
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 15
        request.setValue(token, forHTTPHeaderField: tokenHeaderName)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw transportError(from: error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw error(forStatus: status, body: data) }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw LLMError.malformedResponse("health 响应不是 JSON")
        }
        guard json["ok"] as? Bool == true else {
            throw error(forBridgeCode: json["code"] as? String ?? "",
                        message: json["message"] as? String ?? "")
        }
        return BridgeHealth(subscriptionType: json["subscriptionType"] as? String)
    }

    // MARK: - token 文件

    /// 桥接进程启动时把随机 token 写进 app 沙盒容器（方向与 RemoteControlServer 相反：
    /// 那边 app 写、外部工具读）。token 每次桥接启动都会变，所以每次请求都重新读
    static func bridgeTokenFileURL() -> URL? {
        (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: false))?
            .appendingPathComponent("XiangqiNotebook/claude-bridge-token.txt")
    }

    static func readBridgeToken() -> String? {
        guard let url = bridgeTokenFileURL(),
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - 请求构造（纯函数，便于单测）

    /// 把 wireMessages 变成桥接请求体：`.system` 抽出作 systemPrompt，最后一条 `.user`
    /// 是本次提问，其余 user/assistant 依序进 transcript。本线路一轮收敛，历史里不该有
    /// tool 角色消息与 toolCalls——真出现也只丢弃工具部分，正文照带。
    static func requestBody(messages: [LLMMessage], model: String) throws -> Data {
        var systemPrompt: String?
        var turns: [[String: String]] = []
        for message in messages {
            switch message.role {
            case .system:
                systemPrompt = message.content
            case .user, .assistant:
                guard let text = message.content, !text.isEmpty else { continue }
                turns.append(["role": message.role.rawValue, "text": text])
            case .tool:
                continue
            }
        }

        var question = ""
        if let last = turns.last, last["role"] == LLMMessage.Role.user.rawValue {
            question = last["text"] ?? ""
            turns.removeLast()
        }

        var body: [String: Any] = [
            "question": question,
            "transcript": turns,
        ]
        if let systemPrompt, !systemPrompt.isEmpty {
            body["systemPrompt"] = systemPrompt
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            body["model"] = trimmedModel
        }
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw LLMError.malformedResponse("请求体序列化失败")
        }
    }

    // MARK: - NDJSON 事件解析（纯函数，便于单测）

    /// 桥接 NDJSON 流里的一个事件（契约见 mcp/claude-bridge.mjs 的转译表）
    enum BridgeEvent: Equatable {
        case text(String)
        case thinking(String)
        case ping
        case toolUse(id: String, name: String, argumentsJSON: String)
        case toolResult(id: String, content: String, isError: Bool)
        case done(result: String, usage: TokenUsage?)
        case error(code: String, message: String)
    }

    /// 解析一行 NDJSON；空行、坏 JSON、未知 type 一律返回 nil（桥接升级时尽量不断流）
    static func parseEvent(line: String) -> BridgeEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = json["type"] as? String else { return nil }

        switch type {
        case "text":
            return (json["delta"] as? String).map { .text($0) }
        case "thinking":
            return (json["delta"] as? String).map { .thinking($0) }
        case "ping":
            return .ping
        case "tool_use":
            return .toolUse(
                id: json["id"] as? String ?? "",
                name: json["name"] as? String ?? "",
                // 转回 JSON 字符串，与 OpenAI 线路的 argumentsJSON 同一形状，
                // 供 AnalysisToolbox.parseArgumentsJSON 解析
                argumentsJSON: AnalysisToolbox.json(json["input"] as? [String: Any] ?? [:]))
        case "tool_result":
            return .toolResult(
                id: json["id"] as? String ?? "",
                content: json["content"] as? String ?? "",
                isError: json["isError"] as? Bool ?? false)
        case "done":
            let usage = (json["usage"] as? [String: Any]).flatMap { raw -> TokenUsage? in
                guard let prompt = raw["promptTokens"] as? Int,
                      let completion = raw["completionTokens"] as? Int else { return nil }
                return TokenUsage(promptTokens: prompt,
                                  cachedTokens: raw["cachedTokens"] as? Int ?? 0,
                                  completionTokens: completion)
            }
            return .done(result: json["result"] as? String ?? "", usage: usage)
        case "error":
            return .error(code: json["code"] as? String ?? "",
                          message: json["message"] as? String ?? "")
        default:
            return nil
        }
    }

    /// 剥掉 MCP 工具名前缀（mcp__xiangqi-notebook__evaluate → evaluate），
    /// 让 `AnalysisToolbox.progressDescription` / `resultSummary` 直接可用
    static func shortToolName(_ raw: String) -> String {
        guard raw.hasPrefix("mcp__") else { return raw }
        let parts = raw.components(separatedBy: "__")
        guard parts.count >= 3 else { return raw }
        return parts.dropFirst(2).joined(separator: "__")
    }

    // MARK: - 错误映射（纯函数，便于单测）

    static func error(forBridgeCode code: String, message: String) -> LLMError {
        switch code {
        case "CLAUDE_NOT_LOGGED_IN": return .claudeNotLoggedIn
        case "CLAUDE_NOT_FOUND": return .claudeNotFound
        default: return .badRequest(message.isEmpty ? code : message)
        }
    }

    static func error(forStatus status: Int, body: Data) -> LLMError {
        switch status {
        case 403:
            // token 对不上：app 读到的文件是旧桥接实例写的（比如起了两个桥接）。
            // 归为可重试的网络类问题，提示指向重启桥接
            return .network("桥接鉴权不匹配，重启桥接服务后再试")
        case 409:
            // 单飞行槽被占。ChatViewModel 本就串行，撞上说明有别的客户端在用
            return .rateLimited
        default:
            let message = LLMClient.errorMessage(from: body)
            return .badRequest(message.isEmpty ? "HTTP \(status)" : message)
        }
    }

    /// 连接被拒（桥接没在跑）单独识别，其余沿用 LLMClient 的传输层分类
    static func transportError(from error: Error) -> LLMError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCannotConnectToHost {
            return .bridgeUnreachable
        }
        return LLMClient.transportError(from: error)
    }
}
