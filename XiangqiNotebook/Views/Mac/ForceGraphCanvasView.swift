import SwiftUI

#if os(macOS)

struct ScrollWheelView: NSViewRepresentable {
    var onScroll: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }

    class ScrollWheelNSView: NSView {
        var onScroll: ((CGFloat, CGPoint) -> Void)?

        override func scrollWheel(with event: NSEvent) {
            let delta = event.deltaY
            if abs(delta) > 0.01 {
                let location = convert(event.locationInWindow, from: nil)
                let flippedY = bounds.height - location.y
                onScroll?(delta, CGPoint(x: location.x, y: flippedY))
            }
        }
    }
}

struct ForceGraphCanvasView: View {
    @ObservedObject var viewModel: ForceGraphViewModel
    @State private var dragStart: CGPoint?
    @State private var initialOffset: CGPoint = .zero
    @State private var draggingNodeId: Int?
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                canvas(size: geometry.size)
                    .drawingGroup()
                    .overlay(
                        ScrollWheelView { delta, location in
                            let zoomFactor: CGFloat = delta > 0 ? 1.05 : 0.95
                            let oldScale = viewModel.viewportScale
                            let newScale = max(0.01, min(oldScale * zoomFactor, 10.0))
                            let ratio = newScale / oldScale
                            viewModel.viewportOffset.x = location.x - (location.x - viewModel.viewportOffset.x) * ratio
                            viewModel.viewportOffset.y = location.y - (location.y - viewModel.viewportOffset.y) * ratio
                            viewModel.viewportScale = newScale
                        }
                    )
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            viewModel.handleHover(at: location, canvasSize: geometry.size)
                        case .ended:
                            viewModel.clearHover()
                        @unknown default:
                            break
                        }
                    }
                    .onTapGesture { location in
                        viewModel.handleClick(at: location, canvasSize: geometry.size)
                    }

                if let hoveredId = viewModel.hoveredNodeId,
                   let pos = viewModel.nodePositions[hoveredId] {
                    boardPreviewOverlay(fenId: hoveredId, nodePos: pos, canvasSize: geometry.size)
                }

                if viewModel.isSimulating {
                    VStack {
                        HStack {
                            Spacer()
                            Text("布局计算中...")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                                .padding(8)
                        }
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(viewModel.nodePositions.count) 局面")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(4)
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                canvasSize = geometry.size
                viewModel.zoomToFit(canvasSize: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("适应窗口") {
                    if let window = NSApp.keyWindow {
                        let size = window.contentView?.bounds.size ?? CGSize(width: 800, height: 600)
                        viewModel.zoomToFit(canvasSize: size)
                    }
                }
            }
        }
    }

    private func canvas(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let offset = viewModel.viewportOffset
            let scale = viewModel.viewportScale
            let visibleRect = viewModel.visibleGraphRect(canvasSize: canvasSize)
            let nodeCount = viewModel.nodePositions.count
            let showEdges = nodeCount < 20000 && scale > 0.05

            if showEdges {
                drawEdges(context: &context, canvasSize: canvasSize, offset: offset, scale: scale, visibleRect: visibleRect)
            }

            drawNodes(context: &context, canvasSize: canvasSize, offset: offset, scale: scale, visibleRect: visibleRect)
        }
    }

    private func drawEdges(context: inout GraphicsContext, canvasSize: CGSize, offset: CGPoint, scale: CGFloat, visibleRect: CGRect) {
        let hoveredId = viewModel.hoveredNodeId
        var normalPath = Path()
        var hoveredPath = Path()

        for edge in viewModel.graphData?.edges ?? [] {
            guard let from = viewModel.nodePositions[edge.sourceId],
                  let to = viewModel.nodePositions[edge.targetId] else { continue }

            guard visibleRect.contains(from) || visibleRect.contains(to) else { continue }

            let screenFrom = graphToScreen(from, offset: offset, scale: scale)
            let screenTo = graphToScreen(to, offset: offset, scale: scale)

            let isHovered = hoveredId != nil && (edge.sourceId == hoveredId || edge.targetId == hoveredId)
            if isHovered {
                hoveredPath.move(to: screenFrom)
                hoveredPath.addLine(to: screenTo)
            } else {
                normalPath.move(to: screenFrom)
                normalPath.addLine(to: screenTo)
            }
        }

        context.stroke(normalPath, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
        if !hoveredPath.isEmpty {
            context.stroke(hoveredPath, with: .color(.blue.opacity(0.6)), lineWidth: 1.5)
        }
    }

    private func drawNodes(context: inout GraphicsContext, canvasSize: CGSize, offset: CGPoint, scale: CGFloat, visibleRect: CGRect) {
        let minVisibleRadius: CGFloat = 0.5
        let hoveredId = viewModel.hoveredNodeId
        let currentId = viewModel.currentFenId

        for (fenId, pos) in viewModel.nodePositions {
            guard visibleRect.contains(pos) else { continue }

            let screenPos = graphToScreen(pos, offset: offset, scale: scale)
            let radius = max(viewModel.nodeRadius(for: fenId) * scale, minVisibleRadius)

            let rect = CGRect(
                x: screenPos.x - radius,
                y: screenPos.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let color = viewModel.nodeColor(for: fenId)
            context.fill(Path(ellipseIn: rect), with: .color(color))

            if fenId == hoveredId || fenId == currentId {
                let outlineRect = rect.insetBy(dx: -2, dy: -2)
                context.stroke(
                    Path(ellipseIn: outlineRect),
                    with: .color(fenId == currentId ? .orange : .white),
                    lineWidth: 2
                )
            }
        }
    }

    @ViewBuilder
    private func boardPreviewOverlay(fenId: Int, nodePos: CGPoint, canvasSize: CGSize) -> some View {
        if let boardVM = viewModel.getBoardPreview(for: fenId) {
            let screenPos = graphToScreen(nodePos, offset: viewModel.viewportOffset, scale: viewModel.viewportScale)
            let previewSize: CGFloat = 180
            let xOffset: CGFloat = screenPos.x + previewSize + 20 > canvasSize.width ? -(previewSize + 20) : 20
            let yPos = min(max(screenPos.y - previewSize / 2, 10), canvasSize.height - previewSize - 10)

            ForceGraphBoardPreview(boardViewModel: boardVM, fenId: fenId, edgeCount: viewModel.graphData?.nodes[fenId]?.edgeCount ?? 0)
                .frame(width: previewSize, height: previewSize + 30)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .shadow(radius: 4)
                .position(x: screenPos.x + xOffset + previewSize / 2, y: yPos + previewSize / 2)
                .allowsHitTesting(false)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    initialOffset = viewModel.viewportOffset
                    let graphPoint = viewModel.viewPointToGraphPoint(value.startLocation, canvasSize: canvasSize)
                    draggingNodeId = viewModel.hitTest(at: graphPoint)
                }

                if let nodeId = draggingNodeId {
                    let graphPoint = viewModel.viewPointToGraphPoint(value.location, canvasSize: canvasSize)
                    viewModel.dragNode(nodeId, to: graphPoint)
                } else {
                    viewModel.viewportOffset = CGPoint(
                        x: initialOffset.x + value.translation.width,
                        y: initialOffset.y + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                if draggingNodeId != nil {
                    viewModel.endDragNode()
                }
                dragStart = nil
                draggingNodeId = nil
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newScale = max(0.1, min(viewModel.viewportScale * value, 5.0))
                viewModel.viewportScale = newScale
            }
    }

    private func graphToScreen(_ point: CGPoint, offset: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.x,
            y: point.y * scale + offset.y
        )
    }
}

#endif
