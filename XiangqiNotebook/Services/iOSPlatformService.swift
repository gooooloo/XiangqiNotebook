#if os(iOS)
import SwiftUI
import UIKit

class IOSPlatformService: PlatformService {
    private weak var storedPresentingViewController: UIViewController?
    private weak var viewModel: ViewModel?

    init(presentingViewController: UIViewController?) {
        self.storedPresentingViewController = presentingViewController
    }

    /// 呈现弹窗用的 view controller。
    /// init 注入的实例创建于 app 启动早期，scene 往往尚未 foregroundActive，
    /// 注入值常为 nil；这里每次呈现时实时解析，并下钻到最顶层的 presented VC，
    /// 避免"已在 present 其他控制器"导致的呈现失败
    private var presentingViewController: UIViewController? {
        let root = storedPresentingViewController ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController

        guard var top = root else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
    
    func setViewModel(_ viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    /// 呈现弹窗；presenter 不可用时返回 false。
    /// 调用方在返回 false 时必须自行回调 completion，否则等待回调的
    /// continuation（如 recoverFromUserChoice）会永久泄漏
    @discardableResult
    private func present(_ alert: UIAlertController) -> Bool {
        guard let presenter = presentingViewController else {
            print("⚠️ IOSPlatformService: presentingViewController 不可用，无法呈现弹窗 \(alert.title ?? "")")
            return false
        }
        presenter.present(alert, animated: true)
        return true
    }

    func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }
    
    func showAlert(title: String, message: String) {
        // 直接设置ViewModel的alert状态
        viewModel?.showGlobalAlert(title: title, message: message)
    }
    
    func showWarningAlert(title: String, message: String) {
        // 直接设置ViewModel的alert状态
        viewModel?.showGlobalAlert(title: title, message: message)
    }
    
    func showConfirmAlert(title: String, message: String, completion: @escaping (Bool) throws -> Void) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                do {
                    try completion(true)
                } catch {
                    print("确认对话框回调错误：\(error)")
                }
            })
            
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                do {
                    try completion(false)
                } catch {
                    print("确认对话框回调错误：\(error)")
                }
            })

            if !self.present(alert) {
                do {
                    try completion(false)
                } catch {
                    print("确认对话框回调错误：\(error)")
                }
            }
        }
    }
    
    func saveFile(defaultName: String, completion: @escaping (URL?) -> Void) {
        // 在 iOS 上，我们使用文档选择器来保存文件
        // 这里简化处理，实际应用中需要更复杂的逻辑
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentDirectory.appendingPathComponent(defaultName)
        
        // 通知用户文件已保存到文档目录
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "文件已保存",
                message: "文件已保存到应用文档目录",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            self.present(alert)
            completion(fileURL)
        }
    }

    func openFile(completion: @escaping (URL?) -> Void) {
        // 在 iOS 上，我们使用文档选择器来打开文件
        // 这里简化处理，实际应用中需要使用 UIDocumentPickerViewController
        DispatchQueue.main.async {
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

            // 列出文档目录中的所有 JSON 文件
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
                let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }

                if jsonFiles.isEmpty {
                    let alert = UIAlertController(
                        title: "没有找到文件",
                        message: "文档目录中没有 JSON 文件",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert)
                    completion(nil)
                    return
                }

                // 创建一个选择器让用户选择文件
                // 用 .alert 而非 .actionSheet：iPad 上未配置 popover 锚点的
                // actionSheet 在 present 时会抛 NSGenericException 崩溃
                let alert = UIAlertController(
                    title: "选择文件",
                    message: "请选择要打开的文件",
                    preferredStyle: .alert
                )

                for fileURL in jsonFiles {
                    alert.addAction(UIAlertAction(title: fileURL.lastPathComponent, style: .default) { _ in
                        completion(fileURL)
                    })
                }

                alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                    completion(nil)
                })

                if !self.present(alert) {
                    completion(nil)
                }
            } catch {
                print("无法列出文档目录内容：\(error)")
                completion(nil)
            }
        }
    }
    
    func backupData(_ data: Data, defaultName: String, completion: @escaping (Bool) -> Void) {
        // 在 iOS 上，我们将数据保存到应用的文档目录
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileURL = documentDirectory.appendingPathComponent(defaultName)
        
        do {
            try data.write(to: fileURL)
            
            // 通知用户备份成功
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "备份成功",
                    message: "数据已备份到应用文档目录",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert)
                completion(true)
            }
        } catch {
            print("备份数据失败：\(error)")

            // 通知用户备份失败
            DispatchQueue.main.async {
                let alert = UIAlertController(
                    title: "备份失败",
                    message: "无法保存数据：\(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert)
                completion(false)
            }
        }
    }

    func recoverData(completion: @escaping (Data?) -> Void) {
        // 在 iOS 上，我们从应用的文档目录中恢复数据
        DispatchQueue.main.async {
            let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

            // 列出文档目录中的所有 JSON 文件
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
                let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }

                if jsonFiles.isEmpty {
                    let alert = UIAlertController(
                        title: "没有找到备份",
                        message: "文档目录中没有备份文件",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert)
                    completion(nil)
                    return
                }

                // 创建一个选择器让用户选择文件
                // 用 .alert 而非 .actionSheet：iPad 上未配置 popover 锚点的
                // actionSheet 在 present 时会抛 NSGenericException 崩溃
                let alert = UIAlertController(
                    title: "选择备份",
                    message: "请选择要恢复的备份文件",
                    preferredStyle: .alert
                )

                for fileURL in jsonFiles {
                    alert.addAction(UIAlertAction(title: fileURL.lastPathComponent, style: .default) { _ in
                        do {
                            let data = try Data(contentsOf: fileURL)
                            completion(data)
                        } catch {
                            print("读取备份数据失败：\(error)")

                            // 通知用户恢复失败
                            let errorAlert = UIAlertController(
                                title: "恢复失败",
                                message: "无法读取备份数据：\(error.localizedDescription)",
                                preferredStyle: .alert
                            )
                            errorAlert.addAction(UIAlertAction(title: "确定", style: .default))
                            self.present(errorAlert)
                            completion(nil)
                        }
                    })
                }

                alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                    completion(nil)
                })

                if !self.present(alert) {
                    completion(nil)
                }
            } catch {
                print("无法列出文档目录内容：\(error)")

                // 通知用户恢复失败
                let alert = UIAlertController(
                    title: "恢复失败",
                    message: "无法列出备份文件：\(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert)
                completion(nil)
            }
        }
    }
}
#endif