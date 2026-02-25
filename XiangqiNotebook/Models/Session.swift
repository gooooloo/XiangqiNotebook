import Foundation

/// Session 是一个局面对象的集合
class Session: ObservableObject {
    // MARK: - DatabaseView + SessionData

    /// 基础数据库视图（仅 scope 过滤，不含步数限制）
    /// 用于 BFS 计算可达 fenId 集合
    private var baseDatabaseView: DatabaseView

    /// 数据库视图，封装过滤逻辑
    /// 根据当前 filter 提供对 Database 的过滤访问，所有 fenId 相关的数据访问都应通过此视图
    /// 当 gameStepLimitation 生效时，叠加步数限制过滤
    /// internal 允许同一模块中的其他类型访问（如 ViewModel, Views）
    internal var databaseView: DatabaseView

    /// 单一 sessionData，internal 允许 SessionManager 访问
    internal var sessionData: SessionData

    var sessionDataDirty: Bool = false
    var engineScoreDirty: Bool = false

    // databaseDirty 现在通过 databaseView.isDirty 访问
    var databaseDirty: Bool {
        return databaseView.isDirty
    }

    // MARK: - Static Constants
    static let filterRedOpeningOnly = "red_opening_only"
    static let filterBlackOpeningOnly = "black_opening_only"
    static let filterRedRealGameOnly = "red_real_game_only"
    static let filterBlackRealGameOnly = "black_real_game_only"
    static let filterFocusedPractice = "focused_practice"
    static let filterSpecificGame = "specific_game"
    static let filterSpecificBook = "specific_book"
    static let myRealGameBookId = UUID(uuidString: "7B8E9F0A-1C2D-3E4F-5A6B-7C8D9E0F1A2B")!
    static let myRealRedGameBookId = UUID(uuidString: "2C3D4E5F-6A7B-8C9D-0E1F-2A3B4C5D6E7F")!
    static let myRealBlackGameBookId = UUID(uuidString: "9D0E1F2A-3B4C-5D6E-7F8A-9B0C1D2E3F4A")!
    static let othersRealGameBookId = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!

    @Published public var dataChanged: Bool = false

    // MARK: - 构造与兼容解码

    /// 主构造器：直接注入 DatabaseView（用于 SessionManager）
    /// - Parameters:
    ///   - sessionData: 会话数据
    ///   - databaseView: 数据库视图（已经根据 filter 创建好的）
    init(sessionData: SessionData, databaseView: DatabaseView) throws {
        self.baseDatabaseView = databaseView
        self.databaseView = databaseView
        self.sessionData = sessionData

        // 根据 gameStepLimitation 构建步数限制视图
        rebuildDatabaseView()

        // 设置默认棋书
        setupDefaultBooksIfNeeded()

        // 设置默认 currentGame2（确保指向有效局面）
        setupDefaultCurrentGameIfNeeded()
    }

    // MARK: - Readonly Properties
    var previousFenId: Int? {
        guard sessionData.currentGameStep - 1 >= 0,
              sessionData.currentGameStep - 1 < sessionData.currentGame2.count else {
            return nil
        }
        return sessionData.currentGame2[safe: sessionData.currentGameStep - 1]
    }

    var previousFenObject: FenObject? {
        guard let prevFenId = previousFenId else {
            return nil
        }
        return databaseView.getFenObject(prevFenId)
    }
    
    var currentFenId: Int {
        guard sessionData.currentGameStep < sessionData.currentGame2.count else {
            return sessionData.currentGame2[0] // 返回初始局面作为后备
        }
        return sessionData.currentGame2[sessionData.currentGameStep]
    }

    var currentFenObject: FenObject {
        guard let fenObject = databaseView.getFenObject(currentFenId) else {
            fatalError("FenObject not found for fenId: \(currentFenId)")
        }
        return fenObject
    }

    var currentFen: String {
        return currentFenObject.fen
    }
    
    var currentMove: Move? {
        guard let prevFenId = previousFenId else { return nil }
        return databaseView.move(from: prevFenId, to: currentFenId)
    }
    
    var currentGameMoveList: [MoveListItem] {
        return GameOperations.formatMoveList(
            currentGame: sessionData.currentGame2,
            databaseView: databaseView,
            isHorizontalFlipped: sessionData.isHorizontalFlipped
        )
    }

    var currentGameVariantList: [(moveString: String, move: Move)] {
        currentGameVariantMoves.map { (databaseView.formatMove($0, isHorizontalFlipped: sessionData.isHorizontalFlipped), $0) }
    }
    
    var currentGameVariantMoves: [Move] {
        guard sessionData.currentGameStep != 0,
              let prevFenId = previousFenId,
              databaseView.containsFenId(prevFenId) else {
            return []
        }

        return databaseView.moves(from: prevFenId)
    }

    var currentNextMovesList: [(moveString: String, move: Move)] {
        let moves = databaseView.moves(from: currentFenId)
        return moves.map { (databaseView.formatMove($0, isHorizontalFlipped: sessionData.isHorizontalFlipped), $0) }
    }

    var currentFenComment: String? {
        currentFenObject.comment
    }
    
    var currentFenScore: Int? {
        currentFenObject.score
    }
    
    var currentMoveComment: String? {
        currentMove?.comment
    }

    var currentMoveBadReason: String? {
        currentMove?.badReason
    }

    var currentCombinedComment: String? {
        getCombinedComment(fenObject: currentFenObject, move: currentMove)
    }

    /// 获取与当前局面相关的课程
    /// 返回"课程"书籍及其子书籍中所有包含当前 fenId 的游戏
    var relatedCoursesForCurrentFen: [GameObject] {
        let currentFenId = self.currentFenId

        // 查找名为"课程"的 BookObject
        guard let courseBook = databaseView.getAllBookObjectsUnfiltered().first(where: { $0.name == "课程" }) else {
            return []
        }

        // 获取"课程"及其所有子书籍中的游戏
        let allGames = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: courseBook.id)

        // 过滤出包含当前 fenId 的游戏
        return allGames.filter { game in
            databaseView.gameContainsFenId(gameId: game.id, fenId: currentFenId)
        }
    }

    var currentFenCanChangeInBlackOpening: Bool {
        currentFenObject.canChangeInBlackOpening
    }
    
    var currentFenCanChangeInRedOpening: Bool {
        currentFenObject.canChangeInRedOpening
    }
    
    var currentFenIsInBlackOpening: Bool {
        currentFenObject.isInBlackOpening
    }
    
    var currentFenIsInRedOpening: Bool {
        currentFenObject.isInRedOpening
    }

    var currentFenInRealRedGameTotalCount: Int {
        let gameStatistics = databaseView.myRealRedGameStatisticsByFenId[currentFenId] ?? GameResultStatistics()
        return gameStatistics.redWin + gameStatistics.blackWin + gameStatistics.draw + gameStatistics.notFinished + gameStatistics.unknown
    }

    var currentFenInRealRedGameWinCount: Int {
        databaseView.myRealRedGameStatisticsByFenId[currentFenId]?.redWin ?? 0
    }

    var currentFenInRealRedGameLossCount: Int {
        databaseView.myRealRedGameStatisticsByFenId[currentFenId]?.blackWin ?? 0
    }

    var currentFenInRealRedGameDrawCount: Int {
        databaseView.myRealRedGameStatisticsByFenId[currentFenId]?.draw ?? 0
    }

    var currentFenInRealBlackGameTotalCount: Int {
        let gameStatistics = databaseView.myRealBlackGameStatisticsByFenId[currentFenId] ?? GameResultStatistics()
        return gameStatistics.redWin + gameStatistics.blackWin + gameStatistics.draw + gameStatistics.notFinished + gameStatistics.unknown
    }

    var currentFenInRealBlackGameWinCount: Int {
        databaseView.myRealBlackGameStatisticsByFenId[currentFenId]?.blackWin ?? 0
    }

    var currentFenInRealBlackGameLossCount: Int {
        databaseView.myRealBlackGameStatisticsByFenId[currentFenId]?.redWin ?? 0
    }

    var currentFenInRealBlackGameDrawCount: Int {
        databaseView.myRealBlackGameStatisticsByFenId[currentFenId]?.draw ?? 0
    }

    var gameStepLimitation: Int? {
        sessionData.gameStepLimitation
    }

    var autoExtendGameWhenPlayingBoardFen: Bool {
        sessionData.autoExtendGameWhenPlayingBoardFen
    }

    var currentFilters: [String] {
        sessionData.filters
    }

    var currentSpecificGameId: UUID? {
        sessionData.specificGameId
    }

    var allowAddingNewMoves: Bool {
        sessionData.allowAddingNewMoves
    }

    var canToggleAllowAddingNewMoves: Bool {
        // 无过滤模式下，可以切换
        if sessionData.filters.isEmpty {
            return true
        }

        // 特定棋局模式下，需要检查是否完整录入
        if sessionData.filters.contains(Session.filterSpecificGame) {
            guard let gameId = sessionData.specificGameId,
                  let game = databaseView.getGameObject(gameId) else {
                return true  // 找不到游戏时，允许切换
            }
            // 如果游戏已完整录入，不允许切换（强制禁止添加新走法）
            return !game.isFullyRecorded
        }

        // 其他过滤模式下，不允许切换
        return false
    }

    var currentDataVersion: Int {
        databaseView.dataVersion
    }

    var currentCheckpointDataVersion: Int {
        return databaseDirty ? databaseView.dataVersion - 1 : databaseView.dataVersion
    }

    var currentDataDirty: Bool {
        databaseDirty || sessionDataDirty || engineScoreDirty
    }

    var currentGameStepDisplay: Int {
        sessionData.currentGameStep
    }

    var currentFenPracticeCount: Int {
        currentFenObject.practiceCount
    }

    var maxGameStepDisplay: Int {
        maxGameStep
    }
    
    var maxGameStep: Int {
        sessionData.currentGame2.count - 1
    }
    
    func getScoreByFenId(_ fenId: Int) -> Int? {
        return databaseView.getScoreByFenId(fenId)
    }

    func getEngineScoreByFenId(_ fenId: Int) -> Int? {
        return databaseView.getEngineScoreByFenId(fenId)
    }

    // TODO: 后续统一分数 API
    var currentEngineScore: Int? {
        return databaseView.getEngineScoreByFenId(currentFenId)
    }


    var bookmarkList: [(game: [Int], name: String)] {
        return databaseView.bookmarkList
    }
    
    var isBookmarked: Bool {
        return databaseView.bookmarks[Array(sessionData.currentGame2[0...sessionData.currentGameStep])] != nil
    }
    
    // MARK: - 复习项管理

    var isCurrentFenInReview: Bool {
        databaseView.reviewItems[currentFenId] != nil
    }

    var reviewItemList: [(fenId: Int, srsData: SRSData)] {
        databaseView.reviewItems
            .map { (fenId: $0.key, srsData: $0.value) }
            .sorted { $0.srsData.nextReviewDate < $1.srsData.nextReviewDate }
    }

    func addCurrentFenToReview() {
        let fenId = currentFenId
        guard databaseView.reviewItems[fenId] == nil else { return }
        let gamePath = Array(sessionData.currentGame2[0...sessionData.currentGameStep])
        let srsData = SRSData(gamePath: gamePath)
        databaseView.updateReviewItem(for: fenId, srsData: srsData)
        dataChanged.toggle()
    }

    func removeReviewItem(fenId: Int) {
        databaseView.updateReviewItem(for: fenId, srsData: nil)
        dataChanged.toggle()
    }

    func renameReviewItem(fenId: Int, name: String) {
        guard let srsData = databaseView.reviewItems[fenId] else { return }
        srsData.customName = name.isEmpty ? nil : name
        databaseView.updateReviewItem(for: fenId, srsData: srsData)
        dataChanged.toggle()
    }

    func reviewAgain(fenId: Int) {
        guard let srsData = databaseView.reviewItems[fenId] else { return }
        srsData.nextReviewDate = Date()
        databaseView.updateReviewItem(for: fenId, srsData: srsData)
        dataChanged.toggle()
    }

    /// 返回已到期的复习项，按 nextReviewDate 升序排列
    var dueReviewItems: [(fenId: Int, srsData: SRSData)] {
        databaseView.reviewItems
            .filter { $0.value.isDue }
            .map { (fenId: $0.key, srsData: $0.value) }
            .sorted { $0.srsData.nextReviewDate < $1.srsData.nextReviewDate }
    }

    /// 提交复习评分，更新 SRS 数据并持久化
    func submitReviewRating(fenId: Int, quality: ReviewQuality) {
        guard let srsData = databaseView.reviewItems[fenId] else { return }
        srsData.review(quality: quality)
        databaseView.updateReviewItem(for: fenId, srsData: srsData)
        dataChanged.toggle()
    }

    var isCurrentBlackOrientation: Bool {
        sessionData.isBlackOrientation
    }
    
    var isAnyMoveLocked: Bool {
        sessionData.lockedStep != nil
    }

    var currentAppMode: AppMode {
        sessionData.currentMode
    }

    var canNavigateBeforeLockedStep: Bool {
        sessionData.canNavigateBeforeLockedStep
    }

    var showPath: Bool {
        sessionData.showPath
    }

    var showAllNextMoves: Bool {
        sessionData.showAllNextMoves
    }

    var isCommentEditing: Bool {
        sessionData.isCommentEditing
    }
    
    var blackJustPlayed: Bool {
        currentFenObject.blackJustPlayed
    }

    var redJustPlayed: Bool {
        currentFenObject.redJustPlayed
    }

    private func adjustScore(_ score: Int, nextIsRed: Bool) -> Int {
        // 这里有个技巧：云库的分数是基于下一步行棋方的，而我们的界面想要显示基于当前视角的分数
        let boardIsRed = !sessionData.isBlackOrientation
        return (nextIsRed != boardIsRed) ? -score : score
    }

    var displayScore: String {
        let nextIsRed = currentFen.split(separator: " ")[1] == "r"
        guard let score = currentFenScore else { return "" }
        return "\(adjustScore(score, nextIsRed: nextIsRed))"
    }

    var displayEngineScore: String {
        let nextIsRed = currentFen.split(separator: " ")[1] == "r"
        guard let score = currentEngineScore else { return "" }
        return "\(adjustScore(score, nextIsRed: nextIsRed))"
    }

    func getDisplayScoreForMove(_ move: Move) -> String {
        guard let targetFenId = move.targetFenId,
              let score = getScoreByFenId(targetFenId) else {
            return ""
        }
        
        guard let targetFen = getFenForId(targetFenId) else {
            return ""
        }
        let nextIsRed = targetFen.split(separator: " ")[1] == "r"
        let adjustedScore = adjustScore(score, nextIsRed: nextIsRed)
        
        return String(adjustedScore)
    }

    func getDisplayScoreDeltaForMove(_ move: Move) -> String {
        let sourceFenId = move.sourceFenId
        guard let targetFenId = move.targetFenId,
              let sourceFenScore = getScoreByFenId(sourceFenId),
              let targetFenScore = getScoreByFenId(targetFenId) else {
            return ""
        }

        guard let sourceFen = getFenForId(sourceFenId) else {
            return ""
        }
        let sourceNextIsRed = sourceFen.split(separator: " ")[1] == "r"
        let adjustedSourceScore = adjustScore(sourceFenScore, nextIsRed: sourceNextIsRed)
        
        guard let targetFen = getFenForId(targetFenId) else {
            return ""
        }
        let targetNextIsRed = targetFen.split(separator: " ")[1] == "r"
        let adjustedTargetScore = adjustScore(targetFenScore, nextIsRed: targetNextIsRed)
        
        return String(adjustedTargetScore - adjustedSourceScore)
    }


    func isMoveLocked(_ stepIndex: Int) -> Bool {
        guard let lockedStep = sessionData.lockedStep else {
            return false
        }
        return stepIndex <= lockedStep
    }
    
    func isBadMove(_ move: Move) -> Bool {
        move.isBad({ fenId in
            self.getScoreByFenId(fenId)
        }, engineScore: { fenId in
            self.getEngineScoreByFenId(fenId)
        })
    }
    
    // MARK: - Auto Add to Opening
    func autoAddMovesToOpening() -> (redAdded: Int, blackAdded: Int) {
        var redAdded = 0
        var blackAdded = 0
        
        // 统计各种情况的数量
        var singleGoodMoveCount = 0      // 只有一个好招法的局面
        var multipleGoodMovesCount = 0   // 有多个好招法的局面
        var allBadMovesCount = 0         // 全是坏招法的局面
        var noMovesCount = 0             // 无招法的局面
        var alreadyInRedOpening = 0
        var alreadyInBlackOpening = 0
        
        // Get all fenIds first to avoid issues with dictionary iteration
        // TODO: avoid this allFenIds?
        let allFenIds = databaseView.getAllFenIds()

        for fenId in allFenIds {
            guard let fenObject = databaseView.getFenObject(fenId) else { continue }
            let moves = fenObject.getMoves(fenIdFilter: { _ in true })

            // 过滤出所有好招法（非bad）
            let goodMoves = moves.filter { !isBadMove($0) }

            if goodMoves.count == 1, let goodMove = goodMoves.first {
                // 只有一个好招法的局面（可能总共有多个招法）
                singleGoodMoveCount += 1
                guard let targetFenId = goodMove.targetFenId,
                      let targetFenObject = databaseView.getFenObject(targetFenId) else { return (redAdded, blackAdded) }
                
                // 红方走棋的局面（黑方刚走完）
                if fenObject.blackJustPlayed && !targetFenObject.isInRedOpening {
                    targetFenObject.setInRedOpening(true)
                    redAdded += 1
                } else if fenObject.blackJustPlayed && targetFenObject.isInRedOpening {
                    alreadyInRedOpening += 1
                }
                // 黑方走棋的局面（红方刚走完）
                else if fenObject.redJustPlayed && !targetFenObject.isInBlackOpening {
                    targetFenObject.setInBlackOpening(true)
                    blackAdded += 1
                } else if fenObject.redJustPlayed && targetFenObject.isInBlackOpening {
                    alreadyInBlackOpening += 1
                }
            } else if goodMoves.count > 1 {
                // 有多个好招法
                multipleGoodMovesCount += 1
            } else if moves.count > 0 {
                // 有招法但全是坏招法
                allBadMovesCount += 1
            } else {
                // 无招法
                noMovesCount += 1
            }
        }
        
        // 输出统计信息
        print("Auto Add to Opening Statistics:")
        print("  总局面数: \(allFenIds.count)")
        print("  唯一好招法: \(singleGoodMoveCount)")
        print("  多个好招法: \(multipleGoodMovesCount)")
        print("  全是坏招法: \(allBadMovesCount)")
        print("  无招法: \(noMovesCount)")
        print("  已在红方开局: \(alreadyInRedOpening)")
        print("  已在黑方开局: \(alreadyInBlackOpening)")
        print("  新增红方开局: \(redAdded)")
        print("  新增黑方开局: \(blackAdded)")
        
        if redAdded > 0 || blackAdded > 0 {
            notifyDataChanged(markDatabaseDirty: true)
        }
        
        return (redAdded, blackAdded)
    }
    
    func findNextOpeningGap() -> Int? {
        let currentStep = sessionData.currentGameStep
        let totalSteps = sessionData.currentGame2.count
        
        // 从当前步数+1开始搜索，如果到末尾没找到则从开头继续搜索
        for offset in 1..<totalSteps {
            let stepIndex = (currentStep + offset) % totalSteps
            let fenId = sessionData.currentGame2[stepIndex]

            guard let fenObject = databaseView.getFenObject(fenId) else { continue }

            let moves = fenObject.getMoves(fenIdFilter: { _ in true })

            // 过滤出所有好招法（非bad）
            let goodMoves = moves.filter { !isBadMove($0) }

            // 只有当有多个好招法时才考虑
            if goodMoves.count > 1 {
                var allTargetFensNotInOpening = true

                for goodMove in goodMoves {
                    guard let targetFenId = goodMove.targetFenId,
                          let targetFenObject = databaseView.getFenObject(targetFenId) else { 
                        allTargetFensNotInOpening = false
                        break
                    }
                    
                    // 检查目标局面是否已经在相应的开局库中
                    if fenObject.blackJustPlayed { // 红方走棋
                        if targetFenObject.isInRedOpening {
                            allTargetFensNotInOpening = false
                            break
                        }
                    } else if fenObject.redJustPlayed { // 黑方走棋
                        if targetFenObject.isInBlackOpening {
                            allTargetFensNotInOpening = false
                            break
                        }
                    }
                }
                
                // 如果所有好招法的目标局面都不在开局库中，这就是一个需要手工完善的缺口
                if allTargetFensNotInOpening {
                    return stepIndex
                }
            }
        }
        
        return nil
    }
  
    func getMoveString(move: Move) -> String {
      return databaseView.formatMove(move, isHorizontalFlipped: sessionData.isHorizontalFlipped)
    }

    func getCombinedComment(fenObject: FenObject?, move: Move?) -> String? {
        let fenObject = fenObject ?? (move?.targetFenId != nil ? databaseView.getFenObject(move!.targetFenId!) : nil)
        let moveObject = move

        var text = ""
        if let fenComment = fenObject?.comment, !fenComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "【局面评论】 \(fenComment)"
        }
        if let moveComment = moveObject?.comment, !moveComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !text.isEmpty {
                text += "\n"
            }
            text += "【着法评论】 \(moveComment)"
        }
        if let badReason = moveObject?.badReason, !badReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !text.isEmpty {
                text += "\n"
            }
            text += "【不好在】 \(badReason)"
        }

        if let fenId = fenObject?.fenId,
           let courseBook = databaseView.getAllBookObjectsUnfiltered().first(where: { $0.name == "课程" }) {
            let allGames = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: courseBook.id)
            let relatedCourses = allGames.filter { game in
                databaseView.gameContainsFenId(gameId: game.id, fenId: fenId)
            }

            if !relatedCourses.isEmpty {
                if !text.isEmpty {
                    text += "\n"
                }

                if relatedCourses.count > 5 {
                    text += "【相关课程】共\(relatedCourses.count)个"
                } else {
                    let courseNames = relatedCourses.map { $0.name ?? "未命名课程" }
                    text += "【相关课程】\(courseNames.joined(separator: " / "))"
                }
            }
        }

        return text.isEmpty ? nil : text
    }

    func isRecommendedMove(_ move: Move) -> Bool {
        move.isRecommended
    }

    func isBookmarkInCurrentGame(_ bookmarkGame: [Int]) -> Bool {
        guard let bookmarkFenId = bookmarkGame.last else {
            return false
        }
        return sessionData.currentGame2[0...sessionData.currentGameStep].contains(bookmarkFenId)
    }
    
    func getIdForFen(_ fen: String) -> Int? {
        return databaseView.getIdForFen(fen)
    }

    func getFenForId(_ id: Int?) -> String? {
        return databaseView.getFenForId(id)
    }

    var isCurrentHorizontalFlipped: Bool {
        sessionData.isHorizontalFlipped
    }

    var currentPathIndexDisplay: Int? {
        sessionData.currentPathIndex
    }
    
    var totalPathsCount: Int? {
        sessionData.allGamePaths?.count
    }

    var totalPathsCountFromCurrentFen: Int? {
        guard let fenId = databaseView.getIdForFen(currentFen) else { return nil }
        return sessionData.fenIdToGamePathCount?[fenId]
    }

    var allGameObjects: [GameObject] {
        return databaseView.allGameObjects
    }

    func getGameObjectUnfiltered(_ id: UUID) -> GameObject? {
        return databaseView.getGameObjectUnfiltered(id)
    }

    var allBookObjects: [BookObject] {
        return databaseView.allBookObjectsUnfiltered
    }

    var allTopLevelBookObjects: [BookObject] {
        return databaseView.allTopLevelBookObjectsUnfiltered
    }

    var allFenWithoutScore: [String] {
        return databaseView.allFenWithoutScore
    }

    func getGamesInBook(_ bookId: UUID) -> [GameObject] {
        return databaseView.getGamesInBookUnfiltered(bookId)
    }

    func checkBoardFenInNextMoveList(_ boardFen: String) -> Bool {
        guard databaseView.containsFenId(currentFenId) else { return false }
        let normalizedFen = normalizeFen(boardFen)
        return databaseView.moves(from: currentFenId).contains { move in
            move.targetFenId != nil && move.targetFenId == databaseView.getIdForFen(normalizedFen)
        }
    }

    var hasNextMove: Bool {
        guard databaseView.containsFenId(currentFenId) else { return false }
        return databaseView.moves(from: currentFenId).count > 0
    }

    func getRandomNextMove() -> Move? {
        guard databaseView.containsFenId(currentFenId) else { return nil }
        let moves = databaseView.moves(from: currentFenId)
        let movesWithWeight: [(Move, Int)] = moves.compactMap { move in
            guard let targetFenId = move.targetFenId else { return nil }
            let originalWeight = sessionData.fenIdToGamePathCount?[targetFenId] ?? 0
            let scaledWeight = max(1, Int(sqrt(Double(originalWeight))))
            return scaledWeight > 0 ? (move, scaledWeight) : nil
        }

        let totalWeight = movesWithWeight.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        let randomWeight = Int.random(in: 0..<totalWeight)

        var cumulativeSum = 0
        let selectedMove = movesWithWeight.first { move in
            cumulativeSum += move.1

            // 这里用 cumulativeSum > randomWeight 而不是 >=
            // 原因如下：
            // 假设权重为 [3, 5, 2]，它们在数轴上的区间分别是：
            // 第1个走法：[0,1,2]，第2个走法：[3,4,5,6,7]，第3个走法：[8,9]
            // 随机数 randomWeight 取值范围是 [0, totalWeight)，即 [0,9]
            // 用 > 可以保证每个走法的区间是 [start, end)，严格对应随机数的取值。
            // 如果用 >=，第一个走法的区间会多一个，最后一个走法可能永远选不到。
            // 所以这里必须用 >，这样每个走法被选中的概率才是正确的。
            return cumulativeSum > randomWeight
        }?.0

        return selectedMove
    }
}

// MARK: - Database Operations (数据库相关操作)
extension Session {
    func updateCurrentFenComment(_ comment: String?) {
        let fenObject = currentFenObject
        guard fenObject.comment != comment else { return }

        fenObject.comment = comment

        notifyDataChanged(markDatabaseDirty: true)
    }

    func updateFenScore(_ fenId: Int, score: Int?) {
        guard let fenObject = databaseView.getFenObject(fenId) else { return }
        guard fenObject.score != score else { return }

        fenObject.score = score

        notifyDataChanged(markDatabaseDirty: true)
    }

    func updateEngineScore(_ fenId: Int, score: Int?, engineKey: String) {
        guard databaseView.containsFenId(fenId) else { return }
        let existingScore = databaseView.getEngineScore(fenId: fenId, engineKey: engineKey)
        guard existingScore != score else { return }

        if let score = score {
            Database.shared.setEngineScore(fenId: fenId, engineKey: engineKey, score: score)
        }

        notifyDataChanged(markDatabaseDirty: false, markEngineScoreDirty: true)
    }

    func updateCurrentMoveComment(_ comment: String?) {
        guard let currentMove = currentMove else { return }
        guard currentMove.comment != comment else { return }

        currentMove.comment = comment

        notifyDataChanged(markDatabaseDirty: true)
    }

    func updateCurrentMoveBadReason(_ badReason: String?) {
        guard let currentMove = currentMove else { return }
        guard currentMove.badReason != badReason else { return }

        currentMove.badReason = badReason

        notifyDataChanged(markDatabaseDirty: true)
    }
    
    func setDataClean() {
        databaseView.markClean()
        databaseView.markEngineScoreClean()
        sessionDataDirty = false
        engineScoreDirty = false
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: false)
    }
}

// MARK: - Session Operations (会话相关操作) 
extension Session {
    func flipOrientation() {
        sessionData.isBlackOrientation.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func flipHorizontal() {
        sessionData.isHorizontalFlipped.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func toggleAutoExtendGameWhenPlayingBoardFen() {
        sessionData.autoExtendGameWhenPlayingBoardFen.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func toggleAllowAddingNewMoves() {
        guard canToggleAllowAddingNewMoves else { return }
        sessionData.allowAddingNewMoves.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func setMode(_ mode: AppMode) {
        let oldMode = sessionData.currentMode
        guard oldMode != mode else { return }

        sessionData.currentMode = mode

        // 根据模式设置默认配置
        switch mode {
        case .practice:
            // 练习模式下，不自动拓展
            sessionData.autoExtendGameWhenPlayingBoardFen = false
            // 练习模式下，不显示路径
            sessionData.showPath = false
            // 练习模式下，不显示所有下一步
            sessionData.showAllNextMoves = false
            // 切断当前游戏到锁定步骤（如果有锁定），否则到当前步骤
            cutGameUntilStep(sessionData.lockedStep ?? sessionData.currentGameStep)

        case .normal:
            // 非练习模式下，自动拓展
            sessionData.autoExtendGameWhenPlayingBoardFen = true
            // 非练习模式下，显示路径和所有下一步
            sessionData.showPath = true
            sessionData.showAllNextMoves = true
            // 清除锁定并恢复完整视图
            sessionData.lockedStep = nil
            rebuildDatabaseView()
            // 自动扩展游戏
            autoExtendCurrentGame()

        case .review:
            // 复习模式下，保持用户当前的路径显示设置不变
            sessionData.autoExtendGameWhenPlayingBoardFen = true
            // 清除锁定并恢复完整视图
            sessionData.lockedStep = nil
            rebuildDatabaseView()
            autoExtendCurrentGame()
        }

        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func togglePracticeMode() {
        // 保持向后兼容：在练习模式和常规模式之间切换
        let newMode: AppMode = sessionData.currentMode == .practice ? .normal : .practice
        setMode(newMode)
    }

    func toggleShowPath() {
        sessionData.showPath.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func toggleShowAllNextMoves() {
        sessionData.showAllNextMoves.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func toggleIsCommentEditing() {
        sessionData.isCommentEditing.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }
}

// MARK: - Game Navigation Operations (游戏导航操作)
extension Session {
    func stepBackward() {
        if sessionData.currentGameStep > 0 {
            toStepIndex(sessionData.currentGameStep - 1)
        }
    }
    
    func stepForward() {
        if sessionData.currentGameStep < sessionData.currentGame2.count - 1 {
            toStepIndex(sessionData.currentGameStep + 1)
        }
    }
    
    func toStart() {
        toStepIndex(sessionData.lockedStep ?? 0)
    }
    
    func toEnd() {
        toStepIndex(sessionData.currentGame2.count - 1)
    }
    
    func toStepIndex(_ stepIndex: Int) {
        guard stepIndex != sessionData.currentGameStep else { return }
        guard (0...sessionData.currentGame2.count - 1).contains(stepIndex) else { return }
        
        // 检查是否可以导航到锁定步骤之前
        if let lockedStep = sessionData.lockedStep, !sessionData.canNavigateBeforeLockedStep {
            guard stepIndex >= lockedStep else { return }
        }
        
        sessionData.currentGameStep = stepIndex
        assert(sessionData.currentGameStep < sessionData.currentGame2.count)

        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func toggleLock() {
        if sessionData.lockedStep == nil {
            sessionData.lockedStep = sessionData.currentGameStep
        } else {
            sessionData.lockedStep = nil
        }

        rebuildDatabaseView()
        clearAllGamePaths()

        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func toggleCanNavigateBeforeLockedStep() {
        sessionData.canNavigateBeforeLockedStep.toggle()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }
}

// MARK: - Game Logic Operations (游戏逻辑操作)
extension Session {
  /// 播放新的棋盘局面
  /// - Parameter nextFen: 下一步的 FEN 字符串
  /// - Returns: 是否成功播放（如果目标局面不在当前视图范围内则返回 false）
  @discardableResult
  func playNewBoardFen(_ nextFen: String) -> Bool {
    guard sessionData.currentGameStep >= (sessionData.lockedStep ?? 0) else { return false }

    let normalizedFen = normalizeFen(nextFen)

    // 检查是否允许走这一步
    let fenId = databaseView.getIdForFen(normalizedFen)
    let fenInScope = fenId != nil && databaseView.containsFenId(fenId!)

    // 局面不存在，需要创建 -> 检查创建权限
    if !fenInScope && !sessionData.allowAddingNewMoves {
        return false  // 不允许创建新走法
    }

    if !fenInScope && !sessionData.filters.contains(Session.filterSpecificGame) && !sessionData.filters.isEmpty {
        return false  // 在过滤视图中（但不是特定棋局模式）不允许创建新局面 -- 否则添加到到哪里呢？
    }

    var practiceCountIncremented = false
    if sessionData.currentMode == .practice {
        // 注意统计的是走子之前局面的练习次数（这个局面下怎么应对）
        currentFenObject.incrementPracticeCount()
        practiceCountIncremented = true
    }

    // 清除游戏路径缓存（因为可能需要重新计算）
    var shouldClearAllGamePaths = false
    if databaseView.getIdForFen(normalizedFen) == nil {
        shouldClearAllGamePaths = true
    } else if let fenId = databaseView.getIdForFen(normalizedFen),
              let pathCount = sessionData.fenIdToGamePathCount?[fenId],
              pathCount == 0 {
        shouldClearAllGamePaths = true
    }

    if shouldClearAllGamePaths {
        clearAllGamePaths()
    }

    let oldStep = sessionData.currentGameStep
    cutGameUntilStep(sessionData.currentGameStep)
    var databaseModified = playFensAndAutoExtend([normalizedFen], allowExtend: sessionData.autoExtendGameWhenPlayingBoardFen)
    databaseModified = databaseModified || practiceCountIncremented // 如果增加了练习次数，也需要标记数据库已修改

    if oldStep + 1 < sessionData.currentGame2.count {
        sessionData.currentGameStep = oldStep + 1 // 自动拓展了多步，但我们的游标只移动了一步
    }
    assert(sessionData.currentGameStep < sessionData.currentGame2.count)

    notifyDataChanged(markDatabaseDirty: databaseModified, markSessionDirty: true)
    return true
  }

  /// 播放新的棋局（路径）
  /// - Parameter game: 棋局路径（fenId 数组）
  /// - Returns: 是否成功播放（如果任何 fenId 不在当前视图范围内则返回 false）
  @discardableResult
  func playNewGame(_ game: [Int]) -> Bool {
    guard game.count >= 1 else { return false }

    // we don't support playing a new game with a different starting position
    guard game[0] == sessionData.currentGame2[0] else { return false }

    // 检查所有 fenId 是否都在当前视图范围内
    for fenId in game {
        guard databaseView.containsFenId(fenId) else {
            return false // 有 fenId 不在当前视图范围内，拒绝操作
        }
    }

    let gameDropFirst = Array(game.dropFirst())

    // unlock the game if it's locked
    sessionData.lockedStep = nil
    rebuildDatabaseView()

    clearAllGamePaths()

    cutGameUntilStep(0)
    let databaseModified = playFenIdsAndAutoExtend(gameDropFirst)
    sessionData.currentGameStep = game.count - 1

    notifyDataChanged(markDatabaseDirty: databaseModified, markSessionDirty: true)
    return true
  }


  func playRandomGame() -> Int? {
    updateAllGamePaths()

    let totalPathsCount = sessionData.allGamePaths!.count
    let randomIndex = Int.random(in: 0..<totalPathsCount)
    let selectedPath = sessionData.allGamePaths![randomIndex]

    self.sessionData.currentPathIndex = randomIndex
    self.sessionData.currentGame2 = selectedPath
    self.sessionData.currentGameStep = self.sessionData.lockedStep ?? 0
    notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)

    return totalPathsCount
  }

  func playRandomNextMove(delay: Double = 0) {
    updateAllGamePaths()

    guard let move = getRandomNextMove() else { return }
    
    let targetFenId = move.targetFenId
    guard let targetFen = getFenForId(targetFenId) else { return }

    if delay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        self.playNewBoardFen(targetFen)
      }
    } else {
      playNewBoardFen(targetFen)
    }
  }
  
  func playNextVariant() {
    let sortedVariants = currentGameVariantList.sorted { $0.moveString < $1.moveString }
    guard sortedVariants.count >= 2 else { return }

    let currentIndex = sortedVariants.firstIndex(where: { $0.move.targetFenId == currentFenId })
    let nextIndex = (currentIndex.map { ($0 + 1) % sortedVariants.count }) ?? 0

    playVariantMove(sortedVariants[nextIndex].move)
  }
  
  func playVariantIndex(_ index: Int) {
    // 禁止在锁定步骤时切换变着
    if isMoveLocked(sessionData.currentGameStep) {
      return
    }
    let moves = currentGameVariantMoves
    guard index >= 0, index < moves.count else { return }

    let move = moves[index]
    playVariantMove(move)
  }

  func playVariantMove(_ move: Move) {
    // 禁止在锁定步骤时切换变着
    if isMoveLocked(sessionData.currentGameStep) {
      return
    }
    let targetFenId = move.targetFenId
    guard targetFenId != nil else {return}
    
    let oldStep = sessionData.currentGameStep
    cutGameUntilStep(sessionData.currentGameStep - 1)
    let databaseModified = playFenIdsAndAutoExtend([targetFenId!], allowExtend: sessionData.autoExtendGameWhenPlayingBoardFen)

    sessionData.currentGameStep = oldStep // Invariant: we always at the same step when playing variants
    assert(sessionData.currentGameStep < sessionData.currentGame2.count)

    notifyDataChanged(markDatabaseDirty: databaseModified, markSessionDirty: true)
  }

  func playNextMove(_ move: Move) {
    guard sessionData.autoExtendGameWhenPlayingBoardFen else { return }
    guard let targetFenId = move.targetFenId else { return }
    guard databaseView.containsFenId(targetFenId) else { return }
    guard sessionData.currentGameStep >= (sessionData.lockedStep ?? 0) else { return }

    let oldStep = sessionData.currentGameStep
    cutGameUntilStep(oldStep)
    let databaseModified = playFenIdsAndAutoExtend([targetFenId], allowExtend: true)

    // 不前进 currentGameStep — 仅替换下一步分支
    assert(sessionData.currentGameStep < sessionData.currentGame2.count)

    notifyDataChanged(markDatabaseDirty: databaseModified, markSessionDirty: true)
  }

  func removeCurrentStep() {
    guard sessionData.currentGameStep > (sessionData.lockedStep ?? 0) else { return }

    guard let currentMove = currentMove else { return }
    guard let targetFenId = currentMove.targetFenId else { return }
    previousFenObject?.removeMove(targetFenId: targetFenId)
    currentMove.markAsRemoved()

    cutGameUntilStep(sessionData.currentGameStep - 1)
    autoExtendCurrentGame()

    notifyDataChanged(markDatabaseDirty: true, markSessionDirty: true)
  }

  /// 从特定棋局中删除当前招法的 moveId
  func removeMoveFromGame() {
    // 只在特定棋局模式下生效
    guard sessionData.filters.contains(Session.filterSpecificGame) else { return }

    // 获取当前走法
    guard let currentMove = currentMove else { return }
    let sourceFenId = currentMove.sourceFenId
    guard let targetFenId = currentMove.targetFenId else { return }

    // 获取当前棋局ID
    guard let specificGameId = sessionData.specificGameId else { return }

    // 从 GameObject 中移除当前着法
    let success = databaseView.removeMoveFromGame(
      gameId: specificGameId,
      sourceFenId: sourceFenId,
      targetFenId: targetFenId
    )

    // 触发数据变更通知
    if success {
      // 截断并重建 currentGame2：删除被删除着法之后的所有内容，然后重新扩展
      // cutGameUntilStep 会截断到源局面，移除所有包含已删除着法的 fenId
      // autoExtendCurrentGame 会从源局面重新扩展，只使用棋局中剩余的有效着法
      if sessionData.currentGameStep > 0 {
        cutGameUntilStep(sessionData.currentGameStep - 1)
        autoExtendCurrentGame()
      }

      notifyDataChanged(markDatabaseDirty: true, markSessionDirty: true)
    }
  }
  
  private func playFensAndAutoExtend(_ fens: [String], allowExtend: Bool = true) -> Bool {
    // 确保所有局面对象都存在
    var databaseModified = false
    for fen in fens {
      if databaseView.getIdForFen(fen) == nil {
        _ = databaseView.ensureFenId(for: fen)
        databaseModified = true
      }
    }

    let fenIds = fens.compactMap { databaseView.getIdForFen($0) }
    let moveModified = playFenIdsAndAutoExtend(fenIds, allowExtend: allowExtend)
    return databaseModified || moveModified
  }
  
  private func playFenIdsAndAutoExtend(_ fenIds: [Int], allowExtend: Bool = true) -> Bool {
    // 确保所有移动都存在
    var databaseModified = false
    var currentFenId = sessionData.currentGame2[sessionData.currentGameStep]
    for nextFenId in fenIds {
      // 使用新的 ensureMove API
      let (move, moveId, isNew) = databaseView.ensureMove(from: currentFenId, to: nextFenId)
      if isNew {
        databaseModified = true
      }

    // 如果在特定棋局模式且允许增加新走法，将新创建的 moveId 加入 GameObject
    if sessionData.filters.contains(Session.filterSpecificGame),
        let specificGameId = sessionData.specificGameId,
        let gameObject = databaseView.getGameObject(specificGameId),
        !gameObject.containsMoveId(moveId) {
        gameObject.appendMoveId(moveId, move: move)
        databaseView.updateGameObject(specificGameId, gameObject: gameObject)
        databaseModified = true
    }

      if let currentFenObj = databaseView.getFenObject(currentFenId) {
          let moveAdded = currentFenObj.addMoveIfNeeded(move: move)
          if moveAdded {
              databaseModified = true
          }
      }
      currentFenId = nextFenId
    }

    autoExtendCurrentGame(fenIds, allowExtend: allowExtend)
    return databaseModified
  }
  
  private func autoExtendCurrentGame(_ nextFenIds: [Int]? = nil, allowExtend: Bool = true) {
    let extendedGame = GameOperations.autoExtendGame(
      game: sessionData.currentGame2,
      nextFenIds: nextFenIds,
      databaseView: databaseView,
      allowExtend: allowExtend
    )
    
    if extendedGame != sessionData.currentGame2 {
      updateGameHistory()
      sessionData.currentGame2 = extendedGame

      for i in 0..<sessionData.currentGame2.count {
        let fenId = sessionData.currentGame2[i]
        let nextFenId = i + 1 < sessionData.currentGame2.count ? sessionData.currentGame2[i + 1] : nil
        databaseView.getFenObject(fenId)?.markLastMove(fenId: nextFenId)
      }
    }
  }
  
  private func cutGameUntilStep(_ stepIndex: Int) {
    let (newGame, newStep) = GameOperations.cutGameUntilStep(stepIndex, currentGame: sessionData.currentGame2)
    updateGameHistory()
    sessionData.currentGame2 = newGame
    sessionData.currentGameStep = newStep
  }
  
  private func updateGameHistory() {
    if sessionData.gameHistory == nil {
        sessionData.gameHistory = []
    }

    let currentGame2 = sessionData.currentGame2
    
    // 检查最后一个历史记录是否是当前游戏的前缀
    if let lastHistory = sessionData.gameHistory?.last,
       currentGame2.count >= lastHistory.count,
       Array(currentGame2.prefix(lastHistory.count)) == lastHistory {
        // 如果是前缀，更新最后一个历史记录
        sessionData.gameHistory = sessionData.gameHistory!.dropLast()
        sessionData.gameHistory?.append(currentGame2)
    } else {
        // 如果不是前缀，添加新的历史记录
        sessionData.gameHistory?.append(currentGame2)
    }
    
    // 保持历史记录最多1000个
    if let history = sessionData.gameHistory, history.count > 1000 {
        sessionData.gameHistory = Array(history.suffix(1000))
    }
  }
}

// MARK: - Opening Mark Operations (开局标记操作)
extension Session {
    func setCurrentFenInRedOpening(_ value: Bool) {
        guard let id = databaseView.getIdForFen(currentFen) else { return }
        databaseView.getFenObject(id)?.setInRedOpening(value)
        notifyDataChanged(markDatabaseDirty: true)
    }

    func setCurrentFenInBlackOpening(_ value: Bool) {
        guard let id = databaseView.getIdForFen(currentFen) else { return }
        databaseView.getFenObject(id)?.setInBlackOpening(value)
        notifyDataChanged(markDatabaseDirty: true)
    }
    
    func toggleCurrentFenInRedOpening() {
        guard currentFenCanChangeInRedOpening else {
            return
        }
        
        setCurrentFenInRedOpening(!currentFenIsInRedOpening)
    }
    
    func toggleCurrentFenInBlackOpening() {
        guard currentFenCanChangeInBlackOpening else {
            return
        }

        setCurrentFenInBlackOpening(!currentFenIsInBlackOpening)
    }
}

// MARK: - Step-Limited DatabaseView

extension Session {
    /// 根据 gameStepLimitation 重建 databaseView
    /// 当 gameStepLimitation 生效时，叠加 BFS 计算的可达 fenId 过滤
    private func rebuildDatabaseView() {
        if let limit = sessionData.gameStepLimitation {
            // Step limit active (BFS already starts from lockedStep ?? 0)
            let reachable = computeReachableFenIds(limit: limit)
            databaseView = DatabaseView.withStepLimit(baseDatabaseView, reachableFenIds: reachable)
        } else if sessionData.lockedStep != nil {
            // Lock active, no step limit — filter to reachable positions
            let reachable = computeReachableFenIds(from: baseDatabaseView)
            databaseView = DatabaseView.withLock(baseDatabaseView, reachableFenIds: reachable)
        } else {
            databaseView = baseDatabaseView
        }
    }

    /// BFS 计算从锁定位置出发，通过给定 DatabaseView 可达的所有 fenId（无深度限制）
    /// - Parameter view: 用于探索的 DatabaseView
    /// - Returns: 可达 fenId 集合
    func computeReachableFenIds(from view: DatabaseView) -> Set<Int> {
        let initialPath = Array(sessionData.currentGame2[0...(sessionData.lockedStep ?? 0)])
        var reachable = Set(initialPath)

        var queue: [Int] = []
        if let lastFenId = initialPath.last {
            queue.append(lastFenId)
        }

        var head = 0
        while head < queue.count {
            let fenId = queue[head]
            head += 1

            for move in view.moves(from: fenId) {
                guard let targetFenId = move.targetFenId else { continue }
                guard !reachable.contains(targetFenId) else { continue }
                reachable.insert(targetFenId)
                queue.append(targetFenId)
            }
        }

        return reachable
    }

    /// BFS 计算从锁定位置出发，步数限制内可达的所有 fenId
    /// - Parameter limit: 最大步骤索引（0-based），即 gameStepLimitation
    /// - Returns: 可达 fenId 集合
    func computeReachableFenIds(limit: Int) -> Set<Int> {
        let initialPath = Array(sessionData.currentGame2[0...(sessionData.lockedStep ?? 0)])
        var reachable = Set(initialPath)

        // BFS from the last position in the locked path
        var queue: [(fenId: Int, depth: Int)] = []
        if let lastFenId = initialPath.last {
            queue.append((lastFenId, initialPath.count - 1))
        }

        var head = 0
        while head < queue.count {
            let (fenId, depth) = queue[head]
            head += 1

            // 只在 depth < limit 时探索子节点（子节点深度为 depth+1 <= limit）
            guard depth < limit else { continue }

            for move in baseDatabaseView.moves(from: fenId) {
                guard let targetFenId = move.targetFenId else { continue }
                guard !reachable.contains(targetFenId) else { continue }
                reachable.insert(targetFenId)
                queue.append((targetFenId, depth + 1))
            }
        }

        return reachable
    }
}

// MARK: - Game Step Limitation
extension Session {

    func setGameStepLimitation(_ limit: Int?) {
        if (limit != sessionData.gameStepLimitation) {
            sessionData.gameStepLimitation = limit

            rebuildDatabaseView()
            cutGameUntilStep(sessionData.gameStepLimitation ?? 0)
            autoExtendCurrentGame()
            clearAllGamePaths()

            notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
        }
    }
  
    func toggleBookmark(_ getBookmarkName: () -> String?) -> Bool {
        let game = Array(sessionData.currentGame2[0...sessionData.currentGameStep])

        if databaseView.bookmarks[game] == nil {
            guard let name = getBookmarkName(),
                  !name.isEmpty else {
                return false
            }

            databaseView.updateBookmark(for: game, name: name)
        } else {
            databaseView.updateBookmark(for: game, name: nil)
        }

        notifyDataChanged(markDatabaseDirty: true)
        return true
    }
    
    func loadBookmark(_ game: [Int]) {
        playNewGame(game)
    }
}

// MARK: - Path Operations (路径相关操作)
extension Session {
    func getCurrentFenPathGroups() -> [PathGroup] {
        return currentFenObject.getPathGroups()
    }

    func getPathGroups(fenId: Int) -> [PathGroup] {
        return databaseView.getFenObject(fenId)?.getPathGroups() ?? []
    }

    /// 获取当前局面所有可能走法的路径组
    /// 显示轮到走棋方的所有可能走法，每个走法使用不同的颜色
    func getNextMovesPathGroups() -> [PathGroup] {
        let moves = currentFenObject.getMoves(fenIdFilter: databaseView.containsFenId)
        guard moves.count > 1 else { return [] }

        var pathGroups: [PathGroup] = []

        for (index, move) in moves.enumerated() {
            guard let pieceMove = databaseView.parsePieceMove(move, isHorizontalFlipped: false) else {
                continue
            }

            let fromSquare = MoveRules.coordinateToSquare(
                col: pieceMove.fromColumn,
                row: 9 - pieceMove.fromRow
            )
            let toSquare = MoveRules.coordinateToSquare(
                col: pieceMove.toColumn,
                row: 9 - pieceMove.toRow
            )

            let path = PathConfig(points: [fromSquare, toSquare], showArrow: true, isDashed: false)
            // 每个 move 使用独立的 PathGroup，名称格式为 "NextMoves_N"
            pathGroups.append(PathGroup(paths: [path], name: "NextMoves_\(index)"))
        }

        return pathGroups
    }

    func updateCurrentFenPathGroups(_ pathGroups: [PathGroup]) {
        currentFenObject.setPathGroups(pathGroups)
        notifyDataChanged(markDatabaseDirty: true)
    }
    
    func generateAllGamePaths() -> ([[Int]], [Int: Int]) {
        var allDFSPaths: [[Int]] = []
        var fenIdToGamePathCount: [Int: Int] = [:]

        func dfs(_ dfsPath: [Int]) {
            var isLeaf = true
            let fensInGame = Set(dfsPath)

            guard let lastFenId = dfsPath.last else { return }
            guard databaseView.containsFenId(lastFenId) else { return }
            let moves = databaseView.moves(from: lastFenId)

            var pathCount = 0
            for move in moves {
                if move.targetFenId == nil { continue }
                if fensInGame.contains(move.targetFenId!) { continue }
                if sessionData.gameStepLimitation != nil && dfsPath.count > sessionData.gameStepLimitation! { continue }

                isLeaf = false
                dfs(dfsPath + [move.targetFenId!])

                pathCount += fenIdToGamePathCount[move.targetFenId!]!
            }

            if isLeaf {
                allDFSPaths.append(dfsPath)
            }

            if isLeaf {
                fenIdToGamePathCount[lastFenId] = 1
            } else {
                fenIdToGamePathCount[lastFenId] = pathCount
            }
        }

        let initialPath = Array(sessionData.currentGame2[0...(sessionData.lockedStep ?? 0)])
        for fenId in initialPath {
            fenIdToGamePathCount[fenId] = 1
        }

        dfs(initialPath)

        return (allDFSPaths, fenIdToGamePathCount)
    }

    func searchCurrentMove() -> [Move] {
        guard let currentMove = currentMove else { return [] }
        guard let currentPieceMove = databaseView.parsePieceMove(currentMove, isHorizontalFlipped: sessionData.isHorizontalFlipped) else { return [] }

        // BFS 计算从锁定位置出发的所有可达 fenId
        // databaseView 已经包含 scope 过滤和步数限制过滤
        let reachableFenIds = computeReachableFenIds(from: databaseView)

        var searchResults = Set<Move>()

        for fenId in reachableFenIds {
            guard let fenObject = databaseView.getFenObject(fenId),
                  fenObject.fen.contains(currentPieceMove.piece) else { continue }

            for move in databaseView.moves(from: fenId) {
                if let pieceMove = databaseView.parsePieceMove(move, isHorizontalFlipped: sessionData.isHorizontalFlipped),
                   pieceMove == currentPieceMove {
                    searchResults.insert(move)
                }
            }
        }

        return Array(searchResults)
    }
}

// MARK: - Path Navigation Operations (路径导航操作)
extension Session {
    func goToPreviousPath() {
        updateAllGamePaths()

        guard let allGamePaths = sessionData.allGamePaths, !allGamePaths.isEmpty, let currentPathIndex = sessionData.currentPathIndex else { return }
        
        // 计算前一个路径的索引
        let previousIndex = (currentPathIndex - 1 + allGamePaths.count) % allGamePaths.count
        
        // 如果当前路径不是第一个，则跳转到前一个路径
        if previousIndex != currentPathIndex {
            self.sessionData.currentPathIndex = previousIndex
            sessionData.currentGame2 = allGamePaths[previousIndex]
            sessionData.currentGameStep = sessionData.lockedStep ?? 0
            notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
        }
    }
    
    func goToNextPath() {
        updateAllGamePaths()

        guard let allGamePaths = sessionData.allGamePaths, !allGamePaths.isEmpty, let currentPathIndex = sessionData.currentPathIndex else { return }
        
        // 计算下一个路径的索引
        let nextIndex = (currentPathIndex + 1) % allGamePaths.count
        
        // 如果当前路径不是最后一个，则跳转到下一个路径
        if nextIndex != currentPathIndex {
            self.sessionData.currentPathIndex = nextIndex
            sessionData.currentGame2 = allGamePaths[nextIndex]
            sessionData.currentGameStep = sessionData.lockedStep ?? 0
            notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
        }
    }
}

// MARK: - Game and Book Operations (棋局和棋谱操作)
extension Session {
    func setupDefaultBooksIfNeeded() {
        if databaseView.getBookObjectUnfiltered(Session.myRealRedGameBookId) == nil {
            databaseView.updateBookObject(Session.myRealRedGameBookId, bookObject: BookObject(id: Session.myRealRedGameBookId, name: "我的执红实战"))
        }

        if databaseView.getBookObjectUnfiltered(Session.myRealBlackGameBookId) == nil {
            databaseView.updateBookObject(Session.myRealBlackGameBookId, bookObject: BookObject(id: Session.myRealBlackGameBookId, name: "我的执黑实战"))
        }

        if databaseView.getBookObjectUnfiltered(Session.myRealGameBookId) == nil {
            databaseView.updateBookObject(Session.myRealGameBookId, bookObject: BookObject(id: Session.myRealGameBookId, name: "我的实战"))
        }

        if let myRealGameBook = databaseView.getBookObjectUnfiltered(Session.myRealGameBookId),
           !myRealGameBook.subBookIds.contains(Session.myRealRedGameBookId) {
            myRealGameBook.subBookIds.append(Session.myRealRedGameBookId)
            databaseView.updateBookObject(Session.myRealGameBookId, bookObject: myRealGameBook)
        }

        if let myRealGameBook = databaseView.getBookObjectUnfiltered(Session.myRealGameBookId),
           !myRealGameBook.subBookIds.contains(Session.myRealBlackGameBookId) {
            myRealGameBook.subBookIds.append(Session.myRealBlackGameBookId)
            databaseView.updateBookObject(Session.myRealGameBookId, bookObject: myRealGameBook)
        }

        if databaseView.getBookObjectUnfiltered(Session.othersRealGameBookId) == nil {
            databaseView.updateBookObject(Session.othersRealGameBookId, bookObject: BookObject(id: Session.othersRealGameBookId, name: "他人实战"))
        }
    }

    /// 设置默认的 currentGame2（如果需要）
    /// 确保 currentGame2 从起始局面开始
    func setupDefaultCurrentGameIfNeeded() {
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"

        // 检查 currentGame2 是否需要重置
        var needsReset = false

        if sessionData.currentGame2.isEmpty {
            needsReset = true
        } else if let firstFenId = sessionData.currentGame2.first,
                  let firstFenObject = databaseView.getFenObject(firstFenId) {
            // 检查第一个局面是否是起始局面
            if firstFenObject.fen != startFen {
                needsReset = true
                print("currentGame2 不是从起始局面开始，将重置")
            }
        } else {
            // currentGame2[0] 指向的 fenId 不存在
            needsReset = true
            print("currentGame2[0] 指向无效的 fenId，将重置")
        }

        if needsReset {
            // 查找起始局面的 fenId - use getIdForFen since we're searching by fen
            if let startFenId = databaseView.getIdForFen(startFen) {
                sessionData.currentGame2 = [startFenId]
                sessionData.currentGameStep = 0
                print("已设置默认 currentGame2 为起始局面 fenId=\(startFenId)")
            } else if let firstFenId = databaseView.getAllFenIds().min() {
                // 后备方案：使用最小的 fenId
                sessionData.currentGame2 = [firstFenId]
                sessionData.currentGameStep = 0
                print("已设置默认 currentGame2 为 fenId=\(firstFenId)（起始局面不存在）")
            }
        }
    }

    /// 数据库恢复后重置游戏状态
    /// 清空 currentGame2 并重新设置到起始局面，然后自动扩展
    func resetGameStateForDatabaseRestore() {
        sessionData.currentGame2 = []
        sessionData.currentGameStep = 0
        sessionData.lockedStep = nil
        sessionData.gameHistory = nil
        rebuildDatabaseView()
        clearAllGamePaths()
        setupDefaultCurrentGameIfNeeded()
        autoExtendCurrentGame()
    }

    func addBook(name: String, parentBookId: UUID? = nil) -> UUID {
        let bookId = databaseView.addBook(name: name, parentBookId: parentBookId)
        notifyDataChanged(markDatabaseDirty: false) // Database.addBook 已经调用了 markDirty
        return bookId
    }

    func deleteBook(_ bookId: UUID) {
        databaseView.deleteBook(bookId)
        notifyDataChanged(markDatabaseDirty: false) // Database.deleteBook 已经调用了 markDirty
    }

    func addCurrentGameToMyRealGame(gameInfo: GameObject) -> Bool {
        setupDefaultBooksIfNeeded()

        guard gameInfo.iAmRed || gameInfo.iAmBlack else { return false }
        let targetBookId = gameInfo.iAmRed ? Session.myRealRedGameBookId : Session.myRealBlackGameBookId
        guard let targetBook = databaseView.getBookObjectUnfiltered(targetBookId) else { return false }

        gameInfo.startingFenId = sessionData.currentGame2[0]
        for i in 1..<sessionData.currentGame2.count {
            let currentFenId = sessionData.currentGame2[i]
            let previousFenId = sessionData.currentGame2[i-1]
            let (move, moveId, _) = databaseView.ensureMove(from: previousFenId, to: currentFenId)
            gameInfo.appendMoveId(moveId, move: move)
        }

        databaseView.updateGameObject(gameInfo.id, gameObject: gameInfo)
        targetBook.gameIds.append(gameInfo.id)
        databaseView.updateBookObject(targetBookId, bookObject: targetBook)

        for fenId in sessionData.currentGame2 {
            updateMyRealGameStatistics(fenId: fenId, iAmRed: gameInfo.iAmRed, gameResult: gameInfo.gameResult)
        }

        notifyDataChanged(markDatabaseDirty: true)
        return true
    }

    func updateMyRealGameStatistics(fenId: Int, iAmRed: Bool, gameResult: GameResult) {
        let dictionary = iAmRed ? databaseView.myRealRedGameStatisticsByFenId : databaseView.myRealBlackGameStatisticsByFenId

        let gameStatistics: GameResultStatistics = dictionary[fenId] ?? GameResultStatistics()

        if gameResult == .redWin {
            gameStatistics.redWin += 1
        } else if gameResult == .blackWin {
            gameStatistics.blackWin += 1
        } else if gameResult == .draw {
            gameStatistics.draw += 1
        } else if gameResult == .notFinished {
            gameStatistics.notFinished += 1
        } else {
            gameStatistics.unknown += 1
        }

        if iAmRed {
            databaseView.updateRedGameStatistics(for: fenId, statistics: gameStatistics)
        } else {
            databaseView.updateBlackGameStatistics(for: fenId, statistics: gameStatistics)
        }
    }

    private func subtractGameStatistics(fenId: Int, iAmRed: Bool, gameResult: GameResult, databaseView: DatabaseView) {
        let dictionary = iAmRed ? databaseView.myRealRedGameStatisticsByFenId : databaseView.myRealBlackGameStatisticsByFenId
        guard let gameStatistics = dictionary[fenId] else { return }

        switch gameResult {
        case .redWin:    gameStatistics.redWin = max(0, gameStatistics.redWin - 1)
        case .blackWin:  gameStatistics.blackWin = max(0, gameStatistics.blackWin - 1)
        case .draw:      gameStatistics.draw = max(0, gameStatistics.draw - 1)
        case .notFinished: gameStatistics.notFinished = max(0, gameStatistics.notFinished - 1)
        case .unknown:   gameStatistics.unknown = max(0, gameStatistics.unknown - 1)
        }

        if iAmRed {
            databaseView.updateRedGameStatistics(for: fenId, statistics: gameStatistics)
        } else {
            databaseView.updateBlackGameStatistics(for: fenId, statistics: gameStatistics)
        }
    }

    func addGame(to bookId: UUID, name: String?, redPlayerName: String, blackPlayerName: String, gameDate: Date, gameResult: GameResult, iAmRed: Bool, iAmBlack: Bool, startingFenId: Int?, isFullyRecorded: Bool) -> UUID {
        let id = databaseView.addGame(to: bookId, name: name, redPlayerName: redPlayerName, blackPlayerName: blackPlayerName, gameDate: gameDate, gameResult: gameResult, iAmRed: iAmRed, iAmBlack: iAmBlack, startingFenId: startingFenId, isFullyRecorded: isFullyRecorded)
        notifyDataChanged(markDatabaseDirty: false) // Database.addGame 已经调用了 markDirty
        return id
    }

    func deleteGame(_ gameId: UUID) {
        // 删除前先扣减实战统计（使用未过滤的视图获取棋局信息）
        let fullView = DatabaseView.full(database: Database.shared)
        if let game = fullView.getGameObjectUnfiltered(gameId),
           (game.iAmRed || game.iAmBlack) {
            // 收集棋局涉及的所有 fenId
            var fenIds = Set<Int>()
            if let startFenId = game.startingFenId {
                fenIds.insert(startFenId)
            }
            for moveId in game.moveIds {
                if let move = fullView.move(id: moveId) {
                    fenIds.insert(move.sourceFenId)
                    if let targetFenId = move.targetFenId {
                        fenIds.insert(targetFenId)
                    }
                }
            }
            // 反向扣减统计
            for fenId in fenIds {
                subtractGameStatistics(fenId: fenId, iAmRed: game.iAmRed, gameResult: game.gameResult, databaseView: fullView)
            }
        }

        databaseView.deleteGame(gameId)
        notifyDataChanged(markDatabaseDirty: false) // Database.deleteGame 已经调用了 markDirty
    }

    func updateBook(_ bookId: UUID, name: String) {
        databaseView.updateBook(bookId, name: name)
        notifyDataChanged(markDatabaseDirty: false) // Database.updateBook 已经调用了 markDirty
    }

    func updateGame(_ gameId: UUID, name: String?, redPlayerName: String, blackPlayerName: String, gameDate: Date, gameResult: GameResult, iAmRed: Bool, iAmBlack: Bool, startingFenId: Int?, isFullyRecorded: Bool) {
        databaseView.updateGame(gameId, name: name, redPlayerName: redPlayerName, blackPlayerName: blackPlayerName, gameDate: gameDate, gameResult: gameResult, iAmRed: iAmRed, iAmBlack: iAmBlack, startingFenId: startingFenId, isFullyRecorded: isFullyRecorded)
        notifyDataChanged(markDatabaseDirty: false) // Database.updateGame 已经调用了 markDirty
    }

    func loadGame(_ gameId: UUID) {
        // loadGame() 应该只在 .specificGame() 过滤模式下调用
        // 因为它依赖 DatabaseView 的过滤来确保 auto-extension 沿唯一路径扩展
        assert(sessionData.filters.contains(Session.filterSpecificGame) && sessionData.specificGameId == gameId,
               "loadGame() should only be called in .specificGame() filter context")

        guard let game = databaseView.getGameObject(gameId) else { return }

        // 清除当前游戏状态
        sessionData.gameHistory = nil
        sessionData.lockedStep = nil
        rebuildDatabaseView()
        clearAllGamePaths()

        // 设置起始局面
        let startingFenId = game.startingFenId ?? 1
        sessionData.currentGame2 = [startingFenId]
        sessionData.currentGameStep = 0

        // 利用 DatabaseView 的 .specificGame() 过滤，auto-extension 会沿着唯一路径扩展
        autoExtendCurrentGame()

        // 移动到游戏末尾
        sessionData.currentGameStep = sessionData.currentGame2.count - 1

        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }

    func loadBook(_ bookId: UUID) {
        // loadBook() 应该只在 .specificBook() 过滤模式下调用
        // 因为它依赖 DatabaseView 的过滤来限定可探索的范围
        assert(sessionData.filters.contains(Session.filterSpecificBook) && sessionData.specificBookId == bookId,
               "loadBook() should only be called in .specificBook() filter context")

        // 获取棋谱中的所有棋局（递归包含子棋谱）
        let allGames = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: bookId)

        guard let firstGame = allGames.first else { return }

        // 清除当前游戏状态
        sessionData.gameHistory = nil
        sessionData.lockedStep = nil
        rebuildDatabaseView()
        clearAllGamePaths()

        // 设置起始局面（使用第一个棋局的起始位置）
        let startingFenId = firstGame.startingFenId ?? 1
        sessionData.currentGame2 = [startingFenId]
        sessionData.currentGameStep = 0

        // 利用 DatabaseView 的 .specificBook() 过滤，auto-extension 可以探索棋谱中所有棋局的分支
        autoExtendCurrentGame()

        // 移动到扩展路径的末尾
        sessionData.currentGameStep = sessionData.currentGame2.count - 1

        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }
}


// MARK: - Array Safe Access
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else {
            return nil
        }
        return self[index]
    }
}

// MARK: - 通知数据变更
extension Session {
    private func notifyDataChanged(markDatabaseDirty: Bool = true, markSessionDirty: Bool = false, markEngineScoreDirty: Bool = false) {
        DispatchQueue.main.async {
            if markDatabaseDirty {
                // 通过 DatabaseView 标记为脏，这会自动增加版本号
                self.databaseView.markDirty()
            }
            if markSessionDirty {
                self.sessionDataDirty = true
            }
            if markEngineScoreDirty {
                self.engineScoreDirty = true
            }
            // 不管哪个dirty，都要更新界面
            self.dataChanged.toggle()
        }
    }
}

// MARK: - 锁定与解锁
extension Session {
    /// 清除锁定状态并恢复完整视图
    func unlockIfNeeded() {
        guard sessionData.lockedStep != nil else { return }
        sessionData.lockedStep = nil
        rebuildDatabaseView()
    }

    func lockAndHideAfterCurrentStep() {
        sessionData.lockedStep = sessionData.currentGameStep
        sessionData.autoExtendGameWhenPlayingBoardFen = false
        cutGameUntilStep(sessionData.currentGameStep)
        rebuildDatabaseView()
        clearAllGamePaths()
        notifyDataChanged(markDatabaseDirty: false, markSessionDirty: true)
    }
}

// MARK: - 清除所有路径缓存
extension Session {
    private func clearAllGamePaths() {
        sessionData.allGamePaths = nil
        sessionData.fenIdToGamePathCount = nil
        sessionData.currentPathIndex = nil
    }
}

// MARK: - 更新所有路径缓存
extension Session {
    func updateAllGamePaths() {
        if sessionData.allGamePaths == nil {
            sessionData.currentPathIndex = nil
            (sessionData.allGamePaths, sessionData.fenIdToGamePathCount) = generateAllGamePaths()
        }
        if sessionData.currentPathIndex == nil {
            if let allPaths = sessionData.allGamePaths {
                let currentPath = sessionData.currentGame2
                for (index, path) in allPaths.enumerated() {
                    if path == currentPath {
                        sessionData.currentPathIndex = index
                        return
                    }
                }
            }
            sessionData.currentPathIndex = 0
        }
    }
} 
