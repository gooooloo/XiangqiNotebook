import Foundation

/// SSE 流式响应的累加器。
///
/// 单独成型是因为这是整条链路里最琐碎、最容易出错的一段：
/// `tool_calls` 在流里是按 `index` 分片下发的，`id` 和 `name` 往往只在第一片出现，
/// `arguments` 则要逐片拼成完整 JSON。拼错不会报错，只会让模型收到残缺参数。
/// 做成纯类型后可以拿固定的 SSE 片段单测，不必发真请求。
struct LLMStreamAccumulator {

    private var content = ""
    private var reasoning = ""
    /// 按 index 累积的工具调用分片。用有序数组而非字典，保留下发顺序
    private var toolCalls: [Int: PartialToolCall] = [:]
    private(set) var finishReason: String?
    /// 服务端在流里回报的错误（有些实现 HTTP 给 200，错误塞在某一片里）
    private(set) var streamError: String?
    /// 服务端回报的 token 用量，供估算花费；没回报就是 nil
    private(set) var usage: TokenUsage?

    private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments: String = ""
    }

    /// 本次新增的思考片段，供界面显示「模型正在想什么」
    private(set) var latestReasoningChunk: String?

    /// 消费一行 `data:` 后面的 JSON。返回 false 表示流已结束（收到 [DONE]）
    mutating func consume(dataPayload: String) -> Bool {
        latestReasoningChunk = nil

        let trimmed = dataPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed == "[DONE]" { return false }

        guard let data = trimmed.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // 单片解析失败不中断整个流——个别实现会插入心跳或非标准片段
            return true
        }

        if let error = root["error"] as? [String: Any] {
            streamError = error["message"] as? String ?? "未知错误"
            return false
        }

        // 用量通常单独下发在最后一片里，那片的 choices 是空数组——
        // 必须抢在下面的 choices 判空之前取，否则永远读不到
        if let json = root["usage"] as? [String: Any], let parsed = TokenUsage(json: json) {
            usage = parsed
        }

        guard let choices = root["choices"] as? [[String: Any]], let first = choices.first else {
            return true
        }
        if let reason = first["finish_reason"] as? String, !reason.isEmpty {
            finishReason = reason
        }
        guard let delta = first["delta"] as? [String: Any] else { return true }

        if let text = delta["content"] as? String, !text.isEmpty {
            content += text
        }
        // 推理模型把思考单独放这里（MiniMax 的 reasoning_split、DeepSeek-R1 同名字段）
        if let text = delta["reasoning_content"] as? String, !text.isEmpty {
            reasoning += text
            latestReasoningChunk = text
        }

        if let calls = delta["tool_calls"] as? [[String: Any]] {
            for call in calls {
                // index 缺失时按 0 处理：单工具调用的实现有时省略它
                let index = (call["index"] as? Int) ?? 0
                var partial = toolCalls[index] ?? PartialToolCall()
                if let id = call["id"] as? String, !id.isEmpty { partial.id = id }
                if let function = call["function"] as? [String: Any] {
                    if let name = function["name"] as? String, !name.isEmpty { partial.name = name }
                    if let arguments = function["arguments"] as? String { partial.arguments += arguments }
                }
                toolCalls[index] = partial
            }
        }
        return true
    }

    /// 流结束后组装最终结果
    func finish() throws -> LLMResponse {
        if let streamError { throw LLMError.badRequest(streamError) }

        let calls = toolCalls.keys.sorted().compactMap { index -> LLMToolCall? in
            guard let partial = toolCalls[index], let name = partial.name else { return nil }
            return LLMToolCall(
                id: partial.id ?? "call_\(index)",
                name: name,
                // 一次都没收到 arguments 分片时给个空对象，别让模型侧解析炸掉
                argumentsJSON: partial.arguments.isEmpty ? "{}" : partial.arguments)
        }

        let cleaned = LLMStreamAccumulator.strippingThinkTags(content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMResponse(content: cleaned.isEmpty ? nil : cleaned, toolCalls: calls, usage: usage)
    }

    /// 已累积的思考全文，仅用于界面显示，不进对话记录
    var reasoningText: String { reasoning }

    // MARK: - 思考标签剥离

    /// 剥掉混在正文里的思考段落。
    ///
    /// `reasoning_split` 为 false 时，MiniMax 会把思考留在 content 里包进 `<think>`；
    /// 另有多个项目报过流式下 `<mm:think>` 泄漏进 content 的问题。不剥掉的话，
    /// 思考过程会被当成回答显示出来，甚至被「存为局面注释」写进笔记。
    static func strippingThinkTags(_ text: String) -> String {
        var result = text
        for tag in ["think", "mm:think", "thinking", "reasoning"] {
            result = removingTagged(tag, from: result)
        }
        return result
    }

    private static func removingTagged(_ tag: String, from text: String) -> String {
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        var result = ""
        var rest = Substring(text)

        while let openRange = rest.range(of: open) {
            result += rest[rest.startIndex..<openRange.lowerBound]
            let afterOpen = rest[openRange.upperBound...]
            guard let closeRange = afterOpen.range(of: close) else {
                // 只有开标签没有闭标签：说明后面全是思考（流被截断或标签不完整），整段丢掉
                return result
            }
            rest = afterOpen[closeRange.upperBound...]
        }
        result += rest
        return result
    }
}
