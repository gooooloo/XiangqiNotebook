import Foundation

struct PieceMove: Equatable {
    public let piece: Character
    public let fromRow: Int
    public let fromColumn: Int
    public let toRow: Int
    public let toColumn: Int
}

class Move: Codable, Hashable {
    public let sourceFenId: Int
    public var targetFenId: Int? // nil means removed
    var comment: String?
    var badReason: String?

    #if DEBUG
    var moveStringForTesting: String?
    #endif
    
    // 编码和解码的键名定义
    enum CodingKeys: String, CodingKey {
        case sourceFenId = "source_fen_id"
        case targetFenId = "target_fen_id"
        case comment
        case badReason
    }
    
    // 自定义编码方法，只编码指定字段
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sourceFenId, forKey: .sourceFenId)
        try container.encodeIfPresent(targetFenId, forKey: .targetFenId)
        try container.encodeIfPresent(comment, forKey: .comment)
        try container.encodeIfPresent(badReason, forKey: .badReason)
    }

    
    init(sourceFenId: Int, targetFenId: Int?) {
        self.sourceFenId = sourceFenId
        self.targetFenId = targetFenId
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceFenId = try container.decode(Int.self, forKey: .sourceFenId)
        self.targetFenId = try container.decodeIfPresent(Int.self, forKey: .targetFenId)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
        self.badReason = try container.decodeIfPresent(String.self, forKey: .badReason)
    }
  
    var isRecommended: Bool {
        return hasAnyTagInComment(["#飞刀", "#党大师推荐", "#妙", "#重要", "#关键", "#推荐", "#好棋"])
    }

    func moveString(fenObjects2: [Int: FenObject], isHorizontalFlipped: Bool)-> String {
        #if DEBUG
        if let testString = moveStringForTesting {
            return testString
        }
        #endif

      return Move.stringifyMove(fenObjects2: fenObjects2, from: sourceFenId, to: targetFenId, backup: "TODO", isHorizontalFlipped: isHorizontalFlipped)
    }

    func pieceMove(fenObjects2: [Int: FenObject], isHorizontalFlipped: Bool) -> PieceMove? {
        return Move.extractPieceMove(fenObjects2: fenObjects2, from: sourceFenId, to: targetFenId)
    }

    func markAsRemoved() {
        targetFenId = nil
    }
  
    func isBad(_ getScoreByFenId: (Int) -> Int?) -> Bool {
        if hasAnyTagInComment(["#不好", "#错", "#中刀"]) {
            return true
        }
        
        let sourceFenId = self.sourceFenId
        if let targetFenId = self.targetFenId,
           let sourceScore = getScoreByFenId(sourceFenId),
           let targetScore = getScoreByFenId(targetFenId) {
            // 注意：这个移动是由 source_fen 中的玩家执行的，而不是 target_fen
            // source_fen 的分数是这个玩家的分数
            // target_fen 的分数是下一个玩家的分数
            let scoreBefore = sourceScore
            let scoreAfter = -1 * targetScore
            let scoreBeforeAbs = abs(scoreBefore)
            
            if scoreBeforeAbs >= 700 {
                // 大优大劣，减少 300 分算差
                if scoreAfter <= scoreBefore - 300 {
                    return true
                }
            } else if scoreBeforeAbs >= 200 {
                // 中等优劣，减少 150 分算差
                if scoreAfter <= scoreBefore - 150 {
                    return true
                }
            } else {
                // 均势，减少 100 分影响很大了
                if scoreAfter <= scoreBefore - 100 {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func hasAnyTagInComment(_ tagList: [String]) -> Bool {
        guard let comment = comment else { return false }
        return tagList.contains { comment.contains($0) }
    }
    
    // MARK: - Static Methods
    static func extractPieceMove(fenObjects2: [Int: FenObject], from fenId1: Int, to fenId2: Int?) -> PieceMove? {
        guard let fen1 = fenObjects2[fenId1]?.fen,
                let fenId2 = fenId2,
                let fen2 = fenObjects2[fenId2]?.fen
        else {
            return nil
        }

        func expandRow(_ row: String) -> String {
            var newRow = ""
            for char in row {
                if let num = Int(String(char)), num > 0 && num <= 9 {
                    newRow += String(repeating: ".", count: num)
                } else {
                    newRow.append(char)
                }
            }
            return newRow
        }
        
        func findDiffColumns(_ row1: String, _ row2: String) -> [Int] {
            var columns: [Int] = []
            for i in 0..<9 {
                let index = row1.index(row1.startIndex, offsetBy: i)
                if row1[index] != row2[index] {
                    columns.append(i)
                }
            }
            return columns
        }
        
        let fen1Components = fen1.split(separator: " ")
        let fen2Components = fen2.split(separator: " ")
        
        guard let fen1Board = fen1Components.first,
              let fen2Board = fen2Components.first else {
            return nil
        }
        
        let rows1 = fen1Board.split(separator: "/")
        let rows2 = fen2Board.split(separator: "/")
        
        guard rows1.count == 10, rows2.count == 10 else {
            return nil
        }
        
        var diffRows: [(before: String, after: String, index: Int)] = []
        for i in 0..<10 {
            if rows1[i] != rows2[i] {
                diffRows.append((
                    expandRow(String(rows1[i])),
                    expandRow(String(rows2[i])),
                    i
                ))
            }
        }
        
        // 处理平移
        if diffRows.count == 1 {
            let rowBefore = diffRows[0].before
            let rowAfter = diffRows[0].after
            let rowIndex = diffRows[0].index
            
            let diffColumns = findDiffColumns(rowBefore, rowAfter)
            guard diffColumns.count == 2 else {
                return nil
            }
            
            let column0 = diffColumns[0]
            let column1 = diffColumns[1]
            
            let index0 = rowAfter.index(rowAfter.startIndex, offsetBy: column0)
            let sourceColumn = rowAfter[index0] == "." ? column0 : column1
            let targetColumn = rowAfter[index0] == "." ? column1 : column0
            
            let pieceIndex = rowBefore.index(rowBefore.startIndex, offsetBy: sourceColumn)
            let piece = rowBefore[pieceIndex]
            
            return PieceMove(piece: piece, fromRow: rowIndex, fromColumn: sourceColumn, toRow: rowIndex, toColumn: targetColumn)
        }
        // 处理进退
        else if diffRows.count == 2 {
            let row1Before = diffRows[0].before
            let row1After = diffRows[0].after
            let row1Index = diffRows[0].index
            let row2Before = diffRows[1].before
            let row2After = diffRows[1].after
            let row2Index = diffRows[1].index
            
            let diffColumnsRow1 = findDiffColumns(row1Before, row1After)
            let diffColumnsRow2 = findDiffColumns(row2Before, row2After)
            
            guard diffColumnsRow1.count == 1, diffColumnsRow2.count == 1 else {
                return nil
            }
            
            let columnForRow1 = diffColumnsRow1[0]
            let columnForRow2 = diffColumnsRow2[0]
            
            let index1 = row1After.index(row1After.startIndex, offsetBy: columnForRow1)
            let index2 = row2After.index(row2After.startIndex, offsetBy: columnForRow2)
            
            var piece: Character
            var sourceRow: Int
            var targetRow: Int
            var sourceColumn: Int
            var targetColumn: Int
            
            if row1After[index1] == "." {
                // row1 -> row2
                sourceRow = row1Index
                targetRow = row2Index
                sourceColumn = columnForRow1
                targetColumn = columnForRow2
                let pieceIndex = row1Before.index(row1Before.startIndex, offsetBy: sourceColumn)
                piece = row1Before[pieceIndex]
            } else if row2After[index2] == "." {
                // row2 -> row1
                sourceRow = row2Index
                targetRow = row1Index
                sourceColumn = columnForRow2
                targetColumn = columnForRow1
                let pieceIndex = row2Before.index(row2Before.startIndex, offsetBy: sourceColumn)
                piece = row2Before[pieceIndex]
            } else {
                return nil
            }
            
            return PieceMove(piece: piece, fromRow: sourceRow, fromColumn: sourceColumn, toRow: targetRow, toColumn: targetColumn)
        }
        
        return nil
    }
    
    static func stringifyMove(fenObjects2: [Int: FenObject], from fenId1: Int, to fenId2: Int?, backup: String, isHorizontalFlipped: Bool) -> String {
      guard let fen1 = fenObjects2[fenId1]?.fen,
            let fenId2 = fenId2,
            let fen2 = fenObjects2[fenId2]?.fen
      else {
        return backup
      }

        func expandRow(_ row: String) -> String {
            var newRow = ""
            for char in row {
                if let num = Int(String(char)), num > 0 && num <= 9 {
                    newRow += String(repeating: ".", count: num)
                } else {
                    newRow.append(char)
                }
            }
            return newRow
        }
        
        func findDiffColumns(_ row1: String, _ row2: String) -> [Int] {
            var columns: [Int] = []
            for i in 0..<9 {
                let index = row1.index(row1.startIndex, offsetBy: i)
                if row1[index] != row2[index] {
                    columns.append(i)
                }
            }
            return columns
        }
        
        func stringifyPieceRed(_ ch: Character) -> String? {
            switch ch {
            case "P": return "兵"
            case "C": return "炮"
            case "R": return "车"
            case "N": return "马"
            case "B": return "相"
            case "A": return "仕"
            case "K": return "帅"
            default: return nil
            }
        }
        
        func stringifyPieceBlack(_ ch: Character) -> String? {
            switch ch {
            case "p": return "卒"
            case "c": return "炮"
            case "r": return "车"
            case "n": return "马"
            case "b": return "象"
            case "a": return "士"
            case "k": return "将"
            default: return nil
            }
        }
        
        let normalColumnOrder = !isHorizontalFlipped
        let redColumnTextArray = normalColumnOrder ? ["九", "八", "七", "六", "五", "四", "三", "二", "一"] : ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let blackColumnTextArray = normalColumnOrder ? ["１", "２", "３", "４", "５", "６", "７", "８", "９"] : ["9", "8", "7", "6", "5", "4", "3", "2", "1"]
        let redRowDeltaTextArray = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        let blackRowDeltaTextArray = ["", "１", "２", "３", "４", "５", "６", "７", "８", "９"]
        
        let fen1Components = fen1.split(separator: " ")
        let fen2Components = fen2.split(separator: " ")
        
        guard let fen1Board = fen1Components.first,
              let fen2Board = fen2Components.first else {
            return backup
        }
        
        let rows1 = fen1Board.split(separator: "/")
        let rows2 = fen2Board.split(separator: "/")
        
        guard rows1.count == 10, rows2.count == 10 else {
            return backup
        }
        
        var diffRows: [(before: String, after: String, index: Int)] = []
        for i in 0..<10 {
            if rows1[i] != rows2[i] {
                diffRows.append((
                    expandRow(String(rows1[i])),
                    expandRow(String(rows2[i])),
                    i
                ))
            }
        }
        
        // 处理平移
        if diffRows.count == 1 {
            let rowBefore = diffRows[0].before
            let rowAfter = diffRows[0].after
            
            let diffColumns = findDiffColumns(rowBefore, rowAfter)
            guard diffColumns.count == 2 else {
                return backup
            }
            
            let column0 = diffColumns[0]
            let column1 = diffColumns[1]
            
            let index0 = rowAfter.index(rowAfter.startIndex, offsetBy: column0)
            let sourceColumn = rowAfter[index0] == "." ? column0 : column1
            let targetColumn = rowAfter[index0] == "." ? column1 : column0
            
            let pieceIndex = rowBefore.index(rowBefore.startIndex, offsetBy: sourceColumn)
            let piece = rowBefore[pieceIndex]
            
            if let redPieceText = stringifyPieceRed(piece) {
                return "\(redPieceText)\(redColumnTextArray[sourceColumn])平\(redColumnTextArray[targetColumn])"
            } else if let blackPieceText = stringifyPieceBlack(piece) {
                return "\(blackPieceText)\(blackColumnTextArray[sourceColumn])平\(blackColumnTextArray[targetColumn])"
            }
        }
        // 处理进退
        else if diffRows.count == 2 {
            let row1Before = diffRows[0].before
            let row1After = diffRows[0].after
            let row1Index = diffRows[0].index
            let row2Before = diffRows[1].before
            let row2After = diffRows[1].after
            let row2Index = diffRows[1].index
            
            let diffColumnsRow1 = findDiffColumns(row1Before, row1After)
            let diffColumnsRow2 = findDiffColumns(row2Before, row2After)
            
            guard diffColumnsRow1.count == 1, diffColumnsRow2.count == 1 else {
                return backup
            }
            
            let columnForRow1 = diffColumnsRow1[0]
            let columnForRow2 = diffColumnsRow2[0]
            
            let index1 = row1After.index(row1After.startIndex, offsetBy: columnForRow1)
            let index2 = row2After.index(row2After.startIndex, offsetBy: columnForRow2)
            
            var piece: Character
            var sourceRow: Int
            var targetRow: Int
            var sourceColumn: Int
            var targetColumn: Int
            
            if row1After[index1] == "." {
                // row1 -> row2
                sourceRow = row1Index
                targetRow = row2Index
                sourceColumn = columnForRow1
                targetColumn = columnForRow2
                let pieceIndex = row1Before.index(row1Before.startIndex, offsetBy: sourceColumn)
                piece = row1Before[pieceIndex]
            } else if row2After[index2] == "." {
                // row2 -> row1
                sourceRow = row2Index
                targetRow = row1Index
                sourceColumn = columnForRow2
                targetColumn = columnForRow1
                let pieceIndex = row2Before.index(row2Before.startIndex, offsetBy: sourceColumn)
                piece = row2Before[pieceIndex]
            } else {
                return backup
            }
            
            if let redPieceText = stringifyPieceRed(piece) {
                let action = targetRow < sourceRow ? "进" : "退"
                
                if sourceColumn != targetColumn {
                    return "\(redPieceText)\(redColumnTextArray[sourceColumn])\(action)\(redColumnTextArray[targetColumn])"
                } else {
                    let rowDelta = abs(row1Index - row2Index)
                    return "\(redPieceText)\(redColumnTextArray[sourceColumn])\(action)\(redRowDeltaTextArray[rowDelta])"
                }
            } else if let blackPieceText = stringifyPieceBlack(piece) {
                let action = targetRow > sourceRow ? "进" : "退"
                
                if sourceColumn != targetColumn {
                    return "\(blackPieceText)\(blackColumnTextArray[sourceColumn])\(action)\(blackColumnTextArray[targetColumn])"
                } else {
                    let rowDelta = abs(row1Index - row2Index)
                    return "\(blackPieceText)\(blackColumnTextArray[sourceColumn])\(action)\(blackRowDeltaTextArray[rowDelta])"
                }
            }
        }
        
        return backup
    }

    // 实现 Hashable 协议
    // 注意：只使用不可变的标识属性来计算哈希值
    // comment 和 badReason 是可变的元数据，不应影响对象的标识
    func hash(into hasher: inout Hasher) {
        hasher.combine(sourceFenId)
        hasher.combine(targetFenId)
    }

    static func == (lhs: Move, rhs: Move) -> Bool {
        return lhs.sourceFenId == rhs.sourceFenId && lhs.targetFenId == rhs.targetFenId
    }
} 
