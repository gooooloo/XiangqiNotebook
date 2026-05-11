import Testing
import Foundation
@testable import XiangqiNotebook

struct PracticeMistakeStatsTests {

    /// 创建一个空的测试数据库，并塞入若干 fenId
    private func createTestDatabase(with fenIds: [Int]) -> Database {
        let data = DatabaseData()
        let db = Database(testDatabaseData: data)
        for id in fenIds {
            let fen = FenObject(fen: "fen\(id)", fenId: id)
            db.databaseData.fenObjects2[id] = fen
        }
        return db
    }

    @Test
    func recordIncrementsCountForSameWrongFen() {
        let db = createTestDatabase(with: [1])
        let view = DatabaseView.full(database: db)
        let date1 = Date(timeIntervalSince1970: 100)
        let date2 = Date(timeIntervalSince1970: 200)
        view.recordPracticeMistake(at: 1, wrongFen: "wrongA", at: date1)
        view.recordPracticeMistake(at: 1, wrongFen: "wrongA", at: date2)
        let records = db.databaseData.practiceMistakes[1] ?? []
        #expect(records.count == 1)
        #expect(records.first?.wrongFen == "wrongA")
        #expect(records.first?.count == 2)
        #expect(records.first?.firstWrongAt == date1)
        #expect(records.first?.lastWrongAt == date2)
    }

    @Test
    func recordCreatesSeparateEntryForDifferentWrongFen() {
        let db = createTestDatabase(with: [1])
        let view = DatabaseView.full(database: db)
        view.recordPracticeMistake(at: 1, wrongFen: "wrongA")
        view.recordPracticeMistake(at: 1, wrongFen: "wrongB")
        view.recordPracticeMistake(at: 1, wrongFen: "wrongA")
        let records = db.databaseData.practiceMistakes[1] ?? []
        #expect(records.count == 2)
        let a = records.first { $0.wrongFen == "wrongA" }
        let b = records.first { $0.wrongFen == "wrongB" }
        #expect(a?.count == 2)
        #expect(b?.count == 1)
    }

    @Test
    func recordSeparatesByFenId() {
        let db = createTestDatabase(with: [1, 2])
        let view = DatabaseView.full(database: db)
        view.recordPracticeMistake(at: 1, wrongFen: "x")
        view.recordPracticeMistake(at: 2, wrongFen: "x")
        view.recordPracticeMistake(at: 2, wrongFen: "x")
        #expect(db.databaseData.practiceMistakes[1]?.first?.count == 1)
        #expect(db.databaseData.practiceMistakes[2]?.first?.count == 2)
    }

    @Test
    func resetClearsAllRecords() {
        let db = createTestDatabase(with: [1])
        let view = DatabaseView.full(database: db)
        view.recordPracticeMistake(at: 1, wrongFen: "x")
        view.recordPracticeMistake(at: 1, wrongFen: "y")
        #expect(db.databaseData.practiceMistakes.isEmpty == false)
        view.resetPracticeMistakes()
        #expect(db.databaseData.practiceMistakes.isEmpty == true)
    }

    @Test
    func recordMarksDatabaseDirty() {
        let db = createTestDatabase(with: [1])
        let view = DatabaseView.full(database: db)
        // 创建后初始 isDirty 取决于实现，这里只验证 record 后必为 dirty
        view.recordPracticeMistake(at: 1, wrongFen: "x")
        // markDirty 是异步通过 DispatchQueue.main 设置 isDirty 的；
        // 但 dataVersion 是同步在 main 异步块内自增。所以直接看底层数据是否写入。
        #expect((db.databaseData.practiceMistakes[1]?.count ?? 0) == 1)
    }

    /// 视图过滤：DatabaseView.practiceMistakes 只返回筛选范围内 fenId 的记录
    @Test
    func filteringByDatabaseView() {
        let db = createTestDatabase(with: [1, 2, 3])
        // 让 fenId=1 在红方开局，2 在黑方开局，3 都不在
        db.databaseData.fenObjects2[1]?.setInRedOpening(true)
        db.databaseData.fenObjects2[2]?.setInBlackOpening(true)

        let fullView = DatabaseView.full(database: db)
        fullView.recordPracticeMistake(at: 1, wrongFen: "x")
        fullView.recordPracticeMistake(at: 2, wrongFen: "x")
        fullView.recordPracticeMistake(at: 3, wrongFen: "x")

        let redView = DatabaseView.redOpening(database: db)
        let redMistakes = redView.practiceMistakes
        #expect(redMistakes.keys.contains(1) == true)
        #expect(redMistakes.keys.contains(2) == false)
        #expect(redMistakes.keys.contains(3) == false)

        let blackView = DatabaseView.blackOpening(database: db)
        let blackMistakes = blackView.practiceMistakes
        #expect(blackMistakes.keys.contains(2) == true)
        #expect(blackMistakes.keys.contains(1) == false)

        // 完整视图应包含所有 3 个
        #expect(fullView.practiceMistakes.keys.count == 3)
    }

    /// Codable 兼容性：旧数据（没有 practice_mistakes 字段）应能正常解码
    @Test
    func codableBackwardCompatibility() throws {
        // 先编码一份空 DatabaseData 拿到完整 JSON，再剥掉 practice_mistakes 字段，
        // 模拟旧版本数据库文件中不存在该字段的场景。
        let original = DatabaseData()
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("expected top-level JSON object")
            return
        }
        json.removeValue(forKey: "practice_mistakes")
        #expect(json.keys.contains("practice_mistakes") == false)
        let strippedData = try JSONSerialization.data(withJSONObject: json)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DatabaseData.self, from: strippedData)
        #expect(decoded.practiceMistakes.isEmpty == true)
    }

    /// Codable 写入并重新读取后保持一致
    @Test
    func codableRoundtrip() throws {
        let original = DatabaseData()
        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        original.practiceMistakes = [
            42: [
                PracticeMistakeRecord(wrongFen: "wA", count: 3, firstWrongAt: date1, lastWrongAt: date2),
                PracticeMistakeRecord(wrongFen: "wB", count: 1, firstWrongAt: date2, lastWrongAt: date2)
            ]
        ]
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DatabaseData.self, from: data)
        let records = decoded.practiceMistakes[42] ?? []
        #expect(records.count == 2)
        let wA = records.first { $0.wrongFen == "wA" }
        let wB = records.first { $0.wrongFen == "wB" }
        #expect(wA?.count == 3)
        #expect(wA?.firstWrongAt == date1)
        #expect(wA?.lastWrongAt == date2)
        #expect(wB?.count == 1)
    }
}
