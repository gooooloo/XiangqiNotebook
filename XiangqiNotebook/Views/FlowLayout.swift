import SwiftUI

/// 流式布局，使用 Layout 协议实现
/// 自动将子视图排列成多行，当一行放不下时自动换到下一行
/// 兼容 ScrollView（正确报告自身尺寸）
private struct FlowLayoutEngine: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let containerWidth = proposal.width ?? .infinity
        let rows = computeRows(subviews: subviews, containerWidth: containerWidth)
        var totalHeight: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.size.height }.max() ?? 0
            totalHeight += rowHeight
            if index < rows.count - 1 {
                totalHeight += verticalSpacing
            }
        }
        return CGSize(width: containerWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(subviews: subviews, containerWidth: bounds.width)
        var y = bounds.minY
        for (index, row) in rows.enumerated() {
            var x = bounds.minX
            let rowHeight = row.map { $0.size.height }.max() ?? 0
            for item in row {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + horizontalSpacing
            }
            y += rowHeight
            if index < rows.count - 1 {
                y += verticalSpacing
            }
        }
    }

    private struct LayoutItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private func computeRows(subviews: Subviews, containerWidth: CGFloat) -> [[LayoutItem]] {
        var rows: [[LayoutItem]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = currentRowWidth > 0 ? horizontalSpacing + size.width : size.width

            if currentRowWidth + neededWidth > containerWidth && currentRowWidth > 0 {
                rows.append([])
                currentRowWidth = 0
            }

            rows[rows.count - 1].append(LayoutItem(subview: subview, size: size))
            currentRowWidth += currentRowWidth > 0 ? horizontalSpacing + size.width : size.width
        }

        return rows
    }
}

/// FlowLayout 包装视图，接受数据集合和内容构建器
struct FlowLayout<Data, Content>: View where Data: RandomAccessCollection, Content: View, Data.Element: Identifiable {
    let items: Data
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let content: (Data.Element) -> Content

    init(
        items: Data,
        horizontalSpacing: CGFloat = 8,
        verticalSpacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.items = items
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
        self.content = content
    }

    var body: some View {
        FlowLayoutEngine(horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

#Preview {
    struct PreviewItem: Identifiable {
        let id: Int
        let text: String
    }

    let items = [
        PreviewItem(id: 1, text: "曹开局-002"),
        PreviewItem(id: 2, text: "曹开局-003"),
        PreviewItem(id: 3, text: "曹开局-004"),
        PreviewItem(id: 4, text: "曹开局-005"),
        PreviewItem(id: 5, text: "曹开局-006"),
        PreviewItem(id: 6, text: "中炮进三兵对屏风马"),
        PreviewItem(id: 7, text: "测试"),
    ]

    return ScrollView {
        FlowLayout(items: items) { item in
            Text(item.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
        }
        .padding()
    }
    .frame(width: 300, height: 200)
}
