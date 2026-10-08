#if os(iOS)
import Foundation

/// 手机直接使用已保存的 OAuth 授权，工具仍由 ChatViewModel 在本机执行。
struct ChatGPTSubscriptionClient: LLMSending {
    let config: AIConfig
    var session: URLSession = .shared
    var tokenProvider: () async throws -> String = {
        try await ChatGPTSubscriptionProbe.subscriptionAccessToken()
    }

    func send(messages: [LLMMessage], tools: [[String: Any]],
              onReasoning: @escaping (String) -> Void) async throws -> LLMResponse {
        try Task.checkCancellation()
        let token = try await tokenProvider()
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try Self.requestBody(messages: messages, tools: tools, effort: config.codexReasoningEffort)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                if status == 401 || status == 403 {
                    throw LLMError.badRequest("ChatGPT 授权无效或不可用，请在 AI 设置里重新登录。")
                }
                if status == 429 { throw LLMError.rateLimited }
                if status >= 500 { throw LLMError.serverError(status) }
                throw LLMError.badRequest("ChatGPT 订阅请求失败（HTTP \(status)），请检查账号授权和模型权限。")
            }
            var stream = StreamOutput()
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data: "),
                      let data = String(line.dropFirst(6)).data(using: .utf8),
                      let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                stream.consume(event)
                switch event["type"] as? String {
                case "response.reasoning_summary_text.delta":
                    if let delta = event["delta"] as? String { onReasoning(delta) }
                case "response.completed":
                    guard let response = event["response"] as? [String: Any] else {
                        throw LLMError.malformedResponse("ChatGPT 完成事件缺少响应")
                    }
                    return try Self.completedResponse(stream.merging(into: response))
                case "response.failed", "response.incomplete", "error":
                    let response = event["response"] as? [String: Any]
                    let error = response?["error"] as? [String: Any] ?? event["error"] as? [String: Any]
                    if let code = error?["code"] as? String,
                       code == "subscription_sharing_usage_limit_exceeded" || code == "subscription_sharing_usage_unavailable" {
                        throw LLMError.badRequest("当前 ChatGPT 订阅额度已用完或暂不可用，请等待额度恢复后重试。")
                    }
                    throw LLMError.badRequest("ChatGPT 未完成回答，请检查订阅额度或稍后重试。")
                default: break
                }
            }
            throw LLMError.malformedResponse("ChatGPT 连接中断，未收到完整回答，请重试")
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw LLMError.timeout(seconds: 180) }
            throw LLMError.network(error.localizedDescription)
        }
    }

    static func requestBody(messages: [LLMMessage], tools: [[String: Any]],
                            effort: CodexReasoningEffort) throws -> Data {
        var input: [[String: Any]] = []
        for message in messages {
            // 回传原始 output，保留 reasoning.encrypted_content 与 call_id 的配对。
            if message.role == .assistant, let data = message.responsesOutput,
               let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                input.append(contentsOf: items)
                continue
            }
            if message.role == .tool {
                guard let id = message.toolCallId else { throw LLMError.malformedResponse("工具结果缺少调用 ID") }
                input.append(["type": "function_call_output", "call_id": id, "output": message.content ?? ""])
                continue
            }
            if let content = message.content, !content.isEmpty {
                input.append(["role": message.role == .system ? "developer" : message.role.rawValue, "content": content])
            }
            for call in message.toolCalls {
                input.append(["type": "function_call", "call_id": call.id, "namespace": "xiangqi", "name": call.name, "arguments": call.argumentsJSON])
            }
        }
        let functions = try tools.map { tool -> [String: Any] in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let parameters = function["parameters"] as? [String: Any] else {
                throw LLMError.malformedResponse("工具定义格式无效")
            }
            return ["type": "function", "name": name, "description": function["description"] as? String ?? "",
                    "parameters": parameters, "strict": false]
        }
        return try JSONSerialization.data(withJSONObject: [
            "model": "gpt-6.1-sol", "reasoning": ["effort": effort.rawValue],
            "input": input, "tools": functions.isEmpty ? [] : [["type": "namespace", "name": "xiangqi", "description": "象棋笔记本局面和皮卡鱼分析工具", "tools": functions]], "store": false, "stream": true,
            "include": ["reasoning.encrypted_content"],
        ])
    }

    /// 完成事件可能不再携带已流出的 output；保留每个已完成的 item。
    struct StreamOutput {
        private var items: [Int: [String: Any]] = [:]

        mutating func consume(_ event: [String: Any]) {
            guard event["type"] as? String == "response.output_item.done",
                  let index = event["output_index"] as? Int,
                  let item = event["item"] as? [String: Any] else { return }
            items[index] = item
        }

        func merging(into response: [String: Any]) -> [String: Any] {
            var result = response
            var merged = items
            for (index, item) in (response["output"] as? [[String: Any]] ?? []).enumerated() {
                // 优先使用已完成 item，避免最终快照覆盖完整正文或 encrypted_content。
                if merged[index] == nil { merged[index] = item }
            }
            result["output"] = merged.keys.sorted().compactMap { merged[$0] }
            return result
        }
    }

    static func completedResponse(_ response: [String: Any]) throws -> LLMResponse {
        guard response["status"] as? String == "completed",
              let output = response["output"] as? [[String: Any]] else {
            throw LLMError.malformedResponse("ChatGPT 回答未完成")
        }
        var text = ""
        var calls: [LLMToolCall] = []
        for item in output {
            switch item["type"] as? String {
            case "message":
                for part in item["content"] as? [[String: Any]] ?? [] {
                    if part["type"] as? String == "output_text" { text += part["text"] as? String ?? "" }
                    if part["type"] as? String == "refusal" { text += part["refusal"] as? String ?? "" }
                }
            case "function_call":
                guard let id = item["call_id"] as? String, !id.isEmpty,
                      let name = item["name"] as? String, !name.isEmpty,
                      let arguments = item["arguments"] as? String else {
                    throw LLMError.malformedResponse("ChatGPT 工具调用缺少参数")
                }
                calls.append(LLMToolCall(id: id, name: name, argumentsJSON: arguments))
            default: break
            }
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !calls.isEmpty else {
            let types = output.compactMap { $0["type"] as? String }.joined(separator: ", ")
            let responseID = response["id"] as? String ?? "未知"
            throw LLMError.malformedResponse("ChatGPT 完成了请求，但没有可显示的回答（output: \(types.isEmpty ? "空" : types)；请求 ID: \(responseID)）")
        }
        var usage: TokenUsage?
        if let values = response["usage"] as? [String: Any],
           let input = values["input_tokens"] as? Int, let output = values["output_tokens"] as? Int {
            let details = values["input_tokens_details"] as? [String: Any]
            usage = TokenUsage(promptTokens: input, cachedTokens: details?["cached_tokens"] as? Int ?? 0, completionTokens: output)
        }
        var result = LLMResponse(content: text.isEmpty ? nil : text, toolCalls: calls, usage: usage)
        result.responsesOutput = try JSONSerialization.data(withJSONObject: output)
        return result
    }
}
#endif
