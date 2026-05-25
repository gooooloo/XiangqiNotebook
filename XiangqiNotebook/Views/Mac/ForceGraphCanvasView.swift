import SwiftUI

#if os(macOS)

struct ForceGraphCanvasView: View {
    @ObservedObject var viewModel: ForceGraphViewModel
    @State private var dragStart: CGPoint?
    @State private var initialOffset: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                canvas(size: geometry.size)
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
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                viewModel.zoomToFit(canvasSize: geometry.size)
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

            // Draw edges
            for edge in viewModel.graphData?.edges ?? [] {
                guard let from = viewModel.nodePositions[edge.sourceId],
                      let to = viewModel.nodePositions[edge.targetId] else { continue }

                let screenFrom = graphToScreen(from, offset: offset, scale: scale)
                let screenTo = graphToScreen(to, offset: offset, scale: scale)

                // Skip edges outside visible area
                if !isLineVisible(from: screenFrom, to: screenTo, in: canvasSize) { continue }

                var path = Path()
                path.move(to: screenFrom)
                path.addLine(to: screenTo)

                let isHovered = edge.sourceId == viewModel.hoveredNodeId || edge.targetId == viewModel.hoveredNodeId
                context.stroke(
                    path,
                    with: .color(isHovered ? .blue.opacity(0.6) : .gray.opacity(0.3)),
                    lineWidth: isHovered ? 1.5 : 0.8
                )

                // Draw arrowhead
                drawArrowhead(context: &context, from: screenFrom, to: screenTo, scale: scale, isHovered: isHovered)
            }

            // Draw nodes
            for (fenId, pos) in viewModel.nodePositions {
                let screenPos = graphToScreen(pos, offset: offset, scale: scale)
                if !isPointVisible(screenPos, in: canvasSize, margin: 20) { continue }

                let radius = viewModel.nodeRadius(for: fenId) * scale
                let rect = CGRect(
                    x: screenPos.x - radius,
                    y: screenPos.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let color = viewModel.nodeColor(for: fenId)
                context.fill(Path(ellipseIn: rect), with: .color(color))

                if fenId == viewModel.hoveredNodeId || fenId == viewModel.currentFenId {
                    let outlineRect = rect.insetBy(dx: -2, dy: -2)
                    context.stroke(
                        Path(ellipseIn: outlineRect),
                        with: .color(fenId == viewModel.currentFenId ? .orange : .white),
                        lineWidth: 2
                    )
                }
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
                }
                viewModel.viewportOffset = CGPoint(
                    x: initialOffset.x + value.translation.width,
                    y: initialOffset.y + value.translation.height
                )
            }
            .onEnded { _ in
                dragStart = nil
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

    private func isLineVisible(from: CGPoint, to: CGPoint, in size: CGSize) -> Bool {
        let margin: CGFloat = 50
        let rect = CGRect(x: -margin, y: -margin, width: size.width + margin * 2, height: size.height + margin * 2)
        return rect.contains(from) || rect.contains(to)
    }

    private func isPointVisible(_ point: CGPoint, in size: CGSize, margin: CGFloat) -> Bool {
        point.x >= -margin && point.x <= size.width + margin &&
        point.y >= -margin && point.y <= size.height + margin
    }

    private func drawArrowhead(context: inout GraphicsContext, from: CGPoint, to: CGPoint, scale: CGFloat, isHovered: Bool) {
        let arrowLength: CGFloat = 8 * scale
        let arrowAngle: CGFloat = .pi / 6

        let dx = to.x - from.x
        let dy = to.y - from.y
        let angle = atan2(dy, dx)

        let tipX = to.x
        let tipY = to.y

        var arrowPath = Path()
        arrowPath.move(to: CGPoint(x: tipX, y: tipY))
        arrowPath.addLine(to: CGPoint(
            x: tipX - arrowLength * cos(angle - arrowAngle),
            y: tipY - arrowLength * sin(angle - arrowAngle)
        ))
        arrowPath.addLine(to: CGPoint(
            x: tipX - arrowLength * cos(angle + arrowAngle),
            y: tipY - arrowLength * sin(angle + arrowAngle)
        ))
        arrowPath.closeSubpath()

        context.fill(arrowPath, with: .color(isHovered ? .blue.opacity(0.6) : .gray.opacity(0.5)))
    }
}

#endif
