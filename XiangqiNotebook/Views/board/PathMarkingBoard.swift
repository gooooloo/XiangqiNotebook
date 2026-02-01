import SwiftUI

// 定义动画时间常量
private let pieceAnimationDuration: Double = 0.3

struct PathMarkingBoard: View {
    // MARK: - 属性
    @Binding var pathGroups: [PathGroup]
    @Binding var selectedGroupIndex: Int
    @Binding var selectedPathIndex: Int
    let viewModel: BoardViewModel
    let onSquareClick: ((String) -> Void)? // 添加点击回调
    
    var body: some View {
        GeometryReader { geometry in
            let squareSizeWidth = geometry.size.width / CGFloat(XiangqiBoardUtils.columns.count)
            let squareSizeHeight = geometry.size.height / CGFloat(XiangqiBoardUtils.rows.count)
            let squareSize = min(squareSizeWidth, squareSizeHeight)
            
            let pieceDiffX = ((squareSizeWidth > squareSizeHeight) ? (squareSizeWidth - squareSizeHeight) / 2 : 0) + squareSize/2
            let pieceDiffY = ((squareSizeHeight > squareSizeWidth) ? (squareSizeHeight - squareSizeWidth) / 2 : 0) + squareSize/2
            
            let boardSize = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                // 1. 棋盘背景 (最底层)
                if let boardImage = Image.getCachedImage("board") {
                    boardImage
                        .resizable()
                        .frame(width: boardSize, height: boardSize)
                } else {
                    Color.gray.opacity(0.5)
                        .frame(width: boardSize, height: boardSize)
                }
                
                // 2. 棋子层
                ForEach(
                    viewModel.getPieceViewModels(),
                    id: \.id
                ) { pieceView in
                    if pieceView.square != "" {
                        let position = BoardViewModel.calculateDisplayPosition(
                            square: pieceView.square,
                            squareSizeWidth: squareSizeWidth,
                            squareSizeHeight: squareSizeHeight,
                            pieceDiffX: pieceDiffX,
                            pieceDiffY: pieceDiffY,
                            orientation: viewModel.getOrientation(),
                            isHorizontalFlipped: viewModel.getIsHorizontalFlipped()
                        )
                        
                        PieceView(
                            id: pieceView.id,
                            piece: pieceView.piece,
                            square: pieceView.square,
                            squareSize: squareSize,
                            position: position,
                            shouldAnimate: false
                        )
                    }
                }
                
                // 3. 路径层（最上层）
                PathView(
                    squareSizeWidth: squareSizeWidth,
                    squareSizeHeight: squareSizeHeight,
                    pieceDiffX: pieceDiffX,
                    pieceDiffY: pieceDiffY,
                    orientation: viewModel.getOrientation(),
                    isHorizontalFlipped: viewModel.getIsHorizontalFlipped(),
                    pathGroups: pathGroups,
                    selectedGroupIndex: selectedGroupIndex,
                    selectedPathIndex: selectedPathIndex,
                    piecesBySquare: viewModel.piecesBySquare,
                    animationDuration: pieceAnimationDuration
                )
            }
            .frame(width: boardSize, height: boardSize)
            .onTapGesture { location in
                let x = Int((location.x) / squareSizeWidth)
                let y = Int((location.y) / squareSizeHeight)
                
                guard x >= 0 && x < 9 && y >= 0 && y < 10 else { return }
                
                let row = viewModel.getOrientation() == "red" ? 9 - y : y
                let col1 = viewModel.getOrientation() == "red" ? x : 8 - x
                let col2 = viewModel.getIsHorizontalFlipped() ? 8 - col1 : col1
                
                let square = MoveRules.coordinateToSquare(col: col2, row: row)
                onSquareClick?(square)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
