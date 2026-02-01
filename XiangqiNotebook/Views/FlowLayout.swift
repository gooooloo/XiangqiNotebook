import SwiftUI

/// PreferenceKey for propagating FlowLayout height
private struct FlowLayoutHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 流式布局视图，自动将子视图排列成多行
/// 当一行放不下时自动换到下一行
struct FlowLayout<Data, Content>: View where Data: RandomAccessCollection, Content: View, Data.Element: Identifiable {
    let items: Data
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    let content: (Data.Element) -> Content

    @State private var totalHeight = CGFloat.zero

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
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
        .onPreferenceChange(FlowLayoutHeightKey.self) { newHeight in
            self.totalHeight = newHeight
        }
    }

    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        var rowHeight = CGFloat.zero
        var calculatedHeight: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                content(item)
                    .alignmentGuide(.leading, computeValue: { d in
                        if (abs(width - d.width) > geometry.size.width) {
                            width = 0
                            height -= rowHeight
                            rowHeight = 0
                        }
                        let result = width
                        if index == items.count - 1 {
                            width = 0
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: { d in
                        if (abs(width) > geometry.size.width) {
                            height -= rowHeight
                            rowHeight = d.height
                        } else {
                            rowHeight = max(rowHeight, d.height)
                        }
                        let result = height
                        if index == items.count - 1 {
                            height = 0
                            calculatedHeight = abs(result) + rowHeight + verticalSpacing
                        }
                        return result
                    })
            }

            // Invisible view that propagates the calculated height via PreferenceKey
            Color.clear
                .frame(width: 0, height: 0)
                .preference(key: FlowLayoutHeightKey.self, value: calculatedHeight)
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
