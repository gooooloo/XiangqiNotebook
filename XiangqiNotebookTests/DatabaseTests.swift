import Testing
import Foundation
@testable import XiangqiNotebook

struct DatabaseTests {

    // MARK: - 辅助方法

    private func createTestDatabase() -> Database {
        let data = DatabaseData()
        let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 1 1"
        let fenObject = FenObject(fen: startFen, fenId: 1)
        data.fenObjects2[1] = fenObject
        data.fenToId[startFen] = 1
        return Database(testDatabaseData: data)
    }

    // MARK: - markDirty / markClean Tests

    @Test func testInitialState_IsNotDirty() {
        let db = createTestDatabase()
        #expect(db.isDirty == false)
    }

    @Test @MainActor func testMarkDirty_SetsIsDirtyTrue() async {
        let db = createTestDatabase()
        db.markDirty()

        // markDirty 使用 DispatchQueue.main.async，需要等待
        await Task.yield()

        #expect(db.isDirty == true)
    }

    @Test @MainActor func testMarkClean_SetsIsDirtyFalse() async {
        let db = createTestDatabase()

        // 先标记为脏
        db.markDirty()
        await Task.yield()
        #expect(db.isDirty == true)

        // 再标记为干净
        db.markClean()
        await Task.yield()
        #expect(db.isDirty == false)
    }

    @Test @MainActor func testMarkDirty_IncrementsDataVersion() async {
        let db = createTestDatabase()
        let initialVersion = db.databaseData.dataVersion

        db.markDirty()
        await Task.yield()

        #expect(db.databaseData.dataVersion == initialVersion + 1)
    }

    @Test @MainActor func testMarkDirty_CalledTwice_OnlyIncrementsOnce() async {
        let db = createTestDatabase()
        let initialVersion = db.databaseData.dataVersion

        // markDirty 有 guard !isDirty 保护，第二次不会执行
        db.markDirty()
        await Task.yield()
        db.markDirty()
        await Task.yield()

        #expect(db.databaseData.dataVersion == initialVersion + 1)
    }

    // MARK: - Engine Score Tests

    @Test func testEngineScore_SetAndGet() {
        let db = createTestDatabase()
        db.setEngineScore(fenId: 1, engineKey: "testEngine_d20", score: 150)

        let score = db.getEngineScore(fenId: 1, engineKey: "testEngine_d20")
        #expect(score == 150)
    }

    @Test func testEngineScore_GetNonexistent_ReturnsNil() {
        let db = createTestDatabase()

        let score = db.getEngineScore(fenId: 999, engineKey: "nonexistent")
        #expect(score == nil)
    }

    @Test func testEngineScore_MultipleEngines() {
        let db = createTestDatabase()
        db.setEngineScore(fenId: 1, engineKey: "engineA", score: 100)
        db.setEngineScore(fenId: 1, engineKey: "engineB", score: -50)

        #expect(db.getEngineScore(fenId: 1, engineKey: "engineA") == 100)
        #expect(db.getEngineScore(fenId: 1, engineKey: "engineB") == -50)
    }

    @Test func testActiveEngineScore_WithNoActiveKey_ReturnsNil() {
        let db = createTestDatabase()
        db.setEngineScore(fenId: 1, engineKey: "someEngine", score: 200)

        // activeEngineKey 默认为 nil
        #expect(db.activeEngineKey == nil)
        #expect(db.getActiveEngineScore(fenId: 1) == nil)
    }

    @Test func testActiveEngineScore_WithActiveKey_ReturnsScore() {
        let db = createTestDatabase()
        db.setEngineScore(fenId: 1, engineKey: "activeEngine", score: 300)
        db.activeEngineKey = "activeEngine"

        #expect(db.getActiveEngineScore(fenId: 1) == 300)
    }

    @Test func testSetEngineScore_MarksEngineDirty() {
        let db = createTestDatabase()
        #expect(db.isEngineScoreDirty == false)

        db.setEngineScore(fenId: 1, engineKey: "testEngine", score: 50)

        #expect(db.isEngineScoreDirty == true)
        #expect(db.dirtyEngineKeys.contains("testEngine"))
    }

    @Test func testSetEngineScore_IncrementsEngineDataVersion() {
        let db = createTestDatabase()
        db.setEngineScore(fenId: 1, engineKey: "testEngine", score: 50)

        let version = db.engineScores["testEngine"]?.dataVersion
        #expect(version == 1)

        db.setEngineScore(fenId: 2, engineKey: "testEngine", score: 60)
        #expect(db.engineScores["testEngine"]?.dataVersion == 2)
    }

    @Test func testMarkEngineScoreClean_ClearsDirtyKeys() {
        let db = createTestDatabase()
        db.setEngineScore(fenId: 1, engineKey: "engineA", score: 100)
        db.setEngineScore(fenId: 2, engineKey: "engineB", score: 200)
        #expect(db.dirtyEngineKeys.count == 2)

        db.markEngineScoreClean()

        #expect(db.dirtyEngineKeys.isEmpty)
        #expect(db.isEngineScoreDirty == false)
    }

    // MARK: - restoreFromBackup Tests

    @Test @MainActor func testRestoreFromBackup_ReplacesDatabaseData() {
        let db = createTestDatabase()

        let newData = DatabaseData()
        newData.dataVersion = 99
        let fen = FenObject(fen: "backup_fen", fenId: 42)
        newData.fenObjects2[42] = fen

        db.restoreFromBackup(newData)

        #expect(db.databaseData.dataVersion == 99)
        #expect(db.databaseData.fenObjects2[42]?.fen == "backup_fen")
    }

    @Test @MainActor func testRestoreFromBackup_MarksDirty() {
        let db = createTestDatabase()
        #expect(db.isDirty == false)

        db.restoreFromBackup(DatabaseData())

        #expect(db.isDirty == true)
    }

    // MARK: - Init with Test Data Tests

    @Test func testInitWithTestData_UsesProvidedData() {
        let data = DatabaseData()
        data.dataVersion = 77
        let fen = FenObject(fen: "custom_fen", fenId: 5)
        data.fenObjects2[5] = fen
        data.fenToId["custom_fen"] = 5

        let db = Database(testDatabaseData: data)

        #expect(db.databaseData.dataVersion == 77)
        #expect(db.databaseData.fenObjects2[5]?.fen == "custom_fen")
        #expect(db.isDirty == false)
    }

    @Test func testInitWithTestData_EngineScoresEmpty() {
        let db = createTestDatabase()

        #expect(db.engineScores.isEmpty)
        #expect(db.dirtyEngineKeys.isEmpty)
        #expect(db.activeEngineKey == nil)
    }
}
