import Foundation

enum FenEvalStatus {
    case idle, queued, evaluating
}

#if os(macOS)

struct EvaluationRequest: Identifiable, Equatable {
    let id = UUID()
    let fenId: Int
    let fen: String
    let engineKey: String
    let movetime: Int?

    static func == (lhs: EvaluationRequest, rhs: EvaluationRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct EvaluationQueueState {
    let pendingCount: Int
    let currentRequest: EvaluationRequest?
    let currentDetail: String?
    let completedCount: Int
    let totalEnqueued: Int
    let elapsedSeconds: Double?
    let isIdle: Bool
    let isCompleted: Bool
}

class EvaluationQueue: ObservableObject {
    @Published private(set) var state = EvaluationQueueState(
        pendingCount: 0, currentRequest: nil, currentDetail: nil,
        completedCount: 0, totalEnqueued: 0, elapsedSeconds: nil,
        isIdle: true, isCompleted: false
    )

    private var pendingRequests: [EvaluationRequest] = []
    private var dedupSet: Set<String> = []
    private var processingTask: Task<Void, Never>?
    /// 取消代数：cancelAll 时 +1。被取消的旧任务凭代数识别自己已过期，
    /// 不得再触碰新一代队列的 dedupSet 与发布状态
    private var generation = 0
    private var completedCount = 0
    private var totalEnqueued = 0
    private var lastDetail: String?
    private var startTime: Date?

    private let pikafishService: PikafishService
    private let scoreExists: (Int, String) -> Bool

    var onEvaluationCompleted: ((EvaluationRequest, PikafishService.EvaluationResult) -> Void)?

    init(pikafishService: PikafishService, scoreExists: @escaping (Int, String) -> Bool) {
        self.pikafishService = pikafishService
        self.scoreExists = scoreExists
    }

    func enqueue(_ request: EvaluationRequest) {
        let key = dedupKey(request)
        guard !dedupSet.contains(key) else { return }
        dedupSet.insert(key)
        pendingRequests.append(request)
        totalEnqueued += 1
        if startTime == nil { startTime = Date() }
        updatePublishedState()
        startProcessingIfNeeded()
    }

    func enqueueAll(_ requests: [EvaluationRequest]) {
        for request in requests {
            let key = dedupKey(request)
            guard !dedupSet.contains(key) else { continue }
            dedupSet.insert(key)
            pendingRequests.append(request)
            totalEnqueued += 1
        }
        if !requests.isEmpty && startTime == nil { startTime = Date() }
        updatePublishedState()
        startProcessingIfNeeded()
    }

    func cancelAll() {
        generation += 1
        processingTask?.cancel()
        // 注意：不立即置 nil processingTask。
        // cancel 并不会中断在飞的 evaluatePosition；若此处立即释放槽位，
        // 紧接着的 enqueue 会启动第二个处理任务，与旧任务并发驱动同一个
        // 无锁的 PikafishService。旧任务退出时自行清理并按需重启处理
        pikafishService.stopCurrentSearch()
        pendingRequests.removeAll()
        dedupSet.removeAll()
        completedCount = 0
        totalEnqueued = 0
        lastDetail = nil
        startTime = nil
        updatePublishedState()
    }

    var isIdle: Bool {
        processingTask == nil && pendingRequests.isEmpty
    }

    func statusForFen(fenId: Int, engineKey: String) -> FenEvalStatus {
        if let current = state.currentRequest,
           current.fenId == fenId && current.engineKey == engineKey {
            return .evaluating
        }
        let key = "\(fenId):\(engineKey)"
        if dedupSet.contains(key) {
            return .queued
        }
        return .idle
    }

    // MARK: - Private

    private func dedupKey(_ request: EvaluationRequest) -> String {
        "\(request.fenId):\(request.engineKey)"
    }

    private func startProcessingIfNeeded() {
        guard processingTask == nil else { return }
        let myGeneration = generation
        // 必须在 MainActor 上处理：回调会修改 Session/Database 数据，
        // 队列状态也与主线程的 enqueue/cancelAll 共享，否则产生数据竞争
        processingTask = Task { @MainActor [weak self] in
            while let self = self, !Task.isCancelled, self.generation == myGeneration {
                guard !self.pendingRequests.isEmpty else { break }
                await self.processNext(generation: myGeneration)
            }
            guard let self = self else { return }

            // 无论正常结束还是被取消都要释放任务槽位
            self.processingTask = nil

            if self.generation != myGeneration || Task.isCancelled {
                // 被取消的旧任务退出：若取消后又有新请求入队，在此补启动处理
                if !self.pendingRequests.isEmpty {
                    self.startProcessingIfNeeded()
                } else {
                    self.updatePublishedState()
                }
                return
            }

            self.state = EvaluationQueueState(
                pendingCount: 0,
                currentRequest: nil,
                currentDetail: self.lastDetail,
                completedCount: self.completedCount,
                totalEnqueued: self.totalEnqueued,
                elapsedSeconds: self.startTime.map { Date().timeIntervalSince($0) },
                isIdle: true,
                isCompleted: true
            )
        }
    }

    @MainActor
    private func processNext(generation myGeneration: Int) async {
        guard !pendingRequests.isEmpty else { return }
        let request = pendingRequests.removeFirst()

        if scoreExists(request.fenId, request.engineKey) {
            dedupSet.remove(dedupKey(request))
            completedCount += 1
            updatePublishedState()
            return
        }

        state = EvaluationQueueState(
            pendingCount: pendingRequests.count,
            currentRequest: request,
            currentDetail: lastDetail,
            completedCount: completedCount,
            totalEnqueued: totalEnqueued,
            elapsedSeconds: startTime.map { Date().timeIntervalSince($0) },
            isIdle: false,
            isCompleted: false
        )

        do {
            if let result = try await pikafishService.evaluatePosition(fen: request.fen, movetime: request.movetime) {
                guard !Task.isCancelled, self.generation == myGeneration else { return }
                lastDetail = Self.formatEvalDetail(result)
                completedCount += 1
                onEvaluationCompleted?(request, result)
            }
        } catch {
            if !Task.isCancelled {
                print("[EvaluationQueue] fenId=\(request.fenId) 评估失败: \(error.localizedDescription)")
            }
        }

        // await 期间可能发生了 cancelAll：过期任务不得再触碰新一代队列的
        // dedupSet 与发布状态（否则会把新队列中同一局面的去重键误删）
        guard !Task.isCancelled, self.generation == myGeneration else { return }
        dedupSet.remove(dedupKey(request))
        updatePublishedState()
    }

    private func updatePublishedState() {
        state = EvaluationQueueState(
            pendingCount: pendingRequests.count,
            currentRequest: nil,
            currentDetail: lastDetail,
            completedCount: completedCount,
            totalEnqueued: totalEnqueued,
            elapsedSeconds: startTime.map { Date().timeIntervalSince($0) },
            isIdle: pendingRequests.isEmpty && processingTask == nil,
            isCompleted: false
        )
    }

    static func formatEvalDetail(_ result: PikafishService.EvaluationResult) -> String {
        var parts: [String] = []
        if let depth = result.depth {
            parts.append("深度\(depth)")
        }
        if let ms = result.timeMs {
            parts.append("耗时\(String(format: "%.1f", Double(ms) / 1000.0))s")
        }
        if let h = result.hashfull {
            parts.append("Hash\(h / 10)%")  // hashfull 是千分比
        }
        if result.timedOut {
            parts.append("超时")
        }
        return parts.joined(separator: " ")
    }
}
#endif
