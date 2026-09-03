#if os(iOS)
import Foundation

/// iOS/iPad 专属 Pikafish 评估服务
/// 与 Mac 版(PikafishService，子进程 + UCI 管道)不同，这里把引擎源码直接编译进 App，
/// 通过 PikafishEngineBridge(Objective-C++)进程内调用 Stockfish::Engine，
/// 不走子进程/管道——iOS App Sandbox 本就不允许 Mac 那种子进程方案。
///
/// 出于耗电考虑，参数经过特别选择，明显弱于 Mac 版的深度评分：
/// - Threads/Hash 远低于 Mac 版
/// - 固定 3 秒 movetime，不做深度 34 的完整搜索
/// 因此评分单独存一个 engineKey，不与 Mac 的 `_d34` 共享，避免不同质量的数据互相覆盖。
///
/// 并发：底层只有一个 `Stockfish::Engine`，搜索中再次 `go` 会先阻塞主线程等上一轮结束，
/// 且 bestmove 回调被覆盖后会让上一轮的 continuation 永不恢复、下一轮的被 resume 两次而 trap。
/// 因此互斥必须在这里做（`isBusy`），忙碌时直接抛 `busy`，不依赖各调用方互相记得对方的状态。
/// 所有入口都在主线程调用（`@MainActor`），`isBusy` 的读写因此天然串行。
@MainActor
final class PikafishServiceIOS {

    enum EngineError: Error {
        /// 引擎正被另一个调用方占用（AI 应招 / 问棋分析互斥）
        case busy
    }

    /// 引擎版本，须与 Mac 版 PikafishService.engineVersion 保持一致
    static let engineVersion = "Pikafish_dev-20260213-391d491a"

    /// iOS 专属 engineKey：编码了引擎版本 + "ios" 标记 + 3 秒限时，
    /// 刻意不同于 Mac 的 "_d34"/"_t3s"，避免存储互相覆盖
    static let engineKey = "Pikafish_dev-20260213-391d491a_ios_t3s"

    /// 评估用时（毫秒）
    static let movetimeMs = 3000

    struct EvaluationResult {
        let score: Int
        let depth: Int
        let timeMs: Int
        let hashfull: Int
        let bestMove: String?
    }

    private let bridge = PikafishEngineBridge()
    private var isConfigured = false
    /// 是否有一次搜索在飞。见类型注释
    private(set) var isBusy = false

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        if let nnuePath = Bundle.main.path(forResource: "pikafish", ofType: "nnue") {
            bridge.loadNetwork(path: nnuePath)
        }

        let threadCount = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
        bridge.setThreads(threadCount)
        bridge.setHashMB(64)
    }

    /// 评估局面，movetime 固定 3 秒（与 Self.movetimeMs 一致）。引擎忙碌时抛 `EngineError.busy`
    func evaluatePosition(fen: String) async throws -> EvaluationResult? {
        guard !isBusy else { throw EngineError.busy }
        isBusy = true
        defer { isBusy = false }
        configureIfNeeded()

        let uciFen = PikafishFenConversion.convertFenToUCI(fen)
        bridge.setPosition(fen: uciFen, moves: [])

        return await withCheckedContinuation { continuation in
            bridge.go(movetimeMs: Self.movetimeMs) { result in
                guard let result = result else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: EvaluationResult(
                    score: result.score,
                    depth: result.depth,
                    timeMs: result.timeMs,
                    hashfull: result.hashfull,
                    bestMove: result.bestMove
                ))
            }
        }
    }

    /// MultiPV 多变着分析：返回前 N 条候选线路及各自分数与主变。
    /// 只读分析，不涉及数据库；供 app 内 AI 问棋的 evaluate 工具使用。
    ///
    /// 与 `evaluatePosition` 共用同一个引擎实例，忙碌时抛 `EngineError.busy`。
    func analyzePosition(fen: String, multiPV: Int, movetime: Int) async throws -> [EnginePVLine] {
        guard !isBusy else { throw EngineError.busy }
        isBusy = true
        defer { isBusy = false }
        configureIfNeeded()

        let uciFen = PikafishFenConversion.convertFenToUCI(fen)
        bridge.setPosition(fen: uciFen, moves: [])

        return await withCheckedContinuation { continuation in
            bridge.goMultiPV(movetimeMs: movetime, multiPV: multiPV) { lines in
                continuation.resume(returning: lines.map {
                    EnginePVLine(
                        multipv: $0.multipv,
                        scoreCp: $0.scoreCp,
                        mate: $0.mateInMoves?.intValue,
                        depth: $0.depth,
                        moves: $0.pvMoves
                    )
                })
            }
        }
    }

    /// 中断当前搜索
    func stopCurrentSearch() {
        bridge.stop()
    }

    /// 释放置换表与线程池内存，供 App 进入后台/内存紧张/低电量时调用。
    /// 先 stop() 再 searchClear()：searchClear 内部会阻塞等待搜索线程结束，
    /// 若不先发 stop 信号，搜索线程要等到 movetime（最多 3 秒）自然到期才会返回，
    /// 调用方（主线程）会被这几秒钟卡住
    func releaseResources() {
        bridge.stop()
        bridge.searchClear()
    }
}
#endif
