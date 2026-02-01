import Foundation

// MARK: - Constants
extension XiangqiBoardUtils {
    static let startFEN = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
    static let columns = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
    static let rows = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
}

// MARK: - Utility Functions
enum XiangqiBoardUtils {
    static func fenToPiecesBySquare(_ fen: String) -> [String: String] {
        var piecesBySquare: [String: String] = [:]
        let components = fen.split(separator: " ")
        let boardPart = String(components[0])
        
        let rows = boardPart.split(separator: "/")
        let columnChars = Array("abcdefghi")
        
        for (rowIndex, row) in rows.enumerated() {
            var colIndex = 0
            for char in row {
                if let emptySquares = Int(String(char)) {
                    colIndex += emptySquares
                } else {
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