import Foundation

/// 招法列表显示项，用于五列对齐显示
struct MoveListItem {
    let number: String              // 序号，如 "1.", "2."
    let notation: String            // 招法符号，如 "炮二平五", "马8进7"
    let redOpeningMarker: String    // 红方开局库标识，"r" 或空字符串
    let blackOpeningMarker: String  // 黑方开局库标识，"b" 或空字符串
    let markers: String             // 标记符号，如 "++++", "+++"（表示变着数量）
    let move: Move?                 // 对应的 Move 对象
}

/// GameOperations 包含所有与游戏操作相关的静态方法
class GameOperations {
    // MARK: - Game Operations

    /// 自动扩展游戏路径
    ///
    /// - Parameters:
    ///   - databaseView: 数据库视图，用于访问过滤后的数据
    ///   - game: 当前游戏路径
    ///   - nextFenIds: 可选的下一步 fenId 列表
    ///   - gameStepLimitation: 游戏步数限制
    ///   - allowExtend: 是否允许自动扩展
    static func autoExtendGame(game: [Int],
                            nextFenIds: [Int]? = nil,
                            databaseView: DatabaseView,
                            gameStepLimitation: Int?,
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
            while gameStepLimitation == nil || extendedGame.count < 1 + gameStepLimitation! {
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
    
    // MARK: - Random Game Generation

    /// 使用 DFS 生成随机游戏
    ///
    /// - Parameters:
    ///   - currentFenId: 当前局面 ID
    ///   - databaseView: 数据库视图
    static func makeRandomGameDFS(currentFenId: Int,
                                databaseView: DatabaseView) -> (result: [Int], totalCount: Int)? {
        // 使用默认的随机函数
        return makeRandomGameDFSWithRandomizer(
            currentFenId: currentFenId,
            databaseView: databaseView
        ) { count in
            Int.random(in: 0..<count)
        }
    }
    
    /// 使用 DFS 和自定义随机器生成随机游戏
    ///
    /// - Parameters:
    ///   - currentFenId: 当前局面 ID
    ///   - databaseView: 数据库视图
    ///   - randomizer: 随机选择函数
    static func makeRandomGameDFSWithRandomizer(currentFenId: Int,
                                              databaseView: DatabaseView,
                                              randomizer: (Int) -> Int) -> (result: [Int], totalCount: Int)? {
        var allDFSPaths: [[Int]] = []

        func dfs(_ dfsPath: [Int]) {
            var isLeaf = true
            let fensInGame = Set(dfsPath)

            guard let lastFenId = dfsPath.last else { return }
            guard databaseView.containsFenId(lastFenId) else { return }
            let moves = databaseView.moves(from: lastFenId)

            for move in moves {
                if move.targetFenId == nil { continue }
                if fensInGame.contains(move.targetFenId!) { continue }

                isLeaf = false
                dfs(dfsPath + [move.targetFenId!])
            }

            if isLeaf {
                allDFSPaths.append(dfsPath)
            }
        }

        dfs([currentFenId])

        guard !allDFSPaths.isEmpty else {
            return nil
        }

        let index = randomizer(allDFSPaths.count)
        let result = Array(allDFSPaths[index].dropFirst())
        return (result, allDFSPaths.count)
    }
    
    /// 均匀地随机选择下一步生成游戏
    ///
    /// - Parameters:
    ///   - currentFenId: 当前局面 ID
    ///   - databaseView: 数据库视图
    static func makeRandomGameEvenlyNextStep(currentFenId: Int,
                                           databaseView: DatabaseView) -> (result: [Int], totalCount: Int) {
        var path = [currentFenId]

        func extend(_ path: inout [Int]) {
            let fensInGame = Set(path)

            guard let fenId = path.last else {
                return
            }
            guard databaseView.containsFenId(fenId) else {
                return
            }

            let moves = databaseView.moves(from: fenId)
            let goodMoves = moves.filter { $0.targetFenId != nil && !fensInGame.contains($0.targetFenId!) }

            if !goodMoves.isEmpty {
                let randomMove = goodMoves.randomElement()!
                path.append(randomMove.targetFenId!)
                extend(&path)
            }
        }

        extend(&path)
        return (Array(path.dropFirst()), 0)
    }
    
    /// 生成随机游戏（随机选择 DFS 或均匀策略）
    ///
    /// - Parameters:
    ///   - currentFenId: 当前局面 ID
    ///   - databaseView: 数据库视图
    static func makeRandomGame(currentFenId: Int,
                             databaseView: DatabaseView) -> (result: [Int], totalCount: Int)? {
        if Bool.random() {
            return makeRandomGameDFS(currentFenId: currentFenId,
                                   databaseView: databaseView)
        } else {
            return makeRandomGameEvenlyNextStep(currentFenId: currentFenId,
                                              databaseView: databaseView)
        }
    }
    
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
        let firstMoveIsRed = firstFenObject.fen.split(separator: " ")[1] == "r"
        var moveList: [MoveListItem] = []

        for i in 0..<currentGame.count {
            if i == 0 {
                // 开始位置：空序号，"开始"作为招法，无标记
                moveList.append(MoveListItem(number: "", notation: "开始",
                                            redOpeningMarker: "", blackOpeningMarker: "",
                                            markers: "", move: nil))
                continue
            }

            let prevFenId = currentGame[i - 1]
            let curFenId = currentGame[i]

            guard let move = databaseView.move(from: prevFenId, to: curFenId) else {
                moveList.append(MoveListItem(number: "", notation: "nil_bug",
                                            redOpeningMarker: "", blackOpeningMarker: "",
                                            markers: "", move: nil))
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
