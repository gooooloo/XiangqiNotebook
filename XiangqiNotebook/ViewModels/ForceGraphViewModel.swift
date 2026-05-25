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

    // 外观设置
    @Published var showArrows: Bool = false
    @Published var nodeSizeMultiplier: CGFloat = 1.0
    @Published var lineThickness: CGFloat = 0.5

    // 力度设置
    @Published var centerForce: CGFloat = 0.0
    @Published var repulsionStrength: CGFloat = 0.5
    @Published var attractionStrength: CGFloat = 0.5

    var onNavigateToFenId: ((Int) -> Void)?
    private(set) var cachedMaxDepth: Int = 1

    private var simulation = ForceGraphSimulation()
    private var boardPreviewCache: [Int: BoardViewModel] = [:]
    private let maxCacheSize = 50
    private var lastSnapshot: ForceGraphSnapshot?

    func loadGraph(from databaseView: DatabaseView, rootFenId: Int?) {
        let snapshot = ForceGraphSnapshot.extract(from: databaseView, rootFenId: rootFenId)
        lastSnapshot = snapshot
        self.isSimulating = true
        boardPreviewCache.removeAll()

        Task.detached(priority: .userInitiated) {
            let data = ForceGraphData.build(from: snapshot)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.graphData = data
                self.cachedMaxDepth = max(data.nodes.values.map(\.depth).max() ?? 1, 1)
                self.nodePositions = data.nodes.mapValues { $0.position }
                self.startSimulation(data: data)
            }
        }
    }

    var simulationParams: SimulationParams {
        let nodeCount = nodePositions.count
        let baseRepulsion: CGFloat = nodeCount > 5000 ? 15000 : 20000
        let baseAttraction: CGFloat = nodeCount > 5000 ? 0.003 : 0.002
        return SimulationParams(
            repulsionK: baseRepulsion * (0.2 + repulsionStrength * 1.6),
            attractionK: baseAttraction * (0.2 + attractionStrength * 1.6),
            centerForce: centerForce * 0.05
        )
    }

    private func startSimulation(data: ForceGraphData) {
        let params = simulationParams
        simulation.start(data: data, params: params) { [weak self] positions in
            guard let self = self else { return }
            self.nodePositions = positions
            if !self.simulation.isRunning {
                self.isSimulating = false
            }
        }
    }

    func restartSimulation() {
        guard let snapshot = lastSnapshot else { return }
        isSimulating = true
        Task.detached(priority: .userInitiated) {
            let data = ForceGraphData.build(from: snapshot)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.graphData = data
                self.cachedMaxDepth = max(data.nodes.values.map(\.depth).max() ?? 1, 1)
                self.nodePositions = data.nodes.mapValues { $0.position }
                self.startSimulation(data: data)
            }
        }
    }

    func stop() {
        simulation.stop()
        isSimulating = false
    }

    func dragNode(_ nodeId: Int, to position: CGPoint) {
        nodePositions[nodeId] = position
        simulation.dragState.pin(id: nodeId, position: position)
        if !simulation.isRunning, let data = graphData {
            var updated = data
            for (id, pos) in nodePositions {
                updated.nodes[id]?.position = pos
            }
            startSimulation(data: updated)
        }
    }

    func endDragNode() {
        simulation.dragState.unpin()
    }

    func hitTest(at point: CGPoint) -> Int? {
        let threshold: CGFloat = 12.0 / viewportScale
        for (fenId, pos) in nodePositions {
            let dx = point.x - pos.x
            let dy = point.y - pos.y
            let nodeRadius = nodeRadius(for: fenId)
            let r = nodeRadius + threshold
            if dx * dx + dy * dy <= r * r {
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
        let ratio = CGFloat(node.depth) / CGFloat(cachedMaxDepth)
        return Color(
            hue: 0.0 + ratio * 0.6,
            saturation: 0.7,
            brightness: 0.85
        )
    }

    func viewPointToGraphPoint(_ viewPoint: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - viewportOffset.x) / viewportScale,
            y: (viewPoint.y - viewportOffset.y) / viewportScale
        )
    }

    func visibleGraphRect(canvasSize: CGSize) -> CGRect {
        let topLeft = viewPointToGraphPoint(.zero, canvasSize: canvasSize)
        let bottomRight = viewPointToGraphPoint(CGPoint(x: canvasSize.width, y: canvasSize.height), canvasSize: canvasSize)
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        ).insetBy(dx: -50, dy: -50)
    }
}

#endif
