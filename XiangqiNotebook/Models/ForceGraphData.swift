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
    var realGameCount: Int = 0
}

struct GraphEdge: Identifiable {
    let id: String
    let sourceId: Int
    let targetId: Int
}

struct ForceGraphSnapshot: Sendable {
    let fenEntries: [(fenId: Int, fen: String, realGameCount: Int)]
    let moveEntries: [(sourceId: Int, targetId: Int)]
    let rootFenId: Int?

    static func extractRealGames(from databaseView: DatabaseView, rootFenId: Int?) -> ForceGraphSnapshot {
        let redStats = databaseView.myRealRedGameStatisticsByFenId
        let blackStats = databaseView.myRealBlackGameStatisticsByFenId

        var realGameFenIds = Set<Int>()
        for (fenId, s) in redStats {
            let total = s.redWin + s.blackWin + s.draw + s.notFinished + s.unknown
            if total > 0 { realGameFenIds.insert(fenId) }
        }
        for (fenId, s) in blackStats {
            let total = s.redWin + s.blackWin + s.draw + s.notFinished + s.unknown
            if total > 0 { realGameFenIds.insert(fenId) }
        }

        var fenEntries: [(fenId: Int, fen: String, realGameCount: Int)] = []
        var moveEntries: [(sourceId: Int, targetId: Int)] = []

        for fenId in realGameFenIds {
            guard let fenObject = databaseView.getFenObject(fenId) ?? databaseView.getFenObjectUnfiltered(fenId) else { continue }
            let redTotal = redStats[fenId].map { $0.redWin + $0.blackWin + $0.draw + $0.notFinished + $0.unknown } ?? 0
            let blackTotal = blackStats[fenId].map { $0.redWin + $0.blackWin + $0.draw + $0.notFinished + $0.unknown } ?? 0
            fenEntries.append((fenId: fenId, fen: fenObject.fen, realGameCount: redTotal + blackTotal))

            let moves = databaseView.moves(from: fenId)
            for move in moves {
                guard let targetId = move.targetFenId, realGameFenIds.contains(targetId) else { continue }
                moveEntries.append((sourceId: fenId, targetId: targetId))
            }
        }

        return ForceGraphSnapshot(fenEntries: fenEntries, moveEntries: moveEntries, rootFenId: rootFenId)
    }
}

struct ForceGraphData: Sendable {
    var nodes: [Int: GraphNode]
    var edges: [GraphEdge]

    static func build(from snapshot: ForceGraphSnapshot) -> ForceGraphData {
        var nodes: [Int: GraphNode] = [:]
        var edges: [GraphEdge] = []
        var edgeCounts: [Int: Int] = [:]

        for entry in snapshot.fenEntries {
            nodes[entry.fenId] = GraphNode(
                id: entry.fenId,
                fen: entry.fen,
                position: .zero,
                edgeCount: 0,
                realGameCount: entry.realGameCount
            )
        }

        for entry in snapshot.moveEntries {
            edges.append(GraphEdge(id: "\(entry.sourceId)-\(entry.targetId)", sourceId: entry.sourceId, targetId: entry.targetId))
            edgeCounts[entry.sourceId, default: 0] += 1
            edgeCounts[entry.targetId, default: 0] += 1
        }

        for (fenId, count) in edgeCounts {
            nodes[fenId]?.edgeCount = count
        }

        let depths = computeDepths(from: snapshot.rootFenId, nodes: nodes, edges: edges)
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
        var depthBuckets: [Int: [Int]] = [:]
        for (fenId, depth) in depths {
            depthBuckets[depth, default: []].append(fenId)
        }

        for (depth, fenIds) in depthBuckets {
            let radius = CGFloat(depth) / CGFloat(maxDepth) * CGFloat(nodes.count).squareRoot() * 8
            let count = fenIds.count
            for (i, fenId) in fenIds.enumerated() {
                let angle: CGFloat
                if count == 1 {
                    angle = CGFloat.random(in: 0..<(.pi * 2))
                } else {
                    angle = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.3...0.3)
                }
                let x = cos(angle) * radius + CGFloat.random(in: -10...10)
                let y = sin(angle) * radius + CGFloat.random(in: -10...10)
                nodes[fenId]?.position = CGPoint(x: x, y: y)
                nodes[fenId]?.depth = depth
            }
        }
    }
}

#endif
