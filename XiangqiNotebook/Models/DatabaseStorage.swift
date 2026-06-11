import Foundation

/// DatabaseStorage 负责数据库的持久化逻辑
/// 包括文件 I/O、序列化/反序列化、iCloud 文件协调等
class DatabaseStorage {

    // MARK: - URL Management

    /// 获取 DatabaseData 的 iCloud 存储路径
    static func getDatabaseURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.XiangqiNotebook")?
            .appendingPathComponent("Documents")
            .appendingPathComponent("XiangqiNotebook")
            .appendingPathComponent("database.json")
    }

    /// 检查 URL 是否为 iCloud URL
    static func isICloudURL(_ url: URL) -> Bool {
        return url.path.contains("Mobile Documents") ||
               url.path.contains("ubiquity") ||
               url.absoluteString.contains("com~apple~CloudDocs")
    }

    /// 检查默认存档文件是否存在（含 iCloud 未下载的占位文件）
    /// 用于区分"全新安装（无存档）"与"存档存在但读取失败"
    static func databaseFileExists() -> Bool {
        guard let url = getDatabaseURL() else { return false }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return true }
        // iCloud 未下载到本地时只有隐藏占位文件 .<name>.icloud
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
        return fm.fileExists(atPath: placeholder.path)
    }

    /// 把现有存档文件原样备份到本地 Application Support（覆盖存档前的安全副本）
    /// - Returns: 备份文件 URL；无存档或读取失败返回 nil
    static func backupExistingDatabaseFile() -> URL? {
        guard let url = getDatabaseURL() else { return nil }

        var fileData: Data?
        if isICloudURL(url) {
            let semaphore = DispatchSemaphore(value: 0)
            iCloudFileCoordinator.shared.coordinatedRead(from: url) { result in
                fileData = result
                semaphore.signal()
            }
            semaphore.wait()
        } else {
            fileData = try? Data(contentsOf: url)
        }
        guard let data = fileData else { return nil }

        do {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
            .appendingPathComponent("XiangqiNotebook")
            .appendingPathComponent("OverwriteBackups")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let backupURL = dir.appendingPathComponent("database-\(formatter.string(from: Date())).json")
            try data.write(to: backupURL, options: .atomic)
            print("✅ DatabaseStorage: 覆盖前备份已保存 - \(backupURL.path)")
            return backupURL
        } catch {
            print("❌ DatabaseStorage: 覆盖前备份失败 - \(error)")
            return nil
        }
    }

    // MARK: - Version Management

    /// 从指定 URL 加载数据版本号
    /// - Parameter url: 源 URL
    /// - Returns: 数据版本号
    static func loadDataVersion(from url: URL) throws -> Int {
        let data: Data

        // 如果是 iCloud URL，使用协调读取
        if isICloudURL(url) {
            print("📖 DatabaseStorage: 使用协调读取版本号 - \(url)")
            var readData: Data?
            let semaphore = DispatchSemaphore(value: 0)

            iCloudFileCoordinator.shared.coordinatedRead(from: url) { result in
                readData = result
                semaphore.signal()
            }

            semaphore.wait()

            guard let unwrappedData = readData else {
                throw DatabaseStorageError.fileOperationFailed
            }
            data = unwrappedData
        } else {
            // 直接读取
            data = try Data(contentsOf: url)
        }

        // 字节级扫描版本号：JSONDecoder 即使只解码单字段也要解析整个文档，
        // 大库下远程变更检查会在主线程卡顿
        if let version = extractDataVersion(from: data) {
            print("✅ DatabaseStorage: 读取版本号 \(version)")
            return version
        }

        // 回退：完整解析
        struct VersionOnly: Codable {
            let dataVersion: Int
            enum CodingKeys: String, CodingKey {
                case dataVersion = "data_version"
            }
        }
        let version = try JSONDecoder().decode(VersionOnly.self, from: data)
        print("✅ DatabaseStorage: 读取版本号（完整解析回退）\(version.dataVersion)")
        return version.dataVersion
    }

    /// 在原始字节中扫描 "data_version" 的整数值，不解析 JSON。
    /// 该 key 在 database.json 中只出现在顶层一次；兼容紧凑与 prettyPrinted 格式
    static func extractDataVersion(from data: Data) -> Int? {
        let key = Data("\"data_version\"".utf8)
        guard let keyRange = data.range(of: key) else { return nil }

        var i = keyRange.upperBound
        let whitespace: Set<UInt8> = [UInt8(ascii: ":"), UInt8(ascii: " "), 9, 10, 13]
        while i < data.endIndex, whitespace.contains(data[i]) { i += 1 }

        var negative = false
        if i < data.endIndex, data[i] == UInt8(ascii: "-") {
            negative = true
            i += 1
        }

        var value = 0
        var found = false
        let zero = UInt8(ascii: "0"), nine = UInt8(ascii: "9")
        while i < data.endIndex, data[i] >= zero, data[i] <= nine {
            value = value * 10 + Int(data[i] - zero)
            found = true
            i += 1
        }
        return found ? (negative ? -value : value) : nil
    }

    /// 从默认位置加载数据版本号
    /// - Returns: 数据版本号，如果失败则返回 nil
    static func loadDataVersionFromDefault() -> Int? {
        guard let url = getDatabaseURL() else {
            print("❌ DatabaseStorage: 无法获取数据库 URL")
            return nil
        }

        do {
            return try loadDataVersion(from: url)
        } catch {
            print("❌ DatabaseStorage: 加载版本号失败 - \(error)")
            return nil
        }
    }

    // MARK: - Database Loading

    /// 从指定 URL 加载 DatabaseData
    static func loadDatabaseFromURL(_ url: URL) throws -> DatabaseData {
        let data: Data

        // 如果是 iCloud URL，使用协调读取
        if isICloudURL(url) {
            print("使用协调读取 DatabaseData 从 iCloud: \(url)")
            var readData: Data?
            let semaphore = DispatchSemaphore(value: 0)

            iCloudFileCoordinator.shared.coordinatedRead(from: url) { result in
                readData = result
                semaphore.signal()
            }

            semaphore.wait()

            guard let unwrappedData = readData else {
                throw DatabaseStorageError.fileOperationFailed
            }
            data = unwrappedData
        } else {
            // 直接读取
            data = try Data(contentsOf: url)
        }

        let database = try JSONDecoder().decode(DatabaseData.self, from: data)
        return database
    }

    /// 从默认位置加载 DatabaseData
    static func loadDatabaseFromDefault() -> DatabaseData? {
        guard let dbURL = getDatabaseURL() else {
            print("❌ 无法获取数据库 URL")
            return nil
        }

        do {
            return try loadDatabaseFromURL(dbURL)
        } catch {
            print("❌ DatabaseStorage: 加载失败 - \(error)")
            return nil
        }
    }

    // MARK: - Database Saving

    /// 保存 DatabaseData 到指定 URL
    static func saveDatabaseToURL(_ database: DatabaseData, url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        // 紧凑编码（无 prettyPrinted）：体积约减半，编码与 iCloud 同步都更快
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(database)

        // 如果是 iCloud URL，使用协调写入
        if isICloudURL(url) {
            print("使用协调写入 DatabaseData 到 iCloud: \(url)")

            // 设置保存标志，防止自己触发文件变更通知
            iCloudFileCoordinator.shared.beginSavingDatabase()

            do {
                try iCloudFileCoordinator.shared.coordinatedWrite(data: data, to: url)
                // 写入成功后，延迟清除标志
                iCloudFileCoordinator.shared.endSavingDatabase()
            } catch {
                // 写入失败时立即清除标志
                iCloudFileCoordinator.shared.endSavingDatabase()
                throw error
            }
        } else {
            // 直接写入
            try data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Backup Operations

    /// 保存数据库备份到指定 URL
    /// - Parameter url: 目标 URL
    static func saveDatabaseBackup(_ database: DatabaseData, to url: URL) throws {
        // 确保目录存在
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 编码并保存数据（紧凑编码，与存档一致）
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(database)
        try data.write(to: url, options: .atomic)
        print("✅ DatabaseStorage: 备份保存成功 - \(url)")
    }

    /// 从指定 URL 加载数据库备份
    /// - Parameter url: 源 URL
    /// - Returns: 加载的数据库数据
    static func loadDatabaseBackup(from url: URL) throws -> DatabaseData {
        let data = try Data(contentsOf: url)
        let database = try JSONDecoder().decode(DatabaseData.self, from: data)
        print("✅ DatabaseStorage: 备份加载成功 - \(url)")
        return database
    }

    // MARK: - Crash Recovery Snapshot

    /// 崩溃恢复快照文件（本地，不走 iCloud）。
    /// 区别于正式存档 database.json 与 backupExistingDatabaseFile：
    /// 这是周期性自动写入的"草稿"，仅用于崩溃/被杀后恢复未保存的改动。
    static func recoveryFileURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("XiangqiNotebook") else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recovery.json")
    }

    /// 写入崩溃恢复快照到指定文件（覆盖）。内部核心，便于测试注入路径。
    static func writeRecoverySnapshot(_ database: DatabaseData, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        // 紧凑编码（不 prettyPrinted），周期性写入更快、文件更小
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(database)
        try data.write(to: url, options: .atomic)
    }

    /// 从指定文件读取崩溃恢复快照
    static func loadRecoverySnapshot(from url: URL) -> DatabaseData? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DatabaseData.self, from: data)
    }

    /// 只读取快照的版本号（避免解码整个文件）
    static func recoverySnapshotVersion(at url: URL) -> Int? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        struct VersionOnly: Codable {
            let dataVersion: Int
            enum CodingKeys: String, CodingKey { case dataVersion = "data_version" }
        }
        return (try? JSONDecoder().decode(VersionOnly.self, from: data))?.dataVersion
    }

    // 默认路径的便捷封装（生产代码使用）

    static func writeRecoverySnapshot(_ database: DatabaseData) {
        guard let url = recoveryFileURL() else { return }
        do {
            try writeRecoverySnapshot(database, to: url)
        } catch {
            print("⚠️ DatabaseStorage: 崩溃恢复快照写入失败 - \(error)")
        }
    }

    static func loadRecoverySnapshot() -> DatabaseData? {
        guard let url = recoveryFileURL() else { return nil }
        return loadRecoverySnapshot(from: url)
    }

    static func loadRecoverySnapshotVersion() -> Int? {
        guard let url = recoveryFileURL() else { return nil }
        return recoverySnapshotVersion(at: url)
    }

    static func clearRecoverySnapshot() {
        guard let url = recoveryFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func hasRecoverySnapshot() -> Bool {
        guard let url = recoveryFileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Database Creation

    /// 创建空的数据库（包含起始局面）
    static func createEmptyDatabase() -> DatabaseData {
        let db = DatabaseData()
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fenObject = FenObject(fen: startFen, fenId: 1)
        db.fenObjects2[1] = fenObject
        db.fenToId[startFen] = 1
        return db
    }
}

// MARK: - Errors
enum DatabaseStorageError: Error {
    case urlUnavailable
    case fileOperationFailed
    case loadFailed
}
