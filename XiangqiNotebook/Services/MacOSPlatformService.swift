#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

class MacOSPlatformService: PlatformService {
    private var currentAlertWorkItem: DispatchWorkItem?
    private var currentRunningAlert: NSAlert?
    private var currentAlertDismissed = false

    /// 主线程同步执行；非主线程调用时异步派发到主线程。
    /// 弹窗会从后台任务的 catch 分支调用（如网络查分、引擎应招失败），
    /// dismissCurrentAlert 触碰 AppKit（orderOut/stopModal）与共享状态，
    /// 必须收敛到主线程执行
    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func dismissCurrentAlert() {
        currentAlertWorkItem?.cancel()
        currentAlertWorkItem = nil

        if let alert = currentRunningAlert {
            currentAlertDismissed = true
            alert.window.orderOut(nil)
            NSApp.stopModal()
            currentRunningAlert = nil
        }
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func showAlert(title: String, message: String) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.dismissCurrentAlert()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.currentAlertDismissed = false
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                alert.alertStyle = .informational
                alert.addButton(withTitle: "确定")
                self.currentRunningAlert = alert
                alert.runModal()
                self.currentRunningAlert = nil
            }
            self.currentAlertWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
    }

    func showWarningAlert(title: String, message: String) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.dismissCurrentAlert()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.currentAlertDismissed = false
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                self.currentRunningAlert = alert
                alert.runModal()
                self.currentRunningAlert = nil
            }
            self.currentAlertWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
    }
    
    func saveFile(defaultName: String, completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.title = "选择备份保存位置"
            panel.nameFieldStringValue = defaultName
            panel.allowedContentTypes = [UTType.json]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false  // 显示文件扩展名
            
            panel.begin { response in
                if response == .OK {
                    completion(panel.url)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    func openFile(completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "选择备份文件"
            panel.allowedContentTypes = [UTType.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.isExtensionHidden = false  // 显示文件扩展名
            
            panel.begin { response in
                if response == .OK {
                    completion(panel.url)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    func backupData(_ data: Data, defaultName: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.title = "选择备份保存位置"
            panel.nameFieldStringValue = defaultName
            panel.allowedContentTypes = [UTType.json]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false  // 显示文件扩展名
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try data.write(to: url)
                        completion(true)
                    } catch {
                        print("备份数据失败：\(error)")
                        completion(false)
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    func recoverData(completion: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = "选择备份文件"
            panel.allowedContentTypes = [UTType.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.isExtensionHidden = false  // 显示文件扩展名
            
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        let data = try Data(contentsOf: url)
                        completion(data)
                    } catch {
                        print("读取备份数据失败：\(error)")
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    func showConfirmAlert(title: String, message: String, completion: @escaping (Bool) throws -> Void) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.dismissCurrentAlert()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.currentAlertDismissed = false
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.addButton(withTitle: "保留本地")
                alert.addButton(withTitle: "使用远程")

                self.currentRunningAlert = alert
                let response = alert.runModal()
                self.currentRunningAlert = nil

                guard !self.currentAlertDismissed else { return }
                do {
                    try completion(response == .alertFirstButtonReturn)
                } catch {
                    print("确认对话框回调错误：\(error)")
                }
            }
            self.currentAlertWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
    }

    func showConfirmAlert(title: String, message: String, confirmTitle: String, cancelTitle: String, completion: @escaping (Bool) -> Void) {
        runOnMain { [weak self] in
            guard let self else { return }
            self.dismissCurrentAlert()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.currentAlertDismissed = false
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.addButton(withTitle: confirmTitle)
                alert.addButton(withTitle: cancelTitle)

                self.currentRunningAlert = alert
                let response = alert.runModal()
                self.currentRunningAlert = nil

                guard !self.currentAlertDismissed else { return }
                completion(response == .alertFirstButtonReturn)
            }
            self.currentAlertWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
    }
} 
#endif