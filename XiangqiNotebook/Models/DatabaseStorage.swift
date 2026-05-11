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

        // 只解码版本号字段以提高性能
        struct VersionOnly: Codable {
            let dataVersion: Int
            enum CodingKeys: String, CodingKey {
                case dataVersion = "data_version"
            }
        }
        let version = try JSONDecoder().decode(VersionOnly.self, from: data)
        print("✅ DatabaseStorage: 读取版本号 \(version.dataVersion)")
        return version.dataVersion
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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

        // 编码并保存数据
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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

    // MARK: - Database Creation

    /// 创建空的数据库（包含标准开局和虚拟根局面）
    /// fenId=1 为标准开局（与 SessionData.currentGame2 默认值 [1] 保持兼容）
    /// fenId=2 为虚拟根 origin；其后新增局面从 3 开始分配
    static func createEmptyDatabase() -> DatabaseData {
        let db = DatabaseData()
        // 1. 标准开局（fenId=1 与默认 SessionData 兼容）
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let startObj = FenObject(fen: startFen, fenId: 1)
        db.fenObjects2[1] = startObj
        db.fenToId[startFen] = 1
        // 2. 虚拟根局面
        let origin = FenObject(fen: DatabaseData.originFen, fenId: 2)
        db.fenObjects2[2] = origin
        db.fenToId[DatabaseData.originFen] = 2
        return db
    }
}

// MARK: - Errors
enum DatabaseStorageError: Error {
    case urlUnavailable
    case fileOperationFailed
    case loadFailed
}
