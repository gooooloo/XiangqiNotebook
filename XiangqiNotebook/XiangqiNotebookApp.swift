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
