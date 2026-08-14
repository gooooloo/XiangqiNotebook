import Testing
import Foundation
@testable import XiangqiNotebook

/// 流式响应累加器测试。
///
/// 这是整条链路里最容易出错的一段：tool_calls 按 index 分片下发，id 和 name 往往只在
/// 第一片出现，arguments 要逐片拼成完整 JSON。拼错不报错，只会让模型收到残缺参数，
/// 所以这里的覆盖要密。
struct LLMStreamAccumulatorTests {

    /// 依次喂入若干 data 负载，返回最终结果
    private func run(_ payloads: [String]) throws -> LLMResponse {
        var accumulator = LLMStreamAccumulator()
        for payload in payloads where accumulator.consume(dataPayload: payload) {}
        return try accumulator.finish()
    }

    // MARK: - 文本累积

    @Test func testAccumulatesContentAcrossChunks() throws {
        let response = try run([
            #"{"choices":[{"delta":{"content":"车二"}}]}"#,
            #"{"choices":[{"delta":{"content":"进五是"}}]}"#,
            #"{"choices":[{"delta":{"content":"失着。"}}]}"#,
            "[DONE]",
        ])
        #expect(response.content == "车二进五是失着。")
        #expect(response.toolCalls.isEmpty)
    }

    @Test func testEmptyContentBecomesNil() throws {
        #expect(try run([#"{"choices":[{"delta":{}}]}"#, "[DONE]"]).content == nil)
    }

    @Test func testStopsAtDone() {
        var accumulator = LLMStreamAccumulator()
        // consume 是 mutating，不能直接写在 #expect 里（宏会把它包进不可变闭包）
        let afterChunk = accumulator.consume(dataPayload: #"{"choices":[{"delta":{"content":"a"}}]}"#)
        #expect(afterChunk)
        let afterDone = accumulator.consume(dataPayload: "[DONE]")
        #expect(!afterDone, "收到 [DONE] 后应停止读取")
    }

    @Test func testSurvivesUnparseableChunk() throws {
        // 个别实现会插心跳或非标准片段，不能因为一片坏了就丢掉整轮
        let response = try run([
            #"{"choices":[{"delta":{"content":"前"}}]}"#,
            "not json at all",
            #"{"choices":[{"delta":{"content":"后"}}]}"#,
            "[DONE]",
        ])
        #expect(response.content == "前后")
    }

    // MARK: - 工具调用增量拼接

    @Test func testAssemblesToolCallFromFragments() throws {
        // 典型下发方式：首片带 id 和 name，后续片只带 arguments 的一小段
        let response = try run([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_a","function":{"name":"evaluate","arguments":""}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"mul"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"tipv\":5}"}}]}}]}"#,
            "[DONE]",
        ])
        #expect(response.toolCalls.count == 1)
        let call = try #require(response.toolCalls.first)
        #expect(call.id == "call_a")
        #expect(call.name == "evaluate")
        #expect(call.argumentsJSON == #"{"multipv":5}"#)
        // 拼出来的必须是合法 JSON，否则工具层拿不到参数
        #expect(AnalysisToolbox.parseArgumentsJSON(call.argumentsJSON)?["multipv"] as? Int == 5)
    }

    @Test func testAssemblesMultipleToolCallsKeyedByIndex() throws {
        // 两个工具的分片交错下发，必须按 index 各归各的
        let response = try run([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c0","function":{"name":"get_position","arguments":"{"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":1,"id":"c1","function":{"name":"evaluate","arguments":"{\"multipv\""}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"}"}}]}}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":":5}"}}]}}]}"#,
            "[DONE]",
        ])
        #expect(response.toolCalls.map(\.name) == ["get_position", "evaluate"])
        #expect(response.toolCalls.map(\.id) == ["c0", "c1"])
        #expect(response.toolCalls[0].argumentsJSON == "{}")
        #expect(response.toolCalls[1].argumentsJSON == #"{"multipv":5}"#)
    }

    @Test func testToolCallWithoutIndexDefaultsToZero() throws {
        // 单工具调用时有的实现省略 index
        let response = try run([
            #"{"choices":[{"delta":{"tool_calls":[{"id":"c","function":{"name":"get_position","arguments":"{}"}}]}}]}"#,
            "[DONE]",
        ])
        #expect(response.toolCalls.count == 1)
        #expect(response.toolCalls.first?.name == "get_position")
    }

    @Test func testToolCallWithoutIdGetsFallback() throws {
        // id 要用来把结果配回去，空的会让整轮对话错位
        let response = try run([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"get_position","arguments":"{}"}}]}}]}"#,
            "[DONE]",
        ])
        #expect(response.toolCalls.first?.id.isEmpty == false)
    }

    @Test func testToolCallWithoutArgumentsBecomesEmptyObject() throws {
        // 一片 arguments 都没收到时得给个 {}，别让工具层解析炸掉
        let response = try run([
            #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c","function":{"name":"get_position"}}]}}]}"#,
            "[DONE]",
        ])
        #expect(response.toolCalls.first?.argumentsJSON == "{}")
    }

    // MARK: - 思考内容

    @Test func testReasoningIsCapturedButKeptOutOfContent() throws {
        var accumulator = LLMStreamAccumulator()
        _ = accumulator.consume(dataPayload:
            #"{"choices":[{"delta":{"reasoning_content":"先看引擎候选…"}}]}"#)
        #expect(accumulator.latestReasoningChunk == "先看引擎候选…")
        _ = accumulator.consume(dataPayload: #"{"choices":[{"delta":{"content":"结论是失着。"}}]}"#)
        // 上一片的思考不该粘在这一片上
        #expect(accumulator.latestReasoningChunk == nil)

        let response = try accumulator.finish()
        // 思考只用于进度显示，绝不能混进回答——否则会被当成讲解显示，还会被存进注释
        #expect(response.content == "结论是失着。")
        #expect(accumulator.reasoningText == "先看引擎候选…")
    }

    @Test func testStripsThinkTagsLeakedIntoContent() throws {
        // reasoning_split 为 false 时思考留在 content 里；
        // 另有多个项目报过流式下 <mm:think> 泄漏进 content
        let response = try run([
            #"{"choices":[{"delta":{"content":"<think>我先算一下对方的应手</think>车二进五是失着。"}}]}"#,
            "[DONE]",
        ])
        #expect(response.content == "车二进五是失着。")
    }

    @Test func testStripsThinkTags_variants() {
        #expect(LLMStreamAccumulator.strippingThinkTags("<mm:think>思考</mm:think>正文") == "正文")
        #expect(LLMStreamAccumulator.strippingThinkTags("<thinking>思考</thinking>正文") == "正文")
        // 前后都有正文
        #expect(LLMStreamAccumulator.strippingThinkTags("前<think>思考</think>后") == "前后")
        // 多段
        #expect(LLMStreamAccumulator.strippingThinkTags("a<think>1</think>b<think>2</think>c") == "abc")
        // 没有标签时原样返回
        #expect(LLMStreamAccumulator.strippingThinkTags("干净的正文") == "干净的正文")
    }

    @Test func testStripsThinkTags_unclosedTagDropsRest() {
        // 只有开标签没有闭标签（流被截断），后面整段都是思考，不能当正文显示
        #expect(LLMStreamAccumulator.strippingThinkTags("正文<think>思考被截断") == "正文")
    }

    // MARK: - Token 用量

    @Test func testUsageArrivesInFinalChunkWithEmptyChoices() throws {
        // 用量单独下发在最后一片里，那片的 choices 是空数组——
        // 若在 choices 判空之后才读 usage，就永远读不到
        let response = try run([
            #"{"choices":[{"delta":{"content":"结论"}}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":4200,"completion_tokens":830}}"#,
            "[DONE]",
        ])
        let usage = try #require(response.usage)
        #expect(usage.promptTokens == 4200)
        #expect(usage.completionTokens == 830)
        // 正文不能被那一片影响
        #expect(response.content == "结论")
    }

    @Test func testUsageCapturesCachedTokens() throws {
        let response = try run([
            #"{"choices":[],"usage":{"prompt_tokens":4200,"completion_tokens":10,"prompt_tokens_details":{"cached_tokens":3800}}}"#,
            "[DONE]",
        ])
        #expect(response.usage?.cachedTokens == 3800)
    }

    @Test func testUsageIsNilWhenServerNeverReportsIt() throws {
        // 服务端不认 stream_options 时得是 nil，不能是 0——
        // 0 tokens 看起来像「没花钱」，实际是「不知道」
        let response = try run([#"{"choices":[{"delta":{"content":"x"}}]}"#, "[DONE]"])
        #expect(response.usage == nil)
    }

    // MARK: - 流内错误

    @Test func testErrorInsideStreamSurfacesAsBadRequest() {
        var accumulator = LLMStreamAccumulator()
        // 有些实现 HTTP 给 200，错误塞在某一片里
        let shouldContinue = accumulator.consume(dataPayload: #"{"error":{"message":"context too long"}}"#)
        #expect(!shouldContinue)
        let finished = accumulator
        #expect(throws: LLMError.badRequest("context too long")) {
            try finished.finish()
        }
    }

    @Test func testFinishReasonIsRecorded() {
        var accumulator = LLMStreamAccumulator()
        _ = accumulator.consume(dataPayload:
            #"{"choices":[{"delta":{"content":"x"},"finish_reason":"tool_calls"}]}"#)
        #expect(accumulator.finishReason == "tool_calls")
    }
}
