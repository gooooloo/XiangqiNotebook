import SwiftUI

/// AI 服务配置页，三端共用。
/// 线路分两种：OpenAI 兼容（预设按钮只是帮着少打字，可填任何兼容服务）；
/// Claude Code 订阅（仅 macOS，走本机 claude CLI，见 mcp/claude-bridge.mjs）。
struct AISettingsView: View {

    @Binding var isPresented: Bool

    @State private var wireFormat: AIWireFormat = .openAICompatible
    @State private var baseURL = ""
    @State private var model = ""
    @State private var claudeModel = ""
    @State private var apiKey = ""
    @State private var currency = AIPricing.empty.currency
    @State private var inputPrice = ""
    @State private var outputPrice = ""
    @State private var cachedPrice = ""
    @State private var saveError: String?
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // iOS 只有一种线路，单选段的 Picker 显示出来反而突兀
                    if AIWireFormat.allCases.count > 1 {
                        wireFormatSection
                        Divider()
                    }
                    switch wireFormat {
                    case .openAICompatible:
                        baseURLSection
                        Divider()
                        modelSection
                        Divider()
                        apiKeySection
                        Divider()
                        pricingSection
                    case .claudeCode:
                        claudeCodeSection
                    }
                    Divider()
                    testSection
                }
            }
        }
        .background(AIChatPalette.background)
        .aiChatLightAppearance()
        .frame(minWidth: 420, minHeight: 460)
        .onAppear(perform: load)
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack {
            Text("AI 设置")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AIChatPalette.textPrimary)
            Spacer()
            Button("完成") { save(andClose: true) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AIChatPalette.barBackground)
    }

    // MARK: - 各段

    private var wireFormatSection: some View {
        section("线路") {
            Picker("", selection: $wireFormat) {
                ForEach(AIWireFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: wireFormat) { _ in testState = .idle }
        }
    }

    /// Claude Code（订阅）线路：没有地址、key、单价可填——地址固定 localhost、
    /// 鉴权走本地 token 文件、计费在订阅内
    private var claudeCodeSection: some View {
        section("模型（可选）") {
            field(text: $claudeModel, placeholder: "sonnet", monospaced: true)
            hint("传给 claude --model：可填 sonnet / opus / haiku 或完整模型名，留空用 CLI 默认。"
                 + "用量计在 Claude 订阅内，不按 token 单独收费。")
            hint("需要本机装有 Claude Code（已登录订阅），且桥接服务在运行："
                 + "node mcp/claude-bridge.mjs，安装 launchd 常驻见 mcp/README.md。"
                 + "工具调用经由本 app 的分析接口完成，app 开着即可。")
        }
    }

    private var baseURLSection: some View {
        section("服务地址") {
            FlowLayout(items: AIProviderPreset.all, horizontalSpacing: 6, verticalSpacing: 6) {
                presetChip($0)
            }
            .padding(.bottom, 8)

            field(text: $baseURL, placeholder: "https://api.deepseek.com/v1", monospaced: true)

            if let endpoint = AIConfig.chatCompletionsURL(from: baseURL) {
                hint("实际请求：\(endpoint.absoluteString)")
            } else if !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hint("地址无效，应形如 https://api.deepseek.com/v1", isError: true)
            } else {
                hint("只填域名会自动补 /v1；已带路径的按原样使用。")
            }
        }
    }

    private var modelSection: some View {
        section("模型") {
            field(text: $model, placeholder: "deepseek-chat", monospaced: true)
            hint("须支持 function calling，否则无法调用引擎分析。")
        }
    }

    private var apiKeySection: some View {
        section("API KEY") {
            SecureField("sk-…", text: $apiKey)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                // 底色是硬编码浅色，文字色必须一并固定（见 AIChatPalette.LightAppearance）
                .foregroundColor(AIChatPalette.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(AIChatPalette.bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: AIChatPalette.controlRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AIChatPalette.controlRadius)
                        .stroke(AIChatPalette.border, lineWidth: 0.5)
                )
            hint("存于系统钥匙串，随 iCloud 钥匙串同步——Mac 上配一次，iPhone 免填。")
            if let saveError {
                hint(saveError, isError: true)
            }
        }
    }

    /// 单价让用户自填而不是内置价目表：各家调价频繁、同一家不同模型差好几倍，
    /// 写死的表迟早过期成错误信息
    private var pricingSection: some View {
        section("计费（可选）") {
            HStack(spacing: 8) {
                Picker("", selection: $currency) {
                    ForEach(AIPricing.currencies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 68)

                priceField("输入", text: $inputPrice)
                priceField("输出", text: $outputPrice)
                priceField("缓存", text: $cachedPrice)
            }
            hint("每百万 tokens 的单价，填了才在每条回答下显示估算花费。"
                 + "上面的服务预设若已核对过价目，选中时会自动带出来。")
            hint("「缓存」是缓存命中部分的单价，留空按输入价算。问棋要连着发好几轮请求，"
                 + "每轮都重发同一段 prompt，这一项影响不小。")
        }
    }

    private func priceField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(AIChatPalette.textFaint)
            field(text: text, placeholder: "—", monospaced: true)
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("测试连接") { runTest() }
                    .disabled(!draftConfig.isConfigured || testState == .testing)
                if testState == .testing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            switch testState {
            case .success(let message):
                statusLine(message, color: successColor, symbol: "checkmark.circle.fill")
            case .failure(let message):
                statusLine(message, color: AIChatPalette.bad, symbol: "exclamationmark.circle.fill")
            case .idle, .testing:
                EmptyView()
            }
        }
        .padding(16)
    }

    private var successColor: Color {
        #if os(macOS)
        return Theme.good
        #else
        return XiangqiTheme.good
        #endif
    }

    // MARK: - 组件

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundColor(AIChatPalette.textFaint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private func presetChip(_ preset: AIProviderPreset) -> some View {
        let isSelected = baseURL.trimmingCharacters(in: .whitespacesAndNewlines) == preset.baseURL
        return Button {
            baseURL = preset.baseURL
            // 只在还空着时填建议值，别覆盖用户已经调好的
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model = preset.suggestedModel
            }
            if let pricing = preset.suggestedPricing, !hasAnyPriceFilled {
                currency = pricing.currency
                inputPrice = Self.priceText(pricing.inputPerMillion)
                outputPrice = Self.priceText(pricing.outputPerMillion)
                cachedPrice = Self.priceText(pricing.cachedPerMillion)
            }
            testState = .idle
        } label: {
            Text(preset.name)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : AIChatPalette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? AIChatPalette.accent : AIChatPalette.bubbleBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : AIChatPalette.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func field(text: Binding<String>, placeholder: String, monospaced: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, design: monospaced ? .monospaced : .default))
            // 底色是硬编码浅色，文字色必须一并固定（见 AIChatPalette.LightAppearance）
            .foregroundColor(AIChatPalette.textPrimary)
            #if os(iOS)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(AIChatPalette.bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: AIChatPalette.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AIChatPalette.controlRadius)
                    .stroke(AIChatPalette.border, lineWidth: 0.5)
            )
    }

    private func hint(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(isError ? AIChatPalette.bad : AIChatPalette.textFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusLine(_ text: String, color: Color, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(color)
    }

    // MARK: - 逻辑

    private var draftConfig: AIConfig {
        AIConfig(wireFormat: wireFormat, baseURL: baseURL, model: model, apiKey: apiKey,
                 claudeModel: claudeModel,
                 pricing: AIPricing(
                    currency: currency,
                    inputPerMillion: Self.price(inputPrice),
                    outputPerMillion: Self.price(outputPrice),
                    cachedPerMillion: Self.price(cachedPrice)))
    }

    /// 三个价里但凡填了一个，就不拿预设去覆盖——用户可能是特意调过的
    private var hasAnyPriceFilled: Bool {
        [inputPrice, outputPrice, cachedPrice]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 空串、乱填的都当没填——宁可不显示花费，也别显示一个瞎算的数
    private static func price(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value >= 0 else { return nil }
        return value
    }

    /// 单价回填成文本框内容。用 %g 免得 0.3 显示成 0.300000
    private static func priceText(_ value: Double?) -> String {
        value.map { String(format: "%g", $0) } ?? ""
    }

    private func load() {
        let config = AIConfig.load()
        wireFormat = config.wireFormat
        baseURL = config.baseURL
        model = config.model
        claudeModel = config.claudeModel
        apiKey = config.apiKey
        currency = config.pricing.currency
        inputPrice = Self.priceText(config.pricing.inputPerMillion)
        outputPrice = Self.priceText(config.pricing.outputPerMillion)
        cachedPrice = Self.priceText(config.pricing.cachedPerMillion)
    }

    private func save(andClose: Bool) {
        do {
            try draftConfig.save()
            saveError = nil
            if andClose { isPresented = false }
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// 按线路分派测试。OpenAI 兼容真发一次最小请求（光校验格式说明不了服务是否可用、
    /// key 对不对、这个模型认不认工具调用）；Claude Code 探桥接的 /health
    /// （桥接在不在跑、claude 在不在、登没登录）——不真跑一轮 claude，那要十几秒。
    private func runTest() {
        save(andClose: false)
        guard saveError == nil else { return }

        testState = .testing
        switch wireFormat {
        case .openAICompatible: runOpenAICompatibleTest()
        case .claudeCode: runBridgeTest()
        }
    }

    private func runOpenAICompatibleTest() {
        let client = LLMClient(config: draftConfig)
        Task { @MainActor in
            do {
                let response = try await client.send(
                    messages: [.user("回复 OK 两个字即可。")],
                    tools: AnalysisToolbox.toolSpecs)
                let answered = response.content?.isEmpty == false || !response.toolCalls.isEmpty
                testState = answered
                    ? .success("连接正常，模型接受工具调用")
                    : .failure("服务有响应，但没返回内容，换个模型试试")
            } catch {
                testState = .failure((error as? LLMError)?.errorDescription
                                     ?? error.localizedDescription)
            }
        }
    }

    private func runBridgeTest() {
        Task { @MainActor in
            do {
                let health = try await ClaudeCodeClient.health()
                let subscription = health.subscriptionType.map { "（\($0) 订阅）" } ?? ""
                testState = .success("桥接正常，claude 已登录\(subscription)")
            } catch {
                testState = .failure((error as? LLMError)?.errorDescription
                                     ?? error.localizedDescription)
            }
        }
    }
}
