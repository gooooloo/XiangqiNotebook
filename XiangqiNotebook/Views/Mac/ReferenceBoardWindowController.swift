import SwiftUI
#if os(macOS)
import AppKit

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
                    .textSelection(.enabled)  // 允许选择文本
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}

class ReferenceBoardWindowController: NSWindowController {
    init(fen: String, orientation: String, isHorizontalFlipped: Bool, showPath: Bool, currentFenPathGroups: [PathGroup], score: String = "", scoreDelta: String = "", comments: String = "") {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 700), // 增加窗口高度以适应更多内容
            styleMask: [.titled, .closable, .miniaturizable, .resizable], // 添加 .resizable
            backing: .buffered,
            defer: false
        )
        window.title = "参考棋盘"
        window.minSize = NSSize(width: 400, height: 600) // 设置最小尺寸
        
        let boardViewModel = BoardViewModel(
            fen: fen,
            orientation: orientation,
            isHorizontalFlipped: isHorizontalFlipped,
            showPath: showPath,
            showAllNextMoves: false,
            shouldAnimate: false,
            currentFenPathGroups: currentFenPathGroups
        )
        
        window.contentView = NSHostingView(rootView: ReferenceBoardContentView(
            boardViewModel: boardViewModel,
            score: score,
            scoreDelta: scoreDelta,
            comments: comments
        ))
        
        window.center()
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}
#endif 