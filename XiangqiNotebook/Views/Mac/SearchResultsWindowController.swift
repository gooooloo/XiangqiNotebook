import SwiftUI
#if os(macOS)
import AppKit

struct SearchResultItem: Identifiable {
    let id = UUID()
    let text: String
    let fen: String
    let orientation: String
    let isHorizontalFlipped: Bool
    let showPath: Bool
    let currentFenPathGroups: [PathGroup]
    let score: String
    let scoreDelta: String
    let comments: String?
}

struct SearchResultsGridView: View {
    let items: [SearchResultItem]
    let columns: [GridItem] = [GridItem(.adaptive(minimum: 400), spacing: 24)]
    @State private var hiddenItemIds: Set<UUID> = []
    @State private var orderedItems: [SearchResultItem] = []
    @State private var draggedItem: SearchResultItem?
    
    var filteredItems: [SearchResultItem] {
        orderedItems.filter { !hiddenItemIds.contains($0.id) }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(filteredItems) { item in
                    ReferenceBoardContentView(
                        boardViewModel: BoardViewModel(
                            fen: item.fen,
                            orientation: item.orientation,
                            isHorizontalFlipped: item.isHorizontalFlipped,
                            showPath: item.showPath,
                            showAllNextMoves: false,
                            shouldAnimate: false,
                            currentFenPathGroups: item.currentFenPathGroups
                        ),
                        score: item.score,
                        scoreDelta: item.scoreDelta,
                        comments: item.comments ?? ""
                    )
                    .frame(width: 400, height: 550)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .contextMenu {
                        Button(action: {
                            hiddenItemIds.insert(item.id)
                        }) {
                            Label("隐藏", systemImage: "eye.slash")
                        }
                    }
                    .onDrag {
                        self.draggedItem = item
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: DropViewDelegate(
                        item: item,
                        items: $orderedItems,
                        draggedItem: $draggedItem
                    ))
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            orderedItems = items
        }
    }
}

struct DropViewDelegate: DropDelegate {
    let item: SearchResultItem
    @Binding var items: [SearchResultItem]
    @Binding var draggedItem: SearchResultItem?
    
    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedItem = self.draggedItem,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        
        if fromIndex != toIndex {
            withAnimation {
                let item = items.remove(at: fromIndex)
                items.insert(item, at: toIndex)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

class SearchResultsWindowController: NSWindowController {
    init(items: [SearchResultItem]) {
        // 获取主屏幕尺寸
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 1200)
        let window = NSWindow(
            contentRect: screenRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "搜索结果(\(items.count)) \(items.first?.text ?? "") 右键可隐藏 拖动可排序"
        window.minSize = NSSize(width: 1600, height: 1200)
        let gridView = SearchResultsGridView(items: items)
        let hostingController = NSHostingController(rootView: gridView)
        window.contentViewController = hostingController
        window.center()
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        // 自动最大化窗口
        window?.zoom(nil)
    }
}
#endif 