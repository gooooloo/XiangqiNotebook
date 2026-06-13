import Foundation
@testable import XiangqiNotebook

/// 共享的测试数据库构造器（issue #167）。
///
/// 替代各测试文件各自手写的 `createTestDatabase`。统一三件易错的事：
/// - fen 同时写入 `fenObjects2` 与 `fenToId`；
/// - `addMove` 一致地写入 `fen.moves`（addMoveIfNeeded）+ `moveObjects` + `moveToId`
///   （旧实现有的只写 fen.moves、有的只写 moveObjects/moveToId，不一致）；
/// - moveId 默认自增，需要固定值（如断言 `moveObjects[3]`）时可显式指定。
///
/// fen 串与开局标志逐字保留——`isInRedOpening` 依赖 fen 的走子方（isAuto*），
/// 必须按各测试原本的 fen 字符串构造，不能用占位串替换。
final class TestDatabaseBuilder {
    private let data = DatabaseData()
    private var nextMoveId = 1

    /// 添加一个局面。fen 省略时用 "fen{id}"；开局标志默认 false（等价于不设）
    @discardableResult
    func addFen(_ id: Int, fen: String? = nil, inRedOpening: Bool = false, inBlackOpening: Bool = false) -> TestDatabaseBuilder {
        let fenStr = fen ?? "fen\(id)"
        let obj = FenObject(fen: fenStr, fenId: id)
        obj.setInRedOpening(inRedOpening)
        obj.setInBlackOpening(inBlackOpening)
        data.fenObjects2[id] = obj
        data.fenToId[fenStr] = id
        return self
    }

    /// 批量添加 fenId（fen 用 "fen{id}"，无开局标志）
    @discardableResult
    func addFens(_ ids: [Int]) -> TestDatabaseBuilder {
        for id in ids { addFen(id) }
        return self
    }

    @discardableResult
    func addFens(_ ids: ClosedRange<Int>) -> TestDatabaseBuilder {
        addFens(Array(ids))
    }

    /// 添加一条着法，一致地写入 fen.moves + moveObjects + moveToId。
    /// moveId 省略时自增（从 1 起，且不与显式指定的值重叠）
    @discardableResult
    func addMove(from: Int, to: Int, moveId: Int? = nil) -> TestDatabaseBuilder {
        let mid = moveId ?? nextMoveId
        nextMoveId = Swift.max(nextMoveId, mid) + 1
        let move = Move(sourceFenId: from, targetFenId: to)
        data.fenObjects2[from]?.addMoveIfNeeded(move: move)
        data.moveObjects[mid] = move
        data.moveToId[[from, to]] = mid
        return self
    }

    @discardableResult
    func addRedRealGameStats(fenId: Int, redWin: Int = 0, blackWin: Int = 0, draw: Int = 0, notFinished: Int = 0, unknown: Int = 0) -> TestDatabaseBuilder {
        data.myRealRedGameStatisticsByFenId[fenId] = Self.makeStats(redWin, blackWin, draw, notFinished, unknown)
        return self
    }

    @discardableResult
    func addBlackRealGameStats(fenId: Int, redWin: Int = 0, blackWin: Int = 0, draw: Int = 0, notFinished: Int = 0, unknown: Int = 0) -> TestDatabaseBuilder {
        data.myRealBlackGameStatisticsByFenId[fenId] = Self.makeStats(redWin, blackWin, draw, notFinished, unknown)
        return self
    }

    private static func makeStats(_ r: Int, _ b: Int, _ d: Int, _ nf: Int, _ u: Int) -> GameResultStatistics {
        let s = GameResultStatistics()
        s.redWin = r; s.blackWin = b; s.draw = d; s.notFinished = nf; s.unknown = u
        return s
    }

    /// 直接访问底层 DatabaseData（测试需要追加 GameObject/BookObject/复习项等时用）
    var databaseData: DatabaseData { data }

    func build() -> Database {
        Database(testDatabaseData: data)
    }
}
