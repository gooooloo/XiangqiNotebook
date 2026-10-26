import Foundation
import Security

struct CoachServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A different credential namespace from AIChat. Endpoint-scoped and machine-local.
struct CoachCredential {
    static func query(endpoint: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.gooooloo.XiangqiNotebook.coach",
            kSecAttrAccount as String: endpoint]
        #if os(macOS)
        q[kSecUseDataProtectionKeychain as String] = true
        #endif
        return q
    }
    static func read(endpoint: String) -> String {
        guard !AIKeychain.isRunningInTests else { return "" }
        var q = query(endpoint: endpoint)
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String, endpoint: String) throws {
        guard !AIKeychain.isRunningInTests else { return }
        let q = query(endpoint: endpoint)
        let values: [String: Any] = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(q as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var add = q.merging(values) { _, new in new }
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CoachServiceError(message: "无法保存教练凭据（\(status)）") }
    }
}

final class CoachNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct CoachAPI {
    let endpoint: URL
    let token: String
    static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host))
        else { throw CoachServiceError(message: "请输入 HTTPS 服务根地址；HTTP 仅允许本机调试。") }
        return url
    }
    func request(path: String = "v1/coach", body: Data? = nil) async throws -> CoachSnapshot {
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        let session = URLSession(configuration: .ephemeral, delegate: CoachNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let error = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            throw CoachServiceError(message: error?["error"] ?? "无法连接教练服务，请检查地址和凭据。")
        }
        return try JSONDecoder().decode(CoachSnapshot.self, from: data)
    }
    func post<T: Encodable>(_ path: String, _ body: T) async throws -> CoachSnapshot {
        try await request(path: path, body: JSONEncoder().encode(body))
    }
}
