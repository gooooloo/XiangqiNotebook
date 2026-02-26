import Testing
@testable import XiangqiNotebook

struct XiangqiMoveRulesTests {

    // MARK: - Helper

    /// 创建一个只有双将的最简棋盘
    private func emptyBoardWithKings() -> [String: String] {
        return [
            "e0": "rK",  // 红帅在 e0
            "e9": "bK"   // 黑将在 e9
        ]
    }

    // MARK: - isSameColor Tests

    @Test func testIsSameColor_SameColorRed() {
        #expect(MoveRules.isSameColor("rR", "rK") == true)
        #expect(MoveRules.isSameColor("rN", "rC") == true)
        #expect(MoveRules.isSameColor("rP", "rB") == true)
    }

    @Test func testIsSameColor_SameColorBlack() {
        #expect(MoveRules.isSameColor("bR", "bK") == true)
        #expect(MoveRules.isSameColor("bN", "bC") == true)
    }

    @Test func testIsSameColor_DifferentColor() {
        #expect(MoveRules.isSameColor("rR", "bR") == false)
        #expect(MoveRules.isSameColor("bK", "rK") == false)
        #expect(MoveRules.isSameColor("rP", "bP") == false)
    }

    // MARK: - Coordinate Conversion Tests

    @Test func testSquareToCoordinate_a0() {
        let (col, row) = MoveRules.squareToCoordinate("a0")
        #expect(col == 0)
        #expect(row == 0)
    }

    @Test func testSquareToCoordinate_i9() {
        let (col, row) = MoveRules.squareToCoordinate("i9")
        #expect(col == 8)
        #expect(row == 9)
    }

    @Test func testSquareToCoordinate_e4() {
        let (col, row) = MoveRules.squareToCoordinate("e4")
        #expect(col == 4)
        #expect(row == 4)
    }

    @Test func testCoordinateToSquare_0_0() {
        let square = MoveRules.coordinateToSquare(col: 0, row: 0)
        #expect(square == "a0")
    }

    @Test func testCoordinateToSquare_8_9() {
        let square = MoveRules.coordinateToSquare(col: 8, row: 9)
        #expect(square == "i9")
    }

    @Test func testCoordinateConversionRoundTrip() {
        for colIdx in 0..<9 {
            for row in 0..<10 {
                let square = MoveRules.coordinateToSquare(col: colIdx, row: row)
                let (col2, row2) = MoveRules.squareToCoordinate(square)
                #expect(col2 == colIdx)
                #expect(row2 == row)
            }
        }
    }

    // MARK: - Rook (车) Tests

    @Test func testRookMoves_OpenFile() {
        var board = emptyBoardWithKings()
        board["e5"] = "rR"  // 红车在 e5

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e5", piecesBySquare: board)

        // 向上：e6,e7,e8（e9 是黑将，可以吃）
        #expect(moves.contains("e6"))
        #expect(moves.contains("e7"))
        #expect(moves.contains("e8"))
        #expect(moves.contains("e9"))  // 可以吃黑将

        // 向下：e1,e2,e3,e4（e0 是红帅，同色不能走）
        #expect(moves.contains("e4"))
        #expect(moves.contains("e3"))
        #expect(moves.contains("e2"))
        #expect(moves.contains("e1"))
        #expect(!moves.contains("e0"))  // 同色，不能吃

        // 横向：a5-d5 和 f5-i5
        #expect(moves.contains("a5"))
        #expect(moves.contains("d5"))
        #expect(moves.contains("f5"))
        #expect(moves.contains("i5"))
    }

    @Test func testRookMoves_BlockedByOwnPiece() {
        var board = emptyBoardWithKings()
        board["e5"] = "rR"
        board["e7"] = "rN"  // 红马在 e7 阻挡

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e5", piecesBySquare: board)

        #expect(moves.contains("e6"))
        #expect(!moves.contains("e7"))  // 同色
        #expect(!moves.contains("e8"))  // 被挡
    }

    @Test func testRookMoves_CanCaptureEnemy() {
        var board = emptyBoardWithKings()
        board["e5"] = "rR"
        board["e7"] = "bN"  // 黑马

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e5", piecesBySquare: board)

        #expect(moves.contains("e7"))   // 可以吃黑马
        #expect(!moves.contains("e8"))  // 不能越过
    }

    // MARK: - Knight (马) Tests

    @Test func testKnightMoves_Center() {
        var board = emptyBoardWithKings()
        board["e4"] = "rN"  // 红马在 e4

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e4", piecesBySquare: board)

        // 中心马有 8 个跳法位置
        #expect(moves.contains("d6"))
        #expect(moves.contains("f6"))
        #expect(moves.contains("c5"))
        #expect(moves.contains("g5"))
        #expect(moves.contains("c3"))
        #expect(moves.contains("g3"))
        #expect(moves.contains("d2"))
        #expect(moves.contains("f2"))
        #expect(moves.count == 8)
    }

    @Test func testKnightMoves_BlockedByMaLeg() {
        var board = emptyBoardWithKings()
        board["e4"] = "rN"
        board["e5"] = "rC"  // 上方马腿

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e4", piecesBySquare: board)

        // 向上的两个跳法被阻挡
        #expect(!moves.contains("d6"))
        #expect(!moves.contains("f6"))

        // 其他方向不受影响
        #expect(moves.contains("c5"))
        #expect(moves.contains("g5"))
        #expect(moves.count == 6)
    }

    @Test func testKnightMoves_CannotCaptureSameColor() {
        var board = emptyBoardWithKings()
        board["e4"] = "rN"
        board["d6"] = "rR"  // 同色棋子在目标位置

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e4", piecesBySquare: board)
        #expect(!moves.contains("d6"))
    }

    @Test func testKnightMoves_CornerPosition() {
        var board = emptyBoardWithKings()
        board["a0"] = "rN"  // 马在左下角

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "a0", piecesBySquare: board)

        // 角落马的跳法很少
        #expect(moves.count <= 2)
    }

    // MARK: - Elephant (相/象) Tests

    @Test func testRedElephantMoves_CannotCrossRiver() {
        var board = emptyBoardWithKings()
        board["c0"] = "rB"  // 红相在 c0

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "c0", piecesBySquare: board)

        // 红相只能在 0-4 行
        for move in moves {
            let (_, row) = MoveRules.squareToCoordinate(move)
            #expect(row <= 4)
        }
        // c0 的红相应该能走 a2 和 e2
        #expect(moves.contains("a2"))
        #expect(moves.contains("e2"))
    }

    @Test func testBlackElephantMoves_CannotCrossRiver() {
        var board = emptyBoardWithKings()
        board["c9"] = "bB"  // 黑象在 c9

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "c9", piecesBySquare: board)

        // 黑象只能在 5-9 行
        for move in moves {
            let (_, row) = MoveRules.squareToCoordinate(move)
            #expect(row >= 5)
        }
    }

    @Test func testElephantMoves_BlockedByObstacle() {
        var board = emptyBoardWithKings()
        board["c0"] = "rB"
        board["d1"] = "rP"  // 田心有棋子，挡住右上方

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "c0", piecesBySquare: board)

        // 右上方的田心被堵，不能走 e2
        #expect(!moves.contains("e2"))
    }

    // MARK: - Advisor (士/仕) Tests

    @Test func testRedAdvisorMoves_StaysInPalace() {
        var board = emptyBoardWithKings()
        board["e1"] = "rA"  // 红仕在九宫中心

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e1", piecesBySquare: board)

        for move in moves {
            let (col, row) = MoveRules.squareToCoordinate(move)
            #expect(col >= 3 && col <= 5)  // d-f 列
            #expect(row >= 0 && row <= 2)  // 0-2 行
        }
        // 从 e1 应该有 4 个斜线目标
        #expect(moves.count == 4)
    }

    @Test func testRedAdvisorMoves_CornerOfPalace() {
        var board = emptyBoardWithKings()
        board["d0"] = "rA"  // 红仕在九宫角落

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "d0", piecesBySquare: board)

        // 角落只能走到 e1
        #expect(moves.contains("e1"))
        #expect(moves.count == 1)
    }

    @Test func testBlackAdvisorMoves_StaysInPalace() {
        var board = emptyBoardWithKings()
        board["e8"] = "bA"  // 黑士在九宫中心

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e8", piecesBySquare: board)

        for move in moves {
            let (col, row) = MoveRules.squareToCoordinate(move)
            #expect(col >= 3 && col <= 5)
            #expect(row >= 7 && row <= 9)
        }
    }

    // MARK: - King (帅/将) Tests

    @Test func testRedKingMoves_StaysInPalace() {
        var board = [String: String]()
        board["e1"] = "rK"  // 红帅在 e1
        board["e9"] = "bK"  // 黑将在 e9

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e1", piecesBySquare: board)

        for move in moves {
            let (col, row) = MoveRules.squareToCoordinate(move)
            #expect(col >= 3 && col <= 5)
            #expect(row >= 0 && row <= 2)
        }
    }

    @Test func testKingMoves_FacingKingRule_NoObstacle() {
        var board = [String: String]()
        board["e0"] = "rK"
        board["e9"] = "bK"  // 同列无阻挡

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e0", piecesBySquare: board)

        // 不能移到 e1（移动后将帅面对面，e1 到 e9 之间无阻挡）
        #expect(!moves.contains("e1"))
        // 可以横向移动
        #expect(moves.contains("d0") || moves.contains("f0"))
    }

    @Test func testKingMoves_FacingKingRule_WithObstacle() {
        var board = [String: String]()
        board["e0"] = "rK"
        board["e9"] = "bK"
        board["e5"] = "rR"  // e5 有阻挡

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e0", piecesBySquare: board)

        // 有阻挡，可以走 e1
        #expect(moves.contains("e1"))
    }

    // MARK: - Cannon (炮) Tests

    @Test func testCannonMoves_MovesFreely() {
        var board = emptyBoardWithKings()
        board["e5"] = "rC"

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e5", piecesBySquare: board)

        // 可以移到空格
        #expect(moves.contains("e6"))
        #expect(moves.contains("e7"))
        #expect(moves.contains("e8"))
        // e9 是黑将，没有炮架，不能吃
        #expect(!moves.contains("e9"))
        // e0 是红帅，同色不能走，且没有炮架
        #expect(!moves.contains("e0"))
    }

    @Test func testCannonMoves_CannotCaptureWithoutPlatform() {
        var board = emptyBoardWithKings()
        board["e5"] = "rC"
        board["e7"] = "bP"  // 黑卒，无炮架

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e5", piecesBySquare: board)

        #expect(moves.contains("e6"))
        #expect(!moves.contains("e7"))  // 无炮架不能吃
        #expect(!moves.contains("e8"))  // 不能越过
    }

    @Test func testCannonMoves_CanCaptureWithPlatform() {
        var board = [String: String]()
        board["e0"] = "rK"
        board["e9"] = "bK"
        board["e5"] = "rC"
        board["e7"] = "rN"  // 炮架（红马）
        // 黑将作为目标在 e9

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e5", piecesBySquare: board)

        // 通过 e7 的炮架可以吃 e9 的黑将
        #expect(moves.contains("e9"))
    }

    @Test func testCannonMoves_CannotCaptureWithPlatformSameColor() {
        var board = [String: String]()
        board["e5"] = "rC"
        board["e7"] = "bN"  // 炮架（黑马）
        board["e2"] = "rN"  // 红马在 e2（经炮架不能吃同色）
        board["e0"] = "rK"
        board["e9"] = "bK"

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e5", piecesBySquare: board)

        // 不能通过炮架吃同色棋子
        #expect(!moves.contains("e2"))
    }

    // MARK: - Pawn (兵/卒) Tests

    @Test func testRedPawnMoves_BeforeCrossRiver() {
        var board = emptyBoardWithKings()
        board["e3"] = "rP"  // 红兵在 e3（未过河，红方区域 0-4）

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e3", piecesBySquare: board)

        // 未过河只能前进（row 增加）
        #expect(moves.contains("e4"))
        #expect(!moves.contains("d3"))
        #expect(!moves.contains("f3"))
        #expect(moves.count == 1)
    }

    @Test func testRedPawnMoves_AfterCrossRiver() {
        var board = emptyBoardWithKings()
        board["e6"] = "rP"  // 红兵在 e6（过河，进入 5-9 行）

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e6", piecesBySquare: board)

        // 过河后可以前进和横向
        #expect(moves.contains("e7"))
        #expect(moves.contains("d6"))
        #expect(moves.contains("f6"))
        #expect(moves.count == 3)
    }

    @Test func testBlackPawnMoves_BeforeCrossRiver() {
        var board = emptyBoardWithKings()
        board["e7"] = "bP"  // 黑卒在 e7（未过河，黑方区域 5-9）

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e7", piecesBySquare: board)

        // 未过河只能前进（row 减少）
        #expect(moves.contains("e6"))
        #expect(!moves.contains("d7"))
        #expect(!moves.contains("f7"))
        #expect(moves.count == 1)
    }

    @Test func testBlackPawnMoves_AfterCrossRiver() {
        var board = emptyBoardWithKings()
        board["e3"] = "bP"  // 黑卒在 e3（过河，进入 0-4 行）

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e3", piecesBySquare: board)

        // 过河后可以前进和横向
        #expect(moves.contains("e2"))
        #expect(moves.contains("d3"))
        #expect(moves.contains("f3"))
        #expect(moves.count == 3)
    }

    @Test func testPawnMoves_CannotCaptureOwnPiece() {
        var board = emptyBoardWithKings()
        board["e6"] = "rP"  // 红兵过河
        board["e7"] = "rR"  // 同色阻挡前进

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "e6", piecesBySquare: board)

        #expect(!moves.contains("e7"))
        #expect(moves.contains("d6"))
        #expect(moves.contains("f6"))
    }

    // MARK: - Empty Square Tests

    @Test func testGetLegalDestinations_EmptySquare() {
        let board = emptyBoardWithKings()

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "a5", piecesBySquare: board)
        #expect(moves.isEmpty)
    }

    @Test func testGetLegalDestinations_UnknownPiece() {
        var board = emptyBoardWithKings()
        board["a5"] = "xX"  // 未知棋子

        let moves = MoveRules.getLegalDestinationSquares(fromSquare: "a5", piecesBySquare: board)
        #expect(moves.isEmpty)
    }
}
