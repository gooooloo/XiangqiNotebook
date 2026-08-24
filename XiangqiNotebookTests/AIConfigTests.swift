import Testing
import Foundation
@testable import XiangqiNotebook

/// AI 服务配置的纯逻辑测试。
/// 不碰钥匙串——那部分留给端到端验证，单测里读写真钥匙串既慢又可能弹授权框。
struct AIConfigTests {

    // MARK: - 地址规范化

    @Test func testChatCompletionsURL_appendsPathToVersionedBase() {
        #expect(AIConfig.chatCompletionsURL(from: "https://api.deepseek.com/v1")?.absoluteString
                == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func testChatCompletionsURL_addsV1ForBareHost() {
        // 用户常只填域名，这时补 /v1 是合理默认
        #expect(AIConfig.chatCompletionsURL(from: "https://api.deepseek.com")?.absoluteString
                == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func testChatCompletionsURL_preservesNonV1Paths() {
        // 智谱是 /api/paas/v4，通义是 /compatible-mode/v1——
        // 各家版本段不统一，有路径就不能自作主张改
        #expect(AIConfig.chatCompletionsURL(from: "https://open.bigmodel.cn/api/paas/v4")?.absoluteString
                == "https://open.bigmodel.cn/api/paas/v4/chat/completions")
        #expect(AIConfig.chatCompletionsURL(from: "https://dashscope.aliyuncs.com/compatible-mode/v1")?.absoluteString
                == "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")
    }

    @Test func testChatCompletionsURL_toleratesTrailingSlashAndWhitespace() {
        #expect(AIConfig.chatCompletionsURL(from: "  https://api.deepseek.com/v1///  ")?.absoluteString
                == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func testChatCompletionsURL_doesNotDoubleAppend() {
        // 用户把完整端点粘进来也要能用
        #expect(AIConfig.chatCompletionsURL(from: "https://api.deepseek.com/v1/chat/completions")?.absoluteString
                == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func testChatCompletionsURL_supportsLocalHTTPAndPort() {
        // 本机 Ollama 是 http 且带端口
        #expect(AIConfig.chatCompletionsURL(from: "http://localhost:11434/v1")?.absoluteString
                == "http://localhost:11434/v1/chat/completions")
    }

    @Test func testChatCompletionsURL_stripsQueryAndFragment() {
        #expect(AIConfig.chatCompletionsURL(from: "https://api.deepseek.com/v1?foo=1#bar")?.absoluteString
                == "https://api.deepseek.com/v1/chat/completions")
    }

    @Test func testChatCompletionsURL_rejectsInvalidInput() {
        #expect(AIConfig.chatCompletionsURL(from: "") == nil)
        #expect(AIConfig.chatCompletionsURL(from: "   ") == nil)
        #expect(AIConfig.chatCompletionsURL(from: "api.deepseek.com") == nil, "缺 scheme 应判无效")
        #expect(AIConfig.chatCompletionsURL(from: "ftp://api.deepseek.com") == nil, "非 http(s) 应判无效")
        #expect(AIConfig.chatCompletionsURL(from: "https://") == nil, "缺 host 应判无效")
    }

    // MARK: - 配置完整性

    @Test func testIsConfigured_requiresAllThreeFields() {
        let full = AIConfig(baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", apiKey: "sk-x")
        #expect(full.isConfigured)

        #expect(!AIConfig(baseURL: "", model: "deepseek-chat", apiKey: "sk-x").isConfigured)
        #expect(!AIConfig(baseURL: "https://api.deepseek.com/v1", model: "", apiKey: "sk-x").isConfigured)
        #expect(!AIConfig(baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", apiKey: "").isConfigured)
        #expect(!AIConfig.empty.isConfigured)
    }

    @Test func testIsConfigured_rejectsWhitespaceOnlyAndBadURL() {
        #expect(!AIConfig(baseURL: "https://api.deepseek.com/v1", model: "  ", apiKey: "sk-x").isConfigured)
        #expect(!AIConfig(baseURL: "不是地址", model: "deepseek-chat", apiKey: "sk-x").isConfigured)
    }

    // MARK: - 预设

    @Test func testPresets_allHaveUsableURLs() {
        #expect(!AIProviderPreset.all.isEmpty)
        for preset in AIProviderPreset.all {
            #expect(AIConfig.chatCompletionsURL(from: preset.baseURL) != nil,
                    "预设 \(preset.name) 的地址推不出端点")
            #expect(!preset.suggestedModel.isEmpty, "预设 \(preset.name) 缺建议模型")
        }
    }

    @Test func testPresets_haveDistinctBaseURLs() {
        let urls = AIProviderPreset.all.map(\.baseURL)
        #expect(Set(urls).count == urls.count, "预设地址重复了，说明有一项填错")
    }

    @Test func testPresets_miniMaxRegionalDomainsAreNotConfused() {
        // minimax.io（国际）与 minimaxi.com（国内）只差一个字母，
        // 极易在维护时被「顺手改正」成同一个。锁住两者与各自的归属
        let miniMax = AIProviderPreset.all.filter { $0.name.hasPrefix("MiniMax") }
        #expect(miniMax.count == 2)
        #expect(miniMax.first { $0.name.contains("国际") }?.baseURL == "https://api.minimax.io/v1")
        #expect(miniMax.first { $0.name.contains("国内") }?.baseURL == "https://api.minimaxi.com/v1")
    }

    @Test func testPresets_noBareMiniMaxThatCouldBeMisclicked() {
        // 光秃秃的「MiniMax」会被当成默认而误点，两项必须各带限定词
        #expect(!AIProviderPreset.all.contains { $0.name == "MiniMax" })
    }

    @Test func testPresets_miniMaxInternationalCarriesVerifiedPricing() throws {
        // minimax.io 价目表（M3，Context ≤ 512K，永久五折后）：0.3 / 1.2 / 0.06 美元
        let preset = try #require(AIProviderPreset.all.first { $0.name == "MiniMax 国际" })
        let pricing = try #require(preset.suggestedPricing)
        #expect(pricing.currency == "$")
        #expect(pricing.inputPerMillion == 0.3)
        #expect(pricing.outputPerMillion == 1.2)
        #expect(pricing.cachedPerMillion == 0.06)
    }

    @Test func testPresets_onlyVerifiedProvidersSuggestPricing() throws {
        // 没核对过的服务必须留空。给一个看着像真的的错价，比不给更坏——
        // 用户不会去质疑一个已经填好的数字
        let withPricing = AIProviderPreset.all.filter { $0.suggestedPricing != nil }
        #expect(withPricing.map(\.name) == ["MiniMax 国际"])

        // 国内平台按人民币计价，与那张美元表不是一回事
        let domestic = try #require(AIProviderPreset.all.first { $0.name == "MiniMax 国内" })
        #expect(domestic.suggestedPricing == nil)
    }

    @Test func testPresets_suggestedPricingIsUsable() {
        // 建议价必须真能算出钱来，否则填了也是白填
        for preset in AIProviderPreset.all {
            guard let pricing = preset.suggestedPricing else { continue }
            #expect(pricing.isConfigured, "\(preset.name) 的建议价算不出花费")
            #expect(AIPricing.currencies.contains(pricing.currency),
                    "\(preset.name) 的币种不在可选项里，界面上选不中")
        }
    }

    // MARK: - 计费

    /// MiniMax-M3 的实际价目（$/百万 tokens），拿来当算例
    private let m3 = AIPricing(currency: "$", inputPerMillion: 0.3,
                               outputPerMillion: 1.2, cachedPerMillion: 0.06)

    @Test func testPricing_emptyMeansNoCostShown() {
        #expect(!AIPricing.empty.isConfigured)
        #expect(AIPricing.empty.cost(promptTokens: 10_000, cachedTokens: 0,
                                     completionTokens: 5_000) == nil)
    }

    @Test func testPricing_chargesInputAndOutputSeparately() throws {
        // 100 万输入 + 100 万输出 = 0.3 + 1.2
        let cost = try #require(m3.cost(promptTokens: 1_000_000, cachedTokens: 0,
                                        completionTokens: 1_000_000))
        #expect(abs(cost - 1.5) < 0.000_001)
    }

    @Test func testPricing_cachedPortionIsBilledAtCacheRate() throws {
        // 100 万输入里 80 万命中缓存：20万×0.3 + 80万×0.06 = 0.06 + 0.048
        let cost = try #require(m3.cost(promptTokens: 1_000_000, cachedTokens: 800_000,
                                        completionTokens: 0))
        #expect(abs(cost - 0.108) < 0.000_001)
    }

    @Test func testPricing_cachedTokensAreNotDoubleCounted() throws {
        // cachedTokens 含在 promptTokens 里。若实现把它当额外量加一遍，
        // 这里算出来会比全额输入价还贵
        let full = try #require(m3.cost(promptTokens: 1_000_000, cachedTokens: 0,
                                        completionTokens: 0))
        let cached = try #require(m3.cost(promptTokens: 1_000_000, cachedTokens: 1_000_000,
                                          completionTokens: 0))
        #expect(cached < full)
    }

    @Test func testPricing_missingCacheRateFallsBackToInputRate() throws {
        // 没填缓存价时按输入价算——偏保守，宁可报高不报低
        let noCacheRate = AIPricing(currency: "$", inputPerMillion: 0.3,
                                    outputPerMillion: 1.2, cachedPerMillion: nil)
        let cost = try #require(noCacheRate.cost(promptTokens: 1_000_000, cachedTokens: 900_000,
                                                 completionTokens: 0))
        #expect(abs(cost - 0.3) < 0.000_001)
    }

    @Test func testPricing_cachedTokensAreClampedToPromptTokens() throws {
        // 服务端报了个大于 prompt 的缓存数也不能算出负的新增量
        let cost = try #require(m3.cost(promptTokens: 1000, cachedTokens: 99_999,
                                        completionTokens: 0))
        #expect(cost > 0)
    }

    @Test func testPricing_formatsWithCurrency() {
        let text = m3.formattedCost(promptTokens: 10_000_000, cachedTokens: 0, completionTokens: 0)
        #expect(text == "$3.0000")
    }

    @Test func testPricing_tinyAmountsKeepFourDecimals() {
        // 一次问答就在几厘钱量级，两位小数会把它压成 $0.00——看不出差别，也加不出合计
        // 5000×0.3/M + 800×1.2/M = 0.0015 + 0.00096
        let text = m3.formattedCost(promptTokens: 5_000, cachedTokens: 0, completionTokens: 800)
        #expect(text == "$0.0025")
    }

    @Test func testPricing_zeroUsageIsZero() {
        #expect(m3.formattedCost(promptTokens: 0, cachedTokens: 0, completionTokens: 0) == "$0.0000")
    }

    @Test func testPricing_footerTotalMatchesBreakdownSum() {
        // 页脚与明细必须同一个口径：格式化后也要字面相等，
        // 否则展开一看「上面写 $0.01、下面加出 $0.0093」，用户只会更没底
        let usage = (prompt: 26_400, cached: 19_800, completion: 5_100)
        let footer = m3.formattedCost(promptTokens: usage.prompt, cachedTokens: usage.cached,
                                      completionTokens: usage.completion)
        let lines = m3.breakdown(promptTokens: usage.prompt, cachedTokens: usage.cached,
                                 completionTokens: usage.completion)
        let sum = lines.reduce(0) { $0 + $1.amount }
        #expect(footer == AIPricing.amountText(sum, currency: "$"))
    }

    // MARK: - 计费持久化

    private func scratchDefaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: "AIConfigTests.\(name)"))
        defaults.removePersistentDomain(forName: "AIConfigTests.\(name)")
        return defaults
    }

    /// 测试绝不能碰真钥匙串：key 是用户的真实凭据，删了不可恢复，
    /// 而且带 `kSecAttrSynchronizable`，一删是全设备一起没
    private final class InMemoryKeyStore: APIKeyStoring {
        private var stored: String?
        func read() -> String? { stored }
        func write(_ key: String) throws { stored = key.isEmpty ? nil : key }
    }

    @Test func testPricing_roundTripsThroughUserDefaults() throws {
        let defaults = try scratchDefaults(#function)
        let keyStore = InMemoryKeyStore()
        var config = AIConfig(baseURL: "https://api.minimax.io/v1", model: "MiniMax-M3", apiKey: "k")
        config.pricing = m3
        try config.save(userDefaults: defaults, keyStore: keyStore)

        let loaded = AIConfig.load(userDefaults: defaults, keyStore: keyStore)
        #expect(loaded.pricing.currency == "$")
        #expect(loaded.pricing.inputPerMillion == 0.3)
        #expect(loaded.pricing.outputPerMillion == 1.2)
        #expect(loaded.pricing.cachedPerMillion == 0.06)
    }

    @Test func testPricing_clearedPriceReadsBackAsUnsetNotZero() throws {
        // 关键区别：写 0 会被读成「单价是 0」，估出来永远不花钱。清空必须真的删键
        let defaults = try scratchDefaults(#function)
        let keyStore = InMemoryKeyStore()
        var config = AIConfig(baseURL: "https://x.com/v1", model: "m", apiKey: "k")
        config.pricing = m3
        try config.save(userDefaults: defaults, keyStore: keyStore)

        config.pricing = .empty
        try config.save(userDefaults: defaults, keyStore: keyStore)

        let loaded = AIConfig.load(userDefaults: defaults, keyStore: keyStore)
        #expect(loaded.pricing.inputPerMillion == nil)
        #expect(loaded.pricing.outputPerMillion == nil)
        #expect(!loaded.pricing.isConfigured)
    }

    // MARK: - 花费明细

    @Test func testBreakdown_linesSumToTheSameTotalAsCost() throws {
        // 明细各行相加必须正好等于合计。对不上就是自证不可信——
        // 这个界面存在的全部意义就是让用户能核账
        let usage = (prompt: 26_400, cached: 19_800, completion: 5_100)
        let lines = m3.breakdown(promptTokens: usage.prompt, cachedTokens: usage.cached,
                                 completionTokens: usage.completion)
        let total = try #require(m3.cost(promptTokens: usage.prompt, cachedTokens: usage.cached,
                                         completionTokens: usage.completion))
        #expect(abs(lines.reduce(0) { $0 + $1.amount } - total) < 0.000_000_1)
    }

    @Test func testBreakdown_splitsFreshAndCachedInput() throws {
        let lines = m3.breakdown(promptTokens: 10_000, cachedTokens: 8_000, completionTokens: 2_000)
        #expect(lines.map(\.label) == ["输入", "缓存", "输出"])
        // 「输入」那行只算未命中缓存的部分，不能把缓存 token 重复计一遍
        #expect(lines[0].tokens == 2_000)
        #expect(lines[1].tokens == 8_000)
        #expect(lines[2].tokens == 2_000)
        #expect(lines[0].unitPrice == 0.3)
        #expect(lines[1].unitPrice == 0.06)
        #expect(lines[2].unitPrice == 1.2)
    }

    @Test func testBreakdown_omitsZeroTokenRows() {
        // 服务端不报缓存时不该多出一行「缓存 0」
        let lines = m3.breakdown(promptTokens: 5_000, cachedTokens: 0, completionTokens: 800)
        #expect(lines.map(\.label) == ["输入", "输出"])
    }

    @Test func testBreakdown_stillReportsTokensWithoutPricing() {
        // 没填单价也要让人看见 token 花在哪儿了，只是不给金额
        let lines = AIPricing.empty.breakdown(promptTokens: 5_000, cachedTokens: 0,
                                              completionTokens: 800)
        #expect(lines.map(\.tokens) == [5_000, 800])
        #expect(lines.allSatisfy { $0.unitPrice == nil })
        #expect(lines.allSatisfy { $0.amountText == nil })
    }

    @Test func testBreakdown_cachedFallsBackToInputRate() throws {
        let noCacheRate = AIPricing(currency: "$", inputPerMillion: 0.3,
                                    outputPerMillion: 1.2, cachedPerMillion: nil)
        let lines = noCacheRate.breakdown(promptTokens: 10_000, cachedTokens: 8_000,
                                          completionTokens: 0)
        let cached = try #require(lines.first { $0.label == "缓存" })
        #expect(cached.unitPrice == 0.3)
    }

    @Test func testCostLine_textFormatting() throws {
        let lines = m3.breakdown(promptTokens: 26_400, cachedTokens: 0, completionTokens: 0)
        let input = try #require(lines.first)
        #expect(input.tokensText.contains("26"))
        // %g：0.3 不该显示成 0.300000
        #expect(input.unitPriceText == "$0.3 / 百万")
        #expect(input.amountText == "$0.0079")
    }

    @Test func testAmountText_alwaysFourDecimals() {
        // 大小额都用同一个口径，免得一栏里两种小数位对不齐
        #expect(AIPricing.amountText(0.0053, currency: "$") == "$0.0053")
        #expect(AIPricing.amountText(1.5, currency: "$") == "$1.5000")
        #expect(AIPricing.amountText(0, currency: "¥") == "¥0.0000")
    }

    // MARK: - 建议价兜底

    @Test func testLoad_fillsPricingFromPresetWhenUserNeverSetIt() throws {
        // 花费显示要开箱即用：地址是已核对过的预设时，不必先去设置页点一下
        let defaults = try scratchDefaults(#function)
        let keyStore = InMemoryKeyStore()
        let config = AIConfig(baseURL: "https://api.minimax.io/v1", model: "MiniMax-M3", apiKey: "k")
        try config.save(userDefaults: defaults, keyStore: keyStore)

        let loaded = AIConfig.load(userDefaults: defaults, keyStore: keyStore)
        #expect(loaded.pricing.currency == "$")
        #expect(loaded.pricing.inputPerMillion == 0.3)
        #expect(loaded.pricing.outputPerMillion == 1.2)
        #expect(loaded.pricing.cachedPerMillion == 0.06)
    }

    @Test func testLoad_neverOverridesPricingTheUserSet() throws {
        // 用户自己调过的价是权威，兜底不能盖掉
        let defaults = try scratchDefaults(#function)
        let keyStore = InMemoryKeyStore()
        var config = AIConfig(baseURL: "https://api.minimax.io/v1", model: "MiniMax-M3", apiKey: "k")
        config.pricing = AIPricing(currency: "¥", inputPerMillion: 9,
                                   outputPerMillion: 99, cachedPerMillion: nil)
        try config.save(userDefaults: defaults, keyStore: keyStore)

        let loaded = AIConfig.load(userDefaults: defaults, keyStore: keyStore)
        #expect(loaded.pricing.currency == "¥")
        #expect(loaded.pricing.inputPerMillion == 9)
        #expect(loaded.pricing.outputPerMillion == 99)
    }

    @Test func testLoad_leavesPricingEmptyForUnknownProvider() throws {
        // 不认识的服务不能瞎猜价——宁可不显示花费
        let defaults = try scratchDefaults(#function)
        let keyStore = InMemoryKeyStore()
        let config = AIConfig(baseURL: "https://some-proxy.example.com/v1", model: "m", apiKey: "k")
        try config.save(userDefaults: defaults, keyStore: keyStore)

        #expect(!AIConfig.load(userDefaults: defaults, keyStore: keyStore).pricing.isConfigured)
    }

    @Test func testPresetMatching_toleratesTrailingSlash() {
        #expect(AIProviderPreset.matching(baseURL: "https://api.minimax.io/v1/")?.name == "MiniMax 国际")
        #expect(AIProviderPreset.matching(baseURL: "  https://api.minimax.io/v1  ")?.name == "MiniMax 国际")
        #expect(AIProviderPreset.matching(baseURL: "") == nil)
        // 国际与国内只差一个字母，绝不能互相认领
        #expect(AIProviderPreset.matching(baseURL: "https://api.minimaxi.com/v1")?.name == "MiniMax 国内")
    }

    // MARK: - 线路格式

    @Test func testWireFormat_defaultsToOpenAICompatible() throws {
        // 没存过的老用户升级上来，一切照旧
        let defaults = try scratchDefaults(#function)
        let loaded = AIConfig.load(userDefaults: defaults, keyStore: InMemoryKeyStore())
        #expect(loaded.wireFormat == .openAICompatible)
    }

    @Test func testWireFormat_roundTripsThroughUserDefaults() throws {
        let defaults = try scratchDefaults(#function)
        let keyStore = InMemoryKeyStore()
        var config = AIConfig.empty
        config.wireFormat = .claudeCode
        config.claudeModel = "opus"
        try config.save(userDefaults: defaults, keyStore: keyStore)

        let loaded = AIConfig.load(userDefaults: defaults, keyStore: keyStore)
        #expect(loaded.wireFormat == .claudeCode)
        #expect(loaded.claudeModel == "opus")
    }

    @Test func testWireFormat_unknownStoredValueFallsBack() throws {
        // 将来删掉某种格式（或 iOS 构建读到 macOS 才有的值）时不能崩、不能卡死在没法用的线路上
        let defaults = try scratchDefaults(#function)
        defaults.set("telepathy", forKey: "aiChatWireFormat")
        let loaded = AIConfig.load(userDefaults: defaults, keyStore: InMemoryKeyStore())
        #expect(loaded.wireFormat == .openAICompatible)
    }

    @Test func testIsConfigured_claudeCodeNeedsNoFields() {
        // 地址固定、鉴权走本地 token 文件、模型可空——没有非填不可的项。
        // 桥接在不在跑是运行时的事，isConfigured 拦不了也不该拦
        var config = AIConfig.empty
        config.wireFormat = .claudeCode
        #expect(config.isConfigured)
    }

    @Test func testClaudeModel_isIndependentFromOpenAIModel() throws {
        // 两条线路的模型名互不通用，必须分开存——共用一个字段的话，
        // 切换线路会把 deepseek-chat 之类误传给 claude --model
        let defaults = try scratchDefaults(#function)
        let keyStore = InMemoryKeyStore()
        var config = AIConfig(baseURL: "https://api.deepseek.com/v1",
                              model: "deepseek-chat", apiKey: "k")
        config.claudeModel = "sonnet"
        try config.save(userDefaults: defaults, keyStore: keyStore)

        let loaded = AIConfig.load(userDefaults: defaults, keyStore: keyStore)
        #expect(loaded.model == "deepseek-chat")
        #expect(loaded.claudeModel == "sonnet")
    }

    // MARK: - 凭据安全

    @Test func testSave_neverTouchesTheRealKeychainFromTests() throws {
        // 这条守的是一次真实事故：save 早先只让 userDefaults 可注入，钥匙串写死成全局，
        // 空 apiKey 走到删除分支，把用户真实的 key 抹掉了（且同步删到了其他设备）。
        // 硬闸在此：测试进程里钥匙串一律不动
        #expect(AIKeychain.isRunningInTests)

        try AIKeychain.writeAPIKey("绝不能落到真钥匙串里")
        #expect(AIKeychain.readAPIKey() == nil)
        try AIKeychain.deleteAPIKey()
    }

    @Test func testInMemoryKeyStore_emptyStringClearsTheKey() throws {
        // 清空语义要与钥匙串一致：空串等于删除，而不是存一个空值
        let store = InMemoryKeyStore()
        try store.write("k")
        #expect(store.read() == "k")
        try store.write("")
        #expect(store.read() == nil)
    }
}
