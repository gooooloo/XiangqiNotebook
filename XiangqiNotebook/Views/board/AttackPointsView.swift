import SwiftUI

/// 攻击点位层：把一方所有棋子的控制点画成方框（红方红框、黑方蓝框），
/// 样式与「显示来源招法」的橙色方框（HighlightSquareView）一致，靠颜色和尺寸区分：
/// 橙 0.9 > 红 0.82 > 蓝 0.68，叠在同一点时同心嵌套、互不遮挡。
/// 有 2 个以上棋子攻击同一点时在框角标攻击子数（红：左上角，蓝：右下角）。
struct AttackPointsView: View {
    let redCounts: [String: Int]
    let blackCounts: [String: Int]
    let squareSize: CGFloat
    let squareSizeWidth: CGFloat
    let squareSizeHeight: CGFloat
    let pieceDiffX: CGFloat
    let pieceDiffY: CGFloat
    let orientation: String
    let isHorizontalFlipped: Bool

    var body: some View {
        ZStack {
            attackSquares(counts: redCounts, color: Color.red, sizeFactor: 0.82, cornerDirection: -1)
            attackSquares(counts: blackCounts, color: Color.blue, sizeFactor: 0.68, cornerDirection: 1)
        }
    }

    private func attackSquares(counts: [String: Int], color: Color, sizeFactor: CGFloat, cornerDirection: CGFloat) -> some View {
        let side = squareSize * sizeFactor
        let badgeSize = squareSize * 0.26
        // 数字徽章压在方框对角上（红左上、蓝右下），双方嵌套时也不打架
        let cornerOffset = side / 2 * cornerDirection
        return ForEach(counts.sorted(by: { $0.key < $1.key }), id: \.key) { item in
            let position = BoardViewModel.calculateDisplayPosition(
                square: item.key,
                squareSizeWidth: squareSizeWidth,
                squareSizeHeight: squareSizeHeight,
                pieceDiffX: pieceDiffX,
                pieceDiffY: pieceDiffY,
                orientation: orientation,
                isHorizontalFlipped: isHorizontalFlipped
            )
            ZStack {
                Rectangle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: side, height: side)
                    .background(color.opacity(0.18))
                if item.value > 1 {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.9))
                        Text("\(item.value)")
                            .font(.system(size: squareSize * 0.16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: badgeSize, height: badgeSize)
                    .offset(x: cornerOffset, y: cornerOffset)
                }
            }
            .position(position)
        }
    }
}
