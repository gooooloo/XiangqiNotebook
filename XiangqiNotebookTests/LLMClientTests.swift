import Testing
import Foundation
@testable import XiangqiNotebook

/// OpenAI 兼容客户端的请求构造、响应解析与错误分类测试。
/// 全部用固定 JSON，不发网络。
struct LLMClientTests {

    // MARK: - 消息序列化

    @Test func testWireDictionary_userMessage() {
        let dict = LLMMessage.user("为什么走车二进五不好").wireDictionary()
        #expect(dict["role"] as? String == "user")
        #expect(dict["content"] as? String == "为什么走车二进五不好")
        #expect(dict["tool_calls"] == nil)
        #expect(dict["tool_call_id"] == nil)
    }

    @Test func testWireDictionary_assistantWithToolCallsKeepsNullContent() {
        // assistant 请求工具时 content 常为 null，但字段不能缺——
        // 部分兼容实现会因缺字段直接 400
        let message = LLMMessage.assistant(nil, toolCalls: [
            LLMToolCall(id: "call_1", name: "evaluate", argumentsJSON: #"{"multipv":5}"#),
        ])
        let dict = message.wireDictionary()
        #expect(dict["role"] as? String == "assistant")
        #expect(dict["content"] is NSNull)

        let calls = dict["tool_calls"] as? [[String: Any]]
        #expect(calls?.count == 1)
        #expect(calls?.first?["id"] as? String == "call_1")
        #expect(calls?.first?["type"] as? String == "function")
        let function = calls?.first?["function"] as? [String: Any]
        #expect(function?["name"] as? String == "evaluate")
        #expect(function?["arguments"] as? String == #"{"multipv":5}"#)
    }

    @Test func testWireDictionary_toolResultCarriesCallId() {
        let dict = LLMMessage.toolResult(callId: "call_1", content: #"{"lines":[]}"#).wireDictionary()
        #expect(dict["role"] as? String == "tool")
        #expect(dict["tool_call_id"] as? String == "call_1")
        #expect(dict["content"] as? String == #"{"lines":[]}"#)
    }

    // MARK: - 请求体

    @Test func testRequestBody_includesModelMessagesAndTools() throws {
        let data = try LLMClient.requestBody(
            model: "deepseek-chat",
            messages: [.system("你是象棋教练"), .user("这步怎么样")],
            tools: AnalysisToolbox.toolSpecs)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["model"] as? String == "deepseek-chat")
        #expect((body["messages"] as? [[String: Any]])?.count == 2)
        // 工具数量另有 AnalysisToolboxTests 把关，这里只验「全都带上了」
        #expect((body["tools"] as? [[String: Any]])?.count == AnalysisToolbox.toolSpecs.count)
        #expect(body["tool_choice"] as? String == "auto")
    }

    @Test func testRequestBody_omitsToolFieldsWhenNoTools() throws {
        let data = try LLMClient.requestBody(model: "m", messages: [.user("hi")], tools: [])
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        // 传空 tools 数组有的实现会报错，干脆整个字段不发
        #expect(body["tools"] == nil)
        #expect(body["tool_choice"] == nil)
    }

    @Test func testRequestBody_asksForUsageWhenStreaming() throws {
        // 流式默认不回报用量，不显式索取就估不出花费
        let data = try LLMClient.requestBody(
            model: "m", messages: [.user("hi")], tools: [], stream: true)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        let options = try #require(body["stream_options"] as? [String: Any])
        #expect(options["include_usage"] as? Bool == true)
    }

    @Test func testRequestBody_omitsStreamOptionsWhenNotStreaming() throws {
        let data = try LLMClient.requestBody(model: "m", messages: [.user("hi")], tools: [])
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["stream_options"] == nil)
    }

    // MARK: - Token 用量

    @Test func testTokenUsage_parsesUsageJSON() throws {
        let usage = try #require(TokenUsage(json: [
            "prompt_tokens": 4200,
            "completion_tokens": 830,
            "total_tokens": 5030,
        ]))
        #expect(usage.promptTokens == 4200)
        #expect(usage.completionTokens == 830)
        #expect(usage.cachedTokens == 0)
        #expect(usage.totalTokens == 5030)
    }

    @Test func testTokenUsage_parsesCachedTokens() throws {
        let usage = try #require(TokenUsage(json: [
            "prompt_tokens": 4200,
            "completion_tokens": 830,
            "prompt_tokens_details": ["cached_tokens": 3800],
        ]))
        #expect(usage.cachedTokens == 3800)
        // 缓存数含在 prompt 里，不该被重复计入总数
        #expect(usage.totalTokens == 5030)
    }

    @Test func testTokenUsage_rejectsIncompleteJSON() {
        #expect(TokenUsage(json: ["prompt_tokens": 10]) == nil)
        #expect(TokenUsage(json: [:]) == nil)
    }

    @Test func testTokenUsage_addsUpAcrossRequests() {
        // 工具循环里每一步都是一次独立请求，用量要累加成一条回答的总账
        let total = TokenUsage(promptTokens: 4000, cachedTokens: 0, completionTokens: 200)
            + TokenUsage(promptTokens: 4600, cachedTokens: 3900, completionTokens: 150)
        #expect(total.promptTokens == 8600)
        #expect(total.cachedTokens == 3900)
        #expect(total.completionTokens == 350)
    }

    @Test func testTokenUsage_compactDescription() {
        #expect(TokenUsage(promptTokens: 300, completionTokens: 120).compactDescription
                == "420 tokens")
        #expect(TokenUsage(promptTokens: 24_000, completionTokens: 100).compactDescription
                == "24.1k tokens")
    }

    // MARK: - SSE 行解析

    private func data(_ json: String) -> Data { Data(json.utf8) }

    @Test func testSSEDataPayload_extractsOnlyDataLines() {
        #expect(LLMClient.sseDataPayload(from: "data: {\"a\":1}") == "{\"a\":1}")
        // 无空格的写法也要认
        #expect(LLMClient.sseDataPayload(from: "data:{\"a\":1}") == "{\"a\":1}")
        #expect(LLMClient.sseDataPayload(from: "data: [DONE]") == "[DONE]")
        // 事件名行、注释行、空行都不是负载
        #expect(LLMClient.sseDataPayload(from: "event: message") == nil)
        #expect(LLMClient.sseDataPayload(from: ": keep-alive") == nil)
        #expect(LLMClient.sseDataPayload(from: "") == nil)
    }

    // MARK: - 错误分类

    @Test func testError_authFailures() {
        #expect(LLMClient.error(forStatus: 401, body: Data()) == .unauthorized)
        #expect(LLMClient.error(forStatus: 403, body: Data()) == .unauthorized)
    }

    @Test func testError_rateLimit() {
        #expect(LLMClient.error(forStatus: 429, body: Data()) == .rateLimited)
    }

    @Test func testError_serverErrors() {
        #expect(LLMClient.error(forStatus: 500, body: Data()) == .serverError(500))
        #expect(LLMClient.error(forStatus: 503, body: Data()) == .serverError(503))
    }

    @Test func testError_detectsToolsUnsupported() {
        // 措辞各家不同，抓关键词
        let body = data(#"{"error":{"message":"This model does not support tools"}}"#)
        #expect(LLMClient.error(forStatus: 400, body: body) == .toolsUnsupported)

        let body2 = data(#"{"error":{"message":"function call is not available for this model"}}"#)
        #expect(LLMClient.error(forStatus: 400, body: body2) == .toolsUnsupported)
    }

    @Test func testError_badRequestCarriesServerMessage() {
        let body = data(#"{"error":{"message":"max_tokens too large"}}"#)
        #expect(LLMClient.error(forStatus: 400, body: body) == .badRequest("max_tokens too large"))
    }

    @Test func testError_badRequestWithoutMessageFallsBackToStatus() {
        #expect(LLMClient.error(forStatus: 404, body: Data()) == .badRequest("HTTP 404"))
    }

    @Test func testErrorMessage_readsCommonShapes() {
        #expect(LLMClient.errorMessage(from: data(#"{"error":{"message":"a"}}"#)) == "a")
        #expect(LLMClient.errorMessage(from: data(#"{"error":{"msg":"b"}}"#)) == "b")
        #expect(LLMClient.errorMessage(from: data(#"{"message":"c"}"#)) == "c")
        #expect(LLMClient.errorMessage(from: data(#"{"msg":"d"}"#)) == "d")
        // 非 JSON 时把原文当说明，总比空着强
        #expect(LLMClient.errorMessage(from: data("  gateway timeout  ")) == "gateway timeout")
        #expect(LLMClient.errorMessage(from: data("{}")) == "")
    }

    // MARK: - 可重试性

    @Test func testTimeoutMessage_pointsAtSlowModelNotNetwork() {
        // 措辞很重要：说「连不上」会让人去查网络，但推理型模型超时时网络多半是通的
        let message = try! #require(LLMError.timeout(seconds: 180).errorDescription)
        #expect(message.contains("180"))
        #expect(!message.contains("连不上"))
        #expect(message.contains("模型"))
    }

    @Test func testIsRetryable_onlyForTransientFailures() {
        #expect(LLMError.rateLimited.isRetryable)
        #expect(LLMError.serverError(500).isRetryable)
        #expect(LLMError.timeout(seconds: 180).isRetryable)
        #expect(LLMError.network("timeout").isRetryable)
        // 这些换个 key 或换个模型才有用，重试按钮是误导
        #expect(!LLMError.unauthorized.isRetryable)
        #expect(!LLMError.toolsUnsupported.isRetryable)
        #expect(!LLMError.notConfigured.isRetryable)
        #expect(!LLMError.invalidBaseURL.isRetryable)
    }

    // MARK: - 未配置时不发请求

    @Test func testSend_throwsBeforeHittingNetworkWhenNotConfigured() async {
        let client = LLMClient(config: .empty)
        await #expect(throws: LLMError.notConfigured) {
            try await client.send(messages: [.user("hi")], tools: [])
        }
    }
}
