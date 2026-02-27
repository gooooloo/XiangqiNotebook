import Testing
@testable import XiangqiNotebook

struct XiangqiBoardTests {

    // MARK: - BoardConstants Tests

    @Test func testBoardConstants_ColumnCount() {
        #expect(BoardConstants.columns.count == 9)
    }

    @Test func testBoardConstants_RowCount() {
        #expect(BoardConstants.rows.count == 10)
    }

    @Test func testBoardConstants_ColumnOrder() {
        #expect(BoardConstants.columns[0] == "a")
        #expect(BoardConstants.columns[4] == "e")
        #expect(BoardConstants.columns[8] == "i")
    }

    @Test func testBoardConstants_RowOrder() {
        #expect(BoardConstants.rows[0] == 0)
        #expect(BoardConstants.rows[9] == 9)
    }

    @Test func testBoardConstants_AllColumns() {
        let expected = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
        #expect(BoardConstants.columns == expected)
    }

    @Test func testBoardConstants_AllRows() {
        let expected = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        #expect(BoardConstants.rows == expected)
    }

    // MARK: - Valid Square Names

    @Test func testAllSquaresAreValid() {
        // 遍历所有有效格点，确保坐标转换正确
        for col in BoardConstants.columns {
            for row in BoardConstants.rows {
                let square = "\(col)\(row)"
                let (colIdx, rowIdx) = MoveRules.squareToCoordinate(square)
                let reconstructed = MoveRules.coordinateToSquare(col: colIdx, row: rowIdx)
                #expect(reconstructed == square)
            }
        }
    }

    @Test func testTotalSquareCount() {
        // 9列 x 10行 = 90个格点
        let totalSquares = BoardConstants.columns.count * BoardConstants.rows.count
        #expect(totalSquares == 90)
    }
}
