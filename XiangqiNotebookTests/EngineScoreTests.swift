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
    @Test func testHashSizeScalesWithMemory() {
        let gb: UInt64 = 1 << 30
        #expect(PikafishService.hashSizeMB(physicalMemoryBytes: 8 * gb) == 1024)
        #expect(PikafishService.hashSizeMB(physicalMemoryBytes: 16 * gb) == 2048)
        #expect(PikafishService.hashSizeMB(physicalMemoryBytes: 64 * gb) == 4096, "上限 4GB")
        #expect(PikafishService.hashSizeMB(physicalMemoryBytes: 1 * gb) == 256, "下限 256MB")
    }

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

    // MARK: - 跨设备合并（issue #161）

    @Test func testMerge_RemoteOnlyEntriesAreAdded() {
        let local = EngineScoreData()
        local.dataVersion = 3
        local.scores = [1: 100, 2: -50]

        let remote = EngineScoreData()
        remote.dataVersion = 5
        remote.scores = [2: -999, 3: 30]  // 2 与本地冲突，3 为远端独有

        EngineScoreStorage.merge(remote: remote, into: local)

        #expect(local.scores[1] == 100)   // 本地独有保留
        #expect(local.scores[2] == -50)   // 冲突时本地优先
        #expect(local.scores[3] == 30)    // 远端独有补充
        #expect(local.dataVersion == 5)   // 版本取较大者
    }

    @Test func testMerge_EmptyRemote_NoChange() {
        let local = EngineScoreData()
        local.dataVersion = 3
        local.scores = [1: 100]

        EngineScoreStorage.merge(remote: EngineScoreData(), into: local)

        #expect(local.scores == [1: 100])
        #expect(local.dataVersion == 3)
    }
}

struct EngineScoreStoragePlaceholderTests {
    /// 实体文件缺席、同目录有 ".<name>.icloud" 占位 → 视为未下载；实体文件在 → 不是
    @Test func testHasUndownloadedPlaceholder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-score-placeholder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let real = dir.appendingPathComponent("scores.json")
        #expect(!EngineScoreStorage.hasUndownloadedPlaceholder(for: real))

        let placeholder = dir.appendingPathComponent(".scores.json.icloud")
        try Data().write(to: placeholder)
        #expect(EngineScoreStorage.hasUndownloadedPlaceholder(for: real))

        try Data("{}".utf8).write(to: real)
        #expect(!EngineScoreStorage.hasUndownloadedPlaceholder(for: real))
    }
}
