import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct XiangqiNotebookApp: App {
    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacContentView()
                .frame(minWidth: 1000, idealWidth: 1280, maxWidth: .infinity, minHeight: 700, idealHeight: 900, maxHeight: .infinity)
            #else
            // 根据设备类型选择适当的视图
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadContentView()
            } else {
                iPhoneContentView()
            }
            #endif
        }
        #if os(macOS)
        .commands {
            // 主窗口只能有一个：每个 MacContentView 各建一套 ViewModel 与按键监控，
            // 开第二个窗口会让键盘事件被先安装的监控抢走、两套 ViewModel 互相覆盖同一份 session 文件。
            // 参考棋盘 / 搜索结果 / 问棋等辅助窗口由各自的 WindowController 管理，不受影响
            CommandGroup(replacing: .newItem) {}
            MacMenuCommands()

            // 在帮助菜单中添加隐私政策链接
            CommandGroup(after: .help) {
                Button("隐私政策...") {
                    if let url = URL(string: "https://github.com/gooooloo/XiangqiNotebook/blob/main/PRIVACY_POLICY.md") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
        #endif
    }
}
