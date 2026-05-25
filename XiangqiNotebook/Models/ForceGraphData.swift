import Foundation
import CoreGraphics

#if os(macOS)

struct GraphNode: Identifiable {
    let id: Int
    let fen: String
    var position: CGPoint
    var velocity: CGPoint = .zero
    var depth: Int = 0
    var edgeCount: Int = 0
}

struct GraphEdge: Identifiable {
    let id: String
    let sourceId: Int
    let targetId: Int
}

struct ForceGraphData {
    var nodes: [Int: GraphNode]
    var edges: [GraphEdge]

    static func build(from databaseView: DatabaseView, rootFenId: Int?) -> ForceGraphData {
        let allFenIds = databaseView.getAllFenIds().filter { databaseView.containsFenId($0) }
        let fenIdSet = Set(allFenIds)

        var nodes: [Int: GraphNode] = [:]
        var edges: [GraphEdge] = []
        var edgeCounts: [Int: Int] = [:]

        for fenId in allFenIds {
            guard let fenObject = databaseView.getFenObject(fenId) else { continue }
            let filteredMoves = databaseView.moves(from: fenId)
            for move in filteredMoves {
                guard let targetId = move.targetFenId, fenIdSet.contains(targetId) else { continue }
                edges.append(GraphEdge(id: "\(fenId)-\(targetId)", sourceId: fenId, targetId: targetId))
                edgeCounts[fenId, default: 0] += 1
                edgeCounts[targetId, default: 0] += 1
            }
            nodes[fenId] = GraphNode(
                id: fenId,
                fen: fenObject.fen,
                position: .zero,
                edgeCount: 0
            )
        }

        for (fenId, count) in edgeCounts {
            nodes[fenId]?.edgeCount = count
        }

        let depths = computeDepths(from: rootFenId, nodes: nodes, edges: edges)
        assignInitialPositions(nodes: &nodes, depths: depths)

        return ForceGraphData(nodes: nodes, edges: edges)
    }

    private static func computeDepths(from rootFenId: Int?, nodes: [Int: GraphNode], edges: [GraphEdge]) -> [Int: Int] {
        var depths: [Int: Int] = [:]
        guard let root = rootFenId, nodes[root] != nil else {
            var d = 0
            for fenId in nodes.keys {
                depths[fenId] = d % 10
                d += 1
            }
            return depths
        }

        var adjacency: [Int: [Int]] = [:]
        for edge in edges {
            adjacency[edge.sourceId, default: []].append(edge.targetId)
        }

        var queue: [Int] = [root]
        depths[root] = 0
        var idx = 0
        while idx < queue.count {
            let current = queue[idx]
            idx += 1
            let currentDepth = depths[current]!
            for neighbor in adjacency[current] ?? [] {
                if depths[neighbor] == nil {
                    depths[neighbor] = currentDepth + 1
                    queue.append(neighbor)
                }
            }
        }

        for fenId in nodes.keys where depths[fenId] == nil {
            depths[fenId] = (depths.values.max() ?? 0) + 1
        }

        return depths
    }

    private static func assignInitialPositions(nodes: inout [Int: GraphNode], depths: [Int: Int]) {
        let maxDepth = max(depths.values.max() ?? 1, 1)
        var depthCounts: [Int: Int] = [:]

        for (fenId, depth) in depths {
            let count = depthCounts[depth, default: 0]
            depthCounts[depth] = count + 1

            let x = CGFloat(depth) / CGFloat(maxDepth) * 800.0 + CGFloat.random(in: -20...20)
            let y = CGFloat(count) * 60.0 + CGFloat.random(in: -15...15)

            nodes[fenId]?.position = CGPoint(x: x, y: y)
            nodes[fenId]?.depth = depth
        }
    }
}

#endif
