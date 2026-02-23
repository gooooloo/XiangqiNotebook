import SwiftUI

/// 在象棋棋盘上显示路径的视图组件
/// 支持：
/// - 显示带箭头和圆点的路径
/// - 显示纯路径线条
/// - （未来可能支持）单点标记
struct PathView: View {
    let squareSizeWidth: CGFloat
    let squareSizeHeight: CGFloat
    let pieceDiffX: CGFloat
    let pieceDiffY: CGFloat
    let orientation: String
    let isHorizontalFlipped: Bool
    let pathGroups: [PathGroup]
    let selectedGroupIndex: Int
    let selectedPathIndex: Int
    let piecesBySquare: [String: String]  // 添加棋子信息
    let animationDuration: Double  // 添加动画时间参数
    
    // 添加动画控制状态
    @State private var isVisible: Bool = false
    @State private var opacity: Double = 0

    // 透明度常量
    private let pathOpacity: Double = 1.0        // Path 箭头透明度（较深）
    private let nextMovesOpacity: Double = 0.5   // NextMoves 箭头透明度（较浅，以区分 path）

    // Path 颜色（暖色系：红、橙、黄、绿）
    private var pathColors: [Color] {
        [
            Color(red: 0.9, green: 0.3, blue: 0.3).opacity(pathOpacity),   // 红色
            Color(red: 0.9, green: 0.5, blue: 0.1).opacity(pathOpacity),   // 橙色
            Color(red: 0.8, green: 0.7, blue: 0.0).opacity(pathOpacity),   // 金黄色
            Color(red: 0.3, green: 0.7, blue: 0.3).opacity(pathOpacity),   // 绿色
            Color(red: 0.9, green: 0.4, blue: 0.5).opacity(pathOpacity),   // 玫红色
            Color(red: 0.7, green: 0.6, blue: 0.2).opacity(pathOpacity),   // 橄榄色
        ]
    }

    // 圆点大小常量
    private let singlePointDotSize: CGFloat = 26  // 单点路径的圆点大小（由18改为32，更显眼）
    private let pathPointDotSize: CGFloat = 14     // 线段路径上的圆点大小

    // Path 大小倍数（相对于 NextMoves）
    private let pathSizeMultiplier: CGFloat = 2.0  // Path 线条和圆点的放大倍数

    // 路径动画时间常量
    private let pathAnimationDuration: Double = 0.2

    // 判断是否为 NextMoves 组
    private func isNextMovesGroup(_ group: PathGroup) -> Bool {
        group.name?.hasPrefix("NextMoves_") == true
    }

    // NextMoves 颜色（冷色系：蓝、紫、青）
    private var nextMovesColors: [Color] {
        [
            Color(red: 0.2, green: 0.4, blue: 0.9).opacity(nextMovesOpacity),   // 蓝色
            Color(red: 0.6, green: 0.3, blue: 0.8).opacity(nextMovesOpacity),   // 紫色
            Color(red: 0.0, green: 0.6, blue: 0.8).opacity(nextMovesOpacity),   // 青色
            Color(red: 0.4, green: 0.2, blue: 0.7).opacity(nextMovesOpacity),   // 深紫色
            Color(red: 0.1, green: 0.5, blue: 0.6).opacity(nextMovesOpacity),   // 深青色
            Color(red: 0.3, green: 0.3, blue: 0.9).opacity(nextMovesOpacity),   // 靛蓝色
        ]
    }

    // 根据路径组获取颜色
    private func colorForGroup(_ group: PathGroup, index: Int) -> Color {
        // 检测 "NextMoves_N" 格式的组名
        if let name = group.name, name.hasPrefix("NextMoves_") {
            // 提取索引号
            let indexStr = name.dropFirst("NextMoves_".count)
            if let nextMoveIndex = Int(indexStr) {
                // 如果超出预定义颜色数量，动态生成（保持冷色系风格）
                if nextMoveIndex >= nextMovesColors.count {
                    // 使用黄金分割比生成色相，限制在冷色范围（青-蓝-紫：0.5-0.85）
                    let hue = 0.5 + (Double(nextMoveIndex) * 0.618033988749895).truncatingRemainder(dividingBy: 1.0) * 0.35
                    return Color(hue: hue,
                                saturation: 0.8,
                                brightness: 0.85)
                           .opacity(nextMovesOpacity)
                }
                return nextMovesColors[nextMoveIndex]
            }
        }

        // Path 动态颜色生成（保持暖色系风格）
        if index >= pathColors.count {
            // 使用黄金分割比生成色相，限制在暖色范围（红-黄-绿：0.0-0.4）
            let hue = (Double(index) * 0.618033988749895).truncatingRemainder(dividingBy: 1.0) * 0.4
            return Color(hue: hue,
                        saturation: 0.8,
                        brightness: 0.85)
                   .opacity(pathOpacity)
        }
        return pathColors[index]
    }
    
    // 判断是否为选中的路径
    private func isSelectedPath(groupIndex: Int, pathIndex: Int) -> Bool {
        return selectedGroupIndex == groupIndex && selectedPathIndex == pathIndex
    }
    
    // 获取路径的大小倍数
    private func getSizeMultiplier(groupIndex: Int, pathIndex: Int) -> CGFloat {
        return isSelectedPath(groupIndex: groupIndex, pathIndex: pathIndex) ? 2.0 : 1.0
    }
    
    // 渲染单个路径点
    private func renderPathPoint(position: CGPoint, color: Color, size: CGFloat, multiplier: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size * multiplier, height: size * multiplier)
            .position(position)
            .opacity(opacity)
    }
    
    // 渲染路径线条
    // showEndpointCircle: 是否显示终点圆点（用于决定箭头是否需要偏移）
    private func renderPathLine(positions: [CGPoint], color: Color, isDashed: Bool, showArrow: Bool, showEndpointCircle: Bool, multiplier: CGFloat) -> some View {
        let pathShape = Path { path in
            for i in 0..<positions.count-1 {
                let startPos = positions[i]
                let endPos = positions[i+1]

                let angle = atan2(endPos.y - startPos.y, endPos.x - startPos.x)
                let arrowLength: CGFloat = 16 * multiplier
                let arrowAngle: CGFloat = .pi / 6
                let offsetDistance: CGFloat = pathPointDotSize * 0.6 * multiplier

                // 只有在显示终点圆点时才偏移箭头，否则箭头直接到终点
                let arrowPos = (showArrow && showEndpointCircle) ?
                    CGPoint(
                        x: endPos.x - offsetDistance * cos(angle),
                        y: endPos.y - offsetDistance * sin(angle)
                    ) : 
                    showArrow ?
                    CGPoint(
                        x: endPos.x - 0.2 * offsetDistance * cos(angle),
                        y: endPos.y - 0.2 * offsetDistance * sin(angle)
                    ) : endPos
                
                path.move(to: startPos)
                path.addLine(to: endPos)
                
                if showArrow {
                    if isDashed {
                        let crossSize: CGFloat = 14 * multiplier
                        path.move(to: CGPoint(
                            x: endPos.x - crossSize/2,
                            y: endPos.y - crossSize/2
                        ))
                        path.addLine(to: CGPoint(
                            x: endPos.x + crossSize/2,
                            y: endPos.y + crossSize/2
                        ))
                        path.move(to: CGPoint(
                            x: endPos.x + crossSize/2,
                            y: endPos.y - crossSize/2
                        ))
                        path.addLine(to: CGPoint(
                            x: endPos.x - crossSize/2,
                            y: endPos.y + crossSize/2
                        ))
                    } else {
                        let arrowPoint1 = CGPoint(
                            x: arrowPos.x - arrowLength * cos(angle - arrowAngle),
                            y: arrowPos.y - arrowLength * sin(angle - arrowAngle)
                        )
                        let arrowPoint2 = CGPoint(
                            x: arrowPos.x - arrowLength * cos(angle + arrowAngle),
                            y: arrowPos.y - arrowLength * sin(angle + arrowAngle)
                        )
                        
                        path.move(to: arrowPos)
                        path.addLine(to: arrowPoint1)
                        path.move(to: arrowPos)
                        path.addLine(to: arrowPoint2)
                    }
                }
            }
        }
        
        if isDashed {
            return pathShape.stroke(color, style: StrokeStyle(lineWidth: 6 * multiplier, dash: [8 * multiplier, 6 * multiplier]))
                .opacity(opacity)
        } else {
            return pathShape.stroke(color, lineWidth: 6 * multiplier)
                .opacity(opacity)
        }
    }
    
    // 渲染单个路径
    private func renderPath(group: PathGroup, groupIndex: Int, pathIndex: Int) -> some View {
        let positions = group.paths[pathIndex].points.map { square in
            BoardViewModel.calculateDisplayPosition(
                square: square,
                squareSizeWidth: squareSizeWidth,
                squareSizeHeight: squareSizeHeight,
                pieceDiffX: pieceDiffX,
                pieceDiffY: pieceDiffY,
                orientation: orientation,
                isHorizontalFlipped: isHorizontalFlipped
            )
        }
        
        let selectedMultiplier = getSizeMultiplier(groupIndex: groupIndex, pathIndex: pathIndex)
        let groupColor = colorForGroup(group, index: groupIndex)
        // Path 多点路径放大，NextMoves 和单点保持原大小
        let typeMultiplier: CGFloat = (!isNextMovesGroup(group) && positions.count > 1) ? pathSizeMultiplier : 1.0
        let sizeMultiplier = selectedMultiplier * typeMultiplier

        return ZStack {
            if positions.count == 1 {
                // 对于单点，根据该点的棋子颜色选择颜色（不应用 typeMultiplier）
                let square = group.paths[pathIndex].points[0]
                let piece = piecesBySquare[square]
                let pointColor = piece?.hasPrefix("r") == true ? Color.red.opacity(0.4) :
                                piece?.hasPrefix("b") == true ? Color.blue.opacity(0.4) :
                                groupColor
                renderPathPoint(
                    position: positions[0],
                    color: pointColor,
                    size: singlePointDotSize,
                    multiplier: selectedMultiplier  // 单点只用选中倍数，不放大
                )
            } else if positions.count > 1 {
                // 只在 NextMoves 组（showAllNextMoves）时画终点圆点
                // showPath 时不画终点圆点，只画箭头线条
                if group.paths[pathIndex].showArrow && isNextMovesGroup(group) {
                    // 只在终点画圆点，起点不画
                    ForEach(Array(positions.dropFirst()), id: \.self) { position in
                        renderPathPoint(
                            position: position,
                            color: groupColor,
                            size: pathPointDotSize,
                            multiplier: sizeMultiplier
                        )
                    }
                }

                renderPathLine(
                    positions: positions,
                    color: groupColor,
                    isDashed: group.paths[pathIndex].isDashed,
                    showArrow: group.paths[pathIndex].showArrow,
                    showEndpointCircle: isNextMovesGroup(group),
                    multiplier: sizeMultiplier
                )
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(pathGroups.indices), id: \.self) { groupIndex in
                    let group = pathGroups[groupIndex]
                    ForEach(Array(group.paths.indices), id: \.self) { pathIndex in
                        renderPath(group: group, groupIndex: groupIndex, pathIndex: pathIndex)
                    }
                }
            }
            .onAppear {
                // 延迟显示路径，等待棋子移动动画完成
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration - pathAnimationDuration) {
                    withAnimation(.easeIn(duration: pathAnimationDuration)) {
                        opacity = 1
                    }
                }
            }
            .onChange(of: pathGroups) {
                // 当路径组发生变化时，重置动画
                opacity = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration - pathAnimationDuration) {
                    withAnimation(.easeIn(duration: pathAnimationDuration)) {
                        opacity = 1
                    }
                }
            }
        }
    }
} 
