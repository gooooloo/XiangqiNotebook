#if os(iOS)
import Foundation
import CryptoKit
import Network
import Security

/// 最小验证阶段：不复用 Mac 凭据、不触碰 CLI、不启用问棋线路。
@MainActor
final class ChatGPTSubscriptionProbe: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var loggedIn = false
    @Published private(set) var message = "尚未验证手机订阅授权。"
    @Published private(set) var answer = ""
    @Published var browserURL: BrowserURL?
    struct BrowserURL: Identifiable { let id = UUID(); let url: URL }
    private var listener: NWListener?
    private var timeout: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    var awaitingCallback: Bool { pending != nil }
    private var pending: Attempt?
    private var credential: Credential?
    private var retryClientID: String?
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "ChatGPT.loopback")
    private struct Attempt { let state: String; let nonce: String; let verifier: String; let redirect: String; let clientID: String?; let subject: String? }
    private struct Credential: Codable {
        let clientID: String; let subject: String; let email: String?
        let accessToken: String; let refreshToken: String; let idToken: String
        let expiresAt: Date; let scopes: String
    }
    private struct Failure: LocalizedError { let text: String; var errorDescription: String? { text } }
    private func fail(_ text: String) -> Failure { Failure(text: text) }
    init(loadSavedCredential: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        credential = loadSavedCredential ? Self.readCredential() : nil
        loggedIn = credential.map { $0.expiresAt > Date() && $0.scopes.split(separator: " ").contains("chatgpt.tokens.use.direct") } ?? false
        if loggedIn { message = "手机已有有效登录，可测试云端回答。" }
    }
    func login() {
        guard !busy, !loggedIn else { return }
        busy = true; answer = ""; message = "正在启动手机回调监听…"
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let server = try NWListener(using: parameters)
            listener = server
            server.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.listener === server else { return }
                    switch state {
                    case .ready:
                        guard let port = server.port else { self.finish(error: "未取得手机回调端口。"); return }
                        do { try self.openAuthorization(port: port.rawValue) }
                        catch { self.finish(error: error.localizedDescription) }
                    case .failed(let error): self.finish(error: "手机回调监听失败：\(error.localizedDescription)")
                    default: break
                    }
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                connection.start(queue: DispatchQueue.global())
                Self.receive(connection, buffer: Data()) { [weak self] target in
                    Task { @MainActor in self?.callback(target, connection: connection) }
                }
            }
            server.start(queue: queue)
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(180))
                guard !Task.isCancelled else { return }
                self?.requestTask?.cancel()
                self?.finish(error: "登录等待超过 180 秒。请重试；若浏览器无法打开 127.0.0.1，请记录该提示，手机回调尚未验证通过。")
            }
        } catch { finish(error: error.localizedDescription) }
    }
    private func openAuthorization(port: UInt16) throws {
        let state = try Self.random(), nonce = try Self.random(), verifier = try Self.random()
        let redirect = "http://127.0.0.1:\(port)/auth/callback"
        pending = Attempt(state: state, nonce: nonce, verifier: verifier, redirect: redirect,
                          clientID: credential?.clientID ?? retryClientID, subject: credential?.subject)
        var host = defaults.string(forKey: "chatGPTSubscriptionHostID")
        if host == nil { host = "urn:uuid:" + UUID().uuidString; defaults.set(host, forKey: "chatGPTSubscriptionHostID") }
        var values = ["client_id": credential?.clientID ?? retryClientID ?? "dynamic_agent_client", "ext_agent_host_id": host!,
                      "response_type": "code", "redirect_uri": redirect,
                      "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
                      "resource": "https://api.openai.com/v1", "state": state, "nonce": nonce,
                      "code_challenge_method": "S256", "code_challenge": Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))]
        if let credential { values["id_token_hint"] = credential.idToken }
        else if retryClientID == nil { values["agent_name_hint"] = "XiangqiNotebook" }
        var url = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        url.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        browserURL = BrowserURL(url: url.url!)
        message = "请在 Safari 授权页完成登录。手机正在监听 \(redirect)，最长等待 180 秒。"
    }
    nonisolated private static func receive(_ connection: NWConnection, buffer: Data, completion: @escaping @Sendable (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, done, error in
            var buffer = buffer; buffer.append(data ?? Data())
            guard buffer.count <= 16384 else { connection.cancel(); return }
            if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                let parts = text.components(separatedBy: "\r\n")[0].split(separator: " ")
                guard parts.count == 3, parts[0] == "GET" else { connection.cancel(); return }
                completion(String(parts[1]))
            } else if !done, error == nil { receive(connection, buffer: buffer, completion: completion) }
            else { connection.cancel() }
        }
    }
    private func callback(_ target: String, connection: NWConnection) {
        guard let attempt = pending,
              let url = URLComponents(string: "http://127.0.0.1" + target), url.path == "/auth/callback" else {
            Self.reply(connection, text: "Invalid callback", status: "404 Not Found"); return
        }
        let items = url.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { Self.reply(connection, text: "Invalid callback", status: "400 Bad Request"); return }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard values["state"] == attempt.state else { Self.reply(connection, text: "Invalid state", status: "400 Bad Request"); return }
        if let error = values["error"] { Self.reply(connection, text: "Authorization declined"); finish(error: "授权未完成：\(error)"); return }
        guard let code = values["code"], !code.isEmpty,
              let client = values["client_id"] ?? attempt.clientID, !client.isEmpty, client != "dynamic_agent_client",
              attempt.clientID == nil || attempt.clientID == client else {
            Self.reply(connection, text: "Incomplete registration"); finish(error: "回调缺少授权码或有效 client_id，或与本次登记不一致。"); return
        }
        retryClientID = client
        pending = nil; listener?.cancel(); listener = nil
        Self.reply(connection, text: "Authorization received. Return to XiangqiNotebook.")
        browserURL = nil; message = "手机已收到回调，正在交换凭据并验证身份…"
        requestTask = Task {
            do {
                let json = try await Self.token(["grant_type": "authorization_code", "client_id": client, "code": code,
                                                "code_verifier": attempt.verifier, "redirect_uri": attempt.redirect, "resource": "https://api.openai.com/v1"])
                guard let idToken = json["id_token"] as? String else { throw fail("授权响应缺少 ID token。") }
                let identity = try await Self.verify(idToken, clientID: client, nonce: attempt.nonce)
                if let subject = attempt.subject, subject != identity.subject { throw fail("登录账号与原登记不一致。") }
                let record = try Self.record(json, client: client, identity: identity, idToken: idToken)
                try Task.checkCancellation()
                try Self.saveCredential(record); credential = record; loggedIn = true
                finish(error: nil); message = "身份和订阅权限验证通过。请测试云端回答。"
            } catch { if !Task.isCancelled { finish(error: error.localizedDescription) } }
        }
    }
    nonisolated private static func reply(_ connection: NWConnection, text: String, status: String = "200 OK") {
        let body = Data(text.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    func cancel() { requestTask?.cancel(); finish(error: "已取消登录或测试。") }
    private func finish(error: String?) {
        timeout?.cancel(); timeout = nil; pending = nil; listener?.cancel(); listener = nil
        browserURL = nil; busy = false
        if let error { message = error }
    }
    func test(effort: CodexReasoningEffort) {
        guard !busy, credential != nil else { message = "请先在手机登录 ChatGPT。"; return }
        busy = true; answer = ""; message = "正在请求 gpt-6.1-sol；reasoning effort = \(effort.rawValue)…"
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.requestTask?.cancel()
            self?.finish(error: "云端回答等待超过 90 秒，请重试。")
        }
        requestTask = Task {
            do {
                let token = try await accessToken()
                var modelsRequest = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
                modelsRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                let models = try await Self.json(modelsRequest)
                guard let catalog = models["models"] as? [[String: Any]], catalog.contains(where: { $0["slug"] as? String == "gpt-6.1-sol" && $0["visibility"] as? String == "list" }) else {
                    throw fail("当前账号的模型目录未提供 gpt-6.1-sol，未替换为其他模型。")
                }
                var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
                request.httpMethod = "POST"; request.timeoutInterval = 90
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "gpt-6.1-sol", "reasoning": ["effort": effort.rawValue], "input": [["role": "user", "content": "请用一句中文确认：手机已直接连接云端模型。"]], "store": false, "stream": true])
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw fail("订阅推理请求失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）。") }
                var completed = false
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data: "), let data = String(line.dropFirst(6)).data(using: .utf8),
                          let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    switch event["type"] as? String {
                    case "response.output_text.delta": answer += event["delta"] as? String ?? ""
                    case "response.completed": completed = true
                    case "response.failed", "response.incomplete", "error":
                        let response = event["response"] as? [String: Any]
                        let error = response?["error"] as? [String: Any] ?? event["error"] as? [String: Any]
                        throw fail("云端请求未完成：\(error?["code"] as? String ?? event["type"] as? String ?? "unknown")")
                    default: break
                    }
                }
                guard completed, !answer.isEmpty else { throw fail("流已结束，但未收到带回答的 response.completed；不能算验证通过。") }
                message = "验证通过：手机直接获得完整云端回答；gpt-6.1-sol / \(effort.rawValue)。"
            } catch {
                guard !Task.isCancelled else { return }
                message = (error as? URLError)?.code == .timedOut ? "云端回答等待超过 90 秒，请重试。" : error.localizedDescription
            }
            timeout?.cancel(); timeout = nil; busy = false
        }
    }
    private func accessToken() async throws -> String {
        guard let record = credential else { throw fail("请先登录 ChatGPT。") }
        if record.expiresAt.timeIntervalSinceNow > 60 { return record.accessToken }
        loggedIn = false
        let json = try await Self.token(["grant_type": "refresh_token", "client_id": record.clientID, "refresh_token": record.refreshToken, "resource": "https://api.openai.com/v1"])
        let replacement = try Self.record(json, client: record.clientID, identity: (record.subject, record.email), idToken: record.idToken)
        try Task.checkCancellation(); try Self.saveCredential(replacement); credential = replacement; loggedIn = true
        return replacement.accessToken
    }
    private static func record(_ json: [String: Any], client: String, identity: (subject: String, email: String?), idToken: String) throws -> Credential {
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String,
              let expires = json["expires_in"] as? Double, expires > 0,
              let scope = json["scope"] as? String, scope.split(separator: " ").contains("chatgpt.tokens.use.direct"),
              (json["token_type"] as? String)?.lowercased() == "bearer" else {
            throw Failure(text: "授权未授予有效的 ChatGPT 订阅使用凭据。")
        }
        return Credential(clientID: client, subject: identity.subject, email: identity.email, accessToken: access, refreshToken: refresh, idToken: idToken, expiresAt: Date().addingTimeInterval(expires), scopes: scope)
    }
    private static func token(_ values: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(values.map { $0.key + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "&").utf8)
        return try await json(request)
    }
    private static func json(_ request: URLRequest) async throws -> [String: Any] {
        var request = request; request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = (body?["error"] as? [String: Any])?["code"] as? String ?? body?["error"] as? String ?? "unknown_error"
            let safe = String(detail.prefix(100)).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
            throw Failure(text: "官方端点请求失败（HTTP \(code)，\(safe)），请检查网络或重新授权。")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure(text: "官方响应格式无效。") }
        return json
    }
    static func verify(_ token: String, clientID: String, nonce: String, suppliedJWKS: [String: Any]? = nil) async throws -> (subject: String, email: String?) {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3, let headerData = decode(parts[0]), let claimsData = decode(parts[1]), let signature = decode(parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256",
              let kid = header["kid"] as? String else { throw Failure(text: "ID token 签名格式不支持。") }
        let jwks: [String: Any]
        if let suppliedJWKS { jwks = suppliedJWKS }
        else { jwks = try await json(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/jwks.json")!)) }
        guard let keys = jwks["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let n = key["n"] as? String, let e = key["e"] as? String, let modulus = decode(n), let exponent = decode(e) else { throw Failure(text: "未找到官方签名公钥。") }
        func der(_ tag: UInt8, _ content: Data) -> Data {
            let size = content.count
            let length: [UInt8] = size < 128 ? [UInt8(size)] : size < 256 ? [0x81, UInt8(size)] : [0x82, UInt8(size >> 8), UInt8(size & 255)]
            return Data([tag] + length) + content
        }
        func integer(_ data: Data) -> Data { der(2, data.first.map { $0 >= 128 } == true ? Data([0]) + data : data) }
        let encoded = der(0x30, integer(modulus) + integer(exponent))
        guard let publicKey = SecKeyCreateWithData(encoded as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil),
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              claims["iss"] as? String == "https://auth.openai.com",
              (claims["aud"] as? String == clientID || (claims["aud"] as? [String])?.contains(clientID) == true),
              let exp = claims["exp"] as? Double, exp > Date().timeIntervalSince1970,
              (claims["nbf"] as? Double ?? 0) <= Date().timeIntervalSince1970,
              claims["nonce"] as? String == nonce, let sub = claims["sub"] as? String, !sub.isEmpty else {
            throw Failure(text: "ID token 签名、账号或有效期验证失败，未保存凭据。")
        }
        return (sub, claims["email"] as? String)
    }
    private static func random() throws -> String {
        var data = Data(count: 32)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard result == errSecSuccess else { throw Failure(text: "无法生成安全授权参数。") }
        return base64url(data)
    }
    private static func base64url(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    private static func decode(_ value: String) -> Data? {
        let value = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
    private static var keyQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "XiangqiNotebook.ChatGPTSubscription", kSecAttrAccount as String: "probe"] }
    private static func readCredential() -> Credential? {
        var query = keyQuery; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }
    private static func saveCredential(_ record: Credential) throws {
        let data = try JSONEncoder().encode(record)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(keyQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(keyQuery.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw Failure(text: "手机钥匙串保存失败（\(status)）。") }
    }
}
#endif
