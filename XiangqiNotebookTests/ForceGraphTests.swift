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

    private var defaultSnapshot: ForceGraphSnapshot {
        makeSnapshot(
            fenEntries: [
                (1, "fen1", 5),
                (2, "fen2", 3),
                (3, "fen3", 8),
                (4, "fen4", 1),
            ],
            moveEntries: [(1, 2), (1, 3), (2, 3), (3, 4)],
            rootFenId: 1
        )
    }

    @Test func testBuildGraph_AllNodesIncluded() {
        let graph = ForceGraphData.build(from: defaultSnapshot)
        #expect(graph.nodes.count == 4)
        #expect(graph.nodes[1] != nil)
        #expect(graph.nodes[2] != nil)
        #expect(graph.nodes[3] != nil)
        #expect(graph.nodes[4] != nil)
    }

    @Test func testBuildGraph_AllEdgesIncluded() {
        let graph = ForceGraphData.build(from: defaultSnapshot)
        #expect(graph.edges.count == 4)
        let edgeIds = Set(graph.edges.map(\.id))
        #expect(edgeIds.contains("1-2"))
        #expect(edgeIds.contains("1-3"))
        #expect(edgeIds.contains("2-3"))
        #expect(edgeIds.contains("3-4"))
    }

    @Test func testBuildGraph_DepthComputation() {
        let graph = ForceGraphData.build(from: defaultSnapshot)
        #expect(graph.nodes[1]?.depth == 0)
        #expect(graph.nodes[2]?.depth == 1)
        #expect(graph.nodes[3]?.depth == 1)
        #expect(graph.nodes[4]?.depth == 2)
    }

    @Test func testBuildGraph_RealGameCount() {
        let graph = ForceGraphData.build(from: defaultSnapshot)
        #expect(graph.nodes[1]?.realGameCount == 5)
        #expect(graph.nodes[2]?.realGameCount == 3)
        #expect(graph.nodes[3]?.realGameCount == 8)
        #expect(graph.nodes[4]?.realGameCount == 1)
    }

    @Test func testBuildGraph_EdgeCount() {
        let graph = ForceGraphData.build(from: defaultSnapshot)
        #expect(graph.nodes[1]?.edgeCount == 2)
        #expect(graph.nodes[2]?.edgeCount == 2)
        #expect(graph.nodes[3]?.edgeCount == 3)
        #expect(graph.nodes[4]?.edgeCount == 1)
    }

    @Test func testBuildGraph_InitialPositionsAssigned() {
        let graph = ForceGraphData.build(from: defaultSnapshot)
        for (_, node) in graph.nodes {
            #expect(node.position != .zero)
        }
    }

    @Test func testBuildGraph_Empty() {
        let snapshot = makeSnapshot(fenEntries: [], moveEntries: [], rootFenId: nil)
        let graph = ForceGraphData.build(from: snapshot)
        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
    }

    @Test func testBuildGraph_NilRootFenId() {
        let snapshot = makeSnapshot(
            fenEntries: [(1, "fen1", 1), (2, "fen2", 1)],
            moveEntries: [(1, 2)],
            rootFenId: nil
        )
        let graph = ForceGraphData.build(from: snapshot)
        #expect(graph.nodes.count == 2)
        #expect(graph.edges.count == 1)
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
