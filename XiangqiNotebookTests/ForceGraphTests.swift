import Testing
import Foundation
@testable import XiangqiNotebook

#if os(macOS)

struct ForceGraphDataTests {

    private func makeSnapshot(
        fenEntries: [(fenId: Int, fen: String, realGameCount: Int)],
        moveEntries: [(sourceId: Int, targetId: Int)],
        rootFenId: Int?
    ) -> ForceGraphSnapshot {
        ForceGraphSnapshot(fenEntries: fenEntries, moveEntries: moveEntries, rootFenId: rootFenId)
    }

    // Graph with branching: 1->2, 1->3, 2->4, 3->4, 4->5, 4->6
    // Node 1: 0 in, 2 out → KEEP (branch)
    // Node 2: 1 in, 1 out → SKIP
    // Node 3: 1 in, 1 out → SKIP
    // Node 4: 2 in, 2 out → KEEP (convergence + branch)
    // Node 5: 1 in, 0 out → SKIP
    // Node 6: 1 in, 0 out → SKIP
    private var branchingSnapshot: ForceGraphSnapshot {
        makeSnapshot(
            fenEntries: [
                (1, "fen1", 10),
                (2, "fen2", 5),
                (3, "fen3", 5),
                (4, "fen4", 8),
                (5, "fen5", 3),
                (6, "fen6", 2),
            ],
            moveEntries: [(1, 2), (1, 3), (2, 4), (3, 4), (4, 5), (4, 6)],
            rootFenId: 1
        )
    }

    @Test func testBuildGraph_FiltersPassThroughNodes() {
        let graph = ForceGraphData.build(from: branchingSnapshot)
        // Only nodes 1 and 4 are kept (branch/convergence points)
        #expect(graph.nodes[1] != nil)
        #expect(graph.nodes[4] != nil)
        #expect(graph.nodes[2] == nil)
        #expect(graph.nodes[3] == nil)
        #expect(graph.nodes[5] == nil)
        #expect(graph.nodes[6] == nil)
        #expect(graph.nodes.count == 2)
    }

    @Test func testBuildGraph_ReconnectsEdgesThroughSkipped() {
        let graph = ForceGraphData.build(from: branchingSnapshot)
        // Edges 1->2->4 and 1->3->4 should become 1->4
        let edgeIds = Set(graph.edges.map(\.id))
        #expect(edgeIds.contains("1-4"))
    }

    @Test func testBuildGraph_PreservesRealGameCount() {
        let graph = ForceGraphData.build(from: branchingSnapshot)
        #expect(graph.nodes[1]?.realGameCount == 10)
        #expect(graph.nodes[4]?.realGameCount == 8)
    }

    @Test func testBuildGraph_DepthComputation() {
        let graph = ForceGraphData.build(from: branchingSnapshot)
        #expect(graph.nodes[1]?.depth == 0)
        #expect(graph.nodes[4]?.depth == 1)
    }

    @Test func testBuildGraph_Empty() {
        let snapshot = makeSnapshot(fenEntries: [], moveEntries: [], rootFenId: nil)
        let graph = ForceGraphData.build(from: snapshot)
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
    }

    @Test func testBuildGraph_KeepsMultiInNodes() {
        // Node with 2+ in edges is always kept
        let snapshot = makeSnapshot(
            fenEntries: [(1, "a", 1), (2, "b", 1), (3, "c", 1)],
            moveEntries: [(1, 3), (2, 3)],
            rootFenId: nil
        )
        let graph = ForceGraphData.build(from: snapshot)
        #expect(graph.nodes[3] != nil)
    }

    @Test func testBuildGraph_KeepsRootWithZeroIn() {
        // Root with 0 in, 1 out is kept (inDegree != 1)
        let snapshot = makeSnapshot(
            fenEntries: [(1, "a", 5), (2, "b", 3), (3, "c", 1), (4, "d", 1)],
            moveEntries: [(1, 2), (1, 3), (2, 4), (3, 4)],
            rootFenId: 1
        )
        let graph = ForceGraphData.build(from: snapshot)
        #expect(graph.nodes[1] != nil)
        #expect(graph.nodes[4] != nil)
    }
}

struct ForceGraphSimulationTests {

    @Test func testSimulationParams() {
        let params = SimulationParams(repulsionK: 10000, attractionK: 0.01, centerForce: 0.5)
        #expect(params.repulsionK == 10000)
        #expect(params.attractionK == 0.01)
        #expect(params.centerForce == 0.5)
    }

    @Test func testDragState() {
        let state = DragState()
        #expect(state.pinnedId == nil)

        state.pin(id: 42, position: CGPoint(x: 10, y: 20))
        #expect(state.pinnedId == 42)
        #expect(state.pinnedPosition == CGPoint(x: 10, y: 20))
        #expect(state.consumeReheat() == true)
        #expect(state.consumeReheat() == false)

        state.updatePosition(CGPoint(x: 30, y: 40))
        #expect(state.pinnedPosition == CGPoint(x: 30, y: 40))

        state.unpin()
        #expect(state.pinnedId == nil)
    }
}

#endif
