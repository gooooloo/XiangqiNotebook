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
        processingTask?.cancel()
        processingTask = nil
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
        processingTask = Task { [weak self] in
            while let self = self, !Task.isCancelled {
                guard !self.pendingRequests.isEmpty else { break }
                await self.processNext()
            }
            guard let self = self, !Task.isCancelled else { return }
            self.processingTask = nil
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

    private func processNext() async {
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
                guard !Task.isCancelled else { return }
                lastDetail = Self.formatEvalDetail(result)
                completedCount += 1
                onEvaluationCompleted?(request, result)
            }
        } catch {
            if !Task.isCancelled {
                print("[EvaluationQueue] fenId=\(request.fenId) 评估失败: \(error.localizedDescription)")
            }
        }

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
            parts.append("Hash\(h * 100 / 1000)%")
        }
        if result.timedOut {
            parts.append("超时")
        }
        return parts.joined(separator: " ")
    }
}
#endif
