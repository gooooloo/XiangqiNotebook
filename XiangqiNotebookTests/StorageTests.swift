import Testing
import Foundation
@testable import XiangqiNotebook

struct StorageTests {

    // MARK: - DatabaseStorage: isICloudURL Tests

    @Test func testIsICloudURL_WithMobileDocuments_ReturnsTrue() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/iCloud~XiangqiNotebook/database.json")
        #expect(DatabaseStorage.isICloudURL(url) == true)
    }

    @Test func testIsICloudURL_WithUbiquity_ReturnsTrue() {
        let url = URL(fileURLWithPath: "/private/var/mobile/Library/ubiquity/data.json")
        #expect(DatabaseStorage.isICloudURL(url) == true)
    }

    @Test func testIsICloudURL_WithCloudDocs_ReturnsTrue() {
        let url = URL(string: "file:///path/com~apple~CloudDocs/data.json")!
        #expect(DatabaseStorage.isICloudURL(url) == true)
    }

    @Test func testIsICloudURL_WithLocalPath_ReturnsFalse() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/database.json")
        #expect(DatabaseStorage.isICloudURL(url) == false)
    }

    @Test func testIsICloudURL_WithTmpPath_ReturnsFalse() {
        let url = URL(fileURLWithPath: "/tmp/test/database.json")
        #expect(DatabaseStorage.isICloudURL(url) == false)
    }

    // MARK: - DatabaseStorage: createEmptyDatabase Tests

    @Test func testCreateEmptyDatabase_HasStartingPosition() {
        let db = DatabaseStorage.createEmptyDatabase()
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"

        #expect(db.fenObjects2.count == 1)
        #expect(db.fenObjects2[1]?.fen == startFen)
        #expect(db.fenToId[startFen] == 1)
    }

    @Test func testCreateEmptyDatabase_HasEmptyCollections() {
        let db = DatabaseStorage.createEmptyDatabase()

        #expect(db.moveObjects.isEmpty)
        #expect(db.gameObjects.isEmpty)
        #expect(db.bookObjects.isEmpty)
        #expect(db.bookmarks.isEmpty)
    }

    // MARK: - DatabaseStorage: Backup Save/Load Round-Trip Tests

    @Test func testSaveAndLoadBackup_RoundTrip() throws {
        let db = DatabaseData()
        db.dataVersion = 42
        let fen = FenObject(fen: "test_fen", fenId: 1)
        fen.score = 100
        db.fenObjects2[1] = fen
        db.fenToId["test_fen"] = 1

        let move = Move(sourceFenId: 1, targetFenId: 2)
        move.comment = "测试评论"
        db.moveObjects[1] = move

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
        let backupURL = tmpDir.appendingPathComponent("backup.json")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        try DatabaseStorage.saveDatabaseBackup(db, to: backupURL)
        let loaded = try DatabaseStorage.loadDatabaseBackup(from: backupURL)

        #expect(loaded.dataVersion == 42)
        #expect(loaded.fenObjects2[1]?.fen == "test_fen")
        #expect(loaded.fenObjects2[1]?.score == 100)
        #expect(loaded.moveObjects[1]?.comment == "测试评论")
    }

    @Test func testLoadBackup_NonexistentFile_Throws() {
        let url = URL(fileURLWithPath: "/nonexistent/path/backup.json")

        #expect(throws: (any Error).self) {
            try DatabaseStorage.loadDatabaseBackup(from: url)
        }
    }

    // MARK: - DatabaseStorage: saveDatabaseToURL / loadDatabaseFromURL Tests

    @Test func testSaveDatabaseToURL_CreatesDirectoryIfNeeded() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("dir")
        let dbURL = tmpDir.appendingPathComponent("database.json")

        defer {
            try? FileManager.default.removeItem(at: tmpDir.deletingLastPathComponent().deletingLastPathComponent())
        }

        let db = DatabaseStorage.createEmptyDatabase()
        try DatabaseStorage.saveDatabaseToURL(db, url: dbURL)

        #expect(FileManager.default.fileExists(atPath: dbURL.path))
    }

    @Test func testSaveAndLoadDatabaseFromURL_RoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
        let dbURL = tmpDir.appendingPathComponent("database.json")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let db = DatabaseStorage.createEmptyDatabase()
        db.dataVersion = 55

        try DatabaseStorage.saveDatabaseToURL(db, url: dbURL)
        let loaded = try DatabaseStorage.loadDatabaseFromURL(dbURL)

        #expect(loaded.dataVersion == 55)
        #expect(loaded.fenObjects2.count == 1)
    }

    @Test func testLoadDatabaseFromURL_InvalidJSON_Throws() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
        let dbURL = tmpDir.appendingPathComponent("invalid.json")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        // 写入无效 JSON
        try "{ invalid json }".data(using: .utf8)!.write(to: dbURL)

        #expect(throws: (any Error).self) {
            try DatabaseStorage.loadDatabaseFromURL(dbURL)
        }
    }

    // MARK: - DatabaseStorage: loadDataVersion Tests

    @Test func testLoadDataVersion_FromValidFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
        let dbURL = tmpDir.appendingPathComponent("database.json")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let db = DatabaseStorage.createEmptyDatabase()
        db.dataVersion = 123

        try DatabaseStorage.saveDatabaseToURL(db, url: dbURL)
        let version = try DatabaseStorage.loadDataVersion(from: dbURL)

        #expect(version == 123)
    }

    // MARK: - SessionStorage: Save/Load Round-Trip Tests

    @Test func testSaveAndLoadSession_RoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
        let sessionURL = tmpDir.appendingPathComponent("session.json")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let session = SessionData()
        session.currentGame2 = [1, 2, 3]
        session.currentGameStep = 2
        session.isBlackOrientation = true
        session.filters = [Session.filterRedOpeningOnly]

        try SessionStorage.saveSession(session, to: sessionURL)
        let loaded = try SessionStorage.loadSession(from: sessionURL)

        #expect(loaded.currentGame2 == [1, 2, 3])
        #expect(loaded.currentGameStep == 2)
        #expect(loaded.isBlackOrientation == true)
        #expect(loaded.filters == [Session.filterRedOpeningOnly])
    }

    @Test func testLoadSession_NonexistentFile_Throws() {
        let url = URL(fileURLWithPath: "/nonexistent/path/session.json")

        #expect(throws: (any Error).self) {
            try SessionStorage.loadSession(from: url)
        }
    }

    @Test func testLoadSession_InvalidJSON_Throws() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
        let sessionURL = tmpDir.appendingPathComponent("session.json")

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        try "not valid json".data(using: .utf8)!.write(to: sessionURL)

        #expect(throws: (any Error).self) {
            try SessionStorage.loadSession(from: sessionURL)
        }
    }

    // MARK: - SessionStorage: SessionData Codable Completeness Tests

    @Test func testSessionData_AllFieldsPreserved() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("XiangqiNotebookTests_\(UUID().uuidString)")
        let sessionURL = tmpDir.appendingPathComponent("session.json")

        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let session = SessionData()
        session.currentGame2 = [1, 2]
        session.currentGameStep = 1
        session.lockedStep = 0
        session.filters = ["test_filter"]
        session.isBlackOrientation = true
        session.isHorizontalFlipped = true
        session.gameStepLimitation = 10
        session.canNavigateBeforeLockedStep = true
        session.showPath = false
        session.showAllNextMoves = true
        session.autoExtendGameWhenPlayingBoardFen = false
        session.isCommentEditing = true
        session.focusedPracticeGamePath = [1, 2, 3]
        session.allowAddingNewMoves = false

        try SessionStorage.saveSession(session, to: sessionURL)
        let loaded = try SessionStorage.loadSession(from: sessionURL)

        #expect(loaded.currentGame2 == [1, 2])
        #expect(loaded.currentGameStep == 1)
        #expect(loaded.lockedStep == 0)
        #expect(loaded.filters == ["test_filter"])
        #expect(loaded.isBlackOrientation == true)
        #expect(loaded.isHorizontalFlipped == true)
        #expect(loaded.gameStepLimitation == 10)
        #expect(loaded.canNavigateBeforeLockedStep == true)
        #expect(loaded.showPath == false)
        #expect(loaded.showAllNextMoves == true)
        #expect(loaded.autoExtendGameWhenPlayingBoardFen == false)
        #expect(loaded.isCommentEditing == true)
        #expect(loaded.focusedPracticeGamePath == [1, 2, 3])
        #expect(loaded.allowAddingNewMoves == false)
    }
}
