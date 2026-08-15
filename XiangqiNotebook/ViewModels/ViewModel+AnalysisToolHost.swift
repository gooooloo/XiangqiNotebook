import Foundation

/// ViewModel 作为 AI 问棋工具层的宿主。
///
/// 单独成文件是为了不让 ViewModel.swift 继续膨胀：这里只做字段搬运与转调，
/// 不持有任何状态。引擎忙碌互斥留在 ViewModel.swift 的 `remoteEngineAnalyze` 里，
/// 因为那份 `isRemoteAnalyzing` 状态属于 ViewModel 自己。
extension ViewModel: AnalysisToolHost {

    /// 当前局面与笔记的快照。
    /// 远程 `/state` 与 AI 的 `get_position` 工具都从这里取数，两条路不会漂移。
    @MainActor
    func currentPositionSnapshot() -> PositionSnapshot {
        PositionSnapshot(
            fen: currentFen,
            displayFen: displayFen,
            mode: currentAppMode.rawValue,
            step: currentGameStepDisplay,
            maxStep: maxGameStepDisplay,
            orientation: isCurrentBlackOrientation ? "black" : "red",
            isHorizontalFlipped: isCurrentHorizontalFlipped,
            comment: currentFenComment,
            moveComment: currentMoveComment,
            badReason: currentMoveBadReason,
            lastMove: lastMoveForTools(),
            score: displayScore,
            engineScore: displayEngineScore,
            showPath: showPath,
            showAllNextMoves: showAllNextMoves,
            showLastMove: showLastMove,
            isLocked: isAnyMoveLocked,
            isBookmarked: isBookmarked,
            isInReview: isCurrentFenInReview,
            filters: currentFilters,
            nextMoves: currentNextMovesListDisplay.map(\.moveString),
            variants: currentGameVariantListDisplay.map(\.moveString),
            windowTitle: windowTitle
        )
    }

    /// 走到当前局面的那一步。着法名一律按未翻转的棋盘生成——
    /// 工具层其他地方都是这个口径，跟着界面翻转会让同一步棋在不同时候叫两个名字
    @MainActor
    private func lastMoveForTools() -> LastMove? {
        guard hasCurrentMove, let fenBefore = previousFen else { return nil }
        let chinese = Move.stringifyMove(fen1: fenBefore, fen2: currentFen,
                                         backup: "", isHorizontalFlipped: false)
        guard !chinese.isEmpty else { return nil }
        return LastMove(chinese: chinese, fenBefore: fenBefore)
    }

    /// MultiPV 分析，先查笔记本里的缓存。
    ///
    /// 问棋会反复分析同一批局面（同一个局面问两遍、`evaluate_move` 的前后两轮、
    /// 追问时重新核对），每次都现跑既慢又费电，iPhone 上尤其。
    /// 缓存随引擎分数文件走 iCloud，所以 Mac 上算过的局面 iPhone 直接读。
    @MainActor
    func analyzePosition(fen: String, multiPV: Int, movetime: Int) async throws -> EngineAnalysis {
        let fenId = notebookFenId(for: fen)

        if let fenId,
           let cached = Database.shared.findUsableEngineAnalysis(
            fenId: fenId, preferredKey: analysisCacheKey,
            multiPV: multiPV, movetimeMs: movetime) {
            return EngineAnalysis(
                lines: cached.lines(limitedTo: multiPV),
                engine: cached.engine,
                movetimeMs: cached.movetimeMs,
                fromCache: true)
        }

        let lines = try await remoteEngineAnalyze(fen: fen, multiPV: multiPV, movetime: movetime)
        let engine = engineVersionDescription

        // 只缓存笔记本里有的局面：探索性变着（apply_moves 走出来的）不入库，
        // 本来也不会重复问。这样缓存规模天然被笔记本封顶，不必做淘汰。
        // 这里只置脏不落盘，由 flushAnalysisCache 在一轮问棋结束时统一存
        if let fenId, !lines.isEmpty {
            Database.shared.setEngineAnalysis(
                fenId: fenId, engineKey: analysisCacheKey,
                analysis: CachedAnalysis(multiPV: multiPV, movetimeMs: movetime,
                                         engine: engine, lines: lines))
        }

        return EngineAnalysis(lines: lines, engine: engine,
                              movetimeMs: movetime, fromCache: false)
    }

    /// 把本轮攒下的分析缓存落盘，一轮问棋结束时调一次。
    ///
    /// 不在每次未命中时就存：`EngineScoreStorage.saveEngineScore` 是
    /// 「整份读盘 → merge 远端 → 全量 pretty-print 编码 → iCloud 协调写」，
    /// 而一轮完整评点要分析六七次。每次都存就是在主线程上把同一个文件反复重写——
    /// 分数攒到上万条就有几百 KB（实测 12000 条约 230KB），而分析缓存每条还要再占 1–2KB。
    /// 缓存越用越大，这笔开销只会越来越重，偏偏变大正是这个功能的目的。
    ///
    /// 代价是崩溃或强退会丢掉本轮缓存。那只是白算一次、重问会重新算出来，
    /// 不值得为它付每次都写盘的账
    @MainActor
    func flushAnalysisCache() {
        guard Database.shared.isEngineScoreDirty else { return }
        try? Database.shared.saveEngineScores()
    }

    /// 本机分析结果写到哪个 engineKey 名下。
    /// 沿用引擎分数的分文件约定：Mac 与 iOS 各写各的，读的时候才跨 key 找
    private var analysisCacheKey: String {
        #if os(macOS)
        return PikafishService.engineKey
        #elseif os(iOS)
        return PikafishServiceIOS.engineKey
        #else
        return "unavailable"
        #endif
    }

    var engineVersionDescription: String {
        #if os(macOS)
        return PikafishService.engineVersion
        #elseif os(iOS)
        return PikafishServiceIOS.engineVersion
        #else
        return "unavailable"
        #endif
    }
}
