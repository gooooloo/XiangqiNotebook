import Foundation

/// Local durable outbox + immutable iCloud records. No shared mutable manifest, no remote deletion.
actor CoachStore {
    static let shared = CoachStore()
    let localURL: URL
    private let cloudURL: URL?
    private let discoverCloud: Bool
    private var cache: [String: CoachEvent] = [:]
    private var status = "保存在本机"
    private var incomplete = false
    private var pendingCloudNames: Set<String> = []

    init(localURL: URL? = nil, cloudURL: URL? = nil) {
        self.localURL = localURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("XiangqiNotebook/Coach/v1", isDirectory: true)
        self.cloudURL = cloudURL
        self.discoverCloud = localURL == nil
    }
    private func cloudRoot() throws -> URL? {
        if !discoverCloud { return cloudURL }
        guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
        // Pin the local outbox to the first iCloud account. Never upload it to a different account silently.
        let identity = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
        let binding = localURL.appendingPathComponent("account-token.archive")
        if FileManager.default.fileExists(atPath: binding.path) {
            let saved = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(Data(contentsOf: binding))
            guard let saved = saved as? NSObject, saved.isEqual(token) else {
                throw CoachServiceError(message: "iCloud 账号已改变；教练记录继续保存在本机，未上传到新账号。")
            }
        } else { try identity.write(to: binding, options: .atomic) }
        return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.XiangqiNotebook")?
            .appendingPathComponent("Documents/XiangqiNotebook/Coach/v1", isDirectory: true)
    }
    private func coordinated<T>(_ url: URL, write: Bool, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        var result: Result<T, Error>?
        if write {
            coordinator.coordinate(writingItemAt: url, options: [], error: &error) { coordinatedURL in result = Result { try body(coordinatedURL) } }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordinatedURL in result = Result { try body(coordinatedURL) } }
        }
        if let error { throw error }
        guard let result else { throw CoachServiceError(message: "文件暂不可用，请稍后同步") }
        return try result.get()
    }
    private func persist(_ data: Data, at root: URL) throws {
        let url = root.appendingPathComponent(CoachEncoding.hash(data) + ".json")
        try coordinated(url, write: true) { target in
            if FileManager.default.fileExists(atPath: target.path) {
                guard try Data(contentsOf: target) == data else { throw CoachServiceError(message: "检测到教练记录内容冲突；已保留原文件") }
            } else { try data.write(to: target, options: .atomic) }
        }
    }
    func append(_ event: CoachEvent) throws {
        try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
        try scan(localURL, importing: false)
        // A retried durable write may have a later wall clock. Same operation/payload stays one fact.
        if cache.values.contains(where: { $0.id == event.id && $0.deviceID == event.deviceID && $0.payload == event.payload }) { return }
        let data = try CoachEncoding.encode(event)
        try persist(data, at: localURL)
        cache[CoachEncoding.hash(data) + ".json"] = try CoachEncoding.decode(CoachEvent.self, data)
    }
    private func scan(_ root: URL, importing: Bool) throws {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])
        for url in files {
            if url.lastPathComponent.hasSuffix(".icloud") {
                incomplete = true
                let name = String(url.lastPathComponent.dropFirst().dropLast(7))
                if importing { pendingCloudNames.insert(name) }
                try? FileManager.default.startDownloadingUbiquitousItem(at: root.appendingPathComponent(name))
                continue
            }
            guard url.pathExtension == "json" else { continue }
            if importing {
                let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if let download = values?.ubiquitousItemDownloadingStatus, download != .current {
                    incomplete = true
                    pendingCloudNames.insert(url.lastPathComponent)
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    continue
                }
            }
            // Never overwrite / prune local facts if iCloud is incomplete. New immutable files alone are decoded.
            if cache[url.lastPathComponent] != nil { continue }
            do {
                let data = try coordinated(url, write: false) { try Data(contentsOf: $0) }
                let name = CoachEncoding.hash(data) + ".json"
                let duplicatePrefix = CoachEncoding.hash(data) + " "
                guard name == url.lastPathComponent || (importing && url.lastPathComponent.hasPrefix(duplicatePrefix)) else {
                    throw CoachServiceError(message: "文件内容校验失败")
                }
                let event = try CoachEncoding.decode(CoachEvent.self, data)
                guard event.schema == 1 else { throw CoachServiceError(message: "需要较新版本的象棋笔记本") }
                if importing { try persist(data, at: localURL) }
                cache[name] = event
            } catch { incomplete = true }
        }
    }
    func read(now: Date = Date()) throws -> CoachSnapshot {
        try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
        try scan(localURL, importing: false)
        return CoachSnapshot(events: Array(cache.values), syncStatus: status, incomplete: incomplete, now: now)
    }
    func synchronize(now: Date = Date()) -> CoachSnapshot {
        incomplete = false
        pendingCloudNames = []
        do {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            try scan(localURL, importing: false)
            if let cloud = try cloudRoot() {
                try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
                try scan(cloud, importing: true)
                for (filename, _) in cache where !pendingCloudNames.contains(filename) {
                    let target = cloud.appendingPathComponent(filename)
                    if !FileManager.default.fileExists(atPath: target.path) {
                        let data = try Data(contentsOf: localURL.appendingPathComponent(filename))
                        try persist(data, at: cloud)
                    }
                }
                status = incomplete ? "部分 iCloud 记录尚未下载或无法读取；本机记录已保留" : "本机已保存，交由 iCloud 同步（其他设备送达可能延迟）"
            } else { status = "本机已保存；iCloud 暂不可用，恢复后自动同步" }
        } catch {
            incomplete = true
            status = "本机记录已保留；同步未完成：\(error.localizedDescription)"
        }
        return CoachSnapshot(events: Array(cache.values), syncStatus: status, incomplete: incomplete, now: now)
    }
}
