import SwiftUI

class BoardViewModel: Equatable {
    private var orientation: String
    private var isHorizontalFlipped: Bool
    private var showPath: Bool
    private var showAllNextMoves: Bool
    private var shouldAnimate: Bool
    private var fen: String
    private var pieceViewModels: [PieceViewModel] = createPieceViewModels()
    private var currentFenPathGroups: [PathGroup]
    private var nextMovesPathGroups: [PathGroup]
    private var allowConsecutiveMoves: Bool = false

    static func == (lhs: BoardViewModel, rhs: BoardViewModel) -> Bool {
        return lhs.pieceViewModels == rhs.pieceViewModels
    }

    static let `default` = BoardViewModel(
        fen: XiangqiBoardUtils.startFEN,
        orientation: "red",
        isHorizontalFlipped: false,
        showPath: true,
        showAllNextMoves: false,
        shouldAnimate: true,
        currentFenPathGroups: [],
        nextMovesPathGroups: []
    )

    init(fen: String, orientation: String, isHorizontalFlipped: Bool, showPath: Bool, showAllNextMoves: Bool, shouldAnimate: Bool, currentFenPathGroups: [PathGroup], nextMovesPathGroups: [PathGroup] = []) {
        self.fen = fen
        self.orientation = orientation
        self.isHorizontalFlipped = isHorizontalFlipped
        self.showPath = showPath
        self.showAllNextMoves = showAllNextMoves
        self.shouldAnimate = shouldAnimate
        self.currentFenPathGroups = currentFenPathGroups
        self.nextMovesPathGroups = nextMovesPathGroups
        updatePieceViews(fen: fen, force: true)
    }

    public var piecesBySquare: [String: String] {
        return XiangqiBoardUtils.fenToPiecesBySquare(self.fen)
    }

    public func getOrientation() -> String {
        return self.orientation
    }

    public func getIsHorizontalFlipped() -> Bool {
        return self.isHorizontalFlipped
    }

    public func getShowPath() -> Bool {
        return self.showPath
    }

    public func getShowAllNextMoves() -> Bool {
        return self.showAllNextMoves
    }

    public func getShouldAnimate() -> Bool {
        return self.shouldAnimate
    }

    public func getCurrentFenPathGroups() -> [PathGroup] {
        return self.currentFenPathGroups
    }

    public func getNextMovesPathGroups() -> [PathGroup] {
        return self.nextMovesPathGroups
    }
    
    public func getCurrentTurn() -> String {
        let components = fen.split(separator: " ")
        return String(components[1])
    }

    public func isPieceBelongToCurrentPlayer(_ piece: String) -> Bool {
        // 连走模式下允许移动任意棋子，不受走棋方限制
        if allowConsecutiveMoves { return true }
        let currentTurn = getCurrentTurn()
        return (currentTurn == "r" && piece.hasPrefix("r")) ||
               (currentTurn == "b" && piece.hasPrefix("b"))
    }

    public func updateAllowConsecutiveMoves(_ allow: Bool) {
        self.allowConsecutiveMoves = allow
    }

    private static func createPieceViewModels() -> [PieceViewModel] {
        var pieceViewModels: [PieceViewModel] = []

        var dic: [Int : [String]] = [:]
        dic[1] = ["rK", "bK"]
        dic[2] = ["rR", "rN", "rB", "rA", "rC", "bR", "bN", "bB", "bA", "bC"]
        dic[5] = ["rP", "bP"]

        var pieceViewId = 0
        for (key, value) in dic {
            for piece in value {
                for _ in 0..<key {
                    pieceViewModels.append(PieceViewModel(id: pieceViewId, piece: piece, square: ""))
                    pieceViewId += 1
                }
            }
        }   

        assert (pieceViewModels.count == 32, "pieceViewModels 不能为空")

        let sortedPieceViewModels = pieceViewModels.sorted { $0.id < $1.id }
        return sortedPieceViewModels
    }   

    private func reusePieceViewId(
        pieceView: PieceViewModel,
        square: String
    ) -> PieceViewModel {
        return PieceViewModel(
            id: pieceView.id, // KEY POINT: 使用旧 ID
            piece: pieceView.piece,
            square: square
          )
    }

    public func getPieceViewModels() -> [PieceViewModel] {
        return pieceViewModels
    }

    public func updateOrientation(orientation: String) {
        self.orientation = orientation
    }

    public func updateHorizontalFlipped(flipped: Bool) {
        self.isHorizontalFlipped = flipped
    }

    public func updateCurrentFenPathGroups(currentFenPathGroups: [PathGroup]) {
        self.currentFenPathGroups = currentFenPathGroups
    }

    public func updateNextMovesPathGroups(nextMovesPathGroups: [PathGroup]) {
        self.nextMovesPathGroups = nextMovesPathGroups
    }

    public func updatePieceViews(fen: String) {
        updatePieceViews(fen: fen, force: false)
    }

    public func updateShowPath(showPath: Bool) {
        self.showPath = showPath
    }

    public func updateShowAllNextMoves(showAllNextMoves: Bool) {
        self.showAllNextMoves = showAllNextMoves
    }

    public func updateShouldAnimate(_ shouldAnimate: Bool) {
        self.shouldAnimate = shouldAnimate
    }
  
    public func updatePieceViews(fen: String, force: Bool) {
        if self.fen == fen && !force {
            return
        }

        self.fen = fen

        assert (pieceViewModels.count == 32, "pieceViewModels 不能为空")

        let piecesBySquareLocal = piecesBySquare

        // 1. 获取所有需要显示的棋子位置
        var remainingSquares = Set(piecesBySquareLocal.keys)
        
        // 2-4. 将棋子视图分类并准备显示列表
        var usedPV = pieceViewModels.filter { $0.square != "" }
        var unusedPV = pieceViewModels.filter { $0.square == "" }
        var shownPV: [PieceViewModel] = []
        assert (usedPV.count + unusedPV.count + shownPV.count == 32, "棋子数量不正确")
        
        // 5. 第一轮:找到位置和棋子都匹配的视图，这是不动的棋子
        for square in remainingSquares {
            if let piece = piecesBySquareLocal[square],
               let index = usedPV.firstIndex(where: { $0.square == square && $0.piece == piece }) {
                let pieceView = reusePieceViewId(
                    pieceView: usedPV.remove(at: index),
                    square: square
                )
                shownPV.append(pieceView)
                assert (usedPV.count + unusedPV.count + shownPV.count == 32, "棋子数量不正确")

                remainingSquares.remove(square)
            }
        }
        
        // 6. 第二轮:找到棋子类型匹配但位置不同的视图，这是移动的棋子
        for square in remainingSquares {
            if let piece = piecesBySquareLocal[square],
               let index = usedPV.firstIndex(where: { $0.piece == piece }) {
                let pieceView = reusePieceViewId(
                    pieceView: usedPV.remove(at: index),
                    square: square
                )
                shownPV.append(pieceView)
                assert (usedPV.count + unusedPV.count + shownPV.count == 32, "棋子数量不正确")

                remainingSquares.remove(square)
            }
        }
        
        // 7. 第三轮:使用未使用的视图，这是新添加的棋子
        for square in remainingSquares {
            if let piece = piecesBySquareLocal[square],
               let index = unusedPV.firstIndex(where: { $0.piece == piece }) {
                let pieceView = reusePieceViewId(
                    pieceView: unusedPV.remove(at: index),
                    square: square
                )
                shownPV.append(pieceView)
                assert (usedPV.count + unusedPV.count + shownPV.count == 32, "棋子数量不正确")

                remainingSquares.remove(square)
            }
        }
        
        // 8. 确认所有位置都已处理
        assert(remainingSquares.isEmpty, "还有未处理的棋子位置")
        
        // 9-10. 重置未显示的已用视图，这是原来在棋盘上且现在不在的棋子
        for pieceView in usedPV {
          let resetPieceView = reusePieceViewId(
              pieceView: pieceView,
              square: ""
            )
            unusedPV.append(resetPieceView)
        }
        usedPV = []
        assert (usedPV.count + unusedPV.count + shownPV.count == 32, "棋子数量不正确")
        
        // 11. 更新视图数组
        let allPieceViewModels = shownPV + usedPV + unusedPV
        assert (allPieceViewModels.count == 32, "棋子数量不正确")

        // sort by id
        let sortedPieceViewModels = allPieceViewModels.sorted { $0.id < $1.id }
        self.pieceViewModels = sortedPieceViewModels
    }

    static func calculateDisplayPosition(
        square: String,
        squareSizeWidth: CGFloat,
        squareSizeHeight: CGFloat,
        pieceDiffX: CGFloat,
        pieceDiffY: CGFloat,
        orientation: String,
        isHorizontalFlipped: Bool
    ) -> CGPoint {
        let (col, row) = MoveRules.squareToCoordinate(square)
        let rotatedCol = orientation == "red" ? col : 8 - col
        let rotatedCol2 = isHorizontalFlipped ? 8 - rotatedCol : rotatedCol
        let rotatedRow = orientation == "red" ? 9 - row : row
        let x = CGFloat(rotatedCol2) * squareSizeWidth + pieceDiffX
        let y = CGFloat(rotatedRow) * squareSizeHeight + pieceDiffY
        return CGPoint(x: x, y: y)
    }
}


struct PieceViewModel: Equatable {
    let id: Int
    let piece: String
    let square: String
}
