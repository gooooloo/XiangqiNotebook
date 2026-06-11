#if os(macOS)
import XCTest
@testable import XiangqiNotebook

class MockPikafishService: PikafishService {
    var evaluateDelay: UInt64 = 10_000_000 // 10ms
    var resultToReturn: EvaluationResult? = EvaluationResult(
        score: 50, depth: "20", timeMs: 1000, hashfull: 500, timedOut: false, bestMove: "h2e2"
    )
    var evaluateCallCount = 0

    override func evaluatePosition(fen: String, movetime: Int? = nil) async throws -> EvaluationResult? {
        evaluateCallCount += 1
        try await Task.sleep(nanoseconds: evaluateDelay)
        return resultToReturn
    }

    override func stopCurrentSearch() {
        // no-op for tests
    }
}

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

    /// 轮询等待条件成立（替代固定 sleep，降低负载波动下的 flake）
    private func waitUntil(timeout: TimeInterval = 3.0, _ condition: () -> Bool) async throws {
        let start = Date()
        while !condition() && Date().timeIntervalSince(start) < timeout {
            try await Task.sleep(nanoseconds: 20_000_000)
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

        // Wait for processing
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(completedRequests.count, 1)
        XCTAssertEqual(completedRequests.first?.fenId, 1)
        XCTAssertEqual(mock.evaluateCallCount, 1)
        XCTAssertTrue(queue.state.isIdle)
        XCTAssertEqual(queue.state.completedCount, 1)
    }

    func testDeduplication() async throws {
        let (queue, mock) = makeQueue()

        let req1 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "key", movetime: nil)
        let req2 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "key", movetime: nil)
        queue.enqueue(req1)
        queue.enqueue(req2)

        XCTAssertEqual(queue.state.totalEnqueued, 1)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mock.evaluateCallCount, 1)
    }

    func testDifferentEngineKeysNotDeduplicated() async throws {
        let (queue, mock) = makeQueue()
        mock.evaluateDelay = 5_000_000

        let req1 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "deep", movetime: nil)
        let req2 = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "quick", movetime: 3000)
        queue.enqueue(req1)
        queue.enqueue(req2)

        XCTAssertEqual(queue.state.totalEnqueued, 2)

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(mock.evaluateCallCount, 2)
    }

    func testSkipExistingScores() async throws {
        let (queue, mock) = makeQueue(existingScores: ["1:testKey"])

        let request = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "testKey", movetime: nil)
        queue.enqueue(request)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(mock.evaluateCallCount, 0)
        XCTAssertEqual(queue.state.completedCount, 1)
        XCTAssertTrue(queue.state.isIdle)
    }

    func testCancelAll() async throws {
        let mock = MockPikafishService()
        mock.evaluateDelay = 500_000_000 // 500ms per evaluation
        let (queue, _) = makeQueue(mockService: mock)

        for i in 0..<5 {
            queue.enqueue(EvaluationRequest(fenId: i, fen: "fen\(i) r", engineKey: "key", movetime: nil))
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        queue.cancelAll()

        // 队列内容立即清空
        XCTAssertEqual(queue.state.totalEnqueued, 0)
        XCTAssertEqual(queue.state.pendingCount, 0)

        // 在飞的旧任务退出前队列不算 idle（防止并发驱动引擎）；
        // 退出后转为 idle
        try await waitUntil { queue.isIdle }
        XCTAssertTrue(queue.isIdle)
    }

    func testCancelAllThenReenqueue_ProcessesWithoutStatePollution() async throws {
        let mock = MockPikafishService()
        mock.evaluateDelay = 200_000_000 // 200ms
        let (queue, _) = makeQueue(mockService: mock)

        queue.enqueue(EvaluationRequest(fenId: 1, fen: "fen1 r", engineKey: "key", movetime: nil))
        try await Task.sleep(nanoseconds: 50_000_000) // 让请求进入评估中

        queue.cancelAll()
        // 旧任务还在退出途中时立即重新入队同一局面
        queue.enqueue(EvaluationRequest(fenId: 1, fen: "fen1 r", engineKey: "key", movetime: nil))

        try await waitUntil { queue.state.isIdle && queue.state.completedCount == 1 }

        // 新请求被处理恰好一次；旧任务的收尾不得污染新队列的去重与状态
        XCTAssertEqual(queue.state.completedCount, 1)
        XCTAssertTrue(queue.state.isIdle)
        XCTAssertEqual(queue.statusForFen(fenId: 1, engineKey: "key"), .idle)
    }

    func testStatusForFen() async throws {
        let mock = MockPikafishService()
        mock.evaluateDelay = 200_000_000 // 200ms
        let (queue, _) = makeQueue(mockService: mock)

        XCTAssertEqual(queue.statusForFen(fenId: 1, engineKey: "key"), .idle)

        queue.enqueue(EvaluationRequest(fenId: 1, fen: "fen1 r", engineKey: "key", movetime: nil))
        queue.enqueue(EvaluationRequest(fenId: 2, fen: "fen2 r", engineKey: "key", movetime: nil))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(queue.statusForFen(fenId: 1, engineKey: "key"), .evaluating)
        XCTAssertEqual(queue.statusForFen(fenId: 2, engineKey: "key"), .queued)
        XCTAssertEqual(queue.statusForFen(fenId: 3, engineKey: "key"), .idle)

        queue.cancelAll()
    }

    func testEnqueueAll() async throws {
        let (queue, mock) = makeQueue()
        mock.evaluateDelay = 5_000_000

        let requests = (0..<3).map { i in
            EvaluationRequest(fenId: i, fen: "fen\(i) r", engineKey: "key", movetime: nil)
        }
        queue.enqueueAll(requests)

        XCTAssertEqual(queue.state.totalEnqueued, 3)

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mock.evaluateCallCount, 3)
        XCTAssertEqual(queue.state.completedCount, 3)
        XCTAssertTrue(queue.state.isIdle)
    }

    func testCompletionState() async throws {
        let (queue, _) = makeQueue()

        let request = EvaluationRequest(fenId: 1, fen: "test r", engineKey: "key", movetime: nil)
        queue.enqueue(request)

        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(queue.state.isIdle)
        XCTAssertTrue(queue.state.isCompleted)
        XCTAssertEqual(queue.state.completedCount, 1)
        XCTAssertEqual(queue.state.totalEnqueued, 1)
    }
}
#endif
