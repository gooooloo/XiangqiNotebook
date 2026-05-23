import Foundation

/// 快捷键使用统计：记录每个 ActionKey 通过各种方式（快捷键、按钮等）触发的累计次数
///
/// 统计通过快捷键、按钮、菜单等多种方式触发的使用次数。
/// 数据通过 UserDefaults 持久化，仅本地，不参与 iCloud 同步。
class ShortcutUsageStats: ObservableObject {
    static let shared = ShortcutUsageStats()

    private let key: String
    private let userDefaults: UserDefaults

    /// ActionKey.rawValue → { 来源 → 累计触发次数 }
    /// 来源包括：keyboard、button
    @Published private(set) var countsBySource: [String: [String: Int]]

    init(userDefaults: UserDefaults = .standard, key: String = "shortcutUsageStats") {
        self.userDefaults = userDefaults
        self.key = key

        // 尝试从新格式读取
        if let data = userDefaults.dictionary(forKey: key) as? [String: [String: Int]] {
            self.countsBySource = data
        } else if let oldCounts = userDefaults.dictionary(forKey: key) as? [String: Int] {
            // 迁移旧格式（仅有 counts 字典）到新格式
            var newData: [String: [String: Int]] = [:]
            for (actionKey, count) in oldCounts {
                newData[actionKey] = ["keyboard": count]
            }
            self.countsBySource = newData
            self.userDefaults.set(self.countsBySource, forKey: key)
        } else {
            self.countsBySource = [:]
        }
    }

    /// 记录一次快捷键触发
    func recordFromKeyboard(_ actionKey: ActionDefinitions.ActionKey) {
        record(actionKey, from: "keyboard")
    }

    /// 记录一次按钮/菜单触发
    func recordFromButton(_ actionKey: ActionDefinitions.ActionKey) {
        record(actionKey, from: "button")
    }

    /// 内部方法：按来源记录一次触发
    private func record(_ actionKey: ActionDefinitions.ActionKey, from source: String) {
        let rawKey = actionKey.rawValue
        if countsBySource[rawKey] == nil {
            countsBySource[rawKey] = [:]
        }
        countsBySource[rawKey]?[source, default: 0] += 1
        userDefaults.set(countsBySource, forKey: key)
    }

    /// 查询某个动作的总使用次数（所有来源）
    func getTotalCount(for actionKey: ActionDefinitions.ActionKey) -> Int {
        guard let sources = countsBySource[actionKey.rawValue] else { return 0 }
        return sources.values.reduce(0, +)
    }

    /// 查询某个动作的按来源分别的使用次数
    func getCountBySource(for actionKey: ActionDefinitions.ActionKey) -> [String: Int] {
        countsBySource[actionKey.rawValue] ?? [:]
    }

    /// 查询某个动作在特定来源的使用次数
    func count(for actionKey: ActionDefinitions.ActionKey, from source: String = "keyboard") -> Int {
        countsBySource[actionKey.rawValue]?[source] ?? 0
    }

    /// 清空所有统计
    func reset() {
        countsBySource = [:]
        userDefaults.removeObject(forKey: key)
    }
}
