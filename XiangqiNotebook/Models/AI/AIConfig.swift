import Foundation
import Security

// MARK: - 服务预设

/// 常见 OpenAI 兼容服务的地址与建议模型，只是帮用户少打字。
/// 选「自定义」可以填任何兼容服务，包括本机 Ollama。
struct AIProviderPreset: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let baseURL: String
    let suggestedModel: String
    /// 已核对过的单价，选中预设时自动填进计费栏。
    /// 只给确实查证过的服务填——没把握的留空，宁可让用户自己填，
    /// 也不能给一个看着像真的的错价
    let suggestedPricing: AIPricing?

    init(name: String, baseURL: String, suggestedModel: String,
         suggestedPricing: AIPricing? = nil) {
        self.name = name
        self.baseURL = baseURL
        self.suggestedModel = suggestedModel
        self.suggestedPricing = suggestedPricing
    }

    static let all: [AIProviderPreset] = [
        AIProviderPreset(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1",
                         suggestedModel: "deepseek-chat"),
        AIProviderPreset(name: "Kimi", baseURL: "https://api.moonshot.cn/v1",
                         suggestedModel: "moonshot-v1-32k"),
        AIProviderPreset(name: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4",
                         suggestedModel: "glm-4-plus"),
        AIProviderPreset(name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                         suggestedModel: "qwen-max"),
        // MiniMax 分国际 / 国内两套域名，只差一个字母（minimax.io / minimaxi.com），
        // 且要按账号在哪个平台开的来选、而非按物理位置。
        // 两项都带限定词，不留一个光秃秃的「MiniMax」当默认——那必然被误点。
        // 单价取自 minimax.io 价目表（2026-08 核对）的 MiniMax-M3「Context ≤ 512K」档，
        // 已是永久五折后的实际价。512K~1M 档翻倍（0.6 / 2.4 / 0.12），
        // 但问棋一轮撑死几万 token，够不着那一档
        AIProviderPreset(name: "MiniMax 国际", baseURL: "https://api.minimax.io/v1",
                         suggestedModel: "MiniMax-M3",
                         suggestedPricing: AIPricing(currency: "$", inputPerMillion: 0.3,
                                                     outputPerMillion: 1.2,
                                                     cachedPerMillion: 0.06)),
        // 国内平台按人民币计价，与上面那张美元表不是一回事，没核对过就不给建议价
        AIProviderPreset(name: "MiniMax 国内", baseURL: "https://api.minimaxi.com/v1",
                         suggestedModel: "MiniMax-M3"),
        AIProviderPreset(name: "OpenAI", baseURL: "https://api.openai.com/v1",
                         suggestedModel: "gpt-4o"),
        AIProviderPreset(name: "本机 Ollama", baseURL: "http://localhost:11434/v1",
                         suggestedModel: "qwen2.5:14b"),
    ]

    /// 按已保存的地址找回预设，用于补上用户没填的建议值。
    /// 结尾斜杠要容忍——用户手粘的地址常带一个
    static func matching(baseURL: String) -> AIProviderPreset? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        return all.first { $0.baseURL == text }
    }
}

// MARK: - 计费

/// 每百万 tokens 的单价，用于估算每次回答的花费。
///
/// 刻意做成用户自填、而不是内置一张价目表：各家调价频繁、同一家不同模型能差好几倍，
/// 内置的表迟早过期成错误信息，而这个数用户自己是知道的（他买的）。
/// 两个价都留空就只报 token 数，不报钱。
struct AIPricing: Equatable {
    var currency: String
    var inputPerMillion: Double?
    var outputPerMillion: Double?
    /// 缓存命中部分的单价。留空则按输入价算——偏保守，宁可报高不报低
    var cachedPerMillion: Double?

    static let currencies = ["¥", "$"]
    static let empty = AIPricing(currency: "¥", inputPerMillion: nil,
                                 outputPerMillion: nil, cachedPerMillion: nil)

    var isConfigured: Bool { inputPerMillion != nil || outputPerMillion != nil }

    /// 估算花费。输入输出单价都没填返回 nil；只填了一个，另一个按 0 算。
    /// `cachedTokens` 含在 `promptTokens` 里，这里先摘出来单独计价
    func cost(promptTokens: Int, cachedTokens: Int, completionTokens: Int) -> Double? {
        guard isConfigured else { return nil }
        let cached = max(0, min(cachedTokens, promptTokens))
        let fresh = promptTokens - cached
        return Double(fresh) / 1_000_000 * (inputPerMillion ?? 0)
            + Double(cached) / 1_000_000 * (cachedPerMillion ?? inputPerMillion ?? 0)
            + Double(completionTokens) / 1_000_000 * (outputPerMillion ?? 0)
    }

    /// 金额文案
    func formattedCost(promptTokens: Int, cachedTokens: Int, completionTokens: Int) -> String? {
        cost(promptTokens: promptTokens, cachedTokens: cachedTokens,
             completionTokens: completionTokens)
            .map { Self.amountText($0, currency: currency) }
    }

    /// 拆成「输入 / 缓存命中 / 输出」三行，让用户能自己核对这笔钱怎么算出来的。
    ///
    /// `cachedTokens` 含在 `promptTokens` 里，这里先摘出来分别计价——
    /// 明细各行相加必须正好等于 `cost(...)`，对不上就等于自证不可信。
    /// 没填单价时照样出行（`unitPrice` 为 nil），至少让人看见 token 花在哪儿了
    func breakdown(promptTokens: Int, cachedTokens: Int, completionTokens: Int) -> [CostLine] {
        let cached = max(0, min(cachedTokens, promptTokens))
        let fresh = promptTokens - cached
        return [
            line("输入", tokens: fresh, rate: inputPerMillion),
            line("缓存", tokens: cached, rate: cachedPerMillion ?? inputPerMillion),
            line("输出", tokens: completionTokens, rate: outputPerMillion),
        ].filter { $0.tokens > 0 }
    }

    private func line(_ label: String, tokens: Int, rate: Double?) -> CostLine {
        CostLine(label: label, tokens: tokens, currency: currency, unitPrice: rate,
                 amount: Double(tokens) / 1_000_000 * (rate ?? 0))
    }

    /// 金额一律四位小数。
    /// 一次问答常在几厘钱量级，两位小数会把它们全压成 0.00——
    /// 那既看不出差别，明细各行也加不出合计
    static func amountText(_ amount: Double, currency: String) -> String {
        currency + String(format: "%.4f", amount)
    }
}

/// 花费明细的一行：多少 token、按什么单价、算出多少钱
struct CostLine: Equatable {
    let label: String
    let tokens: Int
    let currency: String
    /// 每百万 tokens 的单价；nil 表示这一项没填价
    let unitPrice: Double?
    let amount: Double

    var tokensText: String { tokens.formatted() }

    /// 「$0.3 / 百万」。用 %g 免得 0.3 显示成 0.300000
    var unitPriceText: String? {
        unitPrice.map { "\(currency)\(String(format: "%g", $0)) / 百万" }
    }

    var amountText: String? {
        unitPrice.map { _ in AIPricing.amountText(amount, currency: currency) }
    }
}

// MARK: - 配置

/// AI 问棋的服务配置。
///
/// 地址、模型名与单价存 UserDefaults（沿用 `CourseVideoStorage`、`ShortcutUsageStats` 的
/// 本地存储惯例，不进 iCloud 文档同步）；API key 存钥匙串。
struct AIConfig: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
    var pricing: AIPricing = .empty

    static let empty = AIConfig(baseURL: "", model: "", apiKey: "")

    /// 三项齐全才算配好——缺任何一项都发不出请求
    var isConfigured: Bool {
        !baseURL.trimmed.isEmpty && !model.trimmed.isEmpty && !apiKey.trimmed.isEmpty
            && Self.chatCompletionsURL(from: baseURL) != nil
    }

    // MARK: 地址规范化

    /// 由用户填的 baseURL 推出 chat/completions 端点。
    ///
    /// 规则（纯函数，便于单测）：
    /// - 去首尾空白与结尾斜杠
    /// - 已经指向 /chat/completions 就照用
    /// - 路径为空（用户只填了域名）时补 /v1
    /// - 其余情况保留用户写的路径，只追加 /chat/completions
    ///
    /// 刻意不在有路径时强行补 /v1：智谱是 /api/paas/v4，通义是
    /// /compatible-mode/v1，各家版本段并不统一。
    static func chatCompletionsURL(from baseURL: String) -> URL? {
        var text = baseURL.trimmed
        guard !text.isEmpty else { return nil }
        while text.hasSuffix("/") { text.removeLast() }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else {
            return nil
        }
        // 查询串和片段对 API 端点没有意义，用户误粘进来时直接丢掉
        components.query = nil
        components.fragment = nil

        var path = components.path
        if path.hasSuffix("/chat/completions") {
            components.path = path
            return components.url
        }
        if path.isEmpty {
            path = "/v1"
        }
        components.path = path + "/chat/completions"
        return components.url
    }

    var chatCompletionsURL: URL? {
        Self.chatCompletionsURL(from: baseURL)
    }

    // MARK: 持久化

    private enum Keys {
        static let baseURL = "aiChatBaseURL"
        static let model = "aiChatModel"
        static let currency = "aiChatCurrency"
        static let inputPrice = "aiChatInputPricePerMillion"
        static let outputPrice = "aiChatOutputPricePerMillion"
        static let cachedPrice = "aiChatCachedPricePerMillion"
    }

    static func load(userDefaults: UserDefaults = .standard,
                     keyStore: APIKeyStoring = AIKeychain()) -> AIConfig {
        let baseURL = userDefaults.string(forKey: Keys.baseURL) ?? ""
        let stored = AIPricing(
            currency: userDefaults.string(forKey: Keys.currency) ?? AIPricing.empty.currency,
            // 用 object(forKey:) 而非 double(forKey:)：后者把「没填」和「填了 0」
            // 都返回成 0，分不出来
            inputPerMillion: userDefaults.object(forKey: Keys.inputPrice) as? Double,
            outputPerMillion: userDefaults.object(forKey: Keys.outputPrice) as? Double,
            cachedPerMillion: userDefaults.object(forKey: Keys.cachedPrice) as? Double)

        return AIConfig(
            baseURL: baseURL,
            model: userDefaults.string(forKey: Keys.model) ?? "",
            apiKey: keyStore.read() ?? "",
            // 没填过价就用预设里核对过的建议价兜底。放在这里而不是只放设置页，
            // 是为了让花费显示开箱即用——不必先去开一次设置、点一下预设
            pricing: stored.isConfigured
                ? stored
                : (AIProviderPreset.matching(baseURL: baseURL)?.suggestedPricing ?? stored)
        )
    }

    /// 保存。key 写钥匙串，失败时抛出，供设置页提示用户。
    ///
    /// `keyStore` 必须可注入：早先只有 `userDefaults` 能注入，钥匙串那一半写死成全局，
    /// 于是任何调到 `save` 的测试都会拿空 key 触发删除分支，把用户真实的 key 抹掉——
    /// 这不是假设，是已经发生过一次的事故
    func save(userDefaults: UserDefaults = .standard,
              keyStore: APIKeyStoring = AIKeychain()) throws {
        userDefaults.set(baseURL.trimmed, forKey: Keys.baseURL)
        userDefaults.set(model.trimmed, forKey: Keys.model)
        userDefaults.set(pricing.currency, forKey: Keys.currency)
        Self.setOptionalDouble(pricing.inputPerMillion, forKey: Keys.inputPrice, in: userDefaults)
        Self.setOptionalDouble(pricing.outputPerMillion, forKey: Keys.outputPrice, in: userDefaults)
        Self.setOptionalDouble(pricing.cachedPerMillion, forKey: Keys.cachedPrice, in: userDefaults)
        try keyStore.write(apiKey.trimmed)
    }

    /// 清空的单价要真的删掉键，写 0 会被读成「单价是 0」，估出来永远不花钱
    private static func setOptionalDouble(_ value: Double?, forKey key: String,
                                          in userDefaults: UserDefaults) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}

// MARK: - 钥匙串

/// API key 的存取抽象。
/// 存在的唯一理由是让 `AIConfig.save` 在测试里可以不碰真钥匙串——
/// key 是用户的真实凭据，删掉不可恢复，不能让测试有机会写到它头上。
protocol APIKeyStoring {
    func read() -> String?
    /// 传空串表示清除
    func write(_ key: String) throws
}

/// API key 的钥匙串存取。
///
/// 用数据保护钥匙串 + `kSecAttrSynchronizable`，让 key 随 iCloud 钥匙串同步——
/// Mac 上配一次，iPhone 就不必再填一遍。
///
/// 注意同步的另一面：删除也会同步。误删一次是全设备一起没，且没有回收站可捞。
struct AIKeychain: APIKeyStoring {

    func read() -> String? { Self.readAPIKey() }
    func write(_ key: String) throws { try Self.writeAPIKey(key) }

    /// 测试进程里一律不碰真钥匙串。
    ///
    /// 上面的协议注入已经是正道，这里再加一道硬闸：删除是不可逆的，
    /// 而「某个新测试不小心用了默认参数」这种事只要发生一次就够呛。
    /// 代价是三行，换的是「测试永远不可能毁掉用户凭据」
    static var isRunningInTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private static let service = "com.gooooloo.XiangqiNotebook.aiChat"
    private static let account = "apiKey"

    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "钥匙串访问失败：\(detail)"
            }
        }
    }

    /// 定位同一条记录的查询条件。写、读、删必须完全一致，否则会读不到自己刚写的东西。
    private static func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
        #if os(macOS)
        // macOS 上 synchronizable 条目必须走数据保护钥匙串，
        // 老的文件钥匙串不支持 iCloud 同步
        query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
        #endif
        return query
    }

    static func readAPIKey() -> String? {
        guard !isRunningInTests else { return nil }
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func writeAPIKey(_ key: String) throws {
        guard !isRunningInTests else { return }
        guard !key.isEmpty else {
            try deleteAPIKey()
            return
        }
        let data = Data(key.utf8)
        let query = baseQuery()

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    static func deleteAPIKey() throws {
        guard !isRunningInTests else { return }
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

// MARK: -

/// 本文件内多处要去空白，抽个短名字。刻意 fileprivate——
/// 这类通用小工具不该无谓地铺到全局 String 上
private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
