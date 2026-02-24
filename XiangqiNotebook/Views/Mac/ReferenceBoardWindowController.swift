import SwiftUI
#if os(macOS)
import AppKit

struct ReferenceBoardItem: Identifiable {
    let id = UUID()
    let fen: String
    let orientation: String
    let isHorizontalFlipped: Bool
    let showPath: Bool
    let currentFenPathGroups: [PathGroup]
    let score: String
    let scoreDelta: String
    let comments: String
}

class ReferenceBoardItemsStore: ObservableObject {
    @Published var items: [ReferenceBoardItem] = []

    func append(_ item: ReferenceBoardItem) {
        items.append(item)
    }
}

struct ReferenceBoardContentView: View {
    let boardViewModel: BoardViewModel
    let score: String
    let scoreDelta: String
    let comments: String

    var body: some View {
        VStack(spacing: 10) {
            XiangqiBoard(viewModel: .constant(boardViewModel))
                .disabled(true)
                .frame(width: 400, height: 400)
                .padding()

            HStack {
                Text("分数：\(score)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Int(score) ?? 0 < -100 ? .red : .primary)
                Spacer()
                Text("变化：\(scoreDelta)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(Int(scoreDelta) ?? 0 < -100 ? .red : .primary)
            }
            .padding(.horizontal)

            ScrollView {
                Text(comments)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}

struct ReferenceBoardGridView: View {
    @ObservedObject var store: ReferenceBoardItemsStore
    let columns: [GridItem] = [GridItem(.adaptive(minimum: 400), spacing: 24)]
    @State private var hiddenItemIds: Set<UUID> = []

    var filteredItems: [ReferenceBoardItem] {
        store.items.filter { !hiddenItemIds.contains($0.id) }
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
                        comments: item.comments
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
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

class ReferenceBoardWindowController: NSWindowController {
    private let store: ReferenceBoardItemsStore

    init(item: ReferenceBoardItem) {
        let store = ReferenceBoardItemsStore()
        store.items = [item]
        self.store = store

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "参考棋盘(1)"
        window.minSize = NSSize(width: 400, height: 600)

        let gridView = ReferenceBoardGridView(store: store)
        window.contentView = NSHostingView(rootView: gridView)

        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ item: ReferenceBoardItem) {
        store.append(item)
        window?.title = "参考棋盘(\(store.items.count))"
        window?.makeKeyAndOrderFront(nil)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}
#endif
