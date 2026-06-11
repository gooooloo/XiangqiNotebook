import Foundation
import Combine

/// iCloud 文件协调服务
/// 负责处理 database.json 的多设备同步协调，使用 NSFilePresenter 和 NSFileCoordinator
/// 确保多个设备同时访问时的数据一致性
class iCloudFileCoordinator: NSObject, ObservableObject, NSFilePresenter {

    // MARK: - Singleton
    static let shared = iCloudFileCoordinator()

    // MARK: - Published Properties

    /// 文件变更通知 - 当远程 database.json 被其他设备修改时单调递增。
    /// 用计数代替 Bool：Bool 的「置位/复位」存在覆盖竞态（复位可能吞掉
    /// 并发到达的新通知），计数只增不减，订阅方对每次递增各处理一次
    @Published private(set) var databaseFileChangeCount: Int = 0

    // MARK: - NSFilePresenter Required Properties

    /// 监控的文件 URL（database.json 的 iCloud 位置）
    var presentedItemURL: URL?

    /// NSFilePresenter 回调队列
    var presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.xiangqinotebook.icloudfilecoordinator"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    /// 标记当前设备是否正在保存数据库文件（用于防止自己触发自己的变更通知）。
    /// 写于主线程（保存路径），读于 presenter 回调队列，用锁保护
    private let stateLock = NSLock()
    private var _isSavingDatabase = false
    private var isSavingDatabase: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isSavingDatabase }
        set { stateLock.lock(); defer { stateLock.unlock() }; _isSavingDatabase = newValue }
    }

    // MARK: - Initialization

    /// 初始化并注册为 file presenter
    /// - Parameter databaseURL: database.json 的 iCloud URL（可选）
    private override init() {
        super.init()

        // 构建 database.json 的 iCloud URL（必须与 Database.getDatabaseURL() 路径一致）
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.XiangqiNotebook")?
            .appendingPathComponent("Documents")
            .appendingPathComponent("XiangqiNotebook") {
            self.presentedItemURL = containerURL.appendingPathComponent("database.json")

            // 注册为 file presenter，开始监控文件变更
            NSFileCoordinator.addFilePresenter(self)

            print("[iCloudFileCoordinator] 已注册 file presenter，监控: \(self.presentedItemURL?.path ?? "未知")")
        } else {
            print("[iCloudFileCoordinator] 警告: 无法获取 iCloud Documents 容器 URL")
        }
    }

    deinit {
        // 注销 file presenter
        NSFileCoordinator.removeFilePresenter(self)
        print("[iCloudFileCoordinator] 已注销 file presenter")
    }

    // MARK: - NSFilePresenter Callbacks

    /// 当 presentedItemURL 的文件内容被其他设备修改时调用
    func presentedItemDidChange() {
        // 忽略自己保存时触发的通知
        if isSavingDatabase {
            print("[iCloudFileCoordinator] 忽略自己的保存操作触发的文件变更")
            return
        }

        print("[iCloudFileCoordinator] 检测到远程文件变更")
        publishChange()
    }

    /// 在主线程递增变更计数
    private func publishChange() {
        DispatchQueue.main.async { [weak self] in
            self?.databaseFileChangeCount += 1
        }
    }

    /// 处理文件版本冲突
    /// 旧实现无条件用 gained 的冲突版本覆盖当前文件（冲突版本可能比当前更旧），
    /// 且未经写协调、未标记 isResolved。现按修改时间取较新者，避免静默丢弃新数据
    /// - Parameter version: 新的文件版本
    func presentedItemDidGain(_ version: NSFileVersion) {
        print("[iCloudFileCoordinator] 检测到文件版本: \(version.modificationDate.map { "\($0)" } ?? "未知时间")")

        guard version.isConflict else { return }
        guard let url = presentedItemURL else {
            print("[iCloudFileCoordinator] 错误: presentedItemURL 为空，无法解决冲突")
            return
        }

        do {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let currentModDate = attrs?[.modificationDate] as? Date ?? .distantPast
            let versionModDate = version.modificationDate ?? .distantPast

            if versionModDate > currentModDate {
                // 冲突版本较新：经写协调替换当前文件
                let coordinator = NSFileCoordinator(filePresenter: self)
                var coordError: NSError?
                var replaceError: Error?
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
                    do {
                        try version.replaceItem(at: writeURL, options: .byMoving)
                    } catch {
                        replaceError = error
                    }
                }
                if let error = coordError { throw error }
                if let error = replaceError { throw error }
                print("[iCloudFileCoordinator] 冲突版本较新，已替换当前文件")
            } else {
                print("[iCloudFileCoordinator] 当前文件较新，保留当前文件")
            }

            // 标记所有未解决的冲突版本为已解决，再清理其他版本
            if let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
                for conflict in conflicts {
                    conflict.isResolved = true
                }
            }
            try NSFileVersion.removeOtherVersionsOfItem(at: url)

            print("[iCloudFileCoordinator] 冲突已解决")

            // 通知数据变更
            publishChange()
        } catch {
            print("[iCloudFileCoordinator] 错误: 无法解决文件冲突 - \(error.localizedDescription)")
        }
    }

    // MARK: - Coordinated File Operations

    /// 协调读取文件
    /// - Parameters:
    ///   - url: 要读取的文件 URL
    ///   - completion: 读取完成回调，返回数据或 nil（如果失败）
    func coordinatedRead(from url: URL, completion: @escaping (Data?) -> Void) {
        let coordinator = NSFileCoordinator(filePresenter: self)
        var error: NSError?

        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            do {
                let data = try Data(contentsOf: readURL)
                print("[iCloudFileCoordinator] 协调读取成功: \(readURL.lastPathComponent), 大小: \(data.count) bytes")
                completion(data)
            } catch {
                print("[iCloudFileCoordinator] 错误: 协调读取失败 - \(error.localizedDescription)")
                completion(nil)
            }
        }

        if let error = error {
            print("[iCloudFileCoordinator] 错误: 无法协调读取 - \(error.localizedDescription)")
            completion(nil)
        }
    }

    /// 协调写入文件（带重试机制）
    /// - Parameters:
    ///   - data: 要写入的数据
    ///   - url: 目标文件 URL
    ///   - retryCount: 当前重试次数（内部使用）
    /// - Throws: 写入失败时抛出错误
    func coordinatedWrite(data: Data, to url: URL, retryCount: Int = 0) throws {
        let coordinator = NSFileCoordinator(filePresenter: self)
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                // 写入数据
                try data.write(to: writeURL, options: .atomic)
                print("[iCloudFileCoordinator] 协调写入成功: \(writeURL.lastPathComponent), 大小: \(data.count) bytes")
            } catch {
                writeError = error
                print("[iCloudFileCoordinator] 错误: 协调写入失败 - \(error.localizedDescription)")
            }
        }

        // 处理协调错误
        if let error = coordinationError {
            throw error
        }

        // 处理写入错误（带重试）
        if let error = writeError {
            // 如果失败且未超过重试次数（最多3次），则重试
            if retryCount < 3 {
                print("[iCloudFileCoordinator] 重试写入 (\(retryCount + 1)/3)...")
                Thread.sleep(forTimeInterval: 0.5) // 等待 500ms
                try coordinatedWrite(data: data, to: url, retryCount: retryCount + 1)
            } else {
                throw error
            }
        }
    }

    // MARK: - Utility Methods

    /// 检查 iCloud 是否可用
    /// - Returns: true 如果 iCloud 可用，否则 false
    func isICloudAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }

    /// 读取被监控文件当前的修改时间
    private func currentFileModificationDate() -> Date? {
        guard let url = presentedItemURL else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    // MARK: - Saving State Management

    /// 设置正在保存标志（用于防止自己触发自己的变更通知）
    func beginSavingDatabase() {
        isSavingDatabase = true
        print("[iCloudFileCoordinator] 开始保存数据库，设置保存标志")
    }

    /// 清除正在保存标志。
    /// 延迟一小段时间再清除，确保自己写入触发的通知已被忽略；
    /// 窗口内到达的远程变更通知同样被丢弃，因此窗口结束时用写入后记录的
    /// 文件修改时间做比对，发现文件已被远端改写则补发通知
    func endSavingDatabase() {
        let checkpoint = currentFileModificationDate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.isSavingDatabase = false
            print("[iCloudFileCoordinator] 清除保存标志")
            if let checkpoint,
               let current = self.currentFileModificationDate(),
               current != checkpoint {
                print("[iCloudFileCoordinator] 抑制窗口期间文件被远端改写，补发变更通知")
                self.databaseFileChangeCount += 1
            }
        }
    }
}
