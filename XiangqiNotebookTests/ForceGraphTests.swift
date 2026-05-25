import Testing
import Foundation
@testable import XiangqiNotebook

#if os(macOS)

struct ForceGraphDataTests {

    private func createTestDatabase() -> Database {
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        let fen1 = FenObject(fen: "fen1", fenId: 1)
        fen1.setInRedOpening(true)
        database.databaseData.fenObjects2[1] = fen1
        database.databaseData.fenToId["fen1"] = 1

        let fen2 = FenObject(fen: "fen2", fenId: 2)
        fen2.setInRedOpening(true)
        database.databaseData.fenObjects2[2] = fen2
        database.databaseData.fenToId["fen2"] = 2

        let fen3 = FenObject(fen: "fen3", fenId: 3)
        fen3.setInRedOpening(true)
        database.databaseData.fenObjects2[3] = fen3
        database.databaseData.fenToId["fen3"] = 3

        let fen4 = FenObject(fen: "fen4", fenId: 4)
        fen4.setInRedOpening(false)
        database.databaseData.fenObjects2[4] = fen4
        database.databaseData.fenToId["fen4"] = 4

        let move1to2 = Move(sourceFenId: 1, targetFenId: 2)
        fen1.addMoveIfNeeded(move: move1to2)
        database.databaseData.moveObjects[1] = move1to2
        database.databaseData.moveToId[[1, 2]] = 1

        let move1to3 = Move(sourceFenId: 1, targetFenId: 3)
        fen1.addMoveIfNeeded(move: move1to3)
        database.databaseData.moveObjects[2] = move1to3
        database.databaseData.moveToId[[1, 3]] = 2

        let move2to3 = Move(sourceFenId: 2, targetFenId: 3)
        fen2.addMoveIfNeeded(move: move2to3)
        database.databaseData.moveObjects[3] = move2to3
        database.databaseData.moveToId[[2, 3]] = 3

        let move3to4 = Move(sourceFenId: 3, targetFenId: 4)
        fen3.addMoveIfNeeded(move: move3to4)
        database.databaseData.moveObjects[4] = move3to4
        database.databaseData.moveToId[[3, 4]] = 4

        return database
    }

    @Test func testBuildGraph_FullView_AllNodesIncluded() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: 1)

        #expect(graph.nodes.count == 4)
        #expect(graph.nodes[1] != nil)
        #expect(graph.nodes[2] != nil)
        #expect(graph.nodes[3] != nil)
        #expect(graph.nodes[4] != nil)
    }

    @Test func testBuildGraph_FullView_AllEdgesIncluded() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: 1)

        #expect(graph.edges.count == 4)
        let edgeIds = Set(graph.edges.map(\.id))
        #expect(edgeIds.contains("1-2"))
        #expect(edgeIds.contains("1-3"))
        #expect(edgeIds.contains("2-3"))
        #expect(edgeIds.contains("3-4"))
    }

    @Test func testBuildGraph_FilteredView_RespectsScope() {
        let database = createTestDatabase()
        let view = DatabaseView.redOpening(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: 1)

        // fenId 4 is not in red opening, so it should be excluded
        #expect(graph.nodes[4] == nil)
        // fenId 1, 2, 3 are in red opening
        #expect(graph.nodes[1] != nil)
        #expect(graph.nodes[2] != nil)
        #expect(graph.nodes[3] != nil)

        // Edge 3->4 should be excluded because target (4) is not in scope
        let edgeIds = Set(graph.edges.map(\.id))
        #expect(!edgeIds.contains("3-4"))
        // Edges within scope should be included
        #expect(edgeIds.contains("1-2"))
        #expect(edgeIds.contains("1-3"))
        #expect(edgeIds.contains("2-3"))
    }

    @Test func testBuildGraph_DepthComputation() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: 1)

        #expect(graph.nodes[1]?.depth == 0)
        #expect(graph.nodes[2]?.depth == 1)
        #expect(graph.nodes[3]?.depth == 1)
        #expect(graph.nodes[4]?.depth == 2)
    }

    @Test func testBuildGraph_EdgeCount() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: 1)

        // Node 1: source of 1->2, 1->3 = 2 edges
        // Node 2: target of 1->2, source of 2->3 = 2 edges
        // Node 3: target of 1->3, target of 2->3, source of 3->4 = 3 edges
        // Node 4: target of 3->4 = 1 edge
        #expect(graph.nodes[1]?.edgeCount == 2)
        #expect(graph.nodes[2]?.edgeCount == 2)
        #expect(graph.nodes[3]?.edgeCount == 3)
        #expect(graph.nodes[4]?.edgeCount == 1)
    }

    @Test func testBuildGraph_InitialPositionsAssigned() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: 1)

        for (_, node) in graph.nodes {
            #expect(node.position != .zero)
        }
    }

    @Test func testBuildGraph_EmptyDatabase() {
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)
        let view = DatabaseView.full(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: nil)

        #expect(graph.nodes.isEmpty)
        #expect(graph.edges.isEmpty)
    }

    @Test func testBuildGraph_NilRootFenId() {
        let database = createTestDatabase()
        let view = DatabaseView.full(database: database)

        let graph = ForceGraphData.build(from: view, rootFenId: nil)

        // Should still include all nodes even without a valid root
        #expect(graph.nodes.count == 4)
        #expect(graph.edges.count == 4)
    }
}

struct ForceGraphSimulationTests {

    @Test func testSimulationConverges() async {
        let testDatabaseData = DatabaseData()
        let database = Database(testDatabaseData: testDatabaseData)

        let fen1 = FenObject(fen: "fen1", fenId: 1)
        database.databaseData.fenObjects2[1] = fen1
        database.databaseData.fenToId["fen1"] = 1

        let fen2 = FenObject(fen: "fen2", fenId: 2)
        database.databaseData.fenObjects2[2] = fen2
        database.databaseData.fenToId["fen2"] = 2

        let move = Move(sourceFenId: 1, targetFenId: 2)
        fen1.addMoveIfNeeded(move: move)
        database.databaseData.moveObjects[1] = move
        database.databaseData.moveToId[[1, 2]] = 1

        let view = DatabaseView.full(database: database)
        let graph = ForceGraphData.build(from: view, rootFenId: 1)

        let simulation = ForceGraphSimulation()
        var finalPositions: [Int: CGPoint]?
        var resumed = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            simulation.start(data: graph) { positions in
                finalPositions = positions
                if !simulation.isRunning && !resumed {
                    resumed = true
                    continuation.resume()
                }
            }
        }

        #expect(finalPositions != nil)
        #expect(finalPositions?.count == 2)
    }
}

#endif
