#if os(macOS)
import Foundation
import Security

@objc protocol CodexHelperProtocol {
    func start(bridgeToken: String, remoteToken: String, reply: @escaping (String?) -> Void)
}

/// app 按需启动内置私有 XPC 服务；无需用户安装 Node、SDK 或常驻服务。
@MainActor
enum CodexBridgeService {
    private static var startup: Task<Void, Error>?
    private static var connection: NSXPCConnection?

    static func ensureReady() async throws {
        if let startup { try await startup.value; return }
        let task = Task { @MainActor in
            _ = try prepareToken()
            if (try? await request(path: "ready"))?["ok"] as? Bool == true {
                try await configureRemoteAccess()
                return
            }
            try await startEmbeddedService()
            for _ in 0..<100 {
                try Task.checkCancellation()
                if (try? await request(path: "ready"))?["ok"] as? Bool == true {
                    try await configureRemoteAccess()
                    return
                }
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            throw LLMError.network("ChatGPT 后台服务启动失败，请退出 app 后重新打开。")
        }
        startup = task
        defer { startup = nil }
        try await task.value
    }

    private static func startEmbeddedService() async throws {
        guard let token = ClaudeCodeClient.readBridgeToken(codex: true),
              let remoteURL = ClaudeCodeClient.bridgeTokenFileURL(codex: true)?.deletingLastPathComponent()
                .appendingPathComponent("remote-control-token.txt"),
              let remoteToken = try? String(contentsOf: remoteURL, encoding: .utf8) else {
            throw LLMError.network("app 的象棋分析接口尚未就绪，请稍后重试。")
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/XiangqiCodexHelper.xpc")
        guard FileManager.default.fileExists(atPath: helper.path) else {
            throw LLMError.badRequest("app 内的 ChatGPT 组件不完整，请重新安装完整版本。")
        }
        let requirement = try helperSigningRequirement()
        let xpc = NSXPCConnection(serviceName: "com.gooooloo.XiangqiNotebook.CodexHelper")
        xpc.remoteObjectInterface = NSXPCInterface(with: CodexHelperProtocol.self)
        xpc.setCodeSigningRequirement(requirement)
        xpc.resume()
        connection = xpc
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // 一次性闸门避免 XPC 的失败回调与服务回复竞态导致 continuation 重复恢复。
            let reply = XPCReply(continuation)
            xpc.invalidationHandler = {
                reply.finish(.failure(LLMError.network("ChatGPT 后台连接已断开，请重试。")))
            }
            xpc.interruptionHandler = {
                reply.finish(.failure(LLMError.network("ChatGPT 后台服务被中断，请重试。")))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if reply.finish(.failure(LLMError.network("ChatGPT 后台启动超时，请重试；若从 Xcode 运行，请关闭 Debug XPC Services。"))) {
                    xpc.invalidate()
                }
            }
            let proxy = xpc.remoteObjectProxyWithErrorHandler { error in reply.finish(.failure(error)) }
            guard let proxy = proxy as? CodexHelperProtocol else {
                reply.finish(.failure(LLMError.network("ChatGPT 后台连接失败。"))); return
            }
            proxy.start(bridgeToken: token, remoteToken: remoteToken) { message in
                if let message { reply.finish(.failure(LLMError.network(message))) }
                else { reply.finish(.success(())) }
            }
        }
    }

    private static func helperSigningRequirement() throws -> String {
        var code: SecCode?
        var info: CFDictionary?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw LLMError.badRequest("内置 ChatGPT 组件需要签名的 app，请使用 Xcode 正常构建并运行。")
        }
        return "anchor apple generic and identifier \"com.gooooloo.XiangqiNotebook.CodexHelper\" and certificate leaf[subject.OU] = \"\(team)\""
    }

    private final class XPCReply: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?
        init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
        @discardableResult
        func finish(_ result: Result<Void, Error>) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(with: result)
            return pending != nil
        }
    }

    static func login() async throws {
        try await ensureReady()
        // 有效登录直接复用，避免再次打开浏览器让用户重复授权。
        if (try? await request(path: "health"))?["loggedIn"] as? Bool == true { return }
        _ = try await request(path: "login", method: "POST")
        for _ in 0..<300 {
            try Task.checkCancellation()
            let status = try await request(path: "login-status")
            switch status["state"] as? String {
            case "completed": return
            case "failed": throw LLMError.badRequest(status["message"] as? String ?? "ChatGPT 登录失败，请重试。")
            default: break
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw LLMError.network("ChatGPT 登录等待超时，请重试。")
    }

    private static func prepareToken() throws -> String {
        if let token = ClaudeCodeClient.readBridgeToken(codex: true) { return token }
        guard let url = ClaudeCodeClient.bridgeTokenFileURL(codex: true) else {
            throw LLMError.badRequest("无法保存 ChatGPT 后台连接信息。")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let token = UUID().uuidString + UUID().uuidString
        try token.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return token
    }

    private static func configureRemoteAccess() async throws {
        guard let url = ClaudeCodeClient.bridgeTokenFileURL(codex: true)?.deletingLastPathComponent()
            .appendingPathComponent("remote-control-token.txt"),
            let token = try? String(contentsOf: url, encoding: .utf8) else {
            throw LLMError.network("app 的象棋分析接口尚未就绪，请稍后重试。")
        }
        _ = try await request(path: "configure", method: "POST", body: ["remoteToken": token])
    }

    private static func request(path: String, method: String = "GET", body: [String: String]? = nil) async throws -> [String: Any] {
        guard let token = ClaudeCodeClient.readBridgeToken(codex: true) else {
            throw LLMError.network("ChatGPT 后台服务尚未启动。")
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:9217/\(path)")!)
        request.httpMethod = method
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = path == "health" ? 15 : 2
        request.setValue(token, forHTTPHeaderField: "X-CodexBridge-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.network("ChatGPT 后台服务响应异常。")
        }
        return json
    }
}
#endif
