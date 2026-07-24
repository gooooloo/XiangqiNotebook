#if os(macOS)
import Testing
import Foundation
@testable import XiangqiNotebook

/// RemoteControlServer 鉴权相关测试（issue #169）。
/// 仅 macOS + DEBUG 下编译，与服务本身一致。
struct RemoteControlServerTests {

    private func request(headers: [String], body: String = "") -> String {
        let head = (["POST /action HTTP/1.1"] + headers).joined(separator: "\r\n")
        return head + "\r\n\r\n" + body
    }

    @Test func testExtractToken_PresentAndTrimmed() {
        let req = request(headers: [
            "Host: localhost:9214",
            "X-RemoteControl-Token:  abc123  ",
            "Content-Length: 0"
        ])
        #expect(RemoteControlServer.extractToken(from: req) == "abc123")
    }

    @Test func testExtractToken_CaseInsensitiveHeaderName() {
        let req = request(headers: ["x-remotecontrol-token: deadbeef"])
        #expect(RemoteControlServer.extractToken(from: req) == "deadbeef")
    }

    @Test func testExtractToken_Missing_ReturnsNil() {
        let req = request(headers: ["Host: localhost:9214", "Content-Length: 0"])
        #expect(RemoteControlServer.extractToken(from: req) == nil)
    }

    @Test func testExtractToken_IgnoresBodyOccurrence() {
        // body 里出现同名串不应被当作头
        let req = request(headers: ["Host: localhost"], body: "X-RemoteControl-Token: fake")
        #expect(RemoteControlServer.extractToken(from: req) == nil)
    }

    @Test func testAuthToken_Is64HexChars() {
        let server = RemoteControlServer()
        #expect(server.authToken.count == 64)
        #expect(server.authToken.allSatisfy { $0.isHexDigit })
    }

    @Test func testAuthToken_DifferentPerInstance() {
        let a = RemoteControlServer()
        let b = RemoteControlServer()
        #expect(a.authToken != b.authToken)
    }

    // MARK: - /eval 参数解析

    @Test func testParseEvalParams_defaults() {
        let params = RemoteControlServer.parseEvalParams(json: nil)
        #expect(params.fen == nil)
        #expect(params.multiPV == 3)
        #expect(params.movetime == 5000)
    }

    @Test func testParseEvalParams_explicitValues() {
        let params = RemoteControlServer.parseEvalParams(json: [
            "fen": "abc r", "multipv": 5, "movetime": 10000
        ])
        #expect(params.fen == "abc r")
        #expect(params.multiPV == 5)
        #expect(params.movetime == 10000)
    }

    @Test func testParseEvalParams_clampsOutOfRange() {
        let low = RemoteControlServer.parseEvalParams(json: ["multipv": 0, "movetime": 100])
        #expect(low.multiPV == 1)
        #expect(low.movetime == 500)

        let high = RemoteControlServer.parseEvalParams(json: ["multipv": 99, "movetime": 999_999])
        #expect(high.multiPV == 10)
        #expect(high.movetime == 60000)
    }

    // MARK: - PV 中文着法转换

    @Test func testChinesePV_convertsUCISequence() {
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        let result = RemoteControlServer.chinesePV(fen: startFen, uciMoves: ["h2e2", "h9g7"])
        #expect(result == ["炮二平五", "马８进７"])
    }

    @Test func testChinesePV_truncatesAtInvalidMove() {
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        // 第二着 e5e4 起点无子，序列在此截断
        let result = RemoteControlServer.chinesePV(fen: startFen, uciMoves: ["h2e2", "e5e4"])
        #expect(result == ["炮二平五"])
    }

    // MARK: - /apply 走子应用

    @Test func testApplyUCIMoves_appliesSequence() {
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        let result = RemoteControlServer.applyUCIMoves(fen: startFen, uciMoves: ["h2e2", "h9g7"])
        #expect(result.failedIndex == nil)
        #expect(result.applied.count == 2)
        #expect(result.applied[0].uci == "h2e2")
        #expect(result.applied[0].chinese == "炮二平五")
        #expect(result.applied[0].fen == "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C2C4/9/RNBAKABNR b")
        #expect(result.applied[1].chinese == "马８进７")
        // 走完黑方着法后轮红方
        #expect(result.applied[1].fen.hasSuffix(" r"))
    }

    @Test func testApplyUCIMoves_reportsFailedIndex() {
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        // 第二着起点无子
        let result = RemoteControlServer.applyUCIMoves(fen: startFen, uciMoves: ["h2e2", "e5e4", "h9g7"])
        #expect(result.failedIndex == 1)
        #expect(result.applied.count == 1)
    }

    @Test func testApplyUCIMoves_emptySequence() {
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
        let result = RemoteControlServer.applyUCIMoves(fen: startFen, uciMoves: [])
        #expect(result.failedIndex == nil)
        #expect(result.applied.isEmpty)
    }
}
#endif
