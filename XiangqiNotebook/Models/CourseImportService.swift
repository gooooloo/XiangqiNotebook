import Foundation

/// 课程视频棋谱导入：把一节课识别出的多条线路（共享前缀的着法序列）合并为
/// 单个 GameObject——moveIds 存整棵讲课树的着法集合，变着经 moves(from:)/
/// GamePathEnumerator 自然可达，与「每个视频一局」的组织方式对应。
/// 同时返回各局面 fenId 与视频时间戳的对应关系，供课程视频关联使用。
enum CourseImportService {

    struct LineInput {
        /// PGN 格式起始 FEN（nil = 标准开局）
        var startFen: String?
        /// PGN 坐标着法（行 0 在黑方顶部，与 PGNParser 一致）
        var moves: [String]
        /// 与 moves 对应的视频秒数（第 i 项为第 i 步走完的时刻；可为空或较短）
        var times: [Double]
    }

    struct ImportResult {
        var gameId: UUID
        var lineCount: Int
        /// 去重后归入棋局的着法数
        var moveCount: Int
        /// fenId → 该局面在视频中首次出现的秒数
        var fenTimestamps: [Int: Double]
    }

    enum ImportError: Error, CustomStringConvertible, Equatable {
        case duplicateName(String)
        case emptyLines
        case invalidLine(Int, String)
        case bookNotFound(String)

        var description: String {
            switch self {
            case .duplicateName(let name): return "棋书中已存在同名棋局: \(name)"
            case .emptyLines: return "没有可导入的着法"
            case .invalidLine(let index, let reason): return "第 \(index) 条线路无效: \(reason)"
            case .bookNotFound(let path): return "课程棋书不存在: \(path)"
            }
        }
    }

    /// 从「课程」根棋书沿名称路径解析子棋书（如 ["李享堃", "半途列炮"]）
    static func resolveCourseBook(path: [String], databaseView: DatabaseView) throws -> UUID {
        var bookId = Session.courseBookId
        for name in path {
            guard let book = databaseView.getBookObjectUnfiltered(bookId),
                  let subId = book.subBookIds.first(where: {
                      databaseView.getBookObjectUnfiltered($0)?.name == name
                  }) else {
                throw ImportError.bookNotFound((["课程"] + path).joined(separator: "/"))
            }
            bookId = subId
        }
        return bookId
    }

    /// 把一节课的全部线路导入为目标棋书中的一个棋局。
    /// 复用 PGNParser 的 FEN 推导，保证与既有数据的归一化完全一致（局面自动合并）。
    /// 刻意不做 normalizeGameOrientation 镜像：课程局面必须与视频画面保持对应。
    static func importCourseGame(
        bookId: UUID,
        name: String,
        lines: [LineInput],
        databaseView: DatabaseView
    ) throws -> ImportResult {
        guard lines.contains(where: { !$0.moves.isEmpty }) else {
            throw ImportError.emptyLines
        }
        // 同名即视为已导入，保证批量导入脚本可安全重跑
        if databaseView.getGamesInBookUnfiltered(bookId).contains(where: { $0.name == name }) {
            throw ImportError.duplicateName(name)
        }

        var startingFenId: Int?
        var gameMoveIds: [Int] = []
        var gameMoveIdSet = Set<Int>()
        var fenTimestamps: [Int: Double] = [:]

        // 先整体校验再写库，避免半成品棋局落库
        var fenSequences: [[String]] = []
        for (index, line) in lines.enumerated() {
            var pgnGame = PGNGame()
            pgnGame.coordinateMoves = line.moves
            pgnGame.startingFen = line.startFen
            guard let fens = PGNParser.generateFenSequence(pgnGame) else {
                throw ImportError.invalidLine(index + 1, "着法解析失败")
            }
            fenSequences.append(fens)
        }

        for (line, fens) in zip(lines, fenSequences) {
            let fenIds = fens.map { databaseView.ensureFenId(for: $0) }
            if startingFenId == nil {
                startingFenId = fenIds.first
            }
            for i in 1..<fenIds.count {
                let (move, moveId, _) = databaseView.ensureMove(from: fenIds[i - 1], to: fenIds[i])
                if let fenObject = databaseView.getFenObject(fenIds[i - 1]) {
                    _ = fenObject.addMoveIfNeeded(move: move)
                }
                if !gameMoveIdSet.contains(moveId) {
                    gameMoveIdSet.insert(moveId)
                    gameMoveIds.append(moveId)
                }
                if i - 1 < line.times.count {
                    let t = line.times[i - 1]
                    let fenId = fenIds[i]
                    if fenTimestamps[fenId].map({ t < $0 }) ?? true {
                        fenTimestamps[fenId] = t
                    }
                }
            }
        }

        let gameId = databaseView.addGame(
            to: bookId,
            name: name,
            redPlayerName: "",
            blackPlayerName: "",
            gameDate: Date(),
            gameResult: .unknown,
            iAmRed: false,
            iAmBlack: false,
            startingFenId: startingFenId,
            isFullyRecorded: true
        )

        if let gameObject = databaseView.getGameObjectUnfiltered(gameId) {
            for moveId in gameMoveIds {
                if let move = databaseView.move(id: moveId) {
                    gameObject.appendMoveId(moveId, move: move)
                }
            }
            databaseView.updateGameObject(gameId, gameObject: gameObject)
        }

        return ImportResult(
            gameId: gameId,
            lineCount: lines.count,
            moveCount: gameMoveIds.count,
            fenTimestamps: fenTimestamps
        )
    }
}
