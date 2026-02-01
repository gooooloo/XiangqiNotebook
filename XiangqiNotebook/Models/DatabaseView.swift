import Foundation

/// DatabaseView 提供对 Database 的过滤视图
/// 封装数据访问，内部处理 fenId 过滤逻辑
///
/// 严格语义说明：所有与着法相关的方法（如 `getMoves(...)`、`findMove(...)`）
/// 均要求"源 AND 目标"同时属于当前视图的 scope。
/// 调用方在进入某个 `fenId` 前，建议先使用 `contains(_:)` 进行入口校验。
final class DatabaseView {
    // MARK: - Properties

    private let database: Database
    private let fenIdFilter: (Int) -> Bool
    private let moveIdFilter: ((Int) -> Bool)?
    private let gameIdFilter: ((UUID) -> Bool)?

    // MARK: - Initialization

    /// 创建 DatabaseView 实例
    /// - Parameters:
    ///   - database: 底层数据库实例
    ///   - fenIdFilter: 过滤闭包，返回 true 表示 fenId 属于当前 scope
    ///   - moveIdFilter: 可选的 moveId 过滤闭包，返回 true 表示 moveId 属于当前 scope（用于特定棋局过滤）
    ///   - gameIdFilter: 可选的 gameId 过滤闭包，返回 true 表示 gameId 属于当前 scope（用于特定棋局过滤）
    /// - Note: 通常使用便利构造器（如 `.full()`, `.redOpening()` 等）而非直接调用此初始化方法
    init(database: Database, fenIdFilter: @escaping (Int) -> Bool, moveIdFilter: ((Int) -> Bool)? = nil, gameIdFilter: ((UUID) -> Bool)? = nil) {
        self.database = database
        self.fenIdFilter = fenIdFilter
        self.moveIdFilter = moveIdFilter
        self.gameIdFilter = gameIdFilter
    }

    // MARK: - Filtered Access Methods

    /// 获取 FenObject（如果在 scope 内）
    func getFenObject(_ fenId: Int) -> FenObject? {
        guard containsFenId(fenId) else { return nil }
        return database.databaseData.fenObjects2[fenId]
    }

    /// 检查 fenId 是否属于当前视图 scope
    func containsFenId(_ fenId: Int) -> Bool {
        return fenIdFilter(fenId)
    }

    /// 获取或创建 fenId（如果 fen 不存在则创建新的 FenObject）
    func ensureFenId(for fen: String) -> Int {
        if let fenId = getIdForFen(fen) {
            return fenId
        }
        let newId = database.databaseData.fenObjects2.count + 1
        let fenObject = FenObject(fen: fen, fenId: newId)
        database.databaseData.fenObjects2[newId] = fenObject
        database.databaseData.fenToId[fen] = newId
        markDirty()
        return newId
    }

    func getIdForFen(_ fen: String) -> Int? {
        return database.databaseData.fenToId[fen]
    }

    func getFenForId(_ id: Int?) -> String? {
        guard let id = id else { return nil }
        return getFenObject(id)?.fen
    }

    /// 获取所有 fenId（用于迭代）
    func getAllFenIds() -> [Int] {
        return Array(database.databaseData.fenToId.values)
    }

    // MARK: - New Move API (按提案重构)

    /// 获取从 source 出发的所有 moves（过滤版本 - 业务层）
    /// - 严格语义：源 AND 目标都需在 scope 内，且 moveId 需在 scope 内（如果有 moveIdFilter）
    func moves(from source: Int) -> [Move] {
        guard let fenObject = getFenObject(source) else { return [] }
        return fenObject.moves.filter { move in
            isMoveVisible(sourceFenId: source, targetFenId: move.targetFenId)
        }
    }

    /// 查找特定 move（过滤版本 - 业务层）
    /// - 严格语义：源 AND 目标都需在 scope 内，且 moveId 需在 scope 内（如果有 moveIdFilter）
    func move(from source: Int, to target: Int) -> Move? {
        return moves(from: source).first(where: { $0.targetFenId == target })
    }

    /// Get Move object by its ID (with filtering applied)
    func move(id moveId: Int) -> Move? {
        guard let move = database.databaseData.moveObjects[moveId] else {
            return nil
        }
        guard isMoveVisible(sourceFenId: move.sourceFenId, targetFenId: move.targetFenId) else {
            return nil
        }
        return move
    }

    /// 确保 move 存在（如果不存在则创建 - 持久化层）
    /// - 语义：持久化层直通（不受 scope 过滤影响），由调用方负责业务正确性
    /// - Returns: (move对象, id, 是否新创建)
    func ensureMove(from source: Int, to target: Int) -> (Move, id: Int, isNew: Bool) {
        // Check if move already exists
        if let existingMoveId = database.databaseData.moveToId[[source, target]],
           let existingMove = database.databaseData.moveObjects[existingMoveId] {
            return (existingMove, existingMoveId, false)
        }

        // Create new move
        let newMove = Move(sourceFenId: source, targetFenId: target)
        let newMoveId = database.databaseData.moveObjects.count + 1
        database.databaseData.moveObjects[newMoveId] = newMove
        database.databaseData.moveToId[[source, target]] = newMoveId
        markDirty()

        return (newMove, newMoveId, true)
    }

    /// 格式化 move 为字符串表示（如"炮二平五" - 表示层）
    func formatMove(_ move: Move, isHorizontalFlipped: Bool) -> String {
        return move.moveString(fenObjects2: database.databaseData.fenObjects2, isHorizontalFlipped: isHorizontalFlipped)
    }

    /// 解析 move 为 PieceMove 结构（用于搜索匹配 - 表示层）
    func parsePieceMove(_ move: Move, isHorizontalFlipped: Bool) -> PieceMove? {
        return move.pieceMove(fenObjects2: database.databaseData.fenObjects2, isHorizontalFlipped: isHorizontalFlipped)
    }

    // MARK: - Private Helper

    /// 判断 move 是否可见（封装过滤逻辑，供 DRY 复用）
    private func isMoveVisible(sourceFenId: Int, targetFenId: Int?) -> Bool {
        guard let targetFenId = targetFenId else { return false }
        guard containsFenId(targetFenId) else { return false }

        // Apply moveIdFilter if present
        if let moveIdFilter = moveIdFilter {
            guard let moveId = database.databaseData.moveToId[[sourceFenId, targetFenId]] else { return false }
            return moveIdFilter(moveId)
        }

        return true
    }

    // MARK: - Direct Access (Non-filtered)

    /// 以下属性提供对底层 DatabaseData 的直通访问，不受 scope 过滤影响。
    /// 使用这些属性时，调用方需要自行确保数据的合法性和一致性。
    /// 对于 fenId 相关的访问，建议先通过 `contains(_:)` 验证是否在当前 scope 内。

    private var bookObjects: [UUID: BookObject] {
        database.databaseData.bookObjects
    }

    private var gameObjects: [UUID: GameObject] {
        database.databaseData.gameObjects
    }

    var myRealRedGameStatisticsByFenId: [Int: GameResultStatistics] {
        database.databaseData.myRealRedGameStatisticsByFenId
    }

    var myRealBlackGameStatisticsByFenId: [Int: GameResultStatistics] {
        database.databaseData.myRealBlackGameStatisticsByFenId
    }

    var bookmarks: [[Int]: String] {
        database.databaseData.bookmarks
    }

    var dataVersion: Int {
        database.databaseData.dataVersion
    }

    // MARK: - Book and Game Object Access

    /// 获取特定 BookObject（未过滤）
    /// - Parameter id: BookObject 的 UUID
    /// - Returns: 对应的 BookObject，如果不存在则返回 nil
    /// - Note: BookObject 不受过滤影响，始终返回所有书籍（书籍是组织结构）
    func getBookObjectUnfiltered(_ id: UUID) -> BookObject? {
        return bookObjects[id]
    }

    /// 获取特定 GameObject
    /// - Parameter id: GameObject 的 UUID
    /// - Returns: 对应的 GameObject，如果不存在或被过滤则返回 nil
    /// - Note: 如果设置了 gameIdFilter，只有通过过滤的游戏才会返回
    func getGameObject(_ id: UUID) -> GameObject? {
        guard let game = gameObjects[id] else { return nil }

        // Apply gameIdFilter if present
        if let gameIdFilter = gameIdFilter {
            guard gameIdFilter(id) else { return nil }
        }

        return game
    }

    /// 获取 GameObject（未过滤，忽略 gameIdFilter）
    /// - Parameter id: 游戏 ID
    /// - Returns: 对应的 GameObject，如果不存在则返回 nil
    /// - Note: 此方法不受 gameIdFilter 影响，用于需要访问所有游戏的场景（如棋局浏览器）
    func getGameObjectUnfiltered(_ id: UUID) -> GameObject? {
        return gameObjects[id]
    }

    /// 获取所有 BookObjects（未过滤）
    /// - Returns: 所有 BookObject 的数组
    /// - Note: BookObject 不受过滤影响，始终返回所有书籍
    func getAllBookObjectsUnfiltered() -> [BookObject] {
        return Array(bookObjects.values)
    }

    /// 获取所有 GameObjects
    /// - Returns: 所有 GameObject 的数组（受 gameIdFilter 过滤）
    /// - Note: 如果设置了 gameIdFilter，只返回通过过滤的游戏
    func getAllGameObjects() -> [GameObject] {
        if let gameIdFilter = gameIdFilter {
            return gameObjects.values.filter { gameIdFilter($0.id) }
        }
        return Array(gameObjects.values)
    }

    // MARK: - Dirty State Management

    func markDirty() {
        database.markDirty()
    }

    var isDirty: Bool {
        database.isDirty
    }

    func markClean() {
        database.markClean()
    }

    // MARK: - Persistence Operations

    /// 保存数据库到默认位置
    /// - Note: 这是对底层 Database 的委托调用，不受 scope 过滤影响
    func save() throws {
        try database.save()
    }

    /// 从默认位置重新加载数据库
    /// - Note: 这是对底层 Database 的委托调用，会影响所有 DatabaseView 实例
    func reload() throws {
        try database.reload()
    }

    /// 从备份恢复数据库
    /// - Parameter databaseData: 要恢复的数据库数据
    /// - Note: 这是对底层 Database 的委托调用，会影响所有 DatabaseView 实例
    func restoreFromBackup(_ databaseData: DatabaseData) {
        database.restoreFromBackup(databaseData)
    }

    /// 获取数据库数据用于备份操作
    /// - Note: 这是对底层 DatabaseData 的直通访问，不受 scope 过滤影响
    var databaseDataForBackup: DatabaseData {
        database.databaseData
    }

    // MARK: - Query Methods

    func getScoreByFenId(_ fenId: Int) -> Int? {
        return getFenObject(fenId)?.score
    }

    var bookmarkList: [(game: [Int], name: String)] {
        return database.databaseData.bookmarks.compactMap { game, name in (game, name) }.sorted { $0.name < $1.name }
    }

    var allGameObjects: [GameObject] {
        return getAllGameObjects()
    }

    var allBookObjectsUnfiltered: [BookObject] {
        return getAllBookObjectsUnfiltered()
    }

    var allTopLevelBookObjectsUnfiltered: [BookObject] {
        let allChildrenBookIds = allBookObjectsUnfiltered.flatMap { $0.subBookIds }
        return allBookObjectsUnfiltered.filter { !allChildrenBookIds.contains($0.id) }
    }

    var allFenWithoutScore: [String] {
        return database.databaseData.fenObjects2.values.filter { $0.score == nil }.map { $0.fen }
    }

    func getGamesInBookUnfiltered(_ bookId: UUID) -> [GameObject] {
        return database.databaseData.bookObjects[bookId]?.gameIds.map { database.databaseData.gameObjects[$0]! } ?? []
    }

    func getGamesInBookRecursivelyUnfiltered(bookId: UUID) -> [GameObject] {
        var allGames: [GameObject] = []
        var visitedBookIds = Set<UUID>() // 防止循环引用

        func collectGames(from bookId: UUID) {
            // 防止循环引用
            guard !visitedBookIds.contains(bookId) else {
                return
            }
            visitedBookIds.insert(bookId)

            // 获取当前书籍
            guard let book = database.databaseData.bookObjects[bookId] else {
                return
            }

            // 收集当前书籍的所有游戏
            for gameId in book.gameIds {
                if let game = database.databaseData.gameObjects[gameId] {
                    allGames.append(game)
                }
            }

            // 递归处理所有子书籍
            for subBookId in book.subBookIds {
                collectGames(from: subBookId)
            }
        }

        collectGames(from: bookId)
        return allGames
    }

    /// Check if a game contains a specific fenId
    /// - Parameters:
    ///   - gameId: The game UUID
    ///   - fenId: The position ID to check
    /// - Returns: true if the game contains the fenId, false otherwise
    func gameContainsFenId(gameId: UUID, fenId: Int) -> Bool {
        // Get game object through DatabaseView's public API
        guard let game = database.databaseData.gameObjects[gameId] else {
            return false
        }

        // Check starting position
        if game.startingFenId == fenId {
            return true
        }

        // Check all moves for source and target positions
        for moveId in game.moveIds {
            guard let move = move(id: moveId) else {
                continue
            }
            if move.sourceFenId == fenId || move.targetFenId == fenId {
                return true
            }
        }

        return false
    }

    // MARK: - Book and Game Management Methods

    func addBook(name: String, parentBookId: UUID? = nil) -> UUID {
        let newBookId = UUID()
        let newBook = BookObject(id: newBookId, name: name)
        database.databaseData.bookObjects[newBookId] = newBook
        if let parentId = parentBookId, let parentBook = database.databaseData.bookObjects[parentId] {
            parentBook.subBookIds.append(newBookId)
        }
        markDirty()
        return newBookId
    }

    func deleteBook(_ bookId: UUID) {
        guard let book = database.databaseData.bookObjects[bookId] else { return }
        for subBookId in book.subBookIds {
            deleteBook(subBookId)
        }
        for gameId in book.gameIds {
            database.databaseData.gameObjects.removeValue(forKey: gameId)
        }
        for (_, parentBook) in database.databaseData.bookObjects {
            if let index = parentBook.subBookIds.firstIndex(of: bookId) {
                parentBook.subBookIds.remove(at: index)
            }
        }
        database.databaseData.bookObjects.removeValue(forKey: bookId)
        markDirty()
    }

    func updateBook(_ bookId: UUID, name: String) {
        guard let book = database.databaseData.bookObjects[bookId] else { return }
        book.name = name
        markDirty()
    }

    func addGame(to bookId: UUID, name: String?, redPlayerName: String, blackPlayerName: String, gameDate: Date, gameResult: GameResult, iAmRed: Bool, iAmBlack: Bool, startingFenId: Int?, isFullyRecorded: Bool) -> UUID {
        let newGameId = UUID()
        let newGame = GameObject(id: newGameId)
        newGame.name = name
        newGame.creationDate = Date()
        newGame.gameDate = gameDate
        newGame.redPlayerName = redPlayerName
        newGame.blackPlayerName = blackPlayerName
        newGame.gameResult = gameResult
        newGame.iAmRed = iAmRed
        newGame.iAmBlack = iAmBlack
        newGame.startingFenId = startingFenId
        newGame.isFullyRecorded = isFullyRecorded
        database.databaseData.gameObjects[newGameId] = newGame
        if let book = database.databaseData.bookObjects[bookId] {
            book.gameIds.append(newGameId)
        }
        markDirty()
        return newGameId
    }

    func deleteGame(_ gameId: UUID) {
        for (_, book) in database.databaseData.bookObjects {
            if let index = book.gameIds.firstIndex(of: gameId) {
                book.gameIds.remove(at: index)
            }
        }
        database.databaseData.gameObjects.removeValue(forKey: gameId)
        markDirty()
    }

    func updateGame(_ gameId: UUID, name: String?, redPlayerName: String, blackPlayerName: String, gameDate: Date, gameResult: GameResult, iAmRed: Bool, iAmBlack: Bool, startingFenId: Int?, isFullyRecorded: Bool) {
        guard let game = database.databaseData.gameObjects[gameId] else { return }
        game.name = name
        game.redPlayerName = redPlayerName
        game.blackPlayerName = blackPlayerName
        game.gameDate = gameDate
        game.gameResult = gameResult
        game.iAmRed = iAmRed
        game.iAmBlack = iAmBlack
        game.startingFenId = startingFenId
        game.isFullyRecorded = isFullyRecorded
        markDirty()
    }

    /// 添加 FenObject（如果不存在）
    func addFenObjectIfNeeded(_ fenObject: FenObject) {
        if let fenId = fenObject.fenId, database.databaseData.fenObjects2[fenId] == nil {
            database.databaseData.fenObjects2[fenId] = fenObject
            database.databaseData.fenToId[fenObject.fen] = fenId
            markDirty()
        }
    }

    /// 更新 bookmarks
    func updateBookmark(for game: [Int], name: String?) {
        database.databaseData.bookmarks[game] = name
        markDirty()
    }

    /// 更新 bookObject
    func updateBookObject(_ bookId: UUID, bookObject: BookObject) {
        database.databaseData.bookObjects[bookId] = bookObject
        markDirty()
    }

    /// 更新 gameObject
    func updateGameObject(_ gameId: UUID, gameObject: GameObject) {
        database.databaseData.gameObjects[gameId] = gameObject
        markDirty()
    }

    /// 从特定棋局中删除指定着法
    /// - Parameters:
    ///   - gameId: 棋局 ID
    ///   - sourceFenId: 源局面 ID
    ///   - targetFenId: 目标局面 ID
    /// - Returns: 是否成功删除
    func removeMoveFromGame(gameId: UUID, sourceFenId: Int, targetFenId: Int) -> Bool {
        // 查找 moveId
        guard let moveId = database.databaseData.moveToId[[sourceFenId, targetFenId]] else {
            return false
        }

        // 获取并验证 gameObject
        guard let gameObject = database.databaseData.gameObjects[gameId] else {
            return false
        }

        // 查找并删除 moveId
        guard gameObject.containsMoveId(moveId) else {
            return false
        }

        gameObject.removeMoveId(moveId)
        database.databaseData.gameObjects[gameId] = gameObject
        markDirty()
        return true
    }

    /// 删除 bookObject
    func removeBookObject(_ bookId: UUID) {
        database.databaseData.bookObjects.removeValue(forKey: bookId)
        markDirty()
    }

    /// 删除 gameObject
    func removeGameObject(_ gameId: UUID) {
        database.databaseData.gameObjects.removeValue(forKey: gameId)
        markDirty()
    }

    /// 更新红方实战统计
    func updateRedGameStatistics(for fenId: Int, statistics: GameResultStatistics) {
        database.databaseData.myRealRedGameStatisticsByFenId[fenId] = statistics
        markDirty()
    }

    /// 更新黑方实战统计
    func updateBlackGameStatistics(for fenId: Int, statistics: GameResultStatistics) {
        database.databaseData.myRealBlackGameStatisticsByFenId[fenId] = statistics
        markDirty()
    }

    // MARK: - Convenience Constructors

    /// 便利构造器用于创建不同 scope 的 DatabaseView。
    /// 这些方法在闭包内直接访问 database.databaseData，避免捕获数据快照，
    /// 确保视图始终反映最新的数据库状态。

    /// 完整数据库视图（无过滤）
    static func full(database: Database) -> DatabaseView {
        return DatabaseView(database: database, fenIdFilter: { _ in true })
    }

    /// 红方开局库视图
    static func redOpening(database: Database) -> DatabaseView {
        return DatabaseView(database: database, fenIdFilter: { fenId in
            return database.databaseData.fenObjects2[fenId]?.isInRedOpening ?? false
        })
    }

    /// 黑方开局库视图
    static func blackOpening(database: Database) -> DatabaseView {
        return DatabaseView(database: database, fenIdFilter: { fenId in
            return database.databaseData.fenObjects2[fenId]?.isInBlackOpening ?? false
        })
    }

    /// 红方实战视图
    static func redRealGame(database: Database) -> DatabaseView {
        return DatabaseView(database: database, fenIdFilter: { fenId in
            guard let s = database.databaseData.myRealRedGameStatisticsByFenId[fenId] else { return false }
            return s.redWin + s.blackWin + s.draw + s.notFinished + s.unknown > 0
        })
    }

    /// 黑方实战视图
    static func blackRealGame(database: Database) -> DatabaseView {
        return DatabaseView(database: database, fenIdFilter: { fenId in
            guard let s = database.databaseData.myRealBlackGameStatisticsByFenId[fenId] else { return false }
            return s.redWin + s.blackWin + s.draw + s.notFinished + s.unknown > 0
        })
    }

    /// 专注练习视图
    static func focusedPractice(database: Database, path: [Int]) -> DatabaseView {
        let pathSet = Set(path)
        return DatabaseView(database: database, fenIdFilter: { fenId in
            return pathSet.contains(fenId)
        })
    }

    /// 特定棋局视图
    static func specificGame(database: Database, gameId: UUID) -> DatabaseView {
        return DatabaseView(
            database: database,
            fenIdFilter: { fenId in
                guard let game = database.databaseData.gameObjects[gameId] else {
                    return false
                }

                return game.containsFenId(fenId, moveObjects: database.databaseData.moveObjects)
            },
            moveIdFilter: { moveId in
                guard let game = database.databaseData.gameObjects[gameId] else {
                    return false
                }

                return game.containsMoveId(moveId)
            },
            gameIdFilter: { candidateGameId in
                return candidateGameId == gameId
            }
        )
    }

    /// 特定棋谱视图 - 显示棋谱中所有棋局的所有局面和走法（递归包含子棋谱）
    static func specificBook(database: Database, bookId: UUID) -> DatabaseView {
        // 递归收集棋谱中所有棋局的数据
        let (validFenIds, validMoveIds, validGameIds) = collectBookData(database: database, bookId: bookId)

        return DatabaseView(
            database: database,
            fenIdFilter: { fenId in
                return validFenIds.contains(fenId)
            },
            moveIdFilter: { moveId in
                return validMoveIds.contains(moveId)
            },
            gameIdFilter: { gameId in
                return validGameIds.contains(gameId)
            }
        )
    }

    /// 递归收集棋谱中所有棋局的 fenIds, moveIds, gameIds
    /// - Parameters:
    ///   - database: 数据库实例
    ///   - bookId: 棋谱 ID
    /// - Returns: (fenIds, moveIds, gameIds) 的集合
    private static func collectBookData(database: Database, bookId: UUID)
        -> (fenIds: Set<Int>, moveIds: Set<Int>, gameIds: Set<UUID>) {
        var allFenIds = Set<Int>()
        var allMoveIds = Set<Int>()
        var allGameIds = Set<UUID>()

        // 递归内部函数
        func collectRecursively(bookId: UUID) {
            guard let book = database.databaseData.bookObjects[bookId] else { return }

            // 收集直接包含的棋局数据
            for gameId in book.gameIds {
                guard let game = database.databaseData.gameObjects[gameId] else { continue }
                allGameIds.insert(gameId)

                // 添加起始局面
                if let startFenId = game.startingFenId {
                    allFenIds.insert(startFenId)
                }

                // 添加所有走法及其关联的局面
                for moveId in game.moveIds {
                    allMoveIds.insert(moveId)
                    if let move = database.databaseData.moveObjects[moveId] {
                        allFenIds.insert(move.sourceFenId)
                        if let targetFenId = move.targetFenId {
                            allFenIds.insert(targetFenId)
                        }
                    }
                }
            }

            // 递归处理子棋谱
            for subBookId in book.subBookIds {
                collectRecursively(bookId: subBookId)
            }
        }

        collectRecursively(bookId: bookId)
        return (allFenIds, allMoveIds, allGameIds)
    }

    /// 组合筛选视图 - 支持多个 filter 的 AND 组合
    /// - Parameters:
    ///   - database: 数据库实例
    ///   - filters: filter 字符串数组（如 ["specific_book", "red_opening_only"]）
    ///   - specificGameId: 特定棋局 ID（当 filters 包含 "specific_game" 时需要）
    ///   - specificBookId: 特定棋书 ID（当 filters 包含 "specific_book" 时需要）
    ///   - focusedPracticePath: 专注练习路径（当 filters 包含 "focused_practice" 时需要）
    /// - Returns: 组合后的 DatabaseView
    static func combined(
        database: Database,
        filters: [String],
        specificGameId: UUID? = nil,
        specificBookId: UUID? = nil,
        focusedPracticePath: [Int]? = nil
    ) -> DatabaseView {
        // 如果没有 filter，返回完整视图
        if filters.isEmpty {
            return .full(database: database)
        }

        // 构建基础 fenIdFilter 闭包数组
        var fenIdFilters: [(Int) -> Bool] = []
        var moveIdFilters: [(Int) -> Bool] = []
        var gameIdFilters: [(UUID) -> Bool] = []

        for filter in filters {
            switch filter {
            case Session.filterRedOpeningOnly:
                fenIdFilters.append { fenId in
                    database.databaseData.fenObjects2[fenId]?.isInRedOpening ?? false
                }

            case Session.filterBlackOpeningOnly:
                fenIdFilters.append { fenId in
                    database.databaseData.fenObjects2[fenId]?.isInBlackOpening ?? false
                }

            case Session.filterRedRealGameOnly:
                fenIdFilters.append { fenId in
                    guard let s = database.databaseData.myRealRedGameStatisticsByFenId[fenId] else { return false }
                    return s.redWin + s.blackWin + s.draw + s.notFinished + s.unknown > 0
                }

            case Session.filterBlackRealGameOnly:
                fenIdFilters.append { fenId in
                    guard let s = database.databaseData.myRealBlackGameStatisticsByFenId[fenId] else { return false }
                    return s.redWin + s.blackWin + s.draw + s.notFinished + s.unknown > 0
                }

            case Session.filterFocusedPractice:
                if let path = focusedPracticePath {
                    let pathSet = Set(path)
                    fenIdFilters.append { fenId in
                        pathSet.contains(fenId)
                    }
                }

            case Session.filterSpecificGame:
                if let gameId = specificGameId {
                    fenIdFilters.append { fenId in
                        guard let game = database.databaseData.gameObjects[gameId] else { return false }
                        return game.containsFenId(fenId, moveObjects: database.databaseData.moveObjects)
                    }
                    moveIdFilters.append { moveId in
                        guard let game = database.databaseData.gameObjects[gameId] else { return false }
                        return game.containsMoveId(moveId)
                    }
                    gameIdFilters.append { candidateGameId in
                        candidateGameId == gameId
                    }
                }

            case Session.filterSpecificBook:
                if let bookId = specificBookId {
                    let (validFenIds, validMoveIds, validGameIds) = collectBookData(database: database, bookId: bookId)
                    fenIdFilters.append { fenId in
                        validFenIds.contains(fenId)
                    }
                    moveIdFilters.append { moveId in
                        validMoveIds.contains(moveId)
                    }
                    gameIdFilters.append { gameId in
                        validGameIds.contains(gameId)
                    }
                }

            default:
                break
            }
        }

        // 组合所有 fenIdFilter（AND 逻辑）
        let combinedFenIdFilter: (Int) -> Bool = { fenId in
            for filter in fenIdFilters {
                if !filter(fenId) {
                    return false
                }
            }
            return true
        }

        // 组合所有 moveIdFilter（AND 逻辑）
        let combinedMoveIdFilter: ((Int) -> Bool)? = moveIdFilters.isEmpty ? nil : { moveId in
            for filter in moveIdFilters {
                if !filter(moveId) {
                    return false
                }
            }
            return true
        }

        // 组合所有 gameIdFilter（AND 逻辑）
        let combinedGameIdFilter: ((UUID) -> Bool)? = gameIdFilters.isEmpty ? nil : { gameId in
            for filter in gameIdFilters {
                if !filter(gameId) {
                    return false
                }
            }
            return true
        }

        return DatabaseView(
            database: database,
            fenIdFilter: combinedFenIdFilter,
            moveIdFilter: combinedMoveIdFilter,
            gameIdFilter: combinedGameIdFilter
        )
    }
}
