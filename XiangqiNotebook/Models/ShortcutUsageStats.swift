import Foundation

/// 快捷键使用统计：记录每个 ActionKey 通过快捷键触发的累计次数
///
/// 仅统计通过快捷键触发的次数，不统计按钮点击。
/// 数据通过 UserDefaults 持久化，仅本地，不参与 iCloud 同步。
class ShortcutUsageStats: ObservableObject {
    static let shared = ShortcutUsageStats()

    private let key: String
    private let userDefaults: UserDefaults

    /// ActionKey.rawValue → 累计触发次数
    @Published private(set) var counts: [String: Int]

    init(userDefaults: UserDefaults = .standard, key: String = "shortcutUsageStats") {
        self.userDefaults = userDefaults
        self.key = key
        self.counts = (userDefaults.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    /// 记录一次快捷键触发
    func record(_ actionKey: ActionDefinitions.ActionKey) {
        let rawKey = actionKey.rawValue
        counts[rawKey, default: 0] += 1
        userDefaults.set(counts, forKey: key)
    }

    /// 查询某个动作的累计触发次数
    func count(for actionKey: ActionDefinitions.ActionKey) -> Int {
        counts[actionKey.rawValue] ?? 0
    }

    /// 清空所有统计
    func reset() {
        counts = [:]
        userDefaults.removeObject(forKey: key)
    }
}
