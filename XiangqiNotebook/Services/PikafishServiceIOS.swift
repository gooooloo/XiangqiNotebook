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
final class PikafishServiceIOS {

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

    /// 评估局面，movetime 固定 3 秒（与 Self.movetimeMs 一致）
    func evaluatePosition(fen: String) async -> EvaluationResult? {
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
