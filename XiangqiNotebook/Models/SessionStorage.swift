import Foundation

/// SessionStorage 负责 SessionData 的持久化逻辑
/// 包括文件 I/O、序列化/反序列化等
class SessionStorage {

    // MARK: - URL Management

    /// 获取 SessionData 的本地存储路径
    static func getSessionURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("session.json")
    }

    // MARK: - Session Loading

    /// 从指定 URL 加载 SessionData
    /// - Parameter url: 源 URL
    /// - Returns: 加载的 SessionData
    static func loadSession(from url: URL) throws -> SessionData {
        let data = try Data(contentsOf: url)
        let session = try JSONDecoder().decode(SessionData.self, from: data)
        print("✅ SessionStorage: 加载成功 - \(url)")
        return session
    }

    /// 从默认位置加载 SessionData
    /// - Returns: 加载的 SessionData，如果失败则返回 nil
    static func loadSessionFromDefault() -> SessionData? {
        let sessionURL = getSessionURL()
        do {
            return try loadSession(from: sessionURL)
        } catch {
            print("❌ SessionStorage: 加载失败 - \(error)")
            return nil
        }
    }

    // MARK: - Session Saving

    /// 保存 SessionData 到指定 URL
    /// - Parameters:
    ///   - session: 要保存的 SessionData
    ///   - url: 目标 URL
    static func saveSession(_ session: SessionData, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)
        print("✅ SessionStorage: 保存成功 - \(url)")
    }

    /// 保存 SessionData 到默认位置
    /// - Parameter session: 要保存的 SessionData
    static func saveSessionToDefault(session: SessionData) throws {
        let sessionURL = getSessionURL()
        try saveSession(session, to: sessionURL)
    }
}

// MARK: - Errors
enum SessionStorageError: Error {
    case urlUnavailable
    case fileOperationFailed
    case loadFailed
}
