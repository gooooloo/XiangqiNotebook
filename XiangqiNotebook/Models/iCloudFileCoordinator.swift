import Foundation
import Combine

/// iCloud 文件协调服务
/// 负责处理 database.json 的多设备同步协调，使用 NSFilePresenter 和 NSFileCoordinator
/// 确保多个设备同时访问时的数据一致性
class iCloudFileCoordinator: NSObject, ObservableObject, NSFilePresenter {

    // MARK: - Singleton
    static let shared = iCloudFileCoordinator()

    // MARK: - Published Properties

    /// 文件变更通知 - 当远程 database.json 被其他设备修改时触发
    @Published var databaseFileChanged: Bool = false

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

    /// 标记当前设备是否正在保存数据库文件（用于防止自己触发自己的变更通知）
    private var isSavingDatabase: Bool = false

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

        // 在主线程发布变更通知
        DispatchQueue.main.async { [weak self] in
            self?.databaseFileChanged = true
        }
    }

    /// 处理文件版本冲突
    /// - Parameter version: 新的文件版本
    func presentedItemDidGain(_ version: NSFileVersion) {
        print("[iCloudFileCoordinator] 检测到文件版本冲突: \(version.modificationDate ?? Date())")

        // 尝试自动解决冲突：选择最新版本
        do {
            if version.isConflict {
                // 标记为已解决
                try version.replaceItem(at: presentedItemURL!, options: .byMoving)
                try NSFileVersion.removeOtherVersionsOfItem(at: presentedItemURL!)

                print("[iCloudFileCoordinator] 已自动解决冲突，使用最新版本")

                // 通知数据变更
                DispatchQueue.main.async { [weak self] in
                    self?.databaseFileChanged = true
                }
            }
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

    /// 重置文件变更标志
    func resetFileChangeFlag() {
        DispatchQueue.main.async { [weak self] in
            self?.databaseFileChanged = false
        }
    }

    // MARK: - Saving State Management

    /// 设置正在保存标志（用于防止自己触发自己的变更通知）
    func beginSavingDatabase() {
        isSavingDatabase = true
        print("[iCloudFileCoordinator] 开始保存数据库，设置保存标志")
    }

    /// 清除正在保存标志
    /// 延迟一小段时间再清除标志，确保 iCloud 的通知已经被忽略
    func endSavingDatabase() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isSavingDatabase = false
            print("[iCloudFileCoordinator] 清除保存标志")
        }
    }
}
