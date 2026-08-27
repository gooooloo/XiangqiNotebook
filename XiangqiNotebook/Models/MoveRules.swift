struct MoveRules {
    /// 完整合法走法：在伪合法走法基础上，过滤掉走完后己方被将军
    /// （含将帅对脸暴露、王走入攻击线、送将）的着法
    static func getLegalDestinationSquares(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        guard let piece = piecesBySquare[fromSquare] else { return [] }
        let pseudo = getPseudoDestinationSquares(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        let isRed = piece.hasPrefix("r")
        return pseudo.filter { to in
            !isKingInCheck(isRed: isRed, piecesBySquare: simulateMove(from: fromSquare, to: to, piecesBySquare: piecesBySquare))
        }
    }

    /// 伪合法走法：只考虑单子几何规则，不检查走后己方是否被将军
    static func getPseudoDestinationSquares(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        guard let piece = piecesBySquare[fromSquare] else { return [] }

        // 根据棋子类型调用对应的规则函数
        switch piece {
        case "rR", "bR": // 红方和黑方的车
            return getRookMoves(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rN", "bN": // 马 (Knight)
            return getKnightMoves(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rB", "bB": // 相/象 (Bishop/Elephant)
            return getElephantMoves(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rA", "bA": // 士/仕 (Advisor)
            return getAdvisorMoves(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rK", "bK": // 帅/将 (King)
            return getKingMoves(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rC", "bC": // 炮 (Cannon)
            return getCannonMoves(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rP", "bP": // 兵/卒 (Pawn)
            return getPawnMoves(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        default:
            return []
        }
    }
    
    // 判断是否是己方棋子
    static func isSameColor(_ piece1: String, _ piece2: String) -> Bool {
        return piece1.prefix(1) == piece2.prefix(1)
    }

    /// 模拟走子后的局面（吃子即覆盖）
    private static func simulateMove(from: String, to: String, piecesBySquare: [String: String]) -> [String: String] {
        var board = piecesBySquare
        board[to] = board[from]
        board[from] = nil
        return board
    }

    /// 己方王是否被将军（含将帅对脸）。
    /// 测试/残局数据可能没有王，此时视为不被将军
    static func isKingInCheck(isRed: Bool, piecesBySquare: [String: String]) -> Bool {
        let kingCode = isRed ? "rK" : "bK"
        let enemyKingCode = isRed ? "bK" : "rK"
        guard let kingSquare = piecesBySquare.first(where: { $0.value == kingCode })?.key else {
            return false
        }

        // 将帅对脸：同列且中间无子
        if let enemyKingSquare = piecesBySquare.first(where: { $0.value == enemyKingCode })?.key {
            let (col1, row1) = squareToCoordinate(kingSquare)
            let (col2, row2) = squareToCoordinate(enemyKingSquare)
            if col1 == col2 {
                var blocked = false
                for r in (min(row1, row2) + 1)..<max(row1, row2) {
                    if piecesBySquare[coordinateToSquare(col: col1, row: r)] != nil {
                        blocked = true
                        break
                    }
                }
                if !blocked { return true }
            }
        }

        // 任一敌子的伪合法走法可吃到己方王
        let enemyPrefix = isRed ? "b" : "r"
        for (square, piece) in piecesBySquare where piece.hasPrefix(enemyPrefix) {
            if piece == enemyKingCode { continue } // 对脸已单独判断
            if getPseudoDestinationSquares(fromSquare: square, piecesBySquare: piecesBySquare).contains(kingSquare) {
                return true
            }
        }
        return false
    }
    
    // 判断目标位置是否可以移动（空格或敌方棋子）
    private static func canMoveTo(targetSquare: String, piecesBySquare: [String: String], currentPiece: String) -> Bool {
        if let targetPiece = piecesBySquare[targetSquare] {
            return !isSameColor(currentPiece, targetPiece)
        }
        return true
    }
    
    // 先实现车的移动规则作为示例
    private static func getRookMoves(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        
        // 向右移动
        var col = fromCol + 1
        while col < BoardConstants.columns.count {
            let targetSquare = coordinateToSquare(col: col, row: fromRow)
            if let piece = piecesBySquare[targetSquare] {
                if !isSameColor(currentPiece, piece) {
                    squares.insert(targetSquare)
                }
                break
            }
            squares.insert(targetSquare)
            col += 1
        }
        
        // 向左移动
        col = fromCol - 1
        while col >= 0 {
            let targetSquare = coordinateToSquare(col: col, row: fromRow)
            if let piece = piecesBySquare[targetSquare] {
                if !isSameColor(currentPiece, piece) {
                    squares.insert(targetSquare)
                }
                break
            }
            squares.insert(targetSquare)
            col -= 1
        }
        
        // 向上移动
        var row = fromRow + 1
        while row < BoardConstants.rows.count {
            let targetSquare = coordinateToSquare(col: fromCol, row: row)
            if let piece = piecesBySquare[targetSquare] {
                if !isSameColor(currentPiece, piece) {
                    squares.insert(targetSquare)
                }
                break
            }
            squares.insert(targetSquare)
            row += 1
        }
        
        // 向下移动
        row = fromRow - 1
        while row >= 0 {
            let targetSquare = coordinateToSquare(col: fromCol, row: row)
            if let piece = piecesBySquare[targetSquare] {
                if !isSameColor(currentPiece, piece) {
                    squares.insert(targetSquare)
                }
                break
            }
            squares.insert(targetSquare)
            row -= 1
        }
        
        return squares
    }
    
    static func squareToCoordinate(_ square: String) -> (Int, Int) {
        let col = BoardConstants.columns.firstIndex(of: String(square.prefix(1)))!
        let row = Int(String(square.suffix(1)))!
        return (col, row)
    }
    
    static func coordinateToSquare(col: Int, row: Int) -> String {
        return "\(BoardConstants.columns[col])\(row)"
    }
    
    private static func getKnightMoves(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        
        // 马可能的八个移动方向
        let moves = [
            // 向上跳两格后的左右
            (col: -1, row: 2, blockingSquare: (0, 1)), // 左上
            (col: 1, row: 2, blockingSquare: (0, 1)),  // 右上
            // 向下跳两格后的左右
            (col: -1, row: -2, blockingSquare: (0, -1)), // 左下
            (col: 1, row: -2, blockingSquare: (0, -1)),  // 右下
            // 向左跳两格后的上下
            (col: -2, row: 1, blockingSquare: (-1, 0)),  // 左上
            (col: -2, row: -1, blockingSquare: (-1, 0)), // 左下
            // 向右跳两格后的上下
            (col: 2, row: 1, blockingSquare: (1, 0)),   // 右上
            (col: 2, row: -1, blockingSquare: (1, 0))   // 右下
        ]
        
        for move in moves {
            let newCol = fromCol + move.col
            let newRow = fromRow + move.row
            
            // 检查目标位置是否在棋盘内
            guard newCol >= 0 && newCol < BoardConstants.columns.count &&
                  newRow >= 0 && newRow < BoardConstants.rows.count else {
                continue
            }
            
            // 检查马腿位置
            let blockingCol = fromCol + move.blockingSquare.0
            let blockingRow = fromRow + move.blockingSquare.1
            let blockingSquare = coordinateToSquare(col: blockingCol, row: blockingRow)
            
            // 如果马腿位置有棋子，这个方向就不能走
            if piecesBySquare[blockingSquare] != nil {
                continue
            }
            
            let targetSquare = coordinateToSquare(col: newCol, row: newRow)
            
            // 检查目标位置是否可以移动（空格或敌方棋子）
            if canMoveTo(targetSquare: targetSquare, piecesBySquare: piecesBySquare, currentPiece: currentPiece) {
                squares.insert(targetSquare)
            }
        }
        
        return squares
    }
    
    // 相/象的移动规则
    private static func getElephantMoves(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        let isRed = currentPiece.hasPrefix("r")
        
        // 相/象的四个可能移动方向（田字）
        let moves = [
            (col: 2, row: 2),   // 右上
            (col: 2, row: -2),  // 右下
            (col: -2, row: 2),  // 左上
            (col: -2, row: -2)  // 左下
        ]
        
        for move in moves {
            let newCol = fromCol + move.col
            let newRow = fromRow + move.row
            
            // 检查目标位置是否在棋盘内
            guard newCol >= 0 && newCol < BoardConstants.columns.count else { continue }
            
            // 检查是否过河（红方不能过5线，黑方不能过4线）
            if isRed {
                guard newRow >= 0 && newRow <= 4 else { continue }
            } else {
                guard newRow >= 5 && newRow <= 9 else { continue }
            }
            
            // 检查田心位置是否有棋子
            let blockingCol = fromCol + move.col / 2
            let blockingRow = fromRow + move.row / 2
            let blockingSquare = coordinateToSquare(col: blockingCol, row: blockingRow)
            
            // 如果田心有棋子，这个方向就不能走
            if piecesBySquare[blockingSquare] != nil {
                continue
            }
            
            let targetSquare = coordinateToSquare(col: newCol, row: newRow)
            
            // 检查目标位置是否可以移动（空格或敌方棋子）
            if canMoveTo(targetSquare: targetSquare, piecesBySquare: piecesBySquare, currentPiece: currentPiece) {
                squares.insert(targetSquare)
            }
        }
        
        return squares
    }
    
    // 士/仕的移动规则
    private static func getAdvisorMoves(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        let isRed = currentPiece.hasPrefix("r")
        
        // 斜线移动的四个方向
        let moves = [
            (col: 1, row: 1),   // 右上
            (col: 1, row: -1),  // 右下
            (col: -1, row: 1),  // 左上
            (col: -1, row: -1)  // 左下
        ]
        
        for move in moves {
            let newCol = fromCol + move.col
            let newRow = fromRow + move.row
            
            // 检查是否在九宫格内
            // 红方：d0-f2，黑方：d7-f9
            let validColumns = 3...5  // 对应'd', 'e', 'f'列
            let validRows = isRed ? 0...2 : 7...9
            
            guard validColumns.contains(newCol) && validRows.contains(newRow) else {
                continue
            }
            
            let targetSquare = coordinateToSquare(col: newCol, row: newRow)
            if canMoveTo(targetSquare: targetSquare, piecesBySquare: piecesBySquare, currentPiece: currentPiece) {
                squares.insert(targetSquare)
            }
        }
        
        return squares
    }
    
    // 新增的辅助函数
    private static func findEnemyKingPosition(isRed: Bool, piecesBySquare: [String: String]) -> (col: Int, row: Int)? {
        let enemyKing = isRed ? "bK" : "rK"
        
        for (square, piece) in piecesBySquare {
            if piece == enemyKing {
                return squareToCoordinate(square)
            }
        }
        return nil
    }
    
    // 帅/将的移动规则
    private static func getKingMoves(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        let isRed = currentPiece.hasPrefix("r")
        
        // 使用新函数替换原来的代码
        let enemyKingPosition = findEnemyKingPosition(isRed: isRed, piecesBySquare: piecesBySquare)
        let enemyKingCol = enemyKingPosition?.col ?? -1
        let enemyKingRow = enemyKingPosition?.row ?? -1
        
        // 横竖移动的四个方向
        let moves = [
            (col: 0, row: 1),   // 上
            (col: 0, row: -1),  // 下
            (col: -1, row: 0),  // 左
            (col: 1, row: 0)    // 右
        ]
        
        for move in moves {
            let newCol = fromCol + move.col
            let newRow = fromRow + move.row
            
            // 检查是否在九宫格内
            // 红方：d0-f2，黑方：d7-f9
            let validColumns = 3...5  // 对应'd', 'e', 'f'列
            let validRows = isRed ? 0...2 : 7...9
            
            guard validColumns.contains(newCol) && validRows.contains(newRow) else {
                continue
            }
            
            let targetSquare = coordinateToSquare(col: newCol, row: newRow)
            
            // 检查移动后是否会造成将帅面对面
            if newCol == enemyKingCol {
                // 计算两个将帅之间是否有其他子
                let startRow = min(newRow, enemyKingRow)
                let endRow = max(newRow, enemyKingRow)
                var hasObstacle = false
                
                for r in (startRow + 1)..<endRow {
                    let middleSquare = coordinateToSquare(col: newCol, row: r)
                    if piecesBySquare[middleSquare] != nil,
                       middleSquare != fromSquare { // 跳过己方将帅原位置
                        hasObstacle = true
                        break
                    }
                }
                
                // 如果没有阻挡，则将帅面对面，这个移动不合法
                if !hasObstacle {
                    continue
                }
            }
            
            if canMoveTo(targetSquare: targetSquare, piecesBySquare: piecesBySquare, currentPiece: currentPiece) {
                squares.insert(targetSquare)
            }
        }
        
        return squares
    }
    
    // 炮的移动规则
    private static func getCannonMoves(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        
        // 向四个方向移动的逻辑
        let directions = [
            (colDelta: 1, rowDelta: 0),   // 右
            (colDelta: -1, rowDelta: 0),  // 左
            (colDelta: 0, rowDelta: 1),   // 上
            (colDelta: 0, rowDelta: -1)   // 下
        ]
        
        for direction in directions {
            var col = fromCol
            var row = fromRow
            var foundPlatform = false  // 是否找到炮架
            
            while true {
                col += direction.colDelta
                row += direction.rowDelta
                
                // 检查是否超出棋盘
                guard col >= 0 && col < BoardConstants.columns.count &&
                      row >= 0 && row < BoardConstants.rows.count else {
                    break
                }
                
                let targetSquare = coordinateToSquare(col: col, row: row)
                
                if let piece = piecesBySquare[targetSquare] {
                    if !foundPlatform {
                        // 找到第一个棋子（炮架）
                        foundPlatform = true
                    } else {
                        // 找到第二个棋子，如果是敌方棋子则可以吃
                        if !isSameColor(currentPiece, piece) {
                            squares.insert(targetSquare)
                        }
                        break
                    }
                } else if !foundPlatform {
                    // 没有遇到炮架之前，可以移动到空格
                    squares.insert(targetSquare)
                }
            }
        }
        
        return squares
    }
    
    // MARK: - 攻击点位（控制点）计算

    /// 某一方全部棋子的攻击点位 → 攻击该点的棋子数。
    /// 「攻击」取几何控制语义：若该点上站着敌子，能否吃到它。与走子规则的区别：
    /// - 被己方棋子占据的点也算（保护同样是控制）
    /// - 炮：只有炮架之后的点算攻击点，炮架之前可平移到的空点不算
    /// - 不考虑吃子后己方是否被将军（被钉住的子仍视为在控制）
    static func getAttackedSquareCounts(isRed: Bool, piecesBySquare: [String: String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        let prefix = isRed ? "r" : "b"
        for (square, piece) in piecesBySquare where piece.hasPrefix(prefix) {
            for target in getAttackSquares(fromSquare: square, piecesBySquare: piecesBySquare) {
                counts[target, default: 0] += 1
            }
        }
        return counts
    }

    /// 单个棋子的攻击点位集合（语义见 getAttackedSquareCounts）
    static func getAttackSquares(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        guard let piece = piecesBySquare[fromSquare] else { return [] }

        switch piece {
        case "rR", "bR":
            return getRookAttacks(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rC", "bC":
            return getCannonAttacks(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rN", "bN":
            return getKnightAttacks(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rB", "bB":
            return getElephantAttacks(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rA", "bA":
            return getAdvisorAttacks(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        case "rK", "bK":
            return getKingAttacks(fromSquare: fromSquare)
        case "rP", "bP":
            return getPawnAttacks(fromSquare: fromSquare, piecesBySquare: piecesBySquare)
        default:
            return []
        }
    }

    /// 是否在红方九宫内：d-f 列 × 0-2 行
    static func isInRedPalace(_ square: String) -> Bool {
        let (col, row) = squareToCoordinate(square)
        return (3...5).contains(col) && (0...2).contains(row)
    }

    /// 是否在黑方九宫内：d-f 列 × 7-9 行
    static func isInBlackPalace(_ square: String) -> Bool {
        let (col, row) = squareToCoordinate(square)
        return (3...5).contains(col) && (7...9).contains(row)
    }

    private static let orthogonalDirections = [
        (colDelta: 1, rowDelta: 0),
        (colDelta: -1, rowDelta: 0),
        (colDelta: 0, rowDelta: 1),
        (colDelta: 0, rowDelta: -1)
    ]

    private static func isInsideBoard(col: Int, row: Int) -> Bool {
        return col >= 0 && col < BoardConstants.columns.count &&
               row >= 0 && row < BoardConstants.rows.count
    }

    // 车：沿直线的空点，加上（不论颜色的）第一个挡子所在点
    private static func getRookAttacks(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)

        for direction in orthogonalDirections {
            var col = fromCol + direction.colDelta
            var row = fromRow + direction.rowDelta
            while isInsideBoard(col: col, row: row) {
                let targetSquare = coordinateToSquare(col: col, row: row)
                squares.insert(targetSquare)
                if piecesBySquare[targetSquare] != nil { break }
                col += direction.colDelta
                row += direction.rowDelta
            }
        }
        return squares
    }

    // 炮：炮架之后的空点，加上（不论颜色的）炮架后第一个子所在点；炮架前的点不算
    private static func getCannonAttacks(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)

        for direction in orthogonalDirections {
            var col = fromCol + direction.colDelta
            var row = fromRow + direction.rowDelta
            var foundPlatform = false
            while isInsideBoard(col: col, row: row) {
                let targetSquare = coordinateToSquare(col: col, row: row)
                if foundPlatform {
                    squares.insert(targetSquare)
                    if piecesBySquare[targetSquare] != nil { break }
                } else if piecesBySquare[targetSquare] != nil {
                    foundPlatform = true
                }
                col += direction.colDelta
                row += direction.rowDelta
            }
        }
        return squares
    }

    // 马：不蹩腿的八个落点（不论落点上是谁）
    private static func getKnightAttacks(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)

        let moves = [
            (col: -1, row: 2, blockingSquare: (0, 1)),
            (col: 1, row: 2, blockingSquare: (0, 1)),
            (col: -1, row: -2, blockingSquare: (0, -1)),
            (col: 1, row: -2, blockingSquare: (0, -1)),
            (col: -2, row: 1, blockingSquare: (-1, 0)),
            (col: -2, row: -1, blockingSquare: (-1, 0)),
            (col: 2, row: 1, blockingSquare: (1, 0)),
            (col: 2, row: -1, blockingSquare: (1, 0))
        ]

        for move in moves {
            let newCol = fromCol + move.col
            let newRow = fromRow + move.row
            guard isInsideBoard(col: newCol, row: newRow) else { continue }

            let blockingSquare = coordinateToSquare(col: fromCol + move.blockingSquare.0, row: fromRow + move.blockingSquare.1)
            if piecesBySquare[blockingSquare] != nil { continue }

            squares.insert(coordinateToSquare(col: newCol, row: newRow))
        }
        return squares
    }

    // 相/象：不塞田心的四个落点（不论落点上是谁）
    private static func getElephantAttacks(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        let isRed = currentPiece.hasPrefix("r")

        let moves = [(col: 2, row: 2), (col: 2, row: -2), (col: -2, row: 2), (col: -2, row: -2)]

        for move in moves {
            let newCol = fromCol + move.col
            let newRow = fromRow + move.row
            guard newCol >= 0 && newCol < BoardConstants.columns.count else { continue }
            if isRed {
                guard newRow >= 0 && newRow <= 4 else { continue }
            } else {
                guard newRow >= 5 && newRow <= 9 else { continue }
            }

            let blockingSquare = coordinateToSquare(col: fromCol + move.col / 2, row: fromRow + move.row / 2)
            if piecesBySquare[blockingSquare] != nil { continue }

            squares.insert(coordinateToSquare(col: newCol, row: newRow))
        }
        return squares
    }

    // 士/仕：九宫内的斜向落点（不论落点上是谁）
    private static func getAdvisorAttacks(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        let isRed = currentPiece.hasPrefix("r")

        let validColumns = 3...5
        let validRows = isRed ? 0...2 : 7...9

        for move in [(col: 1, row: 1), (col: 1, row: -1), (col: -1, row: 1), (col: -1, row: -1)] {
            let newCol = fromCol + move.col
            let newRow = fromRow + move.row
            guard validColumns.contains(newCol) && validRows.contains(newRow) else { continue }
            squares.insert(coordinateToSquare(col: newCol, row: newRow))
        }
        return squares
    }

    // 帅/将：九宫内横竖相邻的落点（几何控制，不考虑将帅对脸限制）
    private static func getKingAttacks(fromSquare: String) -> Set<String> {
        var squares = Set<String>()
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        // 从当前所在行推断属于哪侧九宫（王必在己方九宫内）
        let validColumns = 3...5
        let validRows = fromRow <= 2 ? 0...2 : 7...9

        for direction in orthogonalDirections {
            let newCol = fromCol + direction.colDelta
            let newRow = fromRow + direction.rowDelta
            guard validColumns.contains(newCol) && validRows.contains(newRow) else { continue }
            squares.insert(coordinateToSquare(col: newCol, row: newRow))
        }
        return squares
    }

    // 兵/卒：身前一点，过河后加左右两点（不论落点上是谁）
    private static func getPawnAttacks(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        let isRed = currentPiece.hasPrefix("r")

        let newRow = fromRow + (isRed ? 1 : -1)
        if newRow >= 0 && newRow < BoardConstants.rows.count {
            squares.insert(coordinateToSquare(col: fromCol, row: newRow))
        }

        let hasCrossedRiver = (isRed && fromRow > 4) || (!isRed && fromRow < 5)
        if hasCrossedRiver {
            if fromCol > 0 {
                squares.insert(coordinateToSquare(col: fromCol - 1, row: fromRow))
            }
            if fromCol < BoardConstants.columns.count - 1 {
                squares.insert(coordinateToSquare(col: fromCol + 1, row: fromRow))
            }
        }
        return squares
    }

    // 兵/卒的移动规则
    private static func getPawnMoves(fromSquare: String, piecesBySquare: [String: String]) -> Set<String> {
        var squares = Set<String>()
        let currentPiece = piecesBySquare[fromSquare]!
        let (fromCol, fromRow) = squareToCoordinate(fromSquare)
        let isRed = currentPiece.hasPrefix("r")
        
        // 确定前进方向（红方向上，黑方向下）
        let forwardDirection = isRed ? 1 : -1
        
        // 前进一步
        let newRow = fromRow + forwardDirection
        
        // 检查是否在棋盘范围内
        if newRow >= 0 && newRow < BoardConstants.rows.count {
            let targetSquare = coordinateToSquare(col: fromCol, row: newRow)
            if canMoveTo(targetSquare: targetSquare, piecesBySquare: piecesBySquare, currentPiece: currentPiece) {
                squares.insert(targetSquare)
            }
        }
        
        // 判断是否过河
        let hasCrossedRiver = (isRed && fromRow > 4) || (!isRed && fromRow < 5)
        
        // 如果过河，可以向左右移动
        if hasCrossedRiver {
            // 向左移动
            if fromCol > 0 {
                let targetSquare = coordinateToSquare(col: fromCol - 1, row: fromRow)
                if canMoveTo(targetSquare: targetSquare, piecesBySquare: piecesBySquare, currentPiece: currentPiece) {
                    squares.insert(targetSquare)
                }
            }
            
            // 向右移动
            if fromCol < BoardConstants.columns.count - 1 {
                let targetSquare = coordinateToSquare(col: fromCol + 1, row: fromRow)
                if canMoveTo(targetSquare: targetSquare, piecesBySquare: piecesBySquare, currentPiece: currentPiece) {
                    squares.insert(targetSquare)
                }
            }
        }
        
        return squares
    }
}

struct BoardConstants {
    static let columns = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
    static let rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
} 
