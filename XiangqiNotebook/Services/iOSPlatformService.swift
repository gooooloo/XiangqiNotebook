#if os(iOS)
import SwiftUI
import UIKit

class IOSPlatformService: PlatformService {
    private weak var presentingViewController: UIViewController?
    private weak var viewModel: ViewModel?
    
    init(presentingViewController: UIViewController?) {
        self.presentingViewController = presentingViewController
    }
    
    func setViewModel(_ viewModel: ViewModel) {
        self.viewModel = viewModel
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
            
            self.presentingViewController?.present(alert, animated: true)
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
            self.presentingViewController?.present(alert, animated: true)
            completion(fileURL)
        }
    }
    
    func openFile(completion: @escaping (URL?) -> Void) {
        // 在 iOS 上，我们使用文档选择器来打开文件
        // 这里简化处理，实际应用中需要使用 UIDocumentPickerViewController
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
                self.presentingViewController?.present(alert, animated: true)
                completion(nil)
                return
            }
            
            // 创建一个选择器让用户选择文件
            let alert = UIAlertController(
                title: "选择文件",
                message: "请选择要打开的文件",
                preferredStyle: .actionSheet
            )
            
            for fileURL in jsonFiles {
                alert.addAction(UIAlertAction(title: fileURL.lastPathComponent, style: .default) { _ in
                    completion(fileURL)
                })
            }
            
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                completion(nil)
            })
            
            self.presentingViewController?.present(alert, animated: true)
        } catch {
            print("无法列出文档目录内容：\(error)")
            completion(nil)
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
                self.presentingViewController?.present(alert, animated: true)
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
                self.presentingViewController?.present(alert, animated: true)
                completion(false)
            }
        }
    }
    
    func recoverData(completion: @escaping (Data?) -> Void) {
        // 在 iOS 上，我们从应用的文档目录中恢复数据
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
                self.presentingViewController?.present(alert, animated: true)
                completion(nil)
                return
            }
            
            // 创建一个选择器让用户选择文件
            let alert = UIAlertController(
                title: "选择备份",
                message: "请选择要恢复的备份文件",
                preferredStyle: .actionSheet
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
                        self.presentingViewController?.present(errorAlert, animated: true)
                        completion(nil)
                    }
                })
            }
            
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
                completion(nil)
            })
            
            self.presentingViewController?.present(alert, animated: true)
        } catch {
            print("无法列出文档目录内容：\(error)")
            
            // 通知用户恢复失败
            let alert = UIAlertController(
                title: "恢复失败",
                message: "无法列出备份文件：\(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            self.presentingViewController?.present(alert, animated: true)
            completion(nil)
        }
    }
} 
#endif