import Foundation

// MARK: - Constants
extension XiangqiBoardUtils {
    static let startFEN = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
    static let columns = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
    static let rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
}

// MARK: - Utility Functions
enum XiangqiBoardUtils {
    /// 校验 FEN 的棋盘部分结构是否合法：10 行、每行恰好 9 列、字符集正确
    /// 不检查棋子数量等规则层面的合法性；外部输入（如 PGN 的 FEN 头）入库前必须先过此校验
    static func isValidBoardFen(_ fen: String) -> Bool {
        let components = fen.split(separator: " ")
        guard let boardPart = components.first else { return false }

        let rows = boardPart.split(separator: "/")
        guard rows.count == 10 else { return false }

        let validPieces = Set("rnbakcpRNBAKCP")
        for row in rows {
            var colCount = 0
            for char in row {
                if let empty = char.wholeNumberValue, (1...9).contains(empty) {
                    colCount += empty
                } else if validPieces.contains(char) {
                    colCount += 1
                } else {
                    return false
                }
            }
            guard colCount == 9 else { return false }
        }
        return true
    }

    static func fenToPiecesBySquare(_ fen: String) -> [String: String] {
        var piecesBySquare: [String: String] = [:]
        let components = fen.split(separator: " ")
        guard let firstComponent = components.first else { return [:] }
        let boardPart = String(firstComponent)

        let rows = boardPart.split(separator: "/")
        let columnChars = Array("abcdefghi")

        for (rowIndex, row) in rows.enumerated() {
            guard rowIndex < 10 else { break }
            var colIndex = 0
            for char in row {
                if let emptySquares = Int(String(char)) {
                    colIndex += emptySquares
                } else {
                    guard colIndex < columnChars.count else { break }
                    let square = String(columnChars[colIndex]) + String(9 - rowIndex)
                    let piece = fenToPieceCode(String(char))
                    piecesBySquare[square] = piece
                    colIndex += 1
                }
            }
        }

        return piecesBySquare
    }
    
    static func fenToPieceCode(_ piece: String) -> String {
        if piece.lowercased() == piece {
            return "b" + piece.uppercased()
        }
        return "r" + piece.uppercased()
    }
    
    static func piecesBySquareToFen(_ piecesBySquare: [String: String], currentTurn: String) -> String {
        var fenRows: [String] = []
        let columnChars = Array("abcdefghi")
        
        // 遍历每一行（从上到下）
        for rowIndex in 0...9 {
            var fenRow = ""
            var emptyCount = 0
            
            // 遍历每一列（从左到右）
            for colIndex in 0...8 {
                let square = String(columnChars[colIndex]) + String(9 - rowIndex)
                
                if let piece = piecesBySquare[square] {
                    // 如果之前有空格，先添加数字
                    if emptyCount > 0 {
                        fenRow += String(emptyCount)
                        emptyCount = 0
                    }
                    // 添加棋子符号
                    fenRow += pieceCodeToFen(piece)
                } else {
                    emptyCount += 1
                }
            }
            
            // 处理行末的空格
            if emptyCount > 0 {
                fenRow += String(emptyCount)
            }
            
            fenRows.append(fenRow)
        }
        
        // 添加轮次指示符
        return fenRows.joined(separator: "/") + " " + currentTurn
    }
    
    static func pieceCodeToFen(_ pieceCode: String) -> String {
        // 移除颜色前缀（'r'或'b'）并获取棋子类型
        let piece = String(pieceCode.dropFirst())
        // 如果是黑方棋子（以'b'开头），返回小写字母
        return pieceCode.hasPrefix("b") ? piece.lowercased() : piece
    }
    
    /// 将 UCI 着法（如 "h2e2"）应用到给定 FEN，返回新 FEN
    static func getNewFenAfterUCIMove(uciMove: String, fen: String) -> String? {
        guard uciMove.count == 4 else { return nil }
        let chars = Array(uciMove)
        let from = String(chars[0...1])
        let to = String(chars[2...3])
        let pieces = fenToPiecesBySquare(fen)
        return getNewFenAfterMove(from: from, to: to, currentPieces: pieces)
    }

    static func getNewFenAfterMove(from: String, to: String, currentPieces: [String: String]) -> String? {
        guard let movingPiece = currentPieces[from] else { return nil }
        
        // 使用 Dictionary(uniqueKeysWithValues:) 创建深拷贝
        var newPieces = Dictionary(uniqueKeysWithValues: currentPieces.map { ($0.key, $0.value) })
        
        // 移除原位置的棋子
        newPieces.removeValue(forKey: from)
        
        // 放置到新位置
        newPieces[to] = movingPiece
        
        // 根据移动的棋子确定下一步轮到谁走
        let newTurn = movingPiece.hasPrefix("r") ? "b" : "r"
        
        // 返回新的FEN字符串
        return piecesBySquareToFen(newPieces, currentTurn: newTurn)
    }
} 