import SwiftUI

#if os(macOS)

@MainActor
class ForceGraphViewModel: ObservableObject {
    @Published var nodePositions: [Int: CGPoint] = [:]
    @Published var graphData: ForceGraphData?
    @Published var isSimulating: Bool = false
    @Published var hoveredNodeId: Int?
    @Published var selectedNodeId: Int?
    @Published var viewportOffset: CGPoint = .zero
    @Published var viewportScale: CGFloat = 1.0
    @Published var currentFenId: Int?

    var onNavigateToFenId: ((Int) -> Void)?

    private var simulation = ForceGraphSimulation()
    private var boardPreviewCache: [Int: BoardViewModel] = [:]
    private let maxCacheSize = 50

    func loadGraph(from databaseView: DatabaseView, rootFenId: Int?) {
        let data = ForceGraphData.build(from: databaseView, rootFenId: rootFenId)
        self.graphData = data
        self.nodePositions = data.nodes.mapValues { $0.position }
        self.isSimulating = true

        simulation.start(data: data) { [weak self] positions in
            guard let self = self else { return }
            self.nodePositions = positions
            if !self.simulation.isRunning {
                self.isSimulating = false
            }
        }
    }

    func stop() {
        simulation.stop()
        isSimulating = false
    }

    func hitTest(at point: CGPoint) -> Int? {
        let threshold: CGFloat = 12.0 / viewportScale
        for (fenId, pos) in nodePositions {
            let dx = point.x - pos.x
            let dy = point.y - pos.y
            let nodeRadius = nodeRadius(for: fenId)
            if dx * dx + dy * dy <= (nodeRadius + threshold) * (nodeRadius + threshold) {
                return fenId
            }
        }
        return nil
    }

    func handleClick(at viewPoint: CGPoint, canvasSize: CGSize) {
        let graphPoint = viewPointToGraphPoint(viewPoint, canvasSize: canvasSize)
        if let fenId = hitTest(at: graphPoint) {
            selectedNodeId = fenId
            onNavigateToFenId?(fenId)
        }
    }

    func handleHover(at viewPoint: CGPoint, canvasSize: CGSize) {
        let graphPoint = viewPointToGraphPoint(viewPoint, canvasSize: canvasSize)
        hoveredNodeId = hitTest(at: graphPoint)
    }

    func clearHover() {
        hoveredNodeId = nil
    }

    func getBoardPreview(for fenId: Int) -> BoardViewModel? {
        if let cached = boardPreviewCache[fenId] { return cached }
        guard let node = graphData?.nodes[fenId] else { return nil }

        let vm = BoardViewModel(
            fen: node.fen,
            orientation: "red",
            isHorizontalFlipped: false,
            showPath: false,
            showAllNextMoves: false,
            shouldAnimate: false,
            currentFenPathGroups: []
        )
        if boardPreviewCache.count >= maxCacheSize {
            boardPreviewCache.removeValue(forKey: boardPreviewCache.keys.first!)
        }
        boardPreviewCache[fenId] = vm
        return vm
    }

    func zoomToFit(canvasSize: CGSize) {
        guard !nodePositions.isEmpty else { return }
        let xs = nodePositions.values.map(\.x)
        let ys = nodePositions.values.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!
        let minY = ys.min()!, maxY = ys.max()!
        let graphWidth = maxX - minX + 100
        let graphHeight = maxY - minY + 100
        let scaleX = canvasSize.width / graphWidth
        let scaleY = canvasSize.height / graphHeight
        viewportScale = min(scaleX, scaleY, 2.0)
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        viewportOffset = CGPoint(
            x: canvasSize.width / 2 - centerX * viewportScale,
            y: canvasSize.height / 2 - centerY * viewportScale
        )
    }

    func nodeRadius(for fenId: Int) -> CGFloat {
        let edgeCount = graphData?.nodes[fenId]?.edgeCount ?? 0
        return min(max(CGFloat(edgeCount) * 1.5 + 4, 4), 14)
    }

    func nodeColor(for fenId: Int) -> Color {
        guard let node = graphData?.nodes[fenId] else { return .gray }
        if fenId == currentFenId { return .orange }
        if fenId == selectedNodeId { return .yellow }
        let maxDepth = max((graphData?.nodes.values.map(\.depth).max() ?? 1), 1)
        let ratio = CGFloat(node.depth) / CGFloat(maxDepth)
        return Color(
            hue: 0.0 + ratio * 0.6,
            saturation: 0.7,
            brightness: 0.85
        )
    }

    private func viewPointToGraphPoint(_ viewPoint: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - viewportOffset.x) / viewportScale,
            y: (viewPoint.y - viewportOffset.y) / viewportScale
        )
    }
}

#endif
