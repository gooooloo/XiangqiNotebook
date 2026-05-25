import SwiftUI
#if os(macOS)
import AppKit

class ForceGraphWindowController: NSWindowController {
    private let viewModel: ForceGraphViewModel

    init(databaseView: DatabaseView, rootFenId: Int?, currentFenId: Int?, onNavigate: @escaping (Int) -> Void) {
        let vm = ForceGraphViewModel()
        vm.onNavigateToFenId = onNavigate
        vm.currentFenId = currentFenId
        self.viewModel = vm

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "局面图谱"
        window.minSize = NSSize(width: 500, height: 400)

        let contentView = ForceGraphCanvasView(viewModel: vm)
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        super.init(window: window)

        vm.loadGraph(from: databaseView, rootFenId: rootFenId)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateCurrentFenId(_ fenId: Int?) {
        viewModel.currentFenId = fenId
    }

    func reload(databaseView: DatabaseView, rootFenId: Int?, currentFenId: Int?) {
        viewModel.currentFenId = currentFenId
        viewModel.loadGraph(from: databaseView, rootFenId: rootFenId)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}

#endif
