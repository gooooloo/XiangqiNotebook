import Foundation

/// 招法列表显示项，用于五列对齐显示
struct MoveListItem {
    let number: String              // 序号，如 "1.", "2."
    let notation: String            // 招法符号，如 "炮二平五", "马8进7"
    let redOpeningMarker: String    // 红方开局库标识，"r" 或空字符串
    let blackOpeningMarker: String  // 黑方开局库标识，"b" 或空字符串
    let reviewMarker: String        // 复习库标识，"v" 或空字符串
    let markers: String             // 标记符号，如 "++++", "+++"（表示变着数量）
    let move: Move?                 // 对应的 Move 对象
}

/// GameOperations 包含所有与游戏操作相关的静态方法
class GameOperations {
    // MARK: - Game Operations

    /// 自动扩展游戏路径
    ///
    /// - Parameters:
    ///   - game: 当前游戏路径
    ///   - nextFenIds: 可选的下一步 fenId 列表
    ///   - databaseView: 数据库视图，用于访问过滤后的数据（步数限制已由 DatabaseView 的 fenId 过滤处理）
    ///   - allowExtend: 是否允许自动扩展
    static func autoExtendGame(game: [Int],
                            nextFenIds: [Int]? = nil,
                            databaseView: DatabaseView,
                            allowExtend: Bool = true) -> [Int] {
        var extendedGame = game
        var fensInGame = Set(extendedGame)

        // extend game with nextFenIds first
        if let nextFenIds = nextFenIds {
            for nextFenId in nextFenIds {
                // don't loop
                if fensInGame.contains(nextFenId) { break }

                guard let fenId = extendedGame.last else { break }
                guard databaseView.move(from: fenId, to: nextFenId) != nil else { break }

                extendedGame.append(nextFenId)
                fensInGame.insert(nextFenId)
            }
        }

        // extend game with lastMoveFenId or first move
        if allowExtend {
            while true {
                guard let fenId = extendedGame.last else { break }
                guard let fenObject = databaseView.getFenObject(fenId) else { break }
                let moves = databaseView.moves(from: fenId)

                var nextFenId: Int
                if let lastMoveFenId = fenObject.lastMoveFenId,
                    databaseView.move(from: fenId, to: lastMoveFenId) != nil {
                    nextFenId = lastMoveFenId
                } else if !moves.isEmpty,
                    let firstMoveFenId = moves[0].targetFenId {
                    nextFenId = firstMoveFenId
                } else {
                    break
                }

                // don't loop
                if fensInGame.contains(nextFenId) { break }

                extendedGame.append(nextFenId)
                fensInGame.insert(nextFenId)
            }
        }

        return extendedGame
    }
    
    static func cutGameUntilStep(_ stepIndex: Int, currentGame: [Int]) -> ([Int], Int) {
        guard stepIndex >= 0,
              stepIndex <= currentGame.count - 1 else {
            return (currentGame, currentGame.count - 1)
        }
        
        return (Array(currentGame[0...stepIndex]), stepIndex)
    }
    
    // 随机游戏生成已迁移至 GamePathEnumerator（issue #162）：
    // 旧的 makeRandomGameDFS 系列物化全部路径且与 Session 重复，生产代码无调用，已删除

    /// 格式化着法列表
    ///
    /// - Parameters:
    ///   - currentGame: 当前游戏路径
    ///   - databaseView: 数据库视图
    ///   - isHorizontalFlipped: 是否水平翻转
    static func formatMoveList(currentGame: [Int],
                             databaseView: DatabaseView,
                             isHorizontalFlipped: Bool) -> [MoveListItem] {
        guard let firstFenObject = databaseView.getFenObject(currentGame[0]) else {
            return []
        }
        let firstMoveIsRed = firstFenObject.blackJustPlayed
        var moveList: [MoveListItem] = []

        for i in 0..<currentGame.count {
            if i == 0 {
                // 开始位置：空序号，"开始"作为招法，无标记
                moveList.append(MoveListItem(number: "", notation: "开始",
                                            redOpeningMarker: "", blackOpeningMarker: "",
                                            reviewMarker: "", markers: "", move: nil))
                continue
            }

            let prevFenId = currentGame[i - 1]
            let curFenId = currentGame[i]

            guard let move = databaseView.move(from: prevFenId, to: curFenId) else {
                moveList.append(MoveListItem(number: "", notation: "nil_bug",
                                            redOpeningMarker: "", blackOpeningMarker: "",
                                            reviewMarker: "", markers: "", move: nil))
                continue
            }

            let roundOneBased: Int
            if firstMoveIsRed {
                // 0.start 1.red 1.black 2.red 2.black ...
                roundOneBased = (i - 1) / 2 + 1
            } else {
                // 0.start 1.black 2.red 2.black 3.red ...
                roundOneBased = i / 2 + 1
            }

            // 分离为五个部分
            let number = "\(roundOneBased)."
            let notation = databaseView.formatMove(move, isHorizontalFlipped: isHorizontalFlipped)

            // 检查当前局面是否在开局库中
            let curFenObject = databaseView.getFenObject(curFenId)
            let redOpeningMarker = curFenObject?.isInRedOpening == true ? "r" : ""
            let blackOpeningMarker = curFenObject?.isInBlackOpening == true ? "b" : ""
            let reviewMarker = databaseView.reviewItems[curFenId] != nil ? "v" : ""

            let moves = databaseView.moves(from: prevFenId)
            let movesLength = moves.count
            let markers: String
            if movesLength > 1 {
                // multiple choices
                // '+': {2}, '++':{3,4}, '+++':{5,6}, '++++':{7,8} ...
                let plusCount = (movesLength + 1) / 2
                markers = String(repeating: "+", count: plusCount)
            } else {
                markers = ""
            }

            moveList.append(MoveListItem(number: number, notation: notation,
                                        redOpeningMarker: redOpeningMarker,
                                        blackOpeningMarker: blackOpeningMarker,
                                        reviewMarker: reviewMarker,
                                        markers: markers, move: move))
        }

        return moveList
    }
    
    // MARK: - Variant Operations
    static func nextVariantIndex(currentFenId: Int, variantMoves: [Move]) -> Int {
        guard variantMoves.count >= 2 else {
            return 0
        }
        
        guard let currentIndex = variantMoves.firstIndex(where: { $0.targetFenId == currentFenId }) else {
            return 0
        }
        
        return (currentIndex + 1) % variantMoves.count
    }
} 
