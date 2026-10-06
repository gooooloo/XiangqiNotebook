#if os(iOS)
import XCTest
import Security
@testable import XiangqiNotebook

@MainActor
final class ChatGPTSubscriptionProbeTests: XCTestCase {
    func testRealLoopbackRejectsWrongStateAndAcceptsDenial() async throws {
        let suite = "SubscriptionProbeTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let probe = ChatGPTSubscriptionProbe(loadSavedCredential: false, defaults: defaults)
        probe.login()
        defer { probe.cancel() }
        for _ in 0..<100 {
            if probe.browserURL != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let authorization = try XCTUnwrap(probe.browserURL?.url)
        let values = Dictionary(uniqueKeysWithValues: URLComponents(url: authorization, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(values["client_id"], "dynamic_agent_client")
        XCTAssertEqual(values["agent_name_hint"], "XiangqiNotebook")
        XCTAssertEqual(values["code_challenge_method"], "S256")
        XCTAssertTrue(values["scope"]!.contains("chatgpt.tokens.use.direct"))
        let redirect = try XCTUnwrap(values["redirect_uri"])
        XCTAssertTrue(redirect.hasPrefix("http://127.0.0.1:"))
        XCTAssertTrue(redirect.hasSuffix("/auth/callback"))
        let wrong = URL(string: redirect + "?state=wrong&error=access_denied")!
        let (_, response) = try await URLSession.shared.data(from: wrong)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertTrue(probe.busy)
        let correct = URL(string: redirect + "?state=" + values["state"]! + "&error=access_denied")!
        _ = try await URLSession.shared.data(from: correct)
        for _ in 0..<100 {
            if !probe.busy { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(probe.busy)
        XCTAssertFalse(probe.loggedIn)
        XCTAssertTrue(probe.message.contains("access_denied"))
    }

    func testSignatureNonceAudienceAndExpiry() async throws {
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
        var cursor = 0
        func read(_ data: Data, cursor: inout Int) -> Data {
            cursor += 1
            var count = Int(data[cursor]); cursor += 1
            if count & 128 != 0 {
                let bytes = count & 127; count = 0
                for _ in 0..<bytes { count = count * 256 + Int(data[cursor]); cursor += 1 }
            }
            let result = data.subdata(in: cursor..<cursor + count); cursor += count; return result
        }
        let sequence = read(der, cursor: &cursor)
        cursor = 0
        var n = read(sequence, cursor: &cursor)
        if n.first == 0 { n.removeFirst() }
        let e = read(sequence, cursor: &cursor)
        func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let jwks: [String: Any] = ["keys": [["kid": "test", "kty": "RSA", "n": encode(n), "e": encode(e)]]]
        func token(_ overrides: [String: Any] = [:]) throws -> String {
            let header = encode(try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "test"]))
            let claims: [String: Any] = ["iss": "https://auth.openai.com", "aud": "oaiapp_test", "sub": "test-subject", "nonce": "test-nonce", "exp": Date().timeIntervalSince1970 + 300]
            let payload = encode(try JSONSerialization.data(withJSONObject: claims.merging(overrides) { _, new in new }))
            let signed = header + "." + payload
            let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(signed.utf8) as CFData, nil)) as Data
            return signed + "." + encode(signature)
        }
        let valid = try token()
        let identity = try await ChatGPTSubscriptionProbe.verify(valid, clientID: "oaiapp_test", nonce: "test-nonce", suppliedJWKS: jwks)
        XCTAssertEqual(identity.subject, "test-subject")
        for overrides: [String: Any] in [["nonce": "wrong"], ["aud": "other"], ["exp": 1], ["iss": "https://example.com"], ["nbf": Date().timeIntervalSince1970 + 300]] {
            do {
                _ = try await ChatGPTSubscriptionProbe.verify(token(overrides), clientID: "oaiapp_test", nonce: "test-nonce", suppliedJWKS: jwks)
                XCTFail("Invalid claims must be rejected")
            } catch {}
        }
        let parts = valid.split(separator: ".")
        let tampered = String(parts[0]) + "." + encode(Data("{}".utf8)) + "." + parts[2]
        do {
            _ = try await ChatGPTSubscriptionProbe.verify(tampered, clientID: "oaiapp_test", nonce: "test-nonce", suppliedJWKS: jwks)
            XCTFail("Tampered signature must be rejected")
        } catch {}
    }
}
#endif
