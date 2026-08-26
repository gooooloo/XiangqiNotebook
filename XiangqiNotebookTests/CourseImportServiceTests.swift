import Foundation
import Testing
@testable import XiangqiNotebook

struct CourseImportServiceTests {

    /// 造一个含「课程/李享堃/半途列炮」棋书树的测试数据库
    private func makeCourseDatabase() -> (Database, DatabaseView, UUID) {
        let database = Database(testDatabaseData: DatabaseData())
        let databaseView = DatabaseView.full(database: database)
        let courseBook = BookObject(id: Session.courseBookId, name: "课程")
        database.databaseData.bookObjects[Session.courseBookId] = courseBook
        let teacherBookId = databaseView.addBook(name: "李享堃", parentBookId: Session.courseBookId)
        let targetBookId = databaseView.addBook(name: "半途列炮", parentBookId: teacherBookId)
        return (database, databaseView, targetBookId)
    }

    /// 共享 2 步前缀后分叉的两条线路（PGN 坐标）
    private var sharedPrefixLines: [CourseImportService.LineInput] {
        [
            CourseImportService.LineInput(
                startFen: nil,
                moves: ["h7e7", "h0g2", "h9g7", "i0h0"],
                times: [10, 20, 30, 40]),
            CourseImportService.LineInput(
                startFen: nil,
                moves: ["h7e7", "h0g2", "b9c7", "b0c2"],
                times: [10, 20, 50, 60]),
        ]
    }

    @Test func testImportMergesLinesIntoOneGame() throws {
        let (database, databaseView, bookId) = makeCourseDatabase()

        let result = try CourseImportService.importCourseGame(
            bookId: bookId, name: "第2课", lines: sharedPrefixLines, databaseView: databaseView)

        // 一节课一个棋局，moveIds 是去重后的整棵树（2 步共享前缀 + 各 2 步分支）
        let games = databaseView.getGamesInBookUnfiltered(bookId)
        #expect(games.count == 1)
        #expect(result.lineCount == 2)
        #expect(result.moveCount == 6)
        let game = try #require(games.first)
        #expect(game.moveIds.count == 6)
        #expect(game.name == "第2课")

        // 分叉点应有两个后续着法；起点只有一个
        let startFenId = try #require(game.startingFenId)
        #expect(databaseView.moves(from: startFenId).count == 1)
        var fenIds = [startFenId]
        var current = startFenId
        for _ in 0..<2 {
            let moves = databaseView.moves(from: current)
            current = try #require(moves.first?.targetFenId)
            fenIds.append(current)
        }
        #expect(databaseView.moves(from: current).count == 2)

        // 时间戳按首次出现取最小值：共享前缀第 2 步 = 20 秒
        #expect(result.fenTimestamps[current] == 20)
        _ = database
    }

    @Test func testDuplicateNameRejected() throws {
        let (_, databaseView, bookId) = makeCourseDatabase()
        _ = try CourseImportService.importCourseGame(
            bookId: bookId, name: "第2课", lines: sharedPrefixLines, databaseView: databaseView)
        #expect(throws: CourseImportService.ImportError.duplicateName("第2课")) {
            try CourseImportService.importCourseGame(
                bookId: bookId, name: "第2课", lines: sharedPrefixLines, databaseView: databaseView)
        }
    }

    @Test func testSharedPositionsMergeAcrossGames() throws {
        let (database, databaseView, bookId) = makeCourseDatabase()
        _ = try CourseImportService.importCourseGame(
            bookId: bookId, name: "第2课", lines: sharedPrefixLines, databaseView: databaseView)
        let fenCountAfterFirst = database.databaseData.fenObjects2.count
        let moveCountAfterFirst = database.databaseData.moveObjects.count

        // 相同着法导入为另一局：局面与着法全部复用，不产生重复对象
        _ = try CourseImportService.importCourseGame(
            bookId: bookId, name: "第3课", lines: sharedPrefixLines, databaseView: databaseView)
        #expect(database.databaseData.fenObjects2.count == fenCountAfterFirst)
        #expect(database.databaseData.moveObjects.count == moveCountAfterFirst)
        #expect(databaseView.getGamesInBookUnfiltered(bookId).count == 2)
    }

    @Test func testEmptyLinesRejected() {
        let (_, databaseView, bookId) = makeCourseDatabase()
        #expect(throws: CourseImportService.ImportError.emptyLines) {
            try CourseImportService.importCourseGame(
                bookId: bookId, name: "空课", lines: [], databaseView: databaseView)
        }
    }

    @Test func testResolveCourseBook() throws {
        let (_, databaseView, bookId) = makeCourseDatabase()
        let resolved = try CourseImportService.resolveCourseBook(
            path: ["李享堃", "半途列炮"], databaseView: databaseView)
        #expect(resolved == bookId)
        #expect(throws: CourseImportService.ImportError.bookNotFound("课程/不存在")) {
            try CourseImportService.resolveCourseBook(path: ["不存在"], databaseView: databaseView)
        }
    }
}
