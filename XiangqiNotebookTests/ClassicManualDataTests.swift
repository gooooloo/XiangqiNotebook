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
}
