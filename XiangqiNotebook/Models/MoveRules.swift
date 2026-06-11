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
