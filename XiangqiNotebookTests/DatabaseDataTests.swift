import Testing
import Foundation
@testable import XiangqiNotebook

struct DatabaseDataTests {

    // MARK: - Initialization Tests

    @Test func testDefaultInitialization() {
        let db = DatabaseData()

        #expect(db.fenObjects2.isEmpty)
        #expect(db.fenToId.isEmpty)
        #expect(db.moveObjects.isEmpty)
        #expect(db.moveToId.isEmpty)
        #expect(db.gameObjects.isEmpty)
        #expect(db.bookObjects.isEmpty)
        #expect(db.bookmarks.isEmpty)
        #expect(db.reviewItems.isEmpty)
        #expect(db.myRealRedGameStatisticsByFenId.isEmpty)
        #expect(db.myRealBlackGameStatisticsByFenId.isEmpty)
        #expect(db.dataVersion == 0)
    }

    // MARK: - rebuildIndexes Tests

    @Test func testRebuildIndexes_RebuildsFenToId() {
        let db = DatabaseData()
        let fen1 = FenObject(fen: "fen_a", fenId: 1)
        let fen2 = FenObject(fen: "fen_b", fenId: 2)
        db.fenObjects2[1] = fen1
        db.fenObjects2[2] = fen2

        // 手动清空 fenToId
        db.fenToId = [:]

        db.rebuildIndexes()

        #expect(db.fenToId["fen_a"] == 1)
        #expect(db.fenToId["fen_b"] == 2)
    }

    @Test func testRebuildIndexes_RebuildsMoveToId() {
        let db = DatabaseData()

        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        let move2 = Move(sourceFenId: 2, targetFenId: 3)
        db.moveObjects[10] = move1
        db.moveObjects[20] = move2

        // 手动清空 moveToId
        db.moveToId = [:]

        db.rebuildIndexes()

        #expect(db.moveToId[[1, 2]] == 10)
        #expect(db.moveToId[[2, 3]] == 20)
    }

    @Test func testRebuildIndexes_RebuildsFenObjectFenId() {
        let db = DatabaseData()
        let fen = FenObject(fen: "test_fen", fenId: 99)
        fen.fenId = nil  // 模拟 fenId 丢失
        db.fenObjects2[42] = fen

        db.rebuildIndexes()

        #expect(db.fenObjects2[42]?.fenId == 42)
    }

    @Test func testRebuildIndexes_RebuildsFenObjectMoves() {
        let db = DatabaseData()

        let fen1 = FenObject(fen: "fen1", fenId: 1)
        let fen2 = FenObject(fen: "fen2", fenId: 2)
        db.fenObjects2[1] = fen1
        db.fenObjects2[2] = fen2

        let move = Move(sourceFenId: 1, targetFenId: 2)
        db.moveObjects[1] = move

        // 清空 fen1 的 moves
        _ = fen1.moves.count  // 确保 moves 数组是空的

        db.rebuildIndexes()

        // 重建后 fen1 应该有 moves
        #expect(db.fenObjects2[1]?.moves.isEmpty == false)
        #expect(db.fenObjects2[1]?.moves.first?.targetFenId == 2)
    }

    @Test func testRebuildIndexes_IgnoresMoveWithNilTarget() {
        let db = DatabaseData()

        let fen1 = FenObject(fen: "fen1", fenId: 1)
        db.fenObjects2[1] = fen1

        let move = Move(sourceFenId: 1, targetFenId: nil)  // targetFenId 为 nil
        db.moveObjects[1] = move

        db.rebuildIndexes()

        // 不应该把 nil target 的 move 加到 fenObject.moves 中
        #expect(db.fenObjects2[1]?.moves.isEmpty == true)
    }

    @Test func testRebuildIndexes_NilTargetMoveNotInMoveToId() {
        let db = DatabaseData()

        let move = Move(sourceFenId: 1, targetFenId: nil)
        db.moveObjects[1] = move
        db.moveToId = [:]

        db.rebuildIndexes()

        // nil target 的 move 不应被加入 moveToId
        #expect(db.moveToId.isEmpty)
    }

    // MARK: - Serialization Tests

    @Test func testDatabaseDataEncodeDecodeRoundTrip() throws {
        let db = DatabaseData()
        db.dataVersion = 42

        // 添加 FenObject
        let fen = FenObject(fen: "test_fen", fenId: 1)
        fen.score = 100
        db.fenObjects2[1] = fen
        db.fenToId["test_fen"] = 1

        // 添加 Move
        let move = Move(sourceFenId: 1, targetFenId: 2)
        move.comment = "好棋"
        db.moveObjects[1] = move
        db.moveToId[[1, 2]] = 1

        let encoder = JSONEncoder()
        let data = try encoder.encode(db)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DatabaseData.self, from: data)

        #expect(decoded.dataVersion == 42)
        #expect(decoded.fenObjects2[1]?.score == 100)
        #expect(decoded.moveObjects[1]?.comment == "好棋")
        // fenToId 和 moveToId 是重建的
        #expect(decoded.fenToId["test_fen"] == 1)
        #expect(decoded.moveToId[[1, 2]] == 1)
    }

    @Test func testDatabaseDataDecoding_EmptyData() throws {
        let json = """
        {
            "fenObjects2": {},
            "MoveObjects": {},
            "game_objects": [],
            "book_objects": [],
            "bookmarks": [],
            "my_real_red_game_statistics_by_fen_id": {},
            "my_real_black_game_statistics_by_fen_id": {},
            "data_version": 5
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DatabaseData.self, from: data)

        #expect(decoded.fenObjects2.isEmpty)
        #expect(decoded.moveObjects.isEmpty)
        #expect(decoded.dataVersion == 5)
        #expect(decoded.reviewItems.isEmpty)  // 默认空
    }

    @Test func testDatabaseDataDecoding_WithStatistics() throws {
        let db = DatabaseData()

        // 添加实战统计
        let stats = GameResultStatistics()
        stats.redWin = 3
        stats.blackWin = 1
        db.myRealRedGameStatisticsByFenId[1] = stats

        let data = try JSONEncoder().encode(db)
        let decoded = try JSONDecoder().decode(DatabaseData.self, from: data)

        let decodedStats = decoded.myRealRedGameStatisticsByFenId[1]
        #expect(decodedStats?.redWin == 3)
        #expect(decodedStats?.blackWin == 1)
    }

    @Test func testDatabaseDataDecoding_WithBookmarks() throws {
        let db = DatabaseData()
        db.bookmarks[[1, 2, 3]] = "起始变例"
        db.bookmarks[[1, 4]] = "另一变例"

        let data = try JSONEncoder().encode(db)
        let decoded = try JSONDecoder().decode(DatabaseData.self, from: data)

        #expect(decoded.bookmarks[[1, 2, 3]] == "起始变例")
        #expect(decoded.bookmarks[[1, 4]] == "另一变例")
    }

    // MARK: - BookObject Tests

    @Test func testBookObjectInitialization() {
        let id = UUID()
        let book = BookObject(id: id, name: "象棋基础开局")

        #expect(book.id == id)
        #expect(book.name == "象棋基础开局")
        #expect(book.gameIds.isEmpty)
        #expect(book.subBookIds.isEmpty)
        #expect(book.author == "")
    }

    @Test func testBookObjectCodable() throws {
        let id = UUID()
        let book = BookObject(id: id, name: "测试书")
        book.author = "作者名"
        let gameId = UUID()
        book.gameIds.append(gameId)
        let subBookId = UUID()
        book.subBookIds.append(subBookId)

        let db = DatabaseData()
        db.bookObjects[id] = book

        let data = try JSONEncoder().encode(db)
        let decoded = try JSONDecoder().decode(DatabaseData.self, from: data)

        let decodedBook = decoded.bookObjects[id]
        #expect(decodedBook?.name == "测试书")
        #expect(decodedBook?.author == "作者名")
        #expect(decodedBook?.gameIds.contains(gameId) == true)
        #expect(decodedBook?.subBookIds.contains(subBookId) == true)
    }
}
