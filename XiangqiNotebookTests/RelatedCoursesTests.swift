import Testing
import Foundation
@testable import XiangqiNotebook

/// RelatedCourses 功能单元测试
/// 测试 DatabaseView.gameContainsFenId, DatabaseView.getGamesInBookRecursivelyUnfiltered, 和 Session.relatedCoursesForCurrentFen
struct RelatedCoursesTests {

    // MARK: - Helper Methods

    /// 创建测试用的数据库
    private func createTestDatabase() -> Database {
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        // 创建测试局面：fenId 1-5
        for i in 1...5 {
            let fenObject = FenObject(fen: "fen\(i)", fenId: i)
            database.databaseData.fenObjects2[i] = fenObject
            database.databaseData.fenToId["fen\(i)"] = i
        }

        // 创建一些测试着法
        // Move 1: 1 -> 2
        let move1 = Move(sourceFenId: 1, targetFenId: 2)
        database.databaseData.moveObjects[1] = move1
        database.databaseData.moveToId[[1, 2]] = 1

        // Move 2: 2 -> 3
        let move2 = Move(sourceFenId: 2, targetFenId: 3)
        database.databaseData.moveObjects[2] = move2
        database.databaseData.moveToId[[2, 3]] = 2

        // Move 3: 3 -> 4
        let move3 = Move(sourceFenId: 3, targetFenId: 4)
        database.databaseData.moveObjects[3] = move3
        database.databaseData.moveToId[[3, 4]] = 3

        return database
    }

    /// 创建一个测试游戏
    private func createTestGame(id: UUID, name: String, startingFenId: Int?, moveIds: [Int], in database: Database) -> GameObject {
        let game = GameObject(id: id)
        game.name = name
        game.startingFenId = startingFenId
        game.moveIds = moveIds
        database.databaseData.gameObjects[id] = game
        return game
    }

    /// 创建一个测试书籍
    private func createTestBook(id: UUID, name: String, gameIds: [UUID], subBookIds: [UUID], in database: Database) -> BookObject {
        let book = BookObject(id: id, name: name)
        book.gameIds = gameIds
        book.subBookIds = subBookIds
        database.databaseData.bookObjects[id] = book
        return book
    }

    /// 创建测试用的 Session
    private func createTestSession(database: Database) throws -> Session {
        let sessionData = SessionData()
        let databaseView = DatabaseView.full(database: database)
        return try Session(sessionData: sessionData, databaseView: databaseView)
    }

    // MARK: - Session.gameContainsFenId Tests

    @Test func testGameContainsFenId_matchingStartingFen() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let gameId = UUID()
        let game = createTestGame(id: gameId, name: "Test Game", startingFenId: 1, moveIds: [], in: database)

        // 游戏的起始局面是 fenId 1
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 1) == true)

        // 其他局面不在游戏中
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 2) == false)
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 3) == false)
    }

    @Test func testGameContainsFenId_matchingInMoves() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let gameId = UUID()
        // 游戏包含着法 1 (1->2) 和着法 2 (2->3)
        let game = createTestGame(id: gameId, name: "Test Game", startingFenId: nil, moveIds: [1, 2], in: database)

        // fenId 1, 2, 3 都在游戏中（作为着法的源或目标）
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 1) == true)
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 2) == true)
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 3) == true)

        // fenId 4 不在游戏中
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 4) == false)
    }

    @Test func testGameContainsFenId_noMatch() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let gameId = UUID()
        // 游戏只包含起始局面 fenId 1
        let game = createTestGame(id: gameId, name: "Test Game", startingFenId: 1, moveIds: [], in: database)

        // fenId 5 不在游戏中
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 5) == false)
    }

    @Test func testGameContainsFenId_withInvalidMoveId() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let gameId = UUID()
        // 游戏包含一个不存在的着法 ID
        let game = createTestGame(id: gameId, name: "Test Game", startingFenId: 1, moveIds: [999], in: database)

        // 应该跳过无效的 moveId，只检查起始局面
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 1) == true)
        #expect(session.databaseView.gameContainsFenId(gameId: game.id, fenId: 2) == false)
    }

    // MARK: - DatabaseView.getGamesInBookRecursivelyUnfiltered Tests

    @Test func testGetAllGamesFromBook_singleLevel() {
        let database = createTestDatabase()
        let databaseView = DatabaseView.full(database: database)

        // 创建一个书籍，包含两个游戏
        let game1Id = UUID()
        let game2Id = UUID()
        createTestGame(id: game1Id, name: "Game 1", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game2Id, name: "Game 2", startingFenId: 2, moveIds: [], in: database)

        let bookId = UUID()
        createTestBook(id: bookId, name: "Test Book", gameIds: [game1Id, game2Id], subBookIds: [], in: database)

        // 获取书籍中的所有游戏
        let games = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: bookId)

        #expect(games.count == 2)
        #expect(games.contains { $0.id == game1Id })
        #expect(games.contains { $0.id == game2Id })
    }

    @Test func testGetAllGamesFromBook_recursive() {
        let database = createTestDatabase()
        let databaseView = DatabaseView.full(database: database)

        // 创建游戏
        let game1Id = UUID()
        let game2Id = UUID()
        let game3Id = UUID()
        createTestGame(id: game1Id, name: "Game 1", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game2Id, name: "Game 2", startingFenId: 2, moveIds: [], in: database)
        createTestGame(id: game3Id, name: "Game 3", startingFenId: 3, moveIds: [], in: database)

        // 创建子书籍
        let subBookId = UUID()
        createTestBook(id: subBookId, name: "Sub Book", gameIds: [game2Id, game3Id], subBookIds: [], in: database)

        // 创建父书籍
        let parentBookId = UUID()
        createTestBook(id: parentBookId, name: "Parent Book", gameIds: [game1Id], subBookIds: [subBookId], in: database)

        // 获取父书籍中的所有游戏（应该包括子书籍的游戏）
        let games = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: parentBookId)

        #expect(games.count == 3)
        #expect(games.contains { $0.id == game1Id })
        #expect(games.contains { $0.id == game2Id })
        #expect(games.contains { $0.id == game3Id })
    }

    @Test func testGetAllGamesFromBook_emptyBook() {
        let database = createTestDatabase()
        let databaseView = DatabaseView.full(database: database)

        // 创建一个空书籍
        let bookId = UUID()
        createTestBook(id: bookId, name: "Empty Book", gameIds: [], subBookIds: [], in: database)

        // 获取书籍中的所有游戏
        let games = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: bookId)

        #expect(games.isEmpty)
    }

    @Test func testGetAllGamesFromBook_nonExistentBook() {
        let database = createTestDatabase()
        let databaseView = DatabaseView.full(database: database)

        // 获取不存在的书籍中的游戏
        let games = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: UUID())

        #expect(games.isEmpty)
    }

    @Test func testGetAllGamesFromBook_circularReference() {
        let database = createTestDatabase()
        let databaseView = DatabaseView.full(database: database)

        // 创建游戏
        let game1Id = UUID()
        createTestGame(id: game1Id, name: "Game 1", startingFenId: 1, moveIds: [], in: database)

        // 创建循环引用的书籍
        let book1Id = UUID()
        let book2Id = UUID()

        // book1 包含 book2 作为子书籍
        let book1 = createTestBook(id: book1Id, name: "Book 1", gameIds: [game1Id], subBookIds: [book2Id], in: database)

        // book2 包含 book1 作为子书籍（循环引用）
        let book2 = createTestBook(id: book2Id, name: "Book 2", gameIds: [], subBookIds: [book1Id], in: database)

        // 应该能够处理循环引用，不会陷入无限循环
        let games = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: book1Id)

        // 只返回 game1，不会重复
        #expect(games.count == 1)
        #expect(games.first?.id == game1Id)
    }

    @Test func testGetAllGamesFromBook_deepNesting() {
        let database = createTestDatabase()
        let databaseView = DatabaseView.full(database: database)

        // 创建深层嵌套的书籍结构
        let game1Id = UUID()
        let game2Id = UUID()
        let game3Id = UUID()
        createTestGame(id: game1Id, name: "Game 1", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game2Id, name: "Game 2", startingFenId: 2, moveIds: [], in: database)
        createTestGame(id: game3Id, name: "Game 3", startingFenId: 3, moveIds: [], in: database)

        // 第三层
        let book3Id = UUID()
        createTestBook(id: book3Id, name: "Book 3", gameIds: [game3Id], subBookIds: [], in: database)

        // 第二层
        let book2Id = UUID()
        createTestBook(id: book2Id, name: "Book 2", gameIds: [game2Id], subBookIds: [book3Id], in: database)

        // 第一层
        let book1Id = UUID()
        createTestBook(id: book1Id, name: "Book 1", gameIds: [game1Id], subBookIds: [book2Id], in: database)

        // 获取所有游戏
        let games = databaseView.getGamesInBookRecursivelyUnfiltered(bookId: book1Id)

        #expect(games.count == 3)
        #expect(games.contains { $0.id == game1Id })
        #expect(games.contains { $0.id == game2Id })
        #expect(games.contains { $0.id == game3Id })
    }

    // MARK: - Integration Tests (ViewModel.relatedCoursesForCurrentFen)

    // 注意：由于 ViewModel 需要 PlatformService 和复杂的初始化，
    // 这里我们只测试底层方法的集成。实际的 ViewModel 测试应该在 UI 层进行。

    @Test func testRelatedCoursesIntegration_withCourseBook() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        // 创建游戏
        let game1Id = UUID()
        let game2Id = UUID()
        let game3Id = UUID()

        // game1 包含 fenId 1 和 2
        createTestGame(id: game1Id, name: "Course 1", startingFenId: 1, moveIds: [1], in: database)

        // game2 包含 fenId 3 和 4
        createTestGame(id: game2Id, name: "Course 2", startingFenId: 3, moveIds: [3], in: database)

        // game3 不包含 fenId 1
        createTestGame(id: game3Id, name: "Course 3", startingFenId: 5, moveIds: [], in: database)

        // 创建"课程"书籍
        let courseBookId = UUID()
        createTestBook(id: courseBookId, name: "课程", gameIds: [game1Id, game2Id, game3Id], subBookIds: [], in: database)

        // 测试 fenId 1 的相关课程
        let allGames = session.databaseView.getGamesInBookRecursivelyUnfiltered(bookId: courseBookId)
        let relatedGames = allGames.filter { game in
            session.databaseView.gameContainsFenId(gameId: game.id, fenId: 1)
        }

        #expect(relatedGames.count == 1)
        #expect(relatedGames.first?.id == game1Id)
    }

    @Test func testRelatedCoursesIntegration_noCourseBook() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        // 没有创建"课程"书籍

        // 查找"课程"书籍应该返回 nil
        let courseBook = session.databaseView.getAllBookObjectsUnfiltered().first { $0.name == "课程" }
        #expect(courseBook == nil)
    }

    @Test func testRelatedCoursesIntegration_withSubBooks() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        // 创建游戏
        let game1Id = UUID()
        let game2Id = UUID()

        // game1 包含 fenId 1
        createTestGame(id: game1Id, name: "Course 1", startingFenId: 1, moveIds: [], in: database)

        // game2 包含 fenId 1
        createTestGame(id: game2Id, name: "Course 2", startingFenId: 1, moveIds: [1], in: database)

        // 创建子书籍
        let subBookId = UUID()
        createTestBook(id: subBookId, name: "子课程", gameIds: [game2Id], subBookIds: [], in: database)

        // 创建"课程"书籍
        let courseBookId = UUID()
        createTestBook(id: courseBookId, name: "课程", gameIds: [game1Id], subBookIds: [subBookId], in: database)

        // 测试 fenId 1 的相关课程（应该包括子书籍的游戏）
        let allGames = session.databaseView.getGamesInBookRecursivelyUnfiltered(bookId: courseBookId)
        let relatedGames = allGames.filter { game in
            session.databaseView.gameContainsFenId(gameId: game.id, fenId: 1)
        }

        #expect(relatedGames.count == 2)
        #expect(relatedGames.contains { $0.id == game1Id })
        #expect(relatedGames.contains { $0.id == game2Id })
    }

    @Test func testRelatedCoursesIntegration_noMatchingGames() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        // 创建游戏（都不包含 fenId 5）
        let game1Id = UUID()
        let game2Id = UUID()
        createTestGame(id: game1Id, name: "Course 1", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game2Id, name: "Course 2", startingFenId: 2, moveIds: [], in: database)

        // 创建"课程"书籍
        let courseBookId = UUID()
        createTestBook(id: courseBookId, name: "课程", gameIds: [game1Id, game2Id], subBookIds: [], in: database)

        // 测试 fenId 5 的相关课程（应该返回空数组）
        let allGames = session.databaseView.getGamesInBookRecursivelyUnfiltered(bookId: courseBookId)
        let relatedGames = allGames.filter { game in
            session.databaseView.gameContainsFenId(gameId: game.id, fenId: 5)
        }

        #expect(relatedGames.isEmpty)
    }
}
