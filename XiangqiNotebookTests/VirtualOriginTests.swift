import Testing
import Foundation
@testable import XiangqiNotebook

/// 虚拟根局面 origin 的集成测试
struct VirtualOriginTests {

    // MARK: - createEmptyDatabase 行为

    @Test func emptyDatabaseHasStandardOpeningAndOrigin() {
        let db = DatabaseStorage.createEmptyDatabase()
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        // fenId=1 标准开局，fenId=2 虚拟根 origin
        #expect(db.fenObjects2[1]?.fen == startFen)
        #expect(db.fenObjects2[2]?.fen == DatabaseData.originFen)
        #expect(db.originFenId == 2)
    }

    // MARK: - ensureVirtualOriginAndMoves 行为

    @Test func ensureAddsOriginToExistingDatabaseAtMaxIdPlusOne() {
        // 模拟旧版本数据库：只有标准开局在 fenId=1，没有 origin
        let data = DatabaseData()
        let fen1 = FenObject(fen: "standardOpening", fenId: 1)
        data.fenObjects2[1] = fen1
        data.fenToId["standardOpening"] = 1
        let fen2 = FenObject(fen: "someOtherFen", fenId: 2)
        data.fenObjects2[2] = fen2
        data.fenToId["someOtherFen"] = 2

        // 此时还没有 origin
        #expect(data.originFenId == nil)

        Database.ensureVirtualOriginAndMoves(in: data)

        // origin 被分配到 maxId+1 = 3，且原有数据不受影响
        #expect(data.originFenId == 3)
        #expect(data.fenObjects2[3]?.fen == DatabaseData.originFen)
        #expect(data.fenObjects2[1]?.fen == "standardOpening")  // 未被覆盖
        #expect(data.fenObjects2[2]?.fen == "someOtherFen")
    }

    @Test func ensureIsIdempotent() {
        let data = DatabaseData()
        let fen1 = FenObject(fen: "abc", fenId: 1)
        data.fenObjects2[1] = fen1
        data.fenToId["abc"] = 1

        Database.ensureVirtualOriginAndMoves(in: data)
        let firstOriginId = data.originFenId
        let firstCount = data.fenObjects2.count

        Database.ensureVirtualOriginAndMoves(in: data)
        #expect(data.originFenId == firstOriginId)
        #expect(data.fenObjects2.count == firstCount)
    }

    @Test func ensureCreatesVirtualMovesForGamesStartingFens() {
        let data = DatabaseData()
        let fenA = FenObject(fen: "fenA", fenId: 1)
        data.fenObjects2[1] = fenA
        data.fenToId["fenA"] = 1
        let fenB = FenObject(fen: "fenB", fenId: 2)
        data.fenObjects2[2] = fenB
        data.fenToId["fenB"] = 2

        // 两个棋谱：一个从 fenId=1 起始（标准开局），一个从 fenId=2 起始（中局题）
        let game1 = GameObject(id: UUID()); game1.startingFenId = 1; game1.name = "g1"
        let game2 = GameObject(id: UUID()); game2.startingFenId = 2; game2.name = "g2"
        data.gameObjects[game1.id] = game1
        data.gameObjects[game2.id] = game2

        Database.ensureVirtualOriginAndMoves(in: data)

        let originFenId = data.originFenId!
        // 应当为每个 startingFen 创建一个 origin → startingFen 的虚拟着法
        #expect(data.moveToId[[originFenId, 1]] != nil)
        #expect(data.moveToId[[originFenId, 2]] != nil)
        // origin 的 moves 列表中包含这两条虚拟着法
        let originMoves = data.fenObjects2[originFenId]?.moves ?? []
        let targetIds = Set(originMoves.compactMap { $0.targetFenId })
        #expect(targetIds.contains(1))
        #expect(targetIds.contains(2))
    }

    @Test func ensureDoesNotDuplicateExistingVirtualMoves() {
        let data = DatabaseData()
        let fenA = FenObject(fen: "fenA", fenId: 1)
        data.fenObjects2[1] = fenA
        data.fenToId["fenA"] = 1
        let game = GameObject(id: UUID()); game.startingFenId = 1; game.name = "g"
        data.gameObjects[game.id] = game

        Database.ensureVirtualOriginAndMoves(in: data)
        let count1 = data.moveObjects.count

        Database.ensureVirtualOriginAndMoves(in: data)
        // 重复调用不应当创建新的虚拟着法
        #expect(data.moveObjects.count == count1)
    }

    // MARK: - DatabaseView origin 包含

    @Test func allViewsContainOrigin() {
        let data = DatabaseData()
        let fen1 = FenObject(fen: "fen1", fenId: 1)
        fen1.setInRedOpening(true)
        data.fenObjects2[1] = fen1
        data.fenToId["fen1"] = 1
        let fen2 = FenObject(fen: "fen2", fenId: 2)
        fen2.setInBlackOpening(true)
        data.fenObjects2[2] = fen2
        data.fenToId["fen2"] = 2
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let originId = db.originFenId!

        // origin 应该在所有便利视图的 scope 内
        #expect(DatabaseView.full(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.redOpening(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.blackOpening(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.redRealGame(database: db).containsFenId(originId) == true)
        #expect(DatabaseView.blackRealGame(database: db).containsFenId(originId) == true)
    }

    @Test func nonOriginFensStillRespectFilters() {
        // 验证 origin 的特殊处理不会让 filter 对其他 fenId 失效
        let data = DatabaseData()
        let fen1 = FenObject(fen: "fen1", fenId: 1)
        fen1.setInRedOpening(true)
        data.fenObjects2[1] = fen1
        data.fenToId["fen1"] = 1
        let fen2 = FenObject(fen: "fen2", fenId: 2)
        fen2.setInRedOpening(false)
        data.fenObjects2[2] = fen2
        data.fenToId["fen2"] = 2
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let redView = DatabaseView.redOpening(database: db)
        #expect(redView.containsFenId(1) == true)   // 红方开局内
        #expect(redView.containsFenId(2) == false)  // 不在红方开局
    }

    // MARK: - allFenWithoutScore 排除 origin

    @Test func allFenWithoutScoreExcludesOrigin() {
        let data = DatabaseData()
        let fen1 = FenObject(fen: "fen1", fenId: 1)
        // score 为 nil
        data.fenObjects2[1] = fen1
        data.fenToId["fen1"] = 1
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let view = DatabaseView.full(database: db)
        let unscoredFens = view.allFenWithoutScore
        #expect(unscoredFens.contains("fen1") == true)
        #expect(unscoredFens.contains(DatabaseData.originFen) == false)
    }

    // MARK: - Codable 持久化兼容性

    @Test func encodeAndDecodePreservesOrigin() throws {
        let data = DatabaseData()
        Database.ensureVirtualOriginAndMoves(in: data)
        let originId = data.originFenId!

        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DatabaseData.self, from: encoded)
        #expect(decoded.originFenId == originId)
        #expect(decoded.fenObjects2[originId]?.fen == DatabaseData.originFen)
    }

    @Test func decodingLegacyDataWithoutOriginThenEnsuringIsIdempotent() throws {
        // 模拟旧版本数据库 JSON（无 origin）
        let legacy = DatabaseData()
        let fen1 = FenObject(fen: "legacy_fen", fenId: 1)
        legacy.fenObjects2[1] = fen1
        legacy.fenToId["legacy_fen"] = 1

        let encoded = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(DatabaseData.self, from: encoded)
        #expect(decoded.originFenId == nil)

        Database.ensureVirtualOriginAndMoves(in: decoded)
        #expect(decoded.originFenId == 2)

        // 再次 encode/decode + ensure 应保持稳定
        let encoded2 = try JSONEncoder().encode(decoded)
        let decoded2 = try JSONDecoder().decode(DatabaseData.self, from: encoded2)
        Database.ensureVirtualOriginAndMoves(in: decoded2)
        #expect(decoded2.originFenId == 2)
        #expect(decoded2.fenObjects2.count == 2)
    }

    // MARK: - DatabaseView 兜底：containsFenId 对 origin 总是返回 true

    /// 验证 setFilters 中的兜底前提：origin 在任何 view 中都可达
    /// 这是 setFilters 在 currentGame2[0] 不在 scope 时回退到 origin 的关键依据
    // MARK: - 导航到 origin（step 0）不应崩溃

    /// 用户点击招法列表的"起点"行（step 0 = origin）时，所有依赖 currentFen 的访问都不应崩溃。
    /// 历史回归：origin 的 fen 是哨兵 "__origin__"，原来在 Session.displayScore 等多处直接用
    /// `fen.split(" ")[1]` 解析下棋方，遇到 origin 越界崩溃。
    @MainActor
    @Test func navigatingToOriginStepDoesNotCrash() throws {
        let data = DatabaseData()
        let standardFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fen1 = FenObject(fen: standardFen, fenId: 1)
        data.fenObjects2[1] = fen1
        data.fenToId[standardFen] = 1
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)
        let originFenId = db.originFenId!

        let sessionData = SessionData()
        sessionData.currentGame2 = [originFenId, 1]
        sessionData.currentGameStep = 1
        let session = try Session(sessionData: sessionData, databaseView: DatabaseView.full(database: db))

        // 模拟点击"起点"行
        session.toStepIndex(0)
        #expect(session.sessionData.currentGameStep == 0)

        // 在 origin 状态下访问所有显示属性都不应崩溃
        _ = session.currentFen
        _ = session.displayScore
        _ = session.displayEngineScore
        #if os(macOS)
        _ = session.displayDeepEngineScore
        _ = session.displayQuickEngineScore
        #endif

        // 招法列表生成不应崩溃，且首行应为"起点"
        let moveList = session.currentGameMoveList
        #expect(moveList.count == 2)
        #expect(moveList[0].notation == "起点")
        #expect(moveList[1].notation == "标准局面")
    }

    /// 中局题棋谱（startingFenId 不是标准开局）被点击加载后，currentGame2 应该实际更新到该棋谱
    /// 而不是停留在 origin/原先的状态
    @MainActor
    @Test func loadingMiddleGamePuzzleUpdatesCurrentGame() throws {
        let data = DatabaseData()
        let standardFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fenStd = FenObject(fen: standardFen, fenId: 1)
        data.fenObjects2[1] = fenStd
        data.fenToId[standardFen] = 1
        // 中局题的起始局面（任意 fen，关键是 turn=r/b 合法）
        let middleFen = "5k3/9/9/9/9/9/9/9/9/4K4 r - - 1 1"
        let fenMid = FenObject(fen: middleFen, fenId: 2)
        data.fenObjects2[2] = fenMid
        data.fenToId[middleFen] = 2
        let book = BookObject(id: UUID(), name: "puzzles")
        let game = GameObject(id: UUID())
        game.startingFenId = 2
        game.name = "puzzle"
        book.gameIds.append(game.id)
        data.bookObjects[book.id] = book
        data.gameObjects[game.id] = game

        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)
        let originFenId = db.originFenId!

        // 初始 SessionData：默认起步在标准开局（mainSession 状态）
        let sessionData = SessionData()
        sessionData.currentGame2 = [originFenId, 1]
        sessionData.currentGameStep = 1
        let manager = SessionManager.create(from: sessionData, database: db)

        // 用户点击中局棋谱
        manager.loadGame(game.id)

        // 加载后，currentGame2 应该以该棋谱的起始 fenId 起步，而不是停在 origin/标准开局
        let result = manager.mainSession.sessionData.currentGame2
        #expect(result.contains(2), "currentGame2 should contain the puzzle's starting fen (2), got \(result)")
        #expect(result.contains(1) == false, "currentGame2 should not contain the previous standard opening (1)")
    }

    /// 切换 不筛选 → 棋谱(specificBook) → 不筛选，移动列表不应该只剩"起点"
    /// 复现：用户在 不筛选 状态下有完整 game path，切到一个不含当前 path 的 specificBook，
    /// path 被截断到 [origin]；切回 不筛选 时 autoExtend 应能从 origin 重新延伸出某个棋谱
    @MainActor
    @Test func switchingBetweenBookAndNoFilterDoesNotLeaveOnlyOrigin() throws {
        let data = DatabaseData()
        let standardFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fenStd = FenObject(fen: standardFen, fenId: 1)
        data.fenObjects2[1] = fenStd
        data.fenToId[standardFen] = 1
        // 中局题的局面（用于一个独立棋书）
        let midFen = "5k3/9/9/9/9/9/9/9/9/4K4 r - - 1 1"
        let fenMid = FenObject(fen: midFen, fenId: 2)
        data.fenObjects2[2] = fenMid
        data.fenToId[midFen] = 2

        // 棋书 A：包含中局题（不含标准开局）
        let bookA = BookObject(id: UUID(), name: "puzzle book")
        let gameA = GameObject(id: UUID())
        gameA.startingFenId = 2
        gameA.name = "puzzle"
        bookA.gameIds.append(gameA.id)
        data.bookObjects[bookA.id] = bookA
        data.gameObjects[gameA.id] = gameA

        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)
        let originFenId = db.originFenId!

        // 初始：不筛选，currentGame2 = [origin, 1]（origin + 标准开局）
        let sessionData = SessionData()
        sessionData.currentGame2 = [originFenId, 1]
        sessionData.currentGameStep = 1
        let manager = SessionManager.create(from: sessionData, database: db)

        // Step 1: 切到 specificBook（书 A 不含标准开局）
        manager.setFilters([Session.filterSpecificBook], specificBookId: bookA.id)
        // 此时 currentGame2 应被截断到 [origin]，move list 只有"起点"
        #expect(manager.mainSession.sessionData.currentGame2.first == originFenId)

        // Step 2: 切回 不筛选
        manager.setFilters([])
        let result = manager.mainSession.sessionData.currentGame2
        print("DEBUG: after switch back, currentGame2=\(result)")
        // 期望 autoExtend 能从 origin 延伸到某个棋谱（如标准开局或中局题）
        #expect(result.count > 1, "expected autoExtend to extend from origin, got \(result)")
    }

    /// BoardViewModel 接受 origin 的 fen 时不应在解析 piecesBySquare 时崩溃
    @Test func boardViewModelHandlesOriginFen() {
        let bvm = BoardViewModel(
            fen: DatabaseData.originFen,
            orientation: "red",
            isHorizontalFlipped: false,
            showPath: false,
            showAllNextMoves: false,
            shouldAnimate: false,
            currentFenPathGroups: []
        )
        #expect(bvm.isOrigin == true)
        // 访问 piecesBySquare 不应崩溃（曾因 origin fen 不是合法 FEN 而越界）
        #expect(bvm.piecesBySquare.isEmpty)
    }

    // MARK: - Origin 枢纽 (Hub) 行为

    /// 在任何 view 中，origin 的虚拟子着法都应该是全库的所有起点（绕过 filter）。
    /// 这是枢纽语义的基础：让用户在窄 view（例如 .specificGame）中也能从 origin 看到所有棋谱起点。
    @Test func originVirtualMovesBypassFilter() {
        let data = DatabaseData()
        let standardFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fenStd = FenObject(fen: standardFen, fenId: 1)
        data.fenObjects2[1] = fenStd
        data.fenToId[standardFen] = 1
        let midFen = "5k3/9/9/9/9/9/9/9/9/4K4 r - - 1 1"
        let fenMid = FenObject(fen: midFen, fenId: 2)
        data.fenObjects2[2] = fenMid
        data.fenToId[midFen] = 2
        let game = GameObject(id: UUID())
        game.startingFenId = 2
        game.name = "puzzle"
        data.gameObjects[game.id] = game

        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        // 任何 view 中，originVirtualMoves 都返回所有 origin 子节点（标准开局 + 中局题）
        let fullView = DatabaseView.full(database: db)
        let specificView = DatabaseView.specificGame(database: db, gameId: game.id)
        let fullMoves = fullView.originVirtualMoves()
        let specificMoves = specificView.originVirtualMoves()
        let fullTargets = Set(fullMoves.compactMap { $0.targetFenId })
        let specificTargets = Set(specificMoves.compactMap { $0.targetFenId })
        #expect(fullTargets == Set([1, 2]))
        #expect(specificTargets == Set([1, 2]), "originVirtualMoves should bypass filter even in .specificGame")
    }

    /// 用户从终局棋谱通过 origin 枢纽切换到标准开局：清空 filter + currentGame2 复位
    @MainActor
    @Test func hubNavigateFromEndgameToStandardOpening() throws {
        let data = DatabaseData()
        let standardFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        data.fenObjects2[1] = FenObject(fen: standardFen, fenId: 1)
        data.fenToId[standardFen] = 1
        let midFen = "5k3/9/9/9/9/9/9/9/9/4K4 r - - 1 1"
        data.fenObjects2[2] = FenObject(fen: midFen, fenId: 2)
        data.fenToId[midFen] = 2
        let game = GameObject(id: UUID())
        game.startingFenId = 2
        game.name = "puzzle"
        data.gameObjects[game.id] = game

        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)
        let originId = db.originFenId!

        // 初始：在终局棋谱
        let sessionData = SessionData()
        sessionData.currentGame2 = [originId, 2]
        sessionData.currentGameStep = 1
        sessionData.filters = [Session.filterSpecificGame]
        sessionData.specificGameId = game.id
        let manager = SessionManager.create(from: sessionData, database: db)
        #expect(manager.mainSession.sessionData.filters.contains(Session.filterSpecificGame))

        // 走枢纽：切到标准开局（fenId=1）
        let standardId = db.databaseData.standardOpeningFenId!
        manager.navigateToHubChild(startingFenId: standardId)

        // 期望：filter 清空，currentGame2 起点定位到标准开局
        #expect(manager.mainSession.sessionData.filters.isEmpty)
        #expect(manager.mainSession.sessionData.currentGame2.first == originId)
        #expect(manager.mainSession.sessionData.currentGame2[safe: 1] == standardId)
    }

    /// 用户从标准开局通过 origin 枢纽切换到某个终局棋谱：filter 切到 .specificGame + currentGame2 复位
    @MainActor
    @Test func hubNavigateFromStandardOpeningToEndgame() throws {
        let data = DatabaseData()
        let standardFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        data.fenObjects2[1] = FenObject(fen: standardFen, fenId: 1)
        data.fenToId[standardFen] = 1
        let midFen = "5k3/9/9/9/9/9/9/9/9/4K4 r - - 1 1"
        data.fenObjects2[2] = FenObject(fen: midFen, fenId: 2)
        data.fenToId[midFen] = 2
        let game = GameObject(id: UUID())
        game.startingFenId = 2
        game.name = "puzzle"
        data.gameObjects[game.id] = game

        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)
        let originId = db.originFenId!

        // 初始：在标准开局，不筛选
        let sessionData = SessionData()
        sessionData.currentGame2 = [originId, 1]
        sessionData.currentGameStep = 1
        let manager = SessionManager.create(from: sessionData, database: db)
        #expect(manager.mainSession.sessionData.filters.isEmpty)

        // 走枢纽：切到中局题（fenId=2）
        manager.navigateToHubChild(startingFenId: 2)

        // 期望：filter 切到 .specificGame(game.id)，currentGame2 起点是中局题
        #expect(manager.mainSession.sessionData.filters.contains(Session.filterSpecificGame))
        #expect(manager.mainSession.sessionData.specificGameId == game.id)
        #expect(manager.mainSession.sessionData.currentGame2.contains(2))
        #expect(manager.mainSession.sessionData.currentGame2.contains(1) == false)
    }

    /// Origin 上的 currentNextMovesList 应显示所有 hub 项（带 hub label）
    @MainActor
    @Test func originStepShowsHubItemsInNextMovesList() throws {
        let data = DatabaseData()
        let standardFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        data.fenObjects2[1] = FenObject(fen: standardFen, fenId: 1)
        data.fenToId[standardFen] = 1
        let midFen = "5k3/9/9/9/9/9/9/9/9/4K4 r - - 1 1"
        data.fenObjects2[2] = FenObject(fen: midFen, fenId: 2)
        data.fenToId[midFen] = 2
        let game = GameObject(id: UUID())
        game.startingFenId = 2
        game.name = "我的终局题"
        data.gameObjects[game.id] = game

        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)
        let originId = db.originFenId!

        let sessionData = SessionData()
        sessionData.currentGame2 = [originId, 1]
        sessionData.currentGameStep = 0  // 在 origin step
        // 注意：filter 是 .specificGame 也应该显示完整 hub（绕过 filter）
        sessionData.filters = [Session.filterSpecificGame]
        sessionData.specificGameId = game.id

        // 通过 SessionManager.create 触发 setFilters 等正常流程
        let manager = SessionManager.create(from: sessionData, database: db)
        let session = manager.mainSession
        // 把 step 强制回到 0（origin）
        session.toStepIndex(0)

        let hub = session.currentNextMovesList
        let labels = hub.map { $0.moveString }
        #expect(labels.contains("标准开局"))
        #expect(labels.contains("我的终局题"))
        #expect(hub.count == 2, "hub should have exactly 2 entries: standard opening + endgame")
    }

    @Test func originAlwaysReachableAcrossViews() {
        let data = DatabaseData()
        let middleFen = "middlegame_puzzle_fen"
        let fen = FenObject(fen: middleFen, fenId: 1)
        // 不在任何开局/实战
        data.fenObjects2[1] = fen
        data.fenToId[middleFen] = 1
        let db = Database(testDatabaseData: data)
        Database.ensureVirtualOriginAndMoves(in: data)

        let originId = db.originFenId!

        // 中局题局面在红方/黑方开局视图中均不可达
        let redView = DatabaseView.redOpening(database: db)
        #expect(redView.containsFenId(1) == false)
        // 但 origin 始终可达——setFilters 据此进行兜底
        #expect(redView.containsFenId(originId) == true)

        let blackView = DatabaseView.blackOpening(database: db)
        #expect(blackView.containsFenId(1) == false)
        #expect(blackView.containsFenId(originId) == true)
    }
}
