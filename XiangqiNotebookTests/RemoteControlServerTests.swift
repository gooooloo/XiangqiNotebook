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
}
#endif
