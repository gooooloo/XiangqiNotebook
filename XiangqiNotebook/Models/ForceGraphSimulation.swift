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

final class DragState: @unchecked Sendable {
    private let lock = NSLock()
    private var _pinnedId: Int?
    private var _pinnedPosition: CGPoint?
    private var _reheat: Bool = false

    var pinnedId: Int? {
        lock.lock()
        defer { lock.unlock() }
        return _pinnedId
    }

    var pinnedPosition: CGPoint? {
        lock.lock()
        defer { lock.unlock() }
        return _pinnedPosition
    }

    func consumeReheat() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let val = _reheat
        _reheat = false
        return val
    }

    func pin(id: Int, position: CGPoint) {
        lock.lock()
        _pinnedId = id
        _pinnedPosition = position
        _reheat = true
        lock.unlock()
    }

    func updatePosition(_ position: CGPoint) {
        lock.lock()
        _pinnedPosition = position
        lock.unlock()
    }

    func unpin() {
        lock.lock()
        _pinnedId = nil
        _pinnedPosition = nil
        lock.unlock()
    }
}

struct SimulationParams: Sendable {
    var repulsionK: CGFloat = 20000
    var attractionK: CGFloat = 0.002
    var centerForce: CGFloat = 0.0
}

class ForceGraphSimulation {
    private(set) var isRunning: Bool = false
    let dragState = DragState()
    private var task: Task<Void, Never>?

    func start(data: ForceGraphData, params: SimulationParams = SimulationParams(), onUpdate: @escaping @MainActor @Sendable ([Int: CGPoint]) -> Void) {
        stop()
        isRunning = true

        let capturedNodes = data.nodes
        let capturedEdges = data.edges
        let dragState = self.dragState

        task = Task.detached(priority: .userInitiated) { [weak self] in
            var localNodes = capturedNodes
            let localEdges = capturedEdges
            let nodeCount = localNodes.count
            let maxIterations = 10000
            var temperature: CGFloat = 2.0
            let coolingRate: CGFloat = 0.997
            let repulsionK: CGFloat = params.repulsionK
            let attractionK: CGFloat = params.attractionK
            let centerForceK: CGFloat = params.centerForce
            let damping: CGFloat = 0.8
            let theta: CGFloat = 1.0
            let updateInterval = nodeCount > 5000 ? 10 : 5
            let minTemperature: CGFloat = 0.01

            for iteration in 0..<maxIterations {
                if Task.isCancelled { break }

                if dragState.consumeReheat() {
                    temperature = max(temperature, 0.5)
                }

                if let pinnedId = dragState.pinnedId, let pinnedPos = dragState.pinnedPosition {
                    localNodes[pinnedId]?.position = pinnedPos
                    localNodes[pinnedId]?.velocity = .zero
                }

                let nodeIds = Array(localNodes.keys)

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

                var forces: [Int: CGPoint] = [:]
                for id in nodeIds {
                    guard let node = localNodes[id] else { continue }
                    var f = CGPoint.zero
                    tree.calculateRepulsion(on: node.position, repulsionK: repulsionK, theta: theta, force: &f)
                    forces[id] = f
                }

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

                if centerForceK > 0 {
                    let cx = (minX + maxX) / 2
                    let cy = (minY + maxY) / 2
                    for id in nodeIds {
                        guard let node = localNodes[id] else { continue }
                        forces[id, default: .zero].x -= (node.position.x - cx) * centerForceK
                        forces[id, default: .zero].y -= (node.position.y - cy) * centerForceK
                    }
                }

                let pinnedId = dragState.pinnedId
                let maxDisplacement = max(temperature * 50.0, 0.1)
                for id in nodeIds {
                    if id == pinnedId { continue }
                    guard var node = localNodes[id] else { continue }
                    let f = forces[id] ?? .zero
                    node.velocity.x = (node.velocity.x + f.x) * damping
                    node.velocity.y = (node.velocity.y + f.y) * damping
                    let speed = sqrt(node.velocity.x * node.velocity.x + node.velocity.y * node.velocity.y)
                    if speed > maxDisplacement {
                        let s = maxDisplacement / speed
                        node.velocity.x *= s
                        node.velocity.y *= s
                    }
                    node.position.x += node.velocity.x
                    node.position.y += node.velocity.y
                    localNodes[id] = node
                }

                // Collision resolution: push overlapping nodes apart
                for i in 0..<nodeIds.count {
                    let idA = nodeIds[i]
                    guard var nodeA = localNodes[idA] else { continue }
                    let rA = nodeA.radius
                    for j in (i+1)..<nodeIds.count {
                        let idB = nodeIds[j]
                        guard var nodeB = localNodes[idB] else { continue }
                        let dx = nodeA.position.x - nodeB.position.x
                        let dy = nodeA.position.y - nodeB.position.y
                        let distSq = dx * dx + dy * dy
                        let minDist = rA + nodeB.radius + 2
                        let minDistSq = minDist * minDist
                        if distSq < minDistSq && distSq > 0.01 {
                            let dist = sqrt(distSq)
                            let overlap = (minDist - dist) * 0.5
                            let nx = dx / dist
                            let ny = dy / dist
                            if idA != pinnedId {
                                nodeA.position.x += nx * overlap
                                nodeA.position.y += ny * overlap
                                localNodes[idA] = nodeA
                            }
                            if idB != pinnedId {
                                nodeB.position.x -= nx * overlap
                                nodeB.position.y -= ny * overlap
                                localNodes[idB] = nodeB
                            }
                        }
                    }
                }

                temperature *= coolingRate
                if iteration % updateInterval == 0 {
                    let positions = localNodes.mapValues { $0.position }
                    await onUpdate(positions)
                }

                if temperature < minTemperature && pinnedId == nil {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if dragState.pinnedId != nil { continue }
                    break
                }
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
