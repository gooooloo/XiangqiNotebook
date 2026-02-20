import Foundation

/// CourseVideoStorage 负责课程视频关联的本机持久化
/// 使用 UserDefaults 存储 gameId → 视频文件路径的映射，不同步 iCloud
class CourseVideoStorage {
    static let shared = CourseVideoStorage()
    private let key = "courseVideoMappings"

    private init() {}

    func videoPath(for gameId: UUID) -> String? {
        let mappings = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return mappings[gameId.uuidString]
    }

    func setVideoPath(_ path: String, for gameId: UUID) {
        var mappings = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        mappings[gameId.uuidString] = path
        UserDefaults.standard.set(mappings, forKey: key)
    }

    func removeVideoPath(for gameId: UUID) {
        var mappings = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        mappings.removeValue(forKey: gameId.uuidString)
        UserDefaults.standard.set(mappings, forKey: key)
    }

    // MARK: - 时间戳管理

    private let timestampKey = "courseVideoTimestamps"

    func timestamp(for gameId: UUID, fenId: Int) -> String? {
        let mappings = UserDefaults.standard.dictionary(forKey: timestampKey) as? [String: String] ?? [:]
        return mappings["\(gameId.uuidString)_\(fenId)"]
    }

    func setTimestamp(_ timestamp: String, for gameId: UUID, fenId: Int) {
        var mappings = UserDefaults.standard.dictionary(forKey: timestampKey) as? [String: String] ?? [:]
        mappings["\(gameId.uuidString)_\(fenId)"] = timestamp
        UserDefaults.standard.set(mappings, forKey: timestampKey)
    }

    func removeTimestamp(for gameId: UUID, fenId: Int) {
        var mappings = UserDefaults.standard.dictionary(forKey: timestampKey) as? [String: String] ?? [:]
        mappings.removeValue(forKey: "\(gameId.uuidString)_\(fenId)")
        UserDefaults.standard.set(mappings, forKey: timestampKey)
    }
}
