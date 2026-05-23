import Testing
import Foundation
@testable import XiangqiNotebook

@MainActor
struct ShortcutUsageStatsTests {

    /// 隔离的 UserDefaults，避免测试污染真实数据
    private func makeStats() -> (ShortcutUsageStats, UserDefaults, String) {
        let suiteName = "ShortcutUsageStatsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let key = "shortcutUsageStats"
        return (ShortcutUsageStats(userDefaults: defaults, key: key), defaults, suiteName)
    }

    @Test
    func recordFromKeyboardIncrementsCount() {
        let (stats, _, _) = makeStats()
        #expect(stats.getTotalCount(for: .toStart) == 0)
        stats.recordFromKeyboard(.toStart)
        #expect(stats.getTotalCount(for: .toStart) == 1)
        stats.recordFromKeyboard(.toStart)
        stats.recordFromKeyboard(.toStart)
        #expect(stats.getTotalCount(for: .toStart) == 3)
    }

    @Test
    func recordFromButtonIncrementsCount() {
        let (stats, _, _) = makeStats()
        #expect(stats.getTotalCount(for: .toStart) == 0)
        stats.recordFromButton(.toStart)
        #expect(stats.getTotalCount(for: .toStart) == 1)
        stats.recordFromButton(.toStart)
        #expect(stats.getTotalCount(for: .toStart) == 2)
    }

    @Test
    func getTotalCountSumsAllSources() {
        let (stats, _, _) = makeStats()
        stats.recordFromKeyboard(.copyFEN)
        stats.recordFromKeyboard(.copyFEN)
        stats.recordFromButton(.copyFEN)
        #expect(stats.getTotalCount(for: .copyFEN) == 3)
    }

    @Test
    func getCountBySourceShowsBreakdown() {
        let (stats, _, _) = makeStats()
        stats.recordFromKeyboard(.copyFEN)
        stats.recordFromKeyboard(.copyFEN)
        stats.recordFromButton(.copyFEN)
        let breakdown = stats.getCountBySource(for: .copyFEN)
        #expect(breakdown["keyboard"] == 2)
        #expect(breakdown["button"] == 1)
    }

    @Test
    func recordIsPersisted() {
        let suiteName = "ShortcutUsageStatsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let key = "shortcutUsageStats"

        let stats1 = ShortcutUsageStats(userDefaults: defaults, key: key)
        stats1.recordFromKeyboard(.copyFEN)
        stats1.recordFromKeyboard(.copyFEN)

        // 用同样的 UserDefaults 创建新实例，应能读出旧数据
        let stats2 = ShortcutUsageStats(userDefaults: defaults, key: key)
        #expect(stats2.getTotalCount(for: .copyFEN) == 2)
    }

    @Test
    func resetClearsAllCounts() {
        let (stats, _, _) = makeStats()
        stats.recordFromKeyboard(.stepBack)
        stats.recordFromButton(.stepForward)
        #expect(stats.getTotalCount(for: .stepBack) == 1)
        stats.reset()
        #expect(stats.getTotalCount(for: .stepBack) == 0)
        #expect(stats.getTotalCount(for: .stepForward) == 0)
        #expect(stats.countsBySource.isEmpty)
    }

    @Test
    func actionDefinitionsTriggersUsageRecorderOnShortcut() {
        var recorded: [ActionDefinitions.ActionKey] = []
        let ad = ActionDefinitions()
        ad.usageRecorder = { recorded.append($0) }

        var executed = false
        ad.registerAction(.copyFEN, text: "copy", shortcuts: [.single("c")]) {
            executed = true
        }

        // 通过快捷键触发
        let handled = ad.handleKeyDown(character: "c")
        #expect(handled == true)
        #expect(executed == true)
        #expect(recorded == [.copyFEN])
    }

    @Test
    func actionDefinitionsTriggersUsageRecorderForToggle() {
        var recorded: [ActionDefinitions.ActionKey] = []
        let ad = ActionDefinitions()
        ad.usageRecorder = { recorded.append($0) }

        var toggleState = false
        ad.registerToggleAction(
            .toggleLock,
            text: "lock",
            shortcuts: [.single("L")],
            isEnabled: { true },
            isOn: { toggleState },
            action: { toggleState = $0 }
        )

        let handled = ad.handleKeyDown(character: "L")
        #expect(handled == true)
        #expect(toggleState == true)
        #expect(recorded == [.toggleLock])
    }

    @Test
    func directButtonClickDoesNotTriggerUsageRecorderThroughAction() {
        // 通过 action() 直接调用不会通过 usageRecorder 通知
        var recorded: [ActionDefinitions.ActionKey] = []
        let ad = ActionDefinitions()
        ad.usageRecorder = { recorded.append($0) }

        var executed = false
        ad.registerAction(.copyFEN, text: "copy", shortcuts: [.single("c")]) {
            executed = true
        }

        // 模拟按钮点击：直接调用 action()
        ad.getActionInfo(.copyFEN)?.action()

        #expect(executed == true)
        #expect(recorded.isEmpty)
    }
}
