import Testing
import Foundation
@testable import XiangqiNotebook

/// 内置古谱（橘中秘 + 梅花谱）数据与导入器测试（issue #173）。
struct ClassicManualDataTests {

    @Test func testCounts() {
        #expect(ClassicManualData.juzhongmi.count == 20)
        #expect(ClassicManualData.meihuapu.count == 31)
        // 每局至少有主线
        for g in ClassicManualData.juzhongmi + ClassicManualData.meihuapu {
            #expect(!g.lines.isEmpty)
            #expect(!(g.lines.first ?? "").isEmpty)
        }
    }

    /// 校验打包数据每一手都是合法走法（坐标映射 + 变着树重建的最终防线）
    @Test func testAllBundledLinesAreLegal() throws {
        let startFen = normalizeFen(XiangqiBoardUtils.startFEN)

        for game in ClassicManualData.juzhongmi + ClassicManualData.meihuapu {
            for line in game.lines {
                var pieces = XiangqiBoardUtils.fenToPiecesBySquare(startFen)
                for (i, token) in line.split(separator: " ").enumerated() {
                    let appMove = PGNParser.pgnCoordToAppCoord(String(token))
                    let from = String(appMove.prefix(2))
                    let to = String(appMove.suffix(2))
                    let legal = MoveRules.getLegalDestinationSquares(fromSquare: from, piecesBySquare: pieces)
                    #expect(legal.contains(to), "\(game.name) 第 \(i + 1) 手 \(token)→\(appMove) 非法")
                    guard let newFen = XiangqiBoardUtils.getNewFenAfterMove(from: from, to: to, currentPieces: pieces) else {
                        Issue.record("\(game.name) 第 \(i + 1) 手 \(token) 无法落子")
                        break
                    }
                    pieces = XiangqiBoardUtils.fenToPiecesBySquare(normalizeFen(newFen))
                }
            }
        }
    }

    /// 导入器：在「课程」下建《橘中秘》《梅花谱》两本书，导入全部棋局，且幂等
    @Test func testImporterBuildsBooksAndGames() throws {
        let database = Database(testDatabaseData: DatabaseData())
        let sessionData = SessionData()
        let session = try Session(sessionData: sessionData, databaseView: DatabaseView.full(database: database))

        session.setupDefaultBooksIfNeeded()           // 建「课程」等默认书（测试进程跳过古谱导入）
        session.loadClassicManualsIfNeeded(force: true)

        let view = DatabaseView.full(database: database)

        // 两本书挂在「课程」下
        let course = view.getBookObjectUnfiltered(Session.courseBookId)
        #expect(course?.subBookIds.contains(Session.juzhongmiBookId) == true)
        #expect(course?.subBookIds.contains(Session.meihuapuBookId) == true)

        // 局数正确，且每局都有着法
        let jzm = view.getBookObjectUnfiltered(Session.juzhongmiBookId)
        let mhp = view.getBookObjectUnfiltered(Session.meihuapuBookId)
        #expect(jzm?.gameIds.count == 20)
        #expect(mhp?.gameIds.count == 31)
        for gid in (jzm?.gameIds ?? []) {
            #expect(view.getGameObjectUnfiltered(gid)?.moveIds.isEmpty == false)
        }

        // 幂等：再次导入不重复
        session.loadClassicManualsIfNeeded(force: true)
        #expect(view.getBookObjectUnfiltered(Session.juzhongmiBookId)?.gameIds.count == 20)
        #expect(view.getBookObjectUnfiltered(Session.meihuapuBookId)?.gameIds.count == 31)
    }

    /// 加载一局应展开**完整主线**（而非停在分叉、或串到别局的线上）。
    ///
    /// 回归 1：导入未填 fenObject.moves / 未设 lastMoveFenId 时，loadGame 只展开几手就截断。
    /// 回归 2：多局共享局面（各路顺炮）时，旧 autoExtend 依赖全局 lastMoveFenId 选续走，
    ///        会被其它棋局的导入/加载覆盖，导致展开过长或过短。现 loadGame 改用棋局自身
    ///        moveIds 重建主线（GameOperations.mainLinePath），不受跨局污染。
    @Test func testLoadedGameExtendsFullMainLine() throws {
        let database = Database(testDatabaseData: DatabaseData())
        let session = try Session(sessionData: SessionData(), databaseView: DatabaseView.full(database: database))
        session.setupDefaultBooksIfNeeded()
        session.loadClassicManualsIfNeeded(force: true)

        let view = DatabaseView.full(database: database)

        func checkBook(_ bookId: UUID, _ data: [ClassicManualData.Game]) throws {
            let book = try #require(view.getBookObjectUnfiltered(bookId))
            for (idx, gameId) in book.gameIds.enumerated() {
                let mainLineMoveCount = data[idx].lines[0].split(separator: " ").count
                guard let game = view.getGameObjectUnfiltered(gameId) else { continue }
                let specificView = DatabaseView.specificGame(database: database, gameId: gameId)
                // loadGame 用 mainLinePath 重建主线；这里直接校验它沿主线走到底
                let path = GameOperations.mainLinePath(of: game, databaseView: specificView)
                #expect(
                    path.count == mainLineMoveCount + 1,
                    "\(game.name) 主线 \(mainLineMoveCount) 手，实际重建 \(path.count - 1) 手"
                )
            }
        }

        try checkBook(Session.juzhongmiBookId, ClassicManualData.juzhongmi)
        try checkBook(Session.meihuapuBookId, ClassicManualData.meihuapu)
    }

    /// 端到端：通过真实的 SessionManager.loadGame 加载一局，currentGame2 应等于完整主线长度。
    @Test func testLoadGameEndToEndFullMainLine() throws {
        let database = Database(testDatabaseData: DatabaseData())
        let sessionManager = SessionManager.create(from: SessionData(), database: database)
        sessionManager.mainSession.setupDefaultBooksIfNeeded()
        sessionManager.mainSession.loadClassicManualsIfNeeded(force: true)

        let view = DatabaseView.full(database: database)
        let jzm = try #require(view.getBookObjectUnfiltered(Session.juzhongmiBookId))
        let gameId = try #require(jzm.gameIds.first)
        let expectedMoves = ClassicManualData.juzhongmi[0].lines[0].split(separator: " ").count

        sessionManager.loadGame(gameId)
        let loaded = sessionManager.mainSession.sessionData.currentGame2
        #expect(
            loaded.count == expectedMoves + 1,
            "loadGame 后 currentGame2 应有 \(expectedMoves + 1) 个局面，实际 \(loaded.count)"
        )
    }

    /// 回归：加载后招法列表不应出现 "nil_bug"（路径中相邻局面间必须有可见 move）。
    /// 对应用户截图：梅花谱某局主线后半段全是 nil_bug，因 fenObject.moves 未填充，
    /// move(from:to:) 取不到边。
    @Test func testLoadedGameMoveListHasNoNilBug() throws {
        let database = Database(testDatabaseData: DatabaseData())
        let sessionManager = SessionManager.create(from: SessionData(), database: database)
        sessionManager.mainSession.setupDefaultBooksIfNeeded()
        sessionManager.mainSession.loadClassicManualsIfNeeded(force: true)

        let view = DatabaseView.full(database: database)
        let mhp = try #require(view.getBookObjectUnfiltered(Session.meihuapuBookId))

        for gameId in mhp.gameIds {
            sessionManager.loadGame(gameId)
            let path = sessionManager.mainSession.sessionData.currentGame2
            let items = GameOperations.formatMoveList(
                currentGame: path,
                databaseView: sessionManager.mainSession.databaseView,
                isHorizontalFlipped: false
            )
            let nilBugCount = items.filter { $0.notation == "nil_bug" }.count
            let name = view.getGameObjectUnfiltered(gameId)?.name ?? "?"
            #expect(nilBugCount == 0, "\(name) 招法列表出现 \(nilBugCount) 个 nil_bug（路径长 \(path.count)）")
        }
    }

    /// 模拟用户场景：古谱由「旧导入器」导入（未填 fenObject.moves），存盘后重启 app
    /// 重新解码 → rebuildIndexes 应重建 fenObject.moves，使加载后招法列表无 nil_bug。
    /// 即：存量被旧代码导入的数据，重启一次即自愈，无需删库重导。
    @Test func testStaleDataSelfHealsAfterDecode() throws {
        // 1. 正常导入（含本次新增的 addMoveIfNeeded）
        let database = Database(testDatabaseData: DatabaseData())
        let importer = SessionManager.create(from: SessionData(), database: database)
        importer.mainSession.setupDefaultBooksIfNeeded()
        importer.mainSession.loadClassicManualsIfNeeded(force: true)

        // 2. 模拟「旧导入器」遗留状态：清空所有 fenObject.moves（旧代码不填该数组）
        let snapshot = database.databaseData
        for (_, fen) in snapshot.fenObjects2 { fen.moves = [] }

        // 3. 存盘往返：编码 → 解码（解码 init 内会调用 rebuildIndexes 重建 moves）
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(DatabaseData.self, from: data)
        let restoredDB = Database(testDatabaseData: restored)
        let sessionManager = SessionManager.create(from: SessionData(), database: restoredDB)

        // 4. 重启后加载，招法列表不应有 nil_bug
        let view = DatabaseView.full(database: restoredDB)
        let mhp = try #require(view.getBookObjectUnfiltered(Session.meihuapuBookId))
        let gameId = try #require(mhp.gameIds.first)
        sessionManager.loadGame(gameId)
        let path = sessionManager.mainSession.sessionData.currentGame2
        let items = GameOperations.formatMoveList(
            currentGame: path,
            databaseView: sessionManager.mainSession.databaseView,
            isHorizontalFlipped: false
        )
        let nilBugCount = items.filter { $0.notation == "nil_bug" }.count
        #expect(nilBugCount == 0, "重启解码后仍有 \(nilBugCount) 个 nil_bug（路径长 \(path.count)）")
    }
}
