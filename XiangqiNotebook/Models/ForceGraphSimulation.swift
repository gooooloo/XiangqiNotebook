import Foundation
import CoreGraphics

#if os(macOS)

class ForceGraphSimulation {
    var repulsionConstant: CGFloat = 8000
    var attractionConstant: CGFloat = 0.005
    var dampingFactor: CGFloat = 0.85
    var idealEdgeLength: CGFloat = 100
    var coolingRate: CGFloat = 0.995
    private(set) var isRunning: Bool = false

    private var nodes: [Int: GraphNode] = [:]
    private var edges: [GraphEdge] = []
    private var temperature: CGFloat = 1.0
    private var task: Task<Void, Never>?

    func start(data: ForceGraphData, onUpdate: @escaping @MainActor @Sendable ([Int: CGPoint]) -> Void) {
        stop()
        nodes = data.nodes
        edges = data.edges
        temperature = 1.0
        isRunning = true

        let capturedNodes = nodes
        let capturedEdges = edges

        task = Task.detached(priority: .userInitiated) { [weak self] in
            var localNodes = capturedNodes
            let localEdges = capturedEdges
            let maxIterations = 500
            var temperature: CGFloat = 1.0
            let coolingRate: CGFloat = 0.995
            let repulsionK: CGFloat = 8000
            let attractionK: CGFloat = 0.005
            let damping: CGFloat = 0.85

            for iteration in 0..<maxIterations {
                if Task.isCancelled { break }

                var forces: [Int: CGPoint] = [:]
                let nodeIds = Array(localNodes.keys)

                // Repulsive forces between all pairs
                for i in 0..<nodeIds.count {
                    for j in (i+1)..<nodeIds.count {
                        let idA = nodeIds[i]
                        let idB = nodeIds[j]
                        guard let nodeA = localNodes[idA], let nodeB = localNodes[idB] else { continue }

                        let dx = nodeA.position.x - nodeB.position.x
                        let dy = nodeA.position.y - nodeB.position.y
                        let distSq = max(dx * dx + dy * dy, 1.0)
                        let force = repulsionK / distSq
                        let dist = sqrt(distSq)
                        let fx = force * dx / dist
                        let fy = force * dy / dist

                        forces[idA, default: .zero].x += fx
                        forces[idA, default: .zero].y += fy
                        forces[idB, default: .zero].x -= fx
                        forces[idB, default: .zero].y -= fy
                    }
                }

                // Attractive forces along edges
                for edge in localEdges {
                    guard let nodeA = localNodes[edge.sourceId], let nodeB = localNodes[edge.targetId] else { continue }

                    let dx = nodeB.position.x - nodeA.position.x
                    let dy = nodeB.position.y - nodeA.position.y
                    let dist = max(sqrt(dx * dx + dy * dy), 1.0)
                    let force = attractionK * dist
                    let fx = force * dx / dist
                    let fy = force * dy / dist

                    forces[edge.sourceId, default: .zero].x += fx
                    forces[edge.sourceId, default: .zero].y += fy
                    forces[edge.targetId, default: .zero].x -= fx
                    forces[edge.targetId, default: .zero].y -= fy
                }

                // Apply forces with temperature limiting
                let maxDisplacement = max(temperature * 50.0, 0.1)
                for id in nodeIds {
                    guard var node = localNodes[id] else { continue }
                    var f = forces[id] ?? .zero

                    node.velocity.x = (node.velocity.x + f.x) * damping
                    node.velocity.y = (node.velocity.y + f.y) * damping

                    let speed = sqrt(node.velocity.x * node.velocity.x + node.velocity.y * node.velocity.y)
                    if speed > maxDisplacement {
                        let scale = maxDisplacement / speed
                        node.velocity.x *= scale
                        node.velocity.y *= scale
                    }

                    node.position.x += node.velocity.x
                    node.position.y += node.velocity.y
                    localNodes[id] = node
                }

                temperature *= coolingRate

                if iteration % 5 == 0 {
                    let positions = localNodes.mapValues { $0.position }
                    await onUpdate(positions)
                }

                if temperature < 0.01 { break }
            }

            let finalPositions = localNodes.mapValues { $0.position }
            await MainActor.run { [weak self] in
                self?.isRunning = false
            }
            await onUpdate(finalPositions)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }
}

#endif
