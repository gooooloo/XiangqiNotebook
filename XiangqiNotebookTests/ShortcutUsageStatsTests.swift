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
    func recordIncrementsCount() {
        let (stats, _, _) = makeStats()
        #expect(stats.count(for: .toStart) == 0)
        stats.record(.toStart)
        #expect(stats.count(for: .toStart) == 1)
        stats.record(.toStart)
        stats.record(.toStart)
        #expect(stats.count(for: .toStart) == 3)
    }

    @Test
    func recordIsPersisted() {
        let suiteName = "ShortcutUsageStatsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let key = "shortcutUsageStats"

        let stats1 = ShortcutUsageStats(userDefaults: defaults, key: key)
        stats1.record(.copyFEN)
        stats1.record(.copyFEN)

        // 用同样的 UserDefaults 创建新实例，应能读出旧数据
        let stats2 = ShortcutUsageStats(userDefaults: defaults, key: key)
        #expect(stats2.count(for: .copyFEN) == 2)
    }

    @Test
    func resetClearsAllCounts() {
        let (stats, _, _) = makeStats()
        stats.record(.stepBack)
        stats.record(.stepForward)
        #expect(stats.count(for: .stepBack) == 1)
        stats.reset()
        #expect(stats.count(for: .stepBack) == 0)
        #expect(stats.count(for: .stepForward) == 0)
        #expect(stats.counts.isEmpty)
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
    func directButtonClickDoesNotTriggerUsageRecorder() {
        // 按钮点击通过 ActionInfo.action() 直接调用，不经过 executeAction，故不记录
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
