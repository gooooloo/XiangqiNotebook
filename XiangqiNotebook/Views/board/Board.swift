import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 定义动画时间常量
private let pieceAnimationDuration: Double = 0.3
private let pieceAnimationDampingFraction: Double = 0.7

struct XiangqiBoard: View {
    // MARK: - 属性
    @Binding var viewModel: BoardViewModel
    @State private var highlightedSquares: Set<String> = []
    @State private var selectedSquare: String? = nil
    var onMove: ((String) -> Void)?  // 添加回调属性
    @State private var selectedGroupIndex: Int? = nil
    @State private var selectedPathIndex: Int? = nil
    
    // MARK: - 初始化
    init(viewModel: Binding<BoardViewModel> = .constant(.default), onMove: ((String) -> Void)? = nil) {
        _viewModel = viewModel
        self.onMove = onMove
    }
    
    // MARK: - 辅助函数
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
                            id: pieceView.id, // KEY POINT: 使用旧视图的ID
                            piece: pieceView.piece,
                            square: pieceView.square,
                            squareSize: squareSize,
                            position: position,
                            shouldAnimate: viewModel.getShouldAnimate()
                        )
                    }
                }
                
                // 3. 高亮层 (最上层)
                // 先显示选中的方格
                if let selectedSquare = selectedSquare {
                    let position = BoardViewModel.calculateDisplayPosition(
                        square: selectedSquare,
                        squareSizeWidth: squareSizeWidth,
                        squareSizeHeight: squareSizeHeight,
                        pieceDiffX: pieceDiffX,
                        pieceDiffY: pieceDiffY,
                        orientation: viewModel.getOrientation(),
                        isHorizontalFlipped: viewModel.getIsHorizontalFlipped()
                    )
                    
                    HighlightSquareView(
                        squareSize: squareSize,
                        position: position,
                        color: .red
                    )
                }
                
                // 显示其他高亮方格
                ForEach(Array(highlightedSquares), id: \.self) { square in
                    let position = BoardViewModel.calculateDisplayPosition(
                        square: square,
                        squareSizeWidth: squareSizeWidth,
                        squareSizeHeight: squareSizeHeight,
                        pieceDiffX: pieceDiffX,
                        pieceDiffY: pieceDiffY,
                        orientation: viewModel.getOrientation(),
                        isHorizontalFlipped: viewModel.getIsHorizontalFlipped()
                    )
                    
                    HighlightSquareView(
                        squareSize: squareSize,
                        position: position,
                        color: .blue
                    )
                }
                
                // 4. 路径层（最上层）
                // 根据 showPath 和 showAllNextMoves 分别决定是否渲染两种路径组
                if viewModel.getShowPath() {
                    PathView(
                        squareSizeWidth: squareSizeWidth,
                        squareSizeHeight: squareSizeHeight,
                        pieceDiffX: pieceDiffX,
                        pieceDiffY: pieceDiffY,
                        orientation: viewModel.getOrientation(),
                        isHorizontalFlipped: viewModel.getIsHorizontalFlipped(),
                        pathGroups: viewModel.getCurrentFenPathGroups(),
                        selectedGroupIndex: selectedGroupIndex ?? -1,
                        selectedPathIndex: selectedPathIndex ?? -1,
                        piecesBySquare: viewModel.piecesBySquare,
                        animationDuration: pieceAnimationDuration
                    )
                    .allowsHitTesting(false)
                }
                if viewModel.getShowAllNextMoves() {
                    PathView(
                        squareSizeWidth: squareSizeWidth,
                        squareSizeHeight: squareSizeHeight,
                        pieceDiffX: pieceDiffX,
                        pieceDiffY: pieceDiffY,
                        orientation: viewModel.getOrientation(),
                        isHorizontalFlipped: viewModel.getIsHorizontalFlipped(),
                        pathGroups: viewModel.getNextMovesPathGroups(),
                        selectedGroupIndex: -1,
                        selectedPathIndex: -1,
                        piecesBySquare: viewModel.piecesBySquare,
                        animationDuration: pieceAnimationDuration
                    )
                    .allowsHitTesting(false)
                }
            }
            .overlay(
                BoardEventCatcherView(
                    onTap: { point in
                        // 坐标系统转换：macOS 和 iOS 的坐标原点不同
                        //
                        // macOS (NSView): 原点在左下角，y 轴向上增长（数学坐标系）
                        //   示例：点击顶部时 y ≈ boardSize，点击底部时 y ≈ 0
                        //   需要转换：boardSize - y
                        //
                        // iOS (UIView): 原点在左上角，y 轴向下增长（屏幕坐标系）
                        //   示例：点击顶部时 y ≈ 0，点击底部时 y ≈ boardSize
                        //   不需要转换
                        //
                        // handleBoardTap 期望的是 SwiftUI 标准坐标（左上角为原点）
                    #if os(macOS)
                        let p = CGPoint(x: point.x, y: boardSize - point.y)
                    #else
                        let p = point
                    #endif
                        self.handleBoardTap(
                            p,
                            squareSize: squareSize,
                            squareSizeWidth: squareSizeWidth,
                            squareSizeHeight: squareSizeHeight,
                            pieceDiffX: pieceDiffX,
                            pieceDiffY: pieceDiffY
                        )
                    }
                )
                .frame(width: boardSize, height: boardSize)
            )
            .frame(width: boardSize, height: boardSize)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func handleBoardTap(
        _ p: CGPoint,
        squareSize: CGFloat,
        squareSizeWidth: CGFloat,
        squareSizeHeight: CGFloat,
        pieceDiffX: CGFloat,
        pieceDiffY: CGFloat
    ) {
        // 1) 先处理红色选中框点击（清空）
        if let selected = self.selectedSquare {
            let pos = BoardViewModel.calculateDisplayPosition(
                square: selected,
                squareSizeWidth: squareSizeWidth,
                squareSizeHeight: squareSizeHeight,
                pieceDiffX: pieceDiffX,
                pieceDiffY: pieceDiffY,
                orientation: viewModel.getOrientation(),
                isHorizontalFlipped: viewModel.getIsHorizontalFlipped()
            )
            let adjusted = squareSize * 0.9
            let rect = CGRect(
                x: pos.x - adjusted/2,
                y: pos.y - adjusted/2,
                width: adjusted,
                height: adjusted
            )
            if rect.contains(p) {
                self.highlightedSquares = []
                self.selectedSquare = nil
                return
            }
        }

        // 2) 再处理蓝色高亮格（执行走子）
        if !self.highlightedSquares.isEmpty, let selectedSquare2 = self.selectedSquare {
            let adjusted = squareSize * 0.9
            for sq in self.highlightedSquares {
                let pos = BoardViewModel.calculateDisplayPosition(
                    square: sq,
                    squareSizeWidth: squareSizeWidth,
                    squareSizeHeight: squareSizeHeight,
                    pieceDiffX: pieceDiffX,
                    pieceDiffY: pieceDiffY,
                    orientation: viewModel.getOrientation(),
                    isHorizontalFlipped: viewModel.getIsHorizontalFlipped()
                )
                let rect = CGRect(x: pos.x - adjusted/2, y: pos.y - adjusted/2, width: adjusted, height: adjusted)
                if rect.contains(p) {
                    if let newFen = XiangqiBoardUtils.getNewFenAfterMove(
                        from: selectedSquare2,
                        to: sq,
                        currentPieces: viewModel.piecesBySquare
                    ) {
                        self.onMove?(newFen)
                        self.highlightedSquares = []
                        self.selectedSquare = nil
                    }
                    return
                }
            }
        }

        // 3) 最后处理棋子点击（展示可走）
        if self.highlightedSquares.isEmpty {
            let pieceVMs = self.viewModel.getPieceViewModels()
            for pieceView in pieceVMs {
                if pieceView.square.isEmpty { continue }
                let pos = BoardViewModel.calculateDisplayPosition(
                    square: pieceView.square,
                    squareSizeWidth: squareSizeWidth,
                    squareSizeHeight: squareSizeHeight,
                    pieceDiffX: pieceDiffX,
                    pieceDiffY: pieceDiffY,
                    orientation: self.viewModel.getOrientation(),
                    isHorizontalFlipped: self.viewModel.getIsHorizontalFlipped()
                )
                let rect = CGRect(x: pos.x - squareSize/2, y: pos.y - squareSize/2, width: squareSize, height: squareSize)
                if rect.contains(p) {
                    if self.viewModel.isPieceBelongToCurrentPlayer(pieceView.piece) {
                        let legal = MoveRules.getLegalDestinationSquares(
                            fromSquare: pieceView.square,
                            piecesBySquare: self.viewModel.piecesBySquare
                        )
                        self.highlightedSquares = legal
                        self.selectedSquare = pieceView.square
                    }
                    return
                }
            }
        }
    }
}

struct PieceView: View {
    let id: Int
    let piece: String
    let square: String
    let squareSize: CGFloat
    let position: CGPoint
    let shouldAnimate: Bool
    
    var body: some View {
        if let pieceImage = Image.getCachedImage(piece) {
            pieceImage
                .resizable()
                .frame(width: squareSize, height: squareSize)
                .position(position)
                .animation(
                    shouldAnimate ?
                        .spring(response: pieceAnimationDuration, dampingFraction: pieceAnimationDampingFraction) :
                        .linear(duration: 0),
                    value: position
                )
        }
    }
}

struct HighlightSquareView: View {
    let squareSize: CGFloat
    let position: CGPoint
    let color: Color

    var body: some View {
        let adjustedSize = squareSize * 0.9  // 缩小到90%，使相邻方框有明显间隙
        Rectangle()
            .stroke(color, lineWidth: 2)
            .frame(width: adjustedSize, height: adjustedSize)
            .background(color.opacity(0.2))
            .position(x: position.x, y: position.y)
    }
}

// 统一的事件捕获层，支持 macOS 和 iOS
//
// 重要：此视图返回的坐标系统因平台而异！
// - macOS: 返回 NSView 坐标（原点在左下角，y 向上增长）
// - iOS: 返回 UIView 坐标（原点在左上角，y 向下增长）
// 使用时需要在 onTap 回调中进行相应的坐标转换
#if os(macOS)
struct BoardEventCatcherView: NSViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeNSView(context: Context) -> EventCatcherNSView {
        let v = EventCatcherNSView()
        v.onTap = onTap
        return v
    }

    func updateNSView(_ nsView: EventCatcherNSView, context: Context) {
        nsView.onTap = onTap
    }

    class EventCatcherNSView: NSView {
        var onTap: ((CGPoint) -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            onTap?(loc)
        }

        override func rightMouseDown(with event: NSEvent) {
            let loc = convert(event.locationInWindow, from: nil)
            onTap?(loc)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let inside = bounds.contains(point)
            if inside { return self } else { return nil }
        }
    }
}
#else
struct BoardEventCatcherView: UIViewRepresentable {
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> EventCatcherUIView {
        let v = EventCatcherUIView()
        v.onTap = onTap
        return v
    }

    func updateUIView(_ uiView: EventCatcherUIView, context: Context) {
        uiView.onTap = onTap
    }

    class EventCatcherUIView: UIView {
        var onTap: ((CGPoint) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupTapGesture()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupTapGesture()
        }

        private func setupTapGesture() {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            self.addGestureRecognizer(tapGesture)
            self.isUserInteractionEnabled = true
            self.backgroundColor = .clear
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: self)
            onTap?(location)
        }
    }
}
#endif

#Preview {
    XiangqiBoard()
} 
