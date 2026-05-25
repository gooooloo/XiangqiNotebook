import Foundation
import CoreGraphics

#if os(macOS)

private struct QuadTreeNode {
    var centerOfMass: CGPoint = .zero
    var totalMass: Int = 0
    var bounds: CGRect
    var children: [QuadTreeNode]? = nil
    var nodeId: Int? = nil

    mutating func insert(id: Int, position: CGPoint) {
        if bounds.width < 1 { return }

        if totalMass == 0 {
            nodeId = id
            centerOfMass = position
            totalMass = 1
            return
        }

        if children == nil {
            subdivide()
            if let existingId = nodeId, existingId != id {
                nodeId = nil
                insertIntoChild(id: existingId, position: centerOfMass)
            }
        }

        let newCx = (centerOfMass.x * CGFloat(totalMass) + position.x) / CGFloat(totalMass + 1)
        let newCy = (centerOfMass.y * CGFloat(totalMass) + position.y) / CGFloat(totalMass + 1)
        centerOfMass = CGPoint(x: newCx, y: newCy)
        totalMass += 1
        nodeId = nil

        insertIntoChild(id: id, position: position)
    }

    private mutating func subdivide() {
        let midX = bounds.midX
        let midY = bounds.midY
        let w = bounds.width / 2
        let h = bounds.height / 2
        children = [
            QuadTreeNode(bounds: CGRect(x: bounds.minX, y: bounds.minY, width: w, height: h)),
            QuadTreeNode(bounds: CGRect(x: midX, y: bounds.minY, width: w, height: h)),
            QuadTreeNode(bounds: CGRect(x: bounds.minX, y: midY, width: w, height: h)),
            QuadTreeNode(bounds: CGRect(x: midX, y: midY, width: w, height: h)),
        ]
    }

    private mutating func insertIntoChild(id: Int, position: CGPoint) {
        guard var kids = children else { return }
        let midX = bounds.midX
        let midY = bounds.midY
        let idx = (position.x >= midX ? 1 : 0) + (position.y >= midY ? 2 : 0)
        kids[idx].insert(id: id, position: position)
        children = kids
    }

    func calculateRepulsion(on targetPos: CGPoint, repulsionK: CGFloat, theta: CGFloat, force: inout CGPoint) {
        if totalMass == 0 { return }

        let dx = targetPos.x - centerOfMass.x
        let dy = targetPos.y - centerOfMass.y
        let distSq = max(dx * dx + dy * dy, 1.0)

        if nodeId != nil || children == nil {
            if distSq > 1.0 {
                let f = repulsionK * CGFloat(totalMass) / distSq
                let dist = sqrt(distSq)
                force.x += f * dx / dist
                force.y += f * dy / dist
            }
            return
        }

        let size = bounds.width
        if size * size / distSq < theta * theta {
            let f = repulsionK * CGFloat(totalMass) / distSq
            let dist = sqrt(distSq)
            force.x += f * dx / dist
            force.y += f * dy / dist
            return
        }

        if let kids = children {
            for child in kids {
                child.calculateRepulsion(on: targetPos, repulsionK: repulsionK, theta: theta, force: &force)
            }
        }
    }
}

class ForceGraphSimulation {
    private(set) var isRunning: Bool = false
    private var task: Task<Void, Never>?

    func start(data: ForceGraphData, onUpdate: @escaping @MainActor @Sendable ([Int: CGPoint]) -> Void) {
        stop()
        isRunning = true

        let capturedNodes = data.nodes
        let capturedEdges = data.edges

        task = Task.detached(priority: .userInitiated) { [weak self] in
            var localNodes = capturedNodes
            let localEdges = capturedEdges
            let nodeCount = localNodes.count
            let maxIterations = min(500, max(200, 1000 - nodeCount / 20))
            var temperature: CGFloat = 1.5
            let coolingRate: CGFloat = nodeCount > 5000 ? 0.99 : 0.995
            let repulsionK: CGFloat = nodeCount > 5000 ? 15000 : 20000
            let attractionK: CGFloat = nodeCount > 5000 ? 0.003 : 0.002
            let damping: CGFloat = 0.8
            let theta: CGFloat = 1.0
            let updateInterval = nodeCount > 5000 ? 10 : 5

            for iteration in 0..<maxIterations {
                if Task.isCancelled { break }

                let nodeIds = Array(localNodes.keys)

                // Build quadtree
                var minX: CGFloat = .infinity, minY: CGFloat = .infinity
                var maxX: CGFloat = -.infinity, maxY: CGFloat = -.infinity
                for (_, node) in localNodes {
                    minX = min(minX, node.position.x)
                    minY = min(minY, node.position.y)
                    maxX = max(maxX, node.position.x)
                    maxY = max(maxY, node.position.y)
                }
                let size = max(maxX - minX, maxY - minY) + 10
                var tree = QuadTreeNode(bounds: CGRect(x: minX - 5, y: minY - 5, width: size, height: size))
                for (id, node) in localNodes {
                    tree.insert(id: id, position: node.position)
                }

                // Repulsive forces via Barnes-Hut
                var forces: [Int: CGPoint] = [:]
                for id in nodeIds {
                    guard let node = localNodes[id] else { continue }
                    var f = CGPoint.zero
                    tree.calculateRepulsion(on: node.position, repulsionK: repulsionK, theta: theta, force: &f)
                    forces[id] = f
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

                // Apply forces
                let maxDisplacement = max(temperature * 50.0, 0.1)
                for id in nodeIds {
                    guard var node = localNodes[id] else { continue }
                    let f = forces[id] ?? .zero
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
                if iteration % updateInterval == 0 {
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
