import Testing
import Foundation
@testable import XiangqiNotebook

/// Claude Code（订阅）线路客户端的纯逻辑测试。
/// 全部走纯函数：不 spawn claude、不起桥接、不发网络——
/// 桥接协议（NDJSON 事件、请求体形状、错误映射）在这里锁死，真流量留给端到端验证。
struct ClaudeCodeClientTests {

    // MARK: - NDJSON 事件解析

    @Test func testParseEvent_textAndThinkingAndPing() {
        #expect(ClaudeCodeClient.parseEvent(line: #"{"type":"text","delta":"红方"}"#)
                == .text("红方"))
        #expect(ClaudeCodeClient.parseEvent(line: #"{"type":"thinking","delta":"先看候选"}"#)
                == .thinking("先看候选"))
        #expect(ClaudeCodeClient.parseEvent(line: #"{"type":"ping"}"#) == .ping)
    }

    @Test func testParseEvent_toolUseSerializesInputAsSortedJSON() {
        // input 转回 JSON 字符串要与 OpenAI 线路的 argumentsJSON 同形，
        // 供 AnalysisToolbox.parseArgumentsJSON 解析；键排序保证可断言
        let line = #"{"type":"tool_use","id":"t1","name":"mcp__xiangqi-notebook__evaluate","input":{"multipv":5,"fen":"x r"}}"#
        let event = ClaudeCodeClient.parseEvent(line: line)
        #expect(event == .toolUse(id: "t1", name: "mcp__xiangqi-notebook__evaluate",
                                  argumentsJSON: #"{"fen":"x r","multipv":5}"#))
    }

    @Test func testParseEvent_toolUseWithoutInputYieldsEmptyObject() {
        let event = ClaudeCodeClient.parseEvent(line: #"{"type":"tool_use","id":"t1","name":"get_position"}"#)
        #expect(event == .toolUse(id: "t1", name: "get_position", argumentsJSON: "{}"))
    }

    @Test func testParseEvent_toolResult() {
        let line = #"{"type":"tool_result","id":"t1","content":"{\"ok\":true}","isError":false}"#
        #expect(ClaudeCodeClient.parseEvent(line: line)
                == .toolResult(id: "t1", content: #"{"ok":true}"#, isError: false))
    }

    @Test func testParseEvent_doneWithUsage() {
        let line = #"{"type":"done","result":"讲解。","usage":{"promptTokens":800,"cachedTokens":300,"completionTokens":120}}"#
        let expected = ClaudeCodeClient.BridgeEvent.done(
            result: "讲解。",
            usage: TokenUsage(promptTokens: 800, cachedTokens: 300, completionTokens: 120))
        #expect(ClaudeCodeClient.parseEvent(line: line) == expected)
    }

    @Test func testParseEvent_doneWithMalformedUsageStillCarriesResult() {
        // usage 形状不对不能连终稿一起丢——宁可不显示 token 数
        let line = #"{"type":"done","result":"讲解。","usage":{"whatever":1}}"#
        #expect(ClaudeCodeClient.parseEvent(line: line) == .done(result: "讲解。", usage: nil))
    }

    @Test func testParseEvent_error() {
        let line = #"{"type":"error","code":"CLAUDE_NOT_LOGGED_IN","message":"未登录"}"#
        #expect(ClaudeCodeClient.parseEvent(line: line)
                == .error(code: "CLAUDE_NOT_LOGGED_IN", message: "未登录"))
    }

    @Test func testParseEvent_toleratesGarbage() {
        // 桥接/CLI 升级改了事件形状时尽量不断流：未知的忽略，坏的忽略
        #expect(ClaudeCodeClient.parseEvent(line: "") == nil)
        #expect(ClaudeCodeClient.parseEvent(line: "   ") == nil)
        #expect(ClaudeCodeClient.parseEvent(line: "not json") == nil)
        #expect(ClaudeCodeClient.parseEvent(line: #"{"no_type":1}"#) == nil)
        #expect(ClaudeCodeClient.parseEvent(line: #"{"type":"future_event","x":1}"#) == nil)
    }

    // MARK: - 工具名前缀

    @Test func testShortToolName_stripsMCPPrefix() {
        #expect(ClaudeCodeClient.shortToolName("mcp__xiangqi-notebook__evaluate") == "evaluate")
        #expect(ClaudeCodeClient.shortToolName("mcp__xiangqi-notebook__get_position") == "get_position")
        // 已是短名或不认识的形状原样返回
        #expect(ClaudeCodeClient.shortToolName("evaluate") == "evaluate")
        #expect(ClaudeCodeClient.shortToolName("mcp__broken") == "mcp__broken")
    }

    // MARK: - 请求体

    private func bodyJSON(messages: [LLMMessage], model: String = "") throws -> [String: Any] {
        let data = try ClaudeCodeClient.requestBody(messages: messages, model: model)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func testRequestBody_splitsSystemTranscriptAndQuestion() throws {
        let json = try bodyJSON(messages: [
            .system("你是教练"),
            .user("第一问"),
            .assistant("第一答", toolCalls: []),
            .user("第二问"),
        ])
        #expect(json["systemPrompt"] as? String == "你是教练")
        #expect(json["question"] as? String == "第二问")
        let transcript = try #require(json["transcript"] as? [[String: String]])
        #expect(transcript == [["role": "user", "text": "第一问"],
                               ["role": "assistant", "text": "第一答"]])
    }

    @Test func testRequestBody_firstQuestionHasEmptyTranscript() throws {
        let json = try bodyJSON(messages: [.system("s"), .user("问")])
        #expect(json["question"] as? String == "问")
        #expect((json["transcript"] as? [[String: String]])?.isEmpty == true)
    }

    @Test func testRequestBody_skipsToolMessagesAndToolCalls() throws {
        // 本线路一轮收敛，历史里不该有工具往返；真出现（异常残留）也只丢工具部分
        let json = try bodyJSON(messages: [
            .system("s"),
            .user("问"),
            .assistant(nil, toolCalls: [LLMToolCall(id: "c", name: "t", argumentsJSON: "{}")]),
            .toolResult(callId: "c", content: "{}"),
            .assistant("答", toolCalls: []),
            .user("追问"),
        ])
        let transcript = try #require(json["transcript"] as? [[String: String]])
        #expect(transcript == [["role": "user", "text": "问"],
                               ["role": "assistant", "text": "答"]])
        #expect(json["question"] as? String == "追问")
    }

    @Test func testRequestBody_modelOnlyWhenNonEmpty() throws {
        // 空模型不传 --model，让 CLI 用自己的默认
        let messages: [LLMMessage] = [.system("s"), .user("问")]
        #expect(try bodyJSON(messages: messages)["model"] == nil)
        #expect(try bodyJSON(messages: messages, model: "  ")["model"] == nil)
        #expect(try bodyJSON(messages: messages, model: "sonnet")["model"] as? String == "sonnet")
    }

    // MARK: - 错误映射

    @Test func testBridgeCodeErrorMapping() {
        #expect(ClaudeCodeClient.error(forBridgeCode: "CLAUDE_NOT_LOGGED_IN", message: "x")
                == .claudeNotLoggedIn)
        #expect(ClaudeCodeClient.error(forBridgeCode: "CLAUDE_NOT_FOUND", message: "x")
                == .claudeNotFound)
        #expect(ClaudeCodeClient.error(forBridgeCode: "CLAUDE_FAILED", message: "exit 1")
                == .badRequest("exit 1"))
        #expect(ClaudeCodeClient.error(forBridgeCode: "MYSTERY", message: "")
                == .badRequest("MYSTERY"))
    }

    @Test func testStatusErrorMapping() {
        // 409 = 桥接单飞行槽被占，语义就是「请求过于频繁，稍后再试」，且可重试
        #expect(ClaudeCodeClient.error(forStatus: 409, body: Data()) == .rateLimited)
        #expect(ClaudeCodeClient.error(forStatus: 409, body: Data()).isRetryable)
        // 403 = token 对不上（旧桥接实例写的文件），归为可重试并提示重启桥接
        #expect(ClaudeCodeClient.error(forStatus: 403, body: Data()).isRetryable)
    }

    @Test func testTransportError_connectionRefusedMeansBridgeDown() {
        let refused = NSError(domain: NSURLErrorDomain,
                              code: NSURLErrorCannotConnectToHost)
        #expect(ClaudeCodeClient.transportError(from: refused) == .bridgeUnreachable)
        // 其余传输错误沿用通用分类，别都赖到桥接头上
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        #expect(ClaudeCodeClient.transportError(from: timeout)
                == .timeout(seconds: Int(LLMClient.requestTimeout)))
    }

    @Test func testNewLLMErrorsCarryActionableGuidanceAndRetryability() {
        // 文案是显示在对话界面上的，必须说人话、给下一步动作
        #expect(LLMError.bridgeUnreachable.errorDescription?.contains("claude-bridge") == true)
        #expect(LLMError.claudeNotLoggedIn.errorDescription?.contains("登录") == true)
        #expect(LLMError.bridgeUnreachable.isRetryable, "起完桥接就能重试")
        #expect(LLMError.claudeNotLoggedIn.isRetryable, "登录完就能重试")
        #expect(!LLMError.claudeNotFound.isRetryable, "没装 claude 重试也没用")
    }

    // MARK: - 工厂分派

    @Test func testFactory_dispatchesByWireFormat() {
        var config = AIConfig.empty
        #expect(LLMClientFactory.make(config: config) is LLMClient)
        config.wireFormat = .claudeCode
        #expect(LLMClientFactory.make(config: config) is ClaudeCodeClient)
    }
}
