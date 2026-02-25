import Testing
import Foundation
@testable import XiangqiNotebook

struct SRSDataTests {

    // MARK: - Initialization

    @Test func testDefaultInitialization() {
        let srs = SRSData()
        #expect(srs.easeFactor == 2.5)
        #expect(srs.interval == 0)
        #expect(srs.repetitions == 0)
        #expect(srs.lastReviewDate == nil)
        #expect(srs.gamePath == nil)
    }

    @Test func testInitializationWithGamePath() {
        let path = [1, 2, 3]
        let srs = SRSData(gamePath: path)
        #expect(srs.gamePath == path)
    }

    // MARK: - SM-2 Algorithm: Failed Reviews

    @Test func testReviewAgainResetsInterval() {
        let srs = SRSData()
        srs.repetitions = 3
        srs.interval = 15
        srs.review(quality: .again)

        #expect(srs.repetitions == 0)
        #expect(srs.interval == 0)
        #expect(srs.lastReviewDate != nil)
    }

    @Test func testReviewHardResetsInterval() {
        let srs = SRSData()
        srs.repetitions = 3
        srs.interval = 15
        srs.review(quality: .hard)

        #expect(srs.repetitions == 0)
        #expect(srs.interval == 0)
    }

    // MARK: - SM-2 Algorithm: Successful Reviews

    @Test func testFirstSuccessfulReviewSetsInterval1() {
        let srs = SRSData()
        srs.review(quality: .good)

        #expect(srs.repetitions == 1)
        #expect(srs.interval == 1)
    }

    @Test func testSecondSuccessfulReviewSetsInterval6() {
        let srs = SRSData()
        srs.review(quality: .good)
        srs.review(quality: .good)

        #expect(srs.repetitions == 2)
        #expect(srs.interval == 6)
    }

    @Test func testThirdSuccessfulReviewUsesEaseFactor() {
        let srs = SRSData()
        srs.review(quality: .easy)
        srs.review(quality: .easy)
        srs.review(quality: .easy)

        #expect(srs.repetitions == 3)
        // interval = round(6 * easeFactor)
        // easeFactor after 3 easy reviews increases from 2.5
        #expect(srs.interval > 6)
    }

    // MARK: - SM-2 Algorithm: Ease Factor

    @Test func testEaseFactorIncreasesWithEasyReviews() {
        let srs = SRSData()
        let initialEF = srs.easeFactor
        srs.review(quality: .easy)
        #expect(srs.easeFactor > initialEF)
    }

    @Test func testEaseFactorDecreasesWithAgainReviews() {
        let srs = SRSData()
        let initialEF = srs.easeFactor
        srs.review(quality: .again)
        #expect(srs.easeFactor < initialEF)
    }

    @Test func testEaseFactorNeverBelowMinimum() {
        let srs = SRSData()
        // Repeatedly fail to push easeFactor down
        for _ in 0..<20 {
            srs.review(quality: .again)
        }
        #expect(srs.easeFactor >= 1.3)
    }

    // MARK: - SM-2 Algorithm: Next Review Date

    @Test func testNextReviewDateAdvancesAfterReview() {
        let srs = SRSData(nextReviewDate: Date())
        let before = srs.nextReviewDate
        srs.review(quality: .good)
        #expect(srs.nextReviewDate > before)
    }

    @Test func testNextReviewDateAfterFailIsOneDayLater() {
        let srs = SRSData()
        srs.review(quality: .again)
        // interval is 0, but nextReviewDate uses max(interval, 1) = 1 day
        let expectedDate = Calendar.current.date(byAdding: .day, value: 1, to: srs.lastReviewDate!)!
        let diff = abs(srs.nextReviewDate.timeIntervalSince(expectedDate))
        #expect(diff < 1.0) // within 1 second tolerance
    }

    // MARK: - SM-2 Algorithm: Reset After Failure

    @Test func testResetAfterFailureThenRecover() {
        let srs = SRSData()
        // Build up progress
        srs.review(quality: .good) // rep 1, interval 1
        srs.review(quality: .good) // rep 2, interval 6
        srs.review(quality: .good) // rep 3, interval > 6

        // Fail
        srs.review(quality: .again)
        #expect(srs.repetitions == 0)
        #expect(srs.interval == 0)

        // Recover
        srs.review(quality: .good) // rep 1, interval 1
        #expect(srs.repetitions == 1)
        #expect(srs.interval == 1)
    }

    // MARK: - isDue

    @Test func testIsDueWhenPastNextReviewDate() {
        let srs = SRSData(nextReviewDate: Date().addingTimeInterval(-3600))
        #expect(srs.isDue == true)
    }

    @Test func testIsNotDueWhenBeforeNextReviewDate() {
        let srs = SRSData(nextReviewDate: Date().addingTimeInterval(3600))
        #expect(srs.isDue == false)
    }

    // MARK: - Codable

    @Test func testEncodeDecode() throws {
        let srs = SRSData(gamePath: [1, 2, 3])
        srs.easeFactor = 2.3
        srs.interval = 6
        srs.repetitions = 2
        srs.lastReviewDate = Date()

        let encoder = JSONEncoder()
        let data = try encoder.encode(srs)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SRSData.self, from: data)

        #expect(decoded.gamePath == [1, 2, 3])
        #expect(decoded.easeFactor == 2.3)
        #expect(decoded.interval == 6)
        #expect(decoded.repetitions == 2)
        #expect(decoded.lastReviewDate != nil)
    }

    @Test func testEncodeDecodeWithNilGamePath() throws {
        let srs = SRSData()

        let encoder = JSONEncoder()
        let data = try encoder.encode(srs)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SRSData.self, from: data)

        #expect(decoded.gamePath == nil)
        #expect(decoded.easeFactor == 2.5)
    }

    // MARK: - DatabaseData Integration

    @Test func testDatabaseDataReviewItemsDefault() {
        let db = DatabaseData()
        #expect(db.reviewItems.isEmpty)
    }

    @Test func testDatabaseDataReviewItemsSerialization() throws {
        let db = DatabaseData()
        let srs = SRSData(gamePath: [1, 2])
        db.reviewItems[42] = srs

        let encoder = JSONEncoder()
        let data = try encoder.encode(db)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DatabaseData.self, from: data)

        #expect(decoded.reviewItems.count == 1)
        #expect(decoded.reviewItems[42]?.gamePath == [1, 2])
    }

    @Test func testDatabaseDataBackwardCompatibility() throws {
        // Simulate old data without reviewItems field
        // Note: [UUID: X] dictionaries encode as JSON arrays, not objects
        let json = """
        {
            "fenObjects2": {},
            "MoveObjects": {},
            "game_objects": [],
            "book_objects": [],
            "bookmarks": [],
            "my_real_red_game_statistics_by_fen_id": {},
            "my_real_black_game_statistics_by_fen_id": {},
            "data_version": 1
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let db = try decoder.decode(DatabaseData.self, from: data)

        #expect(db.reviewItems.isEmpty)
        #expect(db.dataVersion == 1)
    }

    // MARK: - ReviewQuality

    @Test func testReviewQualityRawValues() {
        #expect(ReviewQuality.again.rawValue == 1)
        #expect(ReviewQuality.hard.rawValue == 2)
        #expect(ReviewQuality.good.rawValue == 4)
        #expect(ReviewQuality.easy.rawValue == 5)
    }

    // MARK: - Session Review Item Management

    private func createTestSession() -> Session {
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fen1 = FenObject(fen: startFen, fenId: 1)
        database.databaseData.fenObjects2[1] = fen1
        database.databaseData.fenToId[startFen] = 1

        let fen2 = FenObject(fen: "fen2 - - 1 1", fenId: 2)
        database.databaseData.fenObjects2[2] = fen2
        database.databaseData.fenToId["fen2 - - 1 1"] = 2

        let move1to2 = Move(sourceFenId: 1, targetFenId: 2)
        fen1.addMoveIfNeeded(move: move1to2)
        database.databaseData.moveObjects[1] = move1to2
        database.databaseData.moveToId[[1, 2]] = 1

        let sessionData = SessionData()
        sessionData.currentGame2 = [1, 2]
        sessionData.currentGameStep = 1
        let databaseView = DatabaseView.full(database: database)
        return try! Session(sessionData: sessionData, databaseView: databaseView)
    }

    @Test func testAddCurrentFenToReview() {
        let session = createTestSession()
        #expect(session.isCurrentFenInReview == false)

        session.addCurrentFenToReview()
        #expect(session.isCurrentFenInReview == true)
        #expect(session.reviewItemList.count == 1)
        #expect(session.reviewItemList[0].fenId == 2)
        #expect(session.reviewItemList[0].srsData.gamePath == [1, 2])
    }

    @Test func testDuplicateAddDoesNotCreateDuplicate() {
        let session = createTestSession()
        session.addCurrentFenToReview()
        session.addCurrentFenToReview()
        #expect(session.reviewItemList.count == 1)
    }

    @Test func testRemoveReviewItem() {
        let session = createTestSession()
        session.addCurrentFenToReview()
        #expect(session.isCurrentFenInReview == true)

        session.removeReviewItem(fenId: session.currentFenId)
        #expect(session.isCurrentFenInReview == false)
        #expect(session.reviewItemList.isEmpty)
    }

    @Test func testIsCurrentFenInReviewReflectsState() {
        let session = createTestSession()
        #expect(session.isCurrentFenInReview == false)

        session.addCurrentFenToReview()
        #expect(session.isCurrentFenInReview == true)

        session.removeReviewItem(fenId: session.currentFenId)
        #expect(session.isCurrentFenInReview == false)
    }

    @Test func testReviewItemListSortedByNextReviewDate() {
        let session = createTestSession()

        // Add review item for fenId 2 (current)
        session.addCurrentFenToReview()

        // Manually add another review item with earlier date
        let earlierDate = Date().addingTimeInterval(-7200)
        let srs = SRSData(gamePath: [1], nextReviewDate: earlierDate)
        session.databaseView.updateReviewItem(for: 1, srsData: srs)

        let list = session.reviewItemList
        #expect(list.count == 2)
        // fenId 1 should come first (earlier nextReviewDate)
        #expect(list[0].fenId == 1)
        #expect(list[1].fenId == 2)
    }
}
