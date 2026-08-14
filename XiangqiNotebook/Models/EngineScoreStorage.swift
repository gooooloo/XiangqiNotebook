import Foundation

/// EngineScoreStorage 负责引擎分数的持久化逻辑
/// 每个 engineKey 对应一个独立的 JSON 文件，存储在 engine_scores/ 目录下
class EngineScoreStorage {

    // MARK: - URL Management

    /// 获取 engine_scores 目录的 iCloud 存储路径
    static func getEngineScoresDirectoryURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.XiangqiNotebook")?
            .appendingPathComponent("Documents")
            .appendingPathComponent("XiangqiNotebook")
            .appendingPathComponent("engine_scores")
    }

    /// 获取指定 engineKey 的文件 URL
    static func getEngineScoreURL(engineKey: String) -> URL? {
        getEngineScoresDirectoryURL()?.appendingPathComponent("\(engineKey).json")
    }

    // MARK: - Loading

    /// 加载指定 engineKey 的引擎分数
    static func loadEngineScore(engineKey: String) -> EngineScoreData? {
        guard let url = getEngineScoreURL(engineKey: engineKey) else {
            print("[EngineScoreStorage] 无法获取 URL for \(engineKey)")
            return nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data: Data
            if DatabaseStorage.isICloudURL(url) {
                var readData: Data?
                let semaphore = DispatchSemaphore(value: 0)
                iCloudFileCoordinator.shared.coordinatedRead(from: url) { result in
                    readData = result
                    semaphore.signal()
                }
                semaphore.wait()
                guard let unwrappedData = readData else {
                    print("[EngineScoreStorage] 协调读取失败: \(engineKey)")
                    return nil
                }
                data = unwrappedData
            } else {
                data = try Data(contentsOf: url)
            }

            let engineScoreData = try JSONDecoder().decode(EngineScoreData.self, from: data)
            print("[EngineScoreStorage] 加载成功: \(engineKey), \(engineScoreData.scores.count) 条分数")
            return engineScoreData
        } catch {
            print("[EngineScoreStorage] 加载失败: \(engineKey) - \(error)")
            return nil
        }
    }

    // MARK: - Merging

    /// 把远端分数合并进本地：远端仅补充本地缺失的 fenId（本地为较新评估，冲突时本地优先），
    /// dataVersion 取较大者。分数按 fenId 是 append-only 字典，合并是安全的
    static func merge(remote: EngineScoreData, into local: EngineScoreData) {
        for (fenId, score) in remote.scores where local.scores[fenId] == nil {
            local.scores[fenId] = score
        }
        // 分析缓存冲突时留信息量大的那条（更宽的 multiPV、更久的 movetime）：
        // 它能服务的请求是另一条的超集，留窄的等于白丢一次已经算过的账
        for (fenId, remoteAnalysis) in remote.analyses {
            if let localAnalysis = local.analyses[fenId],
               localAnalysis.supersedes(remoteAnalysis) {
                continue
            }
            local.analyses[fenId] = remoteAnalysis
        }
        local.dataVersion = max(local.dataVersion, remote.dataVersion)
    }

    // MARK: - Saving

    /// 保存引擎分数到指定 engineKey 的文件。
    /// 写入前先读取远端同名文件并按 fenId 合并：整文件覆盖会抹掉
    /// 另一台设备新增的评估结果（本机评估后保存 = 静默丢弃远端数据）
    static func saveEngineScore(_ engineScoreData: EngineScoreData, engineKey: String) throws {
        guard let url = getEngineScoreURL(engineKey: engineKey) else {
            throw EngineScoreStorageError.urlUnavailable
        }

        // 确保目录存在
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 合并远端（engineScoreData 是引用类型，内存中的数据同时获得远端补充）
        if let remote = loadEngineScore(engineKey: engineKey) {
            merge(remote: remote, into: engineScoreData)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(engineScoreData)

        if DatabaseStorage.isICloudURL(url) {
            try iCloudFileCoordinator.shared.coordinatedWrite(data: data, to: url)
        } else {
            try data.write(to: url, options: .atomic)
        }

        print("[EngineScoreStorage] 保存成功: \(engineKey), \(engineScoreData.scores.count) 条分数")
    }

    // MARK: - Directory Listing

    /// 扫描 engine_scores/ 目录，返回已有 engineKey 列表
    static func listEngineKeys() -> [String] {
        guard let dirURL = getEngineScoresDirectoryURL() else { return [] }

        // 不跳过隐藏文件：iCloud 未下载的占位文件形如 ".<name>.json.icloud"
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        // 对占位文件触发下载，下次加载时即可读到内容
        for url in contents where url.pathExtension == "icloud" {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }

        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }
}

// MARK: - Errors
enum EngineScoreStorageError: Error {
    case urlUnavailable
    case fileOperationFailed
}
