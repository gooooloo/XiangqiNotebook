#if os(macOS)
import SwiftUI
import AppKit

/// 问棋窗口。
///
/// 用独立窗口而不是 sheet 或右栏：问棋回答通常是几段中文讲解加变着，右栏
/// （220–288pt）读着太憋屈；而 sheet 会盖住棋盘，偏偏问棋时最需要对着棋盘看。
/// 独立窗口能和主窗口并排摆，边走边问。承载方式照搬 `ReferenceBoardWindowController`。
final class AIChatWindowController: NSWindowController {

    let chat: ChatViewModel

    init(viewModel: ViewModel) {
        let chat = ChatViewModel(viewModel: viewModel)
        self.chat = chat

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "问棋"
        window.minSize = NSSize(width: 460, height: 420)
        window.contentView = NSHostingView(rootView: AIChatView(chat: chat))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
