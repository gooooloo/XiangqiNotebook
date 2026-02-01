#if os(iOS)
import UIKit

class AlertHandlerViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowAlert),
            name: Notification.Name("ShowAlert"),
            object: nil
        )
    }
    
    @objc func handleShowAlert(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let title = userInfo["title"] as? String,
              let message = userInfo["message"] as? String,
              let styleRaw = userInfo["style"] as? Int,
              let style = UIAlertController.Style(rawValue: styleRaw) else {
            return
        }
        
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: style
        )
        
        alertController.addAction(UIAlertAction(
            title: "确定",
            style: .default
        ))
        
        present(alertController, animated: true)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 
#endif