import Testing
import Foundation
@testable import XiangqiNotebook

/// RelatedRealGames 功能单元测试
/// 测试 Session.relatedRealGamesForCurrentFen 的正确性
struct RelatedRealGamesTests {

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
    @discardableResult
    private func createTestGame(id: UUID, name: String, startingFenId: Int?, moveIds: [Int], gameDate: Date? = nil, creationDate: Date? = nil, in database: Database) -> GameObject {
        let game = GameObject(id: id)
        game.name = name
        game.startingFenId = startingFenId
        game.moveIds = moveIds
        game.gameDate = gameDate
        game.creationDate = creationDate
        database.databaseData.gameObjects[id] = game
        return game
    }

    /// 创建一个测试书籍
    @discardableResult
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

    // MARK: - Index-based Tests

    @Test func testBuildRealGamesIndex_correctMapping() throws {
        let database = createTestDatabase()

        let game1Id = UUID()
        let game2Id = UUID()

        // game1: startingFenId=1, moves [1] (1->2)
        createTestGame(id: game1Id, name: "实战1", startingFenId: 1, moveIds: [1], in: database)
        // game2: startingFenId=3, moves [3] (3->4)
        createTestGame(id: game2Id, name: "实战2", startingFenId: 3, moveIds: [3], in: database)

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [game1Id, game2Id], subBookIds: [], in: database)

        database.buildRealGamesIndex()
        #expect(database.isRealGamesIndexReady == true)

        // fenId 1 -> game1 (startingFenId + move source)
        #expect(database.realGamesByFenId[1]?.contains(game1Id) == true)
        #expect(database.realGamesByFenId[1]?.contains(game2Id) != true)

        // fenId 2 -> game1 (move target)
        #expect(database.realGamesByFenId[2]?.contains(game1Id) == true)

        // fenId 3 -> game2 (startingFenId + move source)
        #expect(database.realGamesByFenId[3]?.contains(game2Id) == true)

        // fenId 4 -> game2 (move target)
        #expect(database.realGamesByFenId[4]?.contains(game2Id) == true)

        // fenId 5 -> no games
        #expect(database.realGamesByFenId[5] == nil)
    }

    @Test func testBuildRealGamesIndex_withSubBooks() throws {
        let database = createTestDatabase()

        let game1Id = UUID()
        let game2Id = UUID()

        createTestGame(id: game1Id, name: "实战1", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game2Id, name: "实战2", startingFenId: 1, moveIds: [], in: database)

        let subBookId = UUID()
        createTestBook(id: subBookId, name: "子书籍", gameIds: [game2Id], subBookIds: [], in: database)
        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [game1Id], subBookIds: [subBookId], in: database)

        database.buildRealGamesIndex()

        // fenId 1 should contain both games (from root and sub-book)
        #expect(database.realGamesByFenId[1]?.count == 2)
        #expect(database.realGamesByFenId[1]?.contains(game1Id) == true)
        #expect(database.realGamesByFenId[1]?.contains(game2Id) == true)
    }

    @Test func testInvalidateRealGamesIndex() throws {
        let database = createTestDatabase()
        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [], subBookIds: [], in: database)

        database.buildRealGamesIndex()
        #expect(database.isRealGamesIndexReady == true)

        database.invalidateRealGamesIndex()
        #expect(database.isRealGamesIndexReady == false)
    }

    @Test func testIndexedAndFallbackResultsConsistent() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let game1Id = UUID()
        let game2Id = UUID()

        createTestGame(id: game1Id, name: "实战1", startingFenId: 1, moveIds: [1], in: database)
        createTestGame(id: game2Id, name: "实战2", startingFenId: 3, moveIds: [], in: database)

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [game1Id, game2Id], subBookIds: [], in: database)

        // Fallback path (no index)
        #expect(database.isRealGamesIndexReady == false)
        let fallbackResult = session.relatedRealGamesForCurrentFen
        let fallbackIds = Set(fallbackResult.map { $0.id })

        // Clear cache by toggling dataChanged
        session.dataChanged.toggle()

        // Index path
        database.buildRealGamesIndex()
        let indexedResult = session.relatedRealGamesForCurrentFen
        let indexedIds = Set(indexedResult.map { $0.id })

        #expect(fallbackIds == indexedIds)
    }

    // MARK: - relatedRealGamesForCurrentFen Tests

    @Test func testRelatedRealGames_withMatchingGames() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let game1Id = UUID()
        let game2Id = UUID()

        // game1 包含 fenId 1 (通过 startingFenId)
        createTestGame(id: game1Id, name: "实战1", startingFenId: 1, moveIds: [], in: database)

        // game2 包含 fenId 1 和 2 (通过 moveIds)
        createTestGame(id: game2Id, name: "实战2", startingFenId: nil, moveIds: [1], in: database)

        // 创建"我的实战"书籍
        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [game1Id, game2Id], subBookIds: [], in: database)

        // 当前局面是 fenId 1（默认），应返回两个匹配的游戏
        let result = session.relatedRealGamesForCurrentFen
        #expect(result.count == 2)
        #expect(result.contains { $0.id == game1Id })
        #expect(result.contains { $0.id == game2Id })
        #expect(session.hasMoreRelatedRealGames == false)
    }

    @Test func testRelatedRealGames_noRealGameBook() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        // 不创建"我的实战"书籍
        let result = session.relatedRealGamesForCurrentFen
        #expect(result.isEmpty)
        #expect(session.hasMoreRelatedRealGames == false)
    }

    @Test func testRelatedRealGames_emptyBook() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        // 创建空的"我的实战"书籍
        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [], subBookIds: [], in: database)

        let result = session.relatedRealGamesForCurrentFen
        #expect(result.isEmpty)
        #expect(session.hasMoreRelatedRealGames == false)
    }

    @Test func testRelatedRealGames_noSorting() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let game1Id = UUID()
        let game2Id = UUID()
        let game3Id = UUID()

        // 所有游戏都包含 fenId 1
        createTestGame(id: game1Id, name: "实战1", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game2Id, name: "实战2", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game3Id, name: "实战3", startingFenId: 1, moveIds: [], in: database)

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [game1Id, game2Id, game3Id], subBookIds: [], in: database)

        let result = session.relatedRealGamesForCurrentFen

        #expect(result.count == 3)
        // 不再要求排序，只验证所有匹配的游戏都被返回
        #expect(result.contains { $0.id == game1Id })
        #expect(result.contains { $0.id == game2Id })
        #expect(result.contains { $0.id == game3Id })
    }

    @Test func testRelatedRealGames_nonMatchingGamesFiltered() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let game1Id = UUID()
        let game2Id = UUID()

        // game1 包含 fenId 1
        createTestGame(id: game1Id, name: "实战1", startingFenId: 1, moveIds: [], in: database)

        // game2 只包含 fenId 5，不包含 fenId 1
        createTestGame(id: game2Id, name: "实战2", startingFenId: 5, moveIds: [], in: database)

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [game1Id, game2Id], subBookIds: [], in: database)

        let result = session.relatedRealGamesForCurrentFen

        #expect(result.count == 1)
        #expect(result[0].id == game1Id)
        #expect(session.hasMoreRelatedRealGames == false)
    }

    @Test func testRelatedRealGames_withSubBooks() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        let game1Id = UUID()
        let game2Id = UUID()

        // 两个游戏都包含 fenId 1
        createTestGame(id: game1Id, name: "实战1", startingFenId: 1, moveIds: [], in: database)
        createTestGame(id: game2Id, name: "实战2", startingFenId: 1, moveIds: [], in: database)

        // game2 在子书籍中
        let subBookId = UUID()
        createTestBook(id: subBookId, name: "红方实战", gameIds: [game2Id], subBookIds: [], in: database)

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: [game1Id], subBookIds: [subBookId], in: database)

        let result = session.relatedRealGamesForCurrentFen

        #expect(result.count == 2)
        #expect(result.contains { $0.id == game1Id })
        #expect(result.contains { $0.id == game2Id })
        #expect(session.hasMoreRelatedRealGames == false)
    }

    // MARK: - 限制5个 + hasMore 测试

    @Test func testRelatedRealGames_maxFiveGames() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        var gameIds: [UUID] = []
        // 创建7个匹配 fenId 1 的游戏
        for i in 1...7 {
            let gameId = UUID()
            gameIds.append(gameId)
            createTestGame(id: gameId, name: "实战\(i)", startingFenId: 1, moveIds: [], in: database)
        }

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: gameIds, subBookIds: [], in: database)

        let result = session.relatedRealGamesForCurrentFen
        #expect(result.count == 5)
        #expect(session.hasMoreRelatedRealGames == true)
    }

    @Test func testRelatedRealGames_exactlyFiveGames() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        var gameIds: [UUID] = []
        // 创建刚好5个匹配的游戏
        for i in 1...5 {
            let gameId = UUID()
            gameIds.append(gameId)
            createTestGame(id: gameId, name: "实战\(i)", startingFenId: 1, moveIds: [], in: database)
        }

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: gameIds, subBookIds: [], in: database)

        let result = session.relatedRealGamesForCurrentFen
        #expect(result.count == 5)
        #expect(session.hasMoreRelatedRealGames == false)
    }

    @Test func testRelatedRealGames_sixGamesHasMore() throws {
        let database = createTestDatabase()
        let session = try createTestSession(database: database)

        var gameIds: [UUID] = []
        // 创建刚好6个匹配的游戏
        for i in 1...6 {
            let gameId = UUID()
            gameIds.append(gameId)
            createTestGame(id: gameId, name: "实战\(i)", startingFenId: 1, moveIds: [], in: database)
        }

        createTestBook(id: Session.myRealGameBookId, name: "我的实战", gameIds: gameIds, subBookIds: [], in: database)

        let result = session.relatedRealGamesForCurrentFen
        #expect(result.count == 5)
        #expect(session.hasMoreRelatedRealGames == true)
    }
}
