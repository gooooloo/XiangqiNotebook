import Foundation

/// 数据库值快照（深拷贝），用于把大库的 JSON 编码/写盘移出主线程：
/// 主线程快速拷出一份与原数据无共享可变状态的副本，后台线程再慢慢编码写盘，
/// 避免编码期间主线程继续修改对象图导致的数据竞争（字典并发读写会直接崩溃）。
///
/// 快照的唯一用途是编码成 JSON，因此只拷贝「参与编码」的字段；
/// 派生索引（DatabaseData.fenToId/moveToId、FenObject.fenId/moves、
/// GameObject 的缓存 Set 等）不参与编码，无需拷贝。
///
/// 维护要求：模型新增参与编码的字段时，必须同步更新对应的 snapshotCopy()。
/// DatabaseDataSnapshotTests 以「快照与原对象的编码结果逐字节一致、
/// 且修改原对象不影响快照」兜底。

extension DatabaseData {
    func snapshotCopy() -> DatabaseData {
        let copy = DatabaseData()
        copy.fenObjects2 = fenObjects2.mapValues { $0.snapshotCopy() }
        copy.moveObjects = moveObjects.mapValues { $0.snapshotCopy() }
        copy.gameObjects = gameObjects.mapValues { $0.snapshotCopy() }
        copy.bookObjects = bookObjects.mapValues { $0.snapshotCopy() }
        copy.bookmarks = bookmarks
        copy.reviewItems = reviewItems.mapValues { $0.snapshotCopy() }
        copy.practiceMistakes = practiceMistakes
        copy.myRealRedGameStatisticsByFenId = myRealRedGameStatisticsByFenId.mapValues { $0.snapshotCopy() }
        copy.myRealBlackGameStatisticsByFenId = myRealBlackGameStatisticsByFenId.mapValues { $0.snapshotCopy() }
        copy.dataVersion = dataVersion
        copy.schemaVersion = schemaVersion
        return copy
    }
}

extension FenObject {
    func snapshotCopy() -> FenObject {
        let copy = FenObject(fen: fen, fenId: fenId ?? 0)
        copy.score = score
        copy.comment = comment
        copy.lastMoveFenId = lastMoveFenId
        copy.inBlackOpening = inBlackOpening
        copy.inRedOpening = inRedOpening
        copy.pathGroups = pathGroups
        copy._practiceCount = _practiceCount
        return copy
    }
}

extension Move {
    func snapshotCopy() -> Move {
        let copy = Move(sourceFenId: sourceFenId, targetFenId: targetFenId)
        copy.comment = comment
        copy.badReason = badReason
        return copy
    }
}

extension GameObject {
    func snapshotCopy() -> GameObject {
        let copy = GameObject(id: id)
        copy.name = name
        copy.creationDate = creationDate
        copy.gameDate = gameDate
        copy.redPlayerName = redPlayerName
        copy.blackPlayerName = blackPlayerName
        copy.iAmRed = iAmRed
        copy.iAmBlack = iAmBlack
        copy.gameResult = gameResult
        copy.startingFenId = startingFenId
        copy.moveIds = moveIds
        copy.isFullyRecorded = isFullyRecorded
        return copy
    }
}

extension BookObject {
    func snapshotCopy() -> BookObject {
        let copy = BookObject(id: id, name: name)
        copy.gameIds = gameIds
        copy.subBookIds = subBookIds
        copy.author = author
        return copy
    }
}

extension GameResultStatistics {
    func snapshotCopy() -> GameResultStatistics {
        let copy = GameResultStatistics()
        copy.redWin = redWin
        copy.blackWin = blackWin
        copy.draw = draw
        copy.notFinished = notFinished
        copy.unknown = unknown
        return copy
    }
}

extension SRSData {
    func snapshotCopy() -> SRSData {
        let copy = SRSData(gamePath: gamePath, nextReviewDate: nextReviewDate)
        copy.customName = customName
        copy.easeFactor = easeFactor
        copy.interval = interval
        copy.repetitions = repetitions
        copy.lastReviewDate = lastReviewDate
        return copy
    }
}
