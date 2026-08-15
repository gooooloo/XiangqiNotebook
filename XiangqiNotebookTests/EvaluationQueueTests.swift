#if os(macOS)
import XCTest
@testable import XiangqiNotebook

/// 假引擎。
///
/// `evaluatePosition` 是非隔离的 async 方法，跑在通用执行器上，而队列的处理任务跑在
/// MainActor 上——两个执行器读写同一批计数器，所以这里的可变状态一律上锁。
class MockPikafishService: PikafishService {
    /// 评估耗时。只用来模拟「要花点时间」，不承担让测试观察到中间态的职责
    var evaluateDelay: UInt64 = 10_000_000 // 10ms
    var resultToReturn: EvaluationResult? = EvaluationResult(
        score: 50, depth: "20", timeMs: 1000, hashfull: 500, timedOut: false, bestMove: "h2e2"
    )

    private let lock = NSLock()
    private var _evaluateCallCount = 0
    private var _holdEvaluation = false

    var evaluateCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _evaluateCallCount
    }

    /// 置 true 时评估进入后一直挂着，直到测试置回 false（或任务被取消）。
    ///
    /// 「让请求停在评估中」必须是确定的。原先靠 `sleep(50ms)` 猜时机——赌它已经开始、
    /// 又还没结束——并行跑测试时 CPU 一忙这个赌注就输：要么还没进评估，要么已经跑完，
    /// 两头都会让断言莫名其妙地失败
    var holdEvaluation: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _holdEvaluation }
        set { lock.lock(); defer { lock.unlock() }; _holdEvaluation = newValue }
    }

    override func evaluatePosition(fen: String, movetime: Int? = nil) async throws -> EvaluationResult? {
        lock.lock()
        _evaluateCallCount += 1
        lock.unlock()

        // 挂起期间照常让出执行器；被取消时 Task.sleep 抛错，连带把这里放出去。
        // 加硬上限是兜底：某条断言失败提前返回时就没人来放行了，不封顶的话
        // 这个任务会一直占着执行器，把之后每一个用例都拖慢
        let deadline = Date().addingTimeInterval(10)
        while holdEvaluation && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await Task.sleep(nanoseconds: evaluateDelay)
        return resultToReturn
    }

    override func stopCurrentSearch() {
        // no-op for tests
    }
}

/// 队列状态由 MainActor 上的处理任务改写，测试也放到 MainActor 上读，
/// 免得断言看到的是另一个执行器上的半成品
@MainActor
final class EvaluationQueueTests: XCTestCase {

    private func makeQueue(
        mockService: MockPikafishService = MockPikafishService(),
        existingScores: Set<String> = []
    ) -> (EvaluationQueue, MockPikafishService) {
        let queue = EvaluationQueue(pikafishService: mockService) { fenId, engineKey in
            existingScores.contains("\(fenId):\(engineKey)")
        }
        return (queue, mockService)
    }

    /// 轮询等待条件成立，替代固定 sleep。
    ///
    /// 超时直接报错并写明在等什么：不然只会看到后面某条断言「值不对」，
    /// 分不清是没等到还是逻辑真的错了——这正是原先这几个用例难查的原因
    private func waitUntil(_ what: String, timeout: TimeInterval = 5.0,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) >= timeout {
                XCTFail("等待超时（\(timeout)s）：\(what)", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testEnqueueAndProcess() async throws {
        let (queue, mock) = makeQueue()
        var completedRequests: [EvaluationRequest] = []
        queue.onEvaluationCompleted = { request, _ in
            completedRequests.append(request)
        }

        let request = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "testKey", movetime: nil)
        queue.enqueue(request)

        XCTAssertEqual(queue.state.totalEnqueued, 1)
        XCTAssertFalse(queue.state.isIdle)

        try await waitUntil("队列跑完") { queue.state.isIdle }

        XCTAssertEqual(completedRequests.count, 1)
        XCTAssertEqual(completedRequests.first?.fenId, 1)
        XCTAssertEqual(mock.evaluateCallCount, 1)
        XCTAssertEqual(queue.state.completedCount, 1)
    }

    func testDeduplication() async throws {
        let (queue, mock) = makeQueue()

        let req1 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "key", movetime: nil)
        let req2 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "key", movetime: nil)
        queue.enqueue(req1)
        queue.enqueue(req2)

        XCTAssertEqual(queue.state.totalEnqueued, 1)

        try await waitUntil("队列跑完") { queue.state.isIdle }

        XCTAssertEqual(mock.evaluateCallCount, 1)
    }

    func testDifferentEngineKeysNotDeduplicated() async throws {
        let (queue, mock) = makeQueue()

        let req1 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "deep", movetime: nil)
        let req2 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "quick", movetime: 3000)
        queue.enqueue(req1)
        queue.enqueue(req2)

        XCTAssertEqual(queue.state.totalEnqueued, 2)

        try await waitUntil("两条都跑完") { queue.state.isIdle }

        XCTAssertEqual(mock.evaluateCallCount, 2)
    }

    func testSkipExistingScores() async throws {
        let (queue, mock) = makeQueue(existingScores: ["1:testKey"])

        let request = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "testKey", movetime: nil)
        queue.enqueue(request)

        try await waitUntil("队列跑完") { queue.state.isIdle }

        XCTAssertEqual(mock.evaluateCallCount, 0)
        XCTAssertEqual(queue.state.completedCount, 1)
    }

    func testCancelAll() async throws {
        let mock = MockPikafishService()
        mock.holdEvaluation = true
        let (queue, _) = makeQueue(mockService: mock)

        for i in 0..<5 {
            queue.enqueue(EvaluationRequest(fenId: i, fen: "fen\(i) r", engineKey: "key", movetime: nil))
        }

        try await waitUntil("第一条进入评估中") { mock.evaluateCallCount == 1 }

        queue.cancelAll()

        // 队列内容立即清空
        XCTAssertEqual(queue.state.totalEnqueued, 0)
        XCTAssertEqual(queue.state.pendingCount, 0)

        // cancelAll 是同步的，这中间没有 await，在飞的旧任务不可能已经退出。
        // 此刻若判为 idle，紧接着的 enqueue 就会另起一个处理任务，
        // 与旧任务并发驱动同一个无锁的 PikafishService
        XCTAssertFalse(queue.isIdle, "在飞的旧任务退出前不得转 idle")

        mock.holdEvaluation = false
        try await waitUntil("旧任务退出后转 idle") { queue.isIdle }
    }

    func testCancelAllThenReenqueue_ProcessesWithoutStatePollution() async throws {
        let mock = MockPikafishService()
        mock.holdEvaluation = true
        let (queue, _) = makeQueue(mockService: mock)

        queue.enqueue(EvaluationRequest(fenId: 1, fen: "fen1 r", engineKey: "key", movetime: nil))
        try await waitUntil("请求进入评估中") { mock.evaluateCallCount == 1 }

        queue.cancelAll()
        // 旧任务还在退出途中时立即重新入队同一局面
        queue.enqueue(EvaluationRequest(fenId: 1, fen: "fen1 r", engineKey: "key", movetime: nil))
        mock.holdEvaluation = false

        try await waitUntil("新请求跑完") { queue.state.isIdle && queue.state.completedCount == 1 }

        // 新请求被处理恰好一次；旧任务的收尾不得污染新队列的去重与状态
        XCTAssertEqual(queue.state.completedCount, 1)
        XCTAssertTrue(queue.state.isIdle)
        XCTAssertEqual(queue.statusForFen(fenId: 1, engineKey: "key"), .idle)
    }

    func testStatusForFen() async throws {
        let mock = MockPikafishService()
        mock.holdEvaluation = true
        let (queue, _) = makeQueue(mockService: mock)

        XCTAssertEqual(queue.statusForFen(fenId: 1, engineKey: "key"), .idle)

        queue.enqueue(EvaluationRequest(fenId: 1, fen: "fen1 r", engineKey: "key", movetime: nil))
        queue.enqueue(EvaluationRequest(fenId: 2, fen: "fen2 r", engineKey: "key", movetime: nil))

        // currentRequest 在调用引擎之前就已写好，所以计数一到 1，1 号必然是「评估中」
        try await waitUntil("1 号进入评估中") { mock.evaluateCallCount == 1 }

        XCTAssertEqual(queue.statusForFen(fenId: 1, engineKey: "key"), .evaluating)
        XCTAssertEqual(queue.statusForFen(fenId: 2, engineKey: "key"), .queued)
        XCTAssertEqual(queue.statusForFen(fenId: 3, engineKey: "key"), .idle)

        mock.holdEvaluation = false
        queue.cancelAll()
    }

    func testEnqueueAll() async throws {
        let (queue, mock) = makeQueue()

        let requests = (0..<3).map { i in
            EvaluationRequest(fenId: i, fen: "fen\(i) r", engineKey: "key", movetime: nil)
        }
        queue.enqueueAll(requests)

        XCTAssertEqual(queue.state.totalEnqueued, 3)

        try await waitUntil("三条都跑完") { queue.state.isIdle }

        XCTAssertEqual(mock.evaluateCallCount, 3)
        XCTAssertEqual(queue.state.completedCount, 3)
    }

    func testCompletionState() async throws {
        let (queue, _) = makeQueue()

        let request = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "key", movetime: nil)
        queue.enqueue(request)

        try await waitUntil("队列跑完") { queue.state.isCompleted }

        XCTAssertTrue(queue.state.isIdle)
        XCTAssertEqual(queue.state.completedCount, 1)
        XCTAssertEqual(queue.state.totalEnqueued, 1)
    }
}
#endif
