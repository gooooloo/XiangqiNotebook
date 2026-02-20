import Testing
import Foundation
@testable import XiangqiNotebook

struct EngineScoreDataTests {

    @Test func testEngineScoreDataInitialization() {
        let data = EngineScoreData()
        #expect(data.dataVersion == 0)
        #expect(data.scores.isEmpty)
    }

    @Test func testEngineScoreDataEncoding() throws {
        let data = EngineScoreData()
        data.dataVersion = 5
        data.scores = [453: 26, 12: -100, 1: 0]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(data)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EngineScoreData.self, from: jsonData)

        #expect(decoded.dataVersion == 5)
        #expect(decoded.scores.count == 3)
        #expect(decoded.scores[453] == 26)
        #expect(decoded.scores[12] == -100)
        #expect(decoded.scores[1] == 0)
    }

    @Test func testEngineScoreDataDecodingFromJSON() throws {
        let json = """
        {
            "data_version": 3,
            "scores": {
                "100": 42,
                "200": -50
            }
        }
        """
        let jsonData = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EngineScoreData.self, from: jsonData)

        #expect(decoded.dataVersion == 3)
        #expect(decoded.scores[100] == 42)
        #expect(decoded.scores[200] == -50)
    }

    @Test func testEngineScoreDataDecodingEmptyScores() throws {
        let json = """
        {
            "data_version": 0,
            "scores": {}
        }
        """
        let jsonData = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EngineScoreData.self, from: jsonData)

        #expect(decoded.dataVersion == 0)
        #expect(decoded.scores.isEmpty)
    }

    @Test func testEngineScoreDataDecodingMissingFields() throws {
        let json = "{}"
        let jsonData = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(EngineScoreData.self, from: jsonData)

        #expect(decoded.dataVersion == 0)
        #expect(decoded.scores.isEmpty)
    }
}

#if os(macOS)
struct PikafishEngineKeyTests {
    @Test func testEngineKeyConstants() {
        #expect(PikafishService.engineVersion == "Pikafish_dev-20260213-391d491a")
        #expect(PikafishService.searchDepth == 34)
        #expect(PikafishService.engineKey == "Pikafish_dev-20260213-391d491a_d34")
    }
}
#endif

struct EngineScoreStorageTests {

    @Test func testEngineScoreRoundTrip() throws {
        // 使用临时目录测试文件读写
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngineScoreTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let data = EngineScoreData()
        data.dataVersion = 7
        data.scores = [1: 100, 2: -50, 3: 0]

        // 保存
        let fileURL = tmpDir.appendingPathComponent("test_engine.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: fileURL, options: .atomic)

        // 读取
        let readData = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(EngineScoreData.self, from: readData)

        #expect(decoded.dataVersion == 7)
        #expect(decoded.scores.count == 3)
        #expect(decoded.scores[1] == 100)
        #expect(decoded.scores[2] == -50)
        #expect(decoded.scores[3] == 0)
    }
}
