import Testing
import Foundation
@testable import XiangqiNotebook

/// 引擎分析缓存测试。
///
/// 缓存的价值全在「能不能命中」上：规则定窄了等于白做（每次参数微调就重算），
/// 定宽了会拿一份信息量不足的结果去回答，模型据此下的结论是错的。
/// 所以复用规则这一条要钉死。
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

    @Test func testSatisfies_widerAndLongerCanServeNarrowerAndShorter() {
        // 这是缓存能真正命中的关键：top-5 里切得出 top-3，
        // 算了 5 秒的结论拿去答 3 秒的请求只会更准
        let cached = analysis(multiPV: 5, movetimeMs: 5000)
        #expect(cached.satisfies(multiPV: 3, movetimeMs: 3000))
        #expect(cached.satisfies(multiPV: 5, movetimeMs: 5000))
    }

    @Test func testSatisfies_rejectsNarrowerOrShorterCache() {
        let cached = analysis(multiPV: 3, movetimeMs: 3000)
        // 只存了 3 条，答不了要 5 条的请求——硬答会少给两条候选，
        // 「这步排第几」就可能算成 null，看起来像「连前几名都没进」
        #expect(!cached.satisfies(multiPV: 5, movetimeMs: 3000))
        // 只算了 3 秒，答不了要 5 秒的请求
        #expect(!cached.satisfies(multiPV: 3, movetimeMs: 5000))
    }

    @Test func testLinesLimitedTo_slicesTopN() {
        let cached = analysis(multiPV: 5, movetimeMs: 5000)
        let sliced = cached.lines(limitedTo: 3)
        #expect(sliced.count == 3)
        #expect(sliced.map(\.multipv) == [1, 2, 3])
        // 要多于存量时不能凭空造，给多少算多少
        #expect(cached.lines(limitedTo: 99).count == 5)
    }

    @Test func testSupersedes_prefersTheMoreInformativeOne() {
        let wide = analysis(multiPV: 5, movetimeMs: 5000)
        let narrow = analysis(multiPV: 3, movetimeMs: 3000)
        #expect(wide.supersedes(narrow))
        #expect(!narrow.supersedes(wide))
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

    @Test func testMerge_keepsTheMoreInformativeAnalysisOnConflict() {
        let local = EngineScoreData()
        local.analyses[1] = analysis(multiPV: 5, movetimeMs: 8000)
        let remote = EngineScoreData()
        remote.analyses[1] = analysis(multiPV: 3, movetimeMs: 3000)

        EngineScoreStorage.merge(remote: remote, into: local)
        // 本地那条更宽更久，留它；换成远端的等于白丢一次已经算过的账
        #expect(local.analyses[1]?.multiPV == 5)
        #expect(local.analyses[1]?.movetimeMs == 8000)
    }

    @Test func testMerge_takesRemoteWhenItIsBetter() {
        let local = EngineScoreData()
        local.analyses[1] = analysis(multiPV: 3, movetimeMs: 3000)
        let remote = EngineScoreData()
        remote.analyses[1] = analysis(multiPV: 5, movetimeMs: 8000)

        EngineScoreStorage.merge(remote: remote, into: local)
        #expect(local.analyses[1]?.multiPV == 5)
    }

    // MARK: - 跨设备查找（iPhone 吃 Mac 算好的结果）

    private let macKey = "pikafish_mac_d34"
    private let iosKey = "pikafish_ios"

    @Test func testFindUsable_prefersOwnEngineKey() {
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 5, movetimeMs: 5000,
                                                      engine: "mac"))
        database.setEngineAnalysis(fenId: 1, engineKey: iosKey,
                                   analysis: analysis(multiPV: 5, movetimeMs: 5000,
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
                                   analysis: analysis(multiPV: 5, movetimeMs: 5000,
                                                      engine: "mac"))

        let found = database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 3, movetimeMs: 3000)
        #expect(found?.engine == "mac")
    }

    @Test func testFindUsable_rejectsCacheThatIsNotGoodEnough() {
        // 宁可重算也不能拿信息量不足的结果充数
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 3000))

        #expect(database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 5, movetimeMs: 3000) == nil)
        #expect(database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 3, movetimeMs: 5000) == nil)
    }

    @Test func testFindUsable_picksTheBestAmongOtherKeys() {
        // 字典遍历顺序不保证，不挑最好的会导致同样的请求时好时坏
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: "a",
                                   analysis: analysis(multiPV: 5, movetimeMs: 3000,
                                                      engine: "short"))
        database.setEngineAnalysis(fenId: 1, engineKey: "b",
                                   analysis: analysis(multiPV: 5, movetimeMs: 9000,
                                                      engine: "long"))

        let found = database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: iosKey, multiPV: 3, movetimeMs: 3000)
        #expect(found?.engine == "long")
    }

    @Test func testSetAnalysis_doesNotDowngradeAnExistingEntry() {
        // 先深评过、后来又快问了一次，不能把好结果换成差的
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 5, movetimeMs: 9000))
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 1000))

        let found = database.findUsableEngineAnalysis(
            fenId: 1, preferredKey: macKey, multiPV: 5, movetimeMs: 9000)
        #expect(found?.movetimeMs == 9000)
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
        // 已有更好的结果时 setEngineAnalysis 直接返回，不该无谓置脏——
        // 否则每轮问棋都会因为「脏了」而白写一次盘，即使一个字节都没变
        let database = TestDatabaseBuilder().addFen(1).build()
        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 5, movetimeMs: 9000))
        database.markEngineScoreClean()

        database.setEngineAnalysis(fenId: 1, engineKey: macKey,
                                   analysis: analysis(multiPV: 3, movetimeMs: 1000))
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
