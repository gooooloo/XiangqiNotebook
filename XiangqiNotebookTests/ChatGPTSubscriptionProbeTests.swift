#if os(iOS)
import XCTest
import Security
@testable import XiangqiNotebook

@MainActor
final class ChatGPTSubscriptionProbeTests: XCTestCase {
    func testSubscriptionRequestAndToolResultRoundTrip() throws {
        let response: [String: Any] = ["status": "completed", "output": [
            ["type": "reasoning", "id": "rs_1", "summary": [], "encrypted_content": "encrypted-test"],
            ["type": "function_call", "id": "fc_1", "call_id": "call_1", "name": "get_position", "arguments": "{}"],
        ], "usage": ["input_tokens": 100, "output_tokens": 20, "input_tokens_details": ["cached_tokens": 40]]]
        let parsed = try ChatGPTSubscriptionClient.completedResponse(response)
        XCTAssertEqual(parsed.toolCalls, [LLMToolCall(id: "call_1", name: "get_position", argumentsJSON: "{}")])
        XCTAssertEqual(parsed.usage, TokenUsage(promptTokens: 100, cachedTokens: 40, completionTokens: 20))
        var assistant = LLMMessage.assistant(parsed.content, toolCalls: parsed.toolCalls)
        assistant.responsesOutput = parsed.responsesOutput
        let data = try ChatGPTSubscriptionClient.requestBody(messages: [
            .system("象棋老师"), .user("这步怎么样"), assistant,
            .toolResult(callId: "call_1", content: "局面分析结果"),
        ], tools: AnalysisToolbox.toolSpecs, effort: .low)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "gpt-6.1-sol")
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "low")
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 5)
        XCTAssertEqual(input[0]["role"] as? String, "developer")
        XCTAssertEqual(input[2]["encrypted_content"] as? String, "encrypted-test")
        XCTAssertEqual(input[3]["call_id"] as? String, "call_1")
        XCTAssertEqual(input[4]["type"] as? String, "function_call_output")
        XCTAssertEqual(input[4]["call_id"] as? String, "call_1")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "namespace")
        XCTAssertEqual(tools.first?["name"] as? String, "xiangqi")
        let functions = try XCTUnwrap(tools.first?["tools"] as? [[String: Any]])
        XCTAssertEqual(functions.first?["name"] as? String, "get_position")
        XCTAssertEqual(functions.first?["strict"] as? Bool, false)
        XCTAssertNil(functions.first?["function"])
        XCTAssertTrue(AIWireFormat.allCases.contains(.codex))
        var config = AIConfig.empty
        config.wireFormat = .codex
        XCTAssertTrue(LLMClientFactory.make(config: config) is ChatGPTSubscriptionClient)
        XCTAssertFalse(config.effectivePricing.isConfigured)
    }

    func testSubscriptionCompletedAnswerAndInvalidOutput() throws {
        let result = try ChatGPTSubscriptionClient.completedResponse([
            "status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": "红方占优"]]]],
        ])
        XCTAssertEqual(result.content, "红方占优")
        XCTAssertTrue(result.toolCalls.isEmpty)
        XCTAssertThrowsError(try ChatGPTSubscriptionClient.completedResponse(["status": "incomplete", "output": []]))
        XCTAssertThrowsError(try ChatGPTSubscriptionClient.completedResponse(["status": "completed", "output": []]))
        XCTAssertThrowsError(try ChatGPTSubscriptionClient.completedResponse([
            "status": "completed", "output": [["type": "function_call", "name": "evaluate"]],
        ]))
    }

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
