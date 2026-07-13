import Testing
import Foundation
@testable import XiangqiNotebook

/// 值快照（深拷贝）完整性测试：
/// 1. 快照与原对象的 JSON 编码结果逐字节一致（字段无遗漏）；
/// 2. 修改原对象后快照的编码结果不变（无共享可变状态）。
///
/// 维护要求：模型新增参与编码的字段时，请在 makeFullyPopulatedData() 里
/// 给该字段赋非默认值，否则本测试无法发现 snapshotCopy() 的遗漏。
struct DatabaseDataSnapshotTests {

    private func makeFullyPopulatedData() -> DatabaseData {
        let data = DatabaseData()

        let fen1 = FenObject(fen: "fen-1", fenId: 1)
        fen1.score = 42
        fen1.comment = "评论1"
        fen1.lastMoveFenId = 2
        fen1.inBlackOpening = true
        fen1.inRedOpening = false
        fen1.pathGroups = [
            PathGroup(
                paths: [PathConfig(points: ["a1", "b2"], showArrow: false, isDashed: true)],
                name: "组1"
            )
        ]
        fen1._practiceCount = 7
        let fen2 = FenObject(fen: "fen-2", fenId: 2)
        data.fenObjects2 = [1: fen1, 2: fen2]

        let move = Move(sourceFenId: 1, targetFenId: 2)
        move.comment = "着法评论"
        move.badReason = "坏棋原因"
        let removedMove = Move(sourceFenId: 2, targetFenId: nil)
        data.moveObjects = [10: move, 11: removedMove]

        let gameId = UUID()
        let game = GameObject(id: gameId)
        game.name = "测试棋局"
        game.creationDate = Date(timeIntervalSince1970: 1_000)
        game.gameDate = Date(timeIntervalSince1970: 2_000)
        game.redPlayerName = "红方"
        game.blackPlayerName = "黑方"
        game.iAmRed = true
        game.iAmBlack = false
        game.gameResult = .redWin
        game.startingFenId = 1
        game.moveIds = [10]
        game.isFullyRecorded = true
        data.gameObjects = [gameId: game]

        let bookId = UUID()
        let book = BookObject(id: bookId, name: "测试棋书")
        book.gameIds = [gameId]
        book.subBookIds = [UUID()]
        book.author = "作者"
        data.bookObjects = [bookId: book]

        data.bookmarks = [[1, 2]: "书签"]

        let srs = SRSData(gamePath: [1, 2], nextReviewDate: Date(timeIntervalSince1970: 3_000))
        srs.customName = "复习项"
        srs.easeFactor = 2.0
        srs.interval = 6
        srs.repetitions = 3
        srs.lastReviewDate = Date(timeIntervalSince1970: 2_500)
        data.reviewItems = [1: srs]

        data.practiceMistakes = [
            1: [
                PracticeMistakeRecord(
                    wrongFen: "wrong-fen",
                    count: 2,
                    firstWrongAt: Date(timeIntervalSince1970: 100),
                    lastWrongAt: Date(timeIntervalSince1970: 200)
                )
            ]
        ]

        let redStats = GameResultStatistics()
        redStats.redWin = 1
        redStats.blackWin = 2
        redStats.draw = 3
        redStats.notFinished = 4
        redStats.unknown = 5
        data.myRealRedGameStatisticsByFenId = [1: redStats]

        let blackStats = GameResultStatistics()
        blackStats.redWin = 6
        data.myRealBlackGameStatisticsByFenId = [2: blackStats]

        data.dataVersion = 123
        return data
    }

    private func encode(_ data: DatabaseData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(data)
    }

    @Test func testSnapshotEncodesIdenticallyToOriginal() throws {
        let original = makeFullyPopulatedData()
        let snapshot = original.snapshotCopy()

        let originalBytes = try encode(original)
        let snapshotBytes = try encode(snapshot)
        #expect(snapshotBytes == originalBytes)
    }

    @Test func testSnapshotIsIndependentOfLaterMutations() throws {
        let original = makeFullyPopulatedData()
        let snapshot = original.snapshotCopy()
        let bytesBeforeMutation = try encode(snapshot)

        // 逐类修改原对象的可变状态，快照编码结果必须不受影响
        original.fenObjects2[1]!.comment = "改动"
        original.fenObjects2[1]!.score = -1
        original.fenObjects2[1]!.pathGroups?.append(PathGroup(paths: [], name: "新组"))
        original.fenObjects2[1]!.incrementPracticeCount()
        original.fenObjects2[3] = FenObject(fen: "fen-3", fenId: 3)
        original.moveObjects[10]!.comment = "改动"
        original.moveObjects[10]!.markAsRemoved()
        original.gameObjects.values.first!.name = "改名"
        original.gameObjects.values.first!.moveIds.append(99)
        original.bookObjects.values.first!.gameIds.append(UUID())
        original.bookmarks[[3]] = "新书签"
        original.reviewItems[1]!.interval = 999
        original.practiceMistakes[1]!.append(
            PracticeMistakeRecord(wrongFen: "w2", firstWrongAt: Date(), lastWrongAt: Date())
        )
        original.myRealRedGameStatisticsByFenId[1]!.redWin = 100
        original.myRealBlackGameStatisticsByFenId[2]!.draw = 100
        original.dataVersion = 456

        let bytesAfterMutation = try encode(snapshot)
        #expect(bytesAfterMutation == bytesBeforeMutation)
    }
}
