import Testing
import Foundation
@testable import XiangqiNotebook

/// 引擎分析缓存测试。
///
/// 复用规则是「配置完全一致才命中」：同样时间里线路越多、每条搜得越浅，
/// 不同配置的结果没有谁能顶替谁。问棋配置固定，一致即命中。
/// 这一条要钉死，放宽了就会拿浅的结果冒充。
struct EngineAnalysisCacheTests {

    private func line(_ rank: Int, cp: Int) -> EnginePVLine {
        EnginePVLine(multipv: rank, scoreCp: cp, mate: nil, depth: 30, moves: ["h2e2", "h9g7"])
    }

    private func analysis(multiPV: Int, movetimeMs: Int,
                          engine: String = "pikafish-mac") -> CachedAnalysis {
        CachedAnalysis(multiPV: multiPV, movetimeMs: movetimeMs, engine: engine,
                       lines: (1...multiPV).map { line($0, cp: 60 - $0 * 10) })
    }

    // MARK: - 复用规则

    @Test func testSatisfies_requiresExactConfig() {
        let cached = analysis(multiPV: 3, movetimeMs: 3000)
        #expect(cached.satisfies(multiPV: 3, movetimeMs: 3000))
        // 线路多的不能顶替：同样 3 秒，5 条里截出的前 3 条比一次 3 条的搜索浅
        #expect(!analysis(multiPV: 5, movetimeMs: 3000).satisfies(multiPV: 3, movetimeMs: 3000))
        // 时间不同也不行：配置就是配置，不混用
        #expect(!analysis(multiPV: 3, movetimeMs: 8000).satisfies(multiPV: 3, movetimeMs: 3000))
        #expect(!cached.satisfies(multiPV: 5, movetimeMs: 3000))
        #expect(!cached.satisfies(multiPV: 3, movetimeMs: 5000))
    }

    // MARK: - 序列化（要跟着引擎分数文件一起落盘）

    @Test func testEngineScoreData_roundTripsAnalysesAlongsideScores() throws {
        let data = EngineScoreData()
        data.scores[7] = 42
        data.analyses[7] = analysis(multiPV: 5, movetimeMs: 5000)

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(EngineScoreData.self, from: encoded)

        #expect(decoded.scores[7] == 42)
        let restored = try #require(decoded.analyses[7])
        #expect(restored.multiPV == 5)
        #expect(restored.movetimeMs == 5000)
        #expect(restored.engine == "pikafish-mac")
        #expect(restored.lines.count == 5)
        #expect(restored.lines.first?.moves == ["h2e2", "h9g7"])
    }

    @Test func testEngineScoreData_oldFileWithoutAnalysesStillLoads() throws {
        // 存量文件没有这个字段，必须照常读出来——读不了就等于把用户的引擎分全丢了
        let json = #"{"data_version": 3, "scores": {"1": 20, "2": -35}}"#
        let decoded = try JSONDecoder().decode(EngineScoreData.self, from: Data(json.utf8))
        #expect(decoded.dataVersion == 3)
        #expect(decoded.scores == [1: 20, 2: -35])
        #expect(decoded.analyses.isEmpty)
    }

    @Test func testEngineScoreData_analysisKeysSurviveIntToStringConversion() throws {
        // JSON 的 key 只能是字符串，Int key 要来回转换。转丢了就是全表落空
        let data = EngineScoreData()
        for fenId in [1, 42, 9999] {
            data.analyses[fenId] = analysis(multiPV: 3, movetimeMs: 3000)
        }
        let decoded = try JSONDecoder().decode(
            EngineScoreData.self, from: try JSONEncoder().encode(data))
        #expect(Set(decoded.analyses.keys) == Set([1, 42, 9999]))
    }

    // MARK: - iCloud 合并

    @Test func testMerge_bringsInRemoteAnalysesTheLocalLacks() {
        // 不合并的话，保存时整文件覆盖会抹掉另一台设备算好的结果
        let local = EngineScoreData()
        local.analyses[1] = analysis(multiPV: 5, movetimeMs: 5000)
        let remote = EngineScoreData()
        remote.analyses[2] = analysis(multiPV: 5, movetimeMs: 5000)

        EngineScoreStorage.merge(remote: remote, into: local)
        #expect(Set(local.analyses.keys) == Set([1, 2]))
    }

    @Test func testMerge_keepsLocalAnalysisOnConflict() {
        // 与分数同一语义：冲突时本地优先。配置不同的两条没有谁更好，本地是本机最新算的
        let local = EngineScoreData()
        local.analyses[1] = analysis(multiPV: 3, movetimeMs: 3000)
        let remote = EngineScoreData()
        remote.analyses[1] = analysis(multiPV: 5, movetimeMs: 8000)

        EngineScoreStorage.merge(remote: remote, into: local)
        #expect(local.analyses[1]?.multiPV == 3)
        #expect(local.analyses[1]?.movetimeMs == 3000)
    }

    // MARK: - 跨设备查找（iPhone 吃 Mac 算好的结果）

    private let macKey = "pikafish_mac_d34"
    private let iosKey = "pikafish_ios"

    @Test func testFindUsable_prefersOwnEngineKey() {
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000,
                                                      engine: "mac"))
        database.setEngineAnalysis(fenId: 1, engineKey: iosKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000,
                                                      engine: "ios"))

        let found = database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 3, movetimeMs: 3000)
        #expect(found?.engine == "ios", "自己这台设备算过就用自己的")
    }

    @Test func testFindUsable_fallsBackToAnotherDevicesResult() {
        // 这条是「iPhone 省电」的全部意义：本机没算过，就用 Mac 算好的，
        // 而不是现场烧一遍电
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000,
                                                      engine: "mac"))

        let found = database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 3, movetimeMs: 3000)
        #expect(found?.engine == "mac")
    }

    @Test func testFindUsable_rejectsDifferentConfig() {
        // 宁可重算也不能拿别的配置充数，哪怕它线路更多、算得更久
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 5, movetimeMs: 8000))

        #expect(database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 3, movetimeMs: 3000) == nil)
        #expect(database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: macKey, multiPV: 3, movetimeMs: 3000) == nil)
    }

    @Test func testFindUsable_isDeterministicAmongOtherKeys() {
        // 字典遍历顺序不保证，同样的请求必须每次拿到同一条
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: "b",
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000, engine: "b"))
        database.setEngineAnalysis(fenId: 1, engineKey: "a",
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000, engine: "a"))

        let found = database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 3, movetimeMs: 3000)
        #expect(found?.engine == "a")
    }

    @Test func testSetAnalysis_replacesEntryOfDifferentConfig() {
        // 旧配置（如以前模型自选的 5 条 8 秒）已不会被命中，新算的直接换掉它
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 5, movetimeMs: 8000))
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000))

        let found = database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: macKey, multiPV: 3, movetimeMs: 3000)
        #expect(found?.multiPV == 3)
    }

    @Test func testSetAnalysis_marksDirtyInsteadOfWritingImmediately() {
        // 落盘要推迟到一轮问棋结束再做一次。saveEngineScore 是整份读-改-写，
        // 一轮评点要分析六七次，每次都存等于在主线程上把几百 KB 的文件反复重写
        let database = TestDatabaseBuilder().addFen(1).build()
        #expect(!database.isEngineScoreDirty)

        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000))
        #expect(database.isEngineScoreDirty, "写完要置脏，否则收尾时那一次保存会被跳过，缓存永远落不了盘")
    }

    @Test func testSetAnalysis_staysCleanWhenTheWriteIsRejected() {
        // 已有同配置的结果时 setEngineAnalysis 直接返回，不该无谓置脏——
        // 否则每轮问棋都会因为「脏了」而白写一次盘，即使一个字节都没变
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000))
        database.markEngineScoreClean()

        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000))
        #expect(!database.isEngineScoreDirty)
    }

    @Test func testMerge_doesNotDisturbScores() {
        // 分数的合并语义（本地优先）不能被分析缓存的改动带偏
        let local = EngineScoreData()
        local.scores[1] = 100
        let remote = EngineScoreData()
        remote.scores[1] = 999
        remote.scores[2] = 50

        EngineScoreStorage.merge(remote: remote, into: local)
        #expect(local.scores[1] == 100, "本地已有的分数不该被远端覆盖")
        #expect(local.scores[2] == 50)
    }
}
