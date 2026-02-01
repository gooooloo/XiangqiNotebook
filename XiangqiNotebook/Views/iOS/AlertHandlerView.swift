#if os(iOS)
import SwiftUI
import UIKit

struct AlertHandlerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AlertHandlerViewController {
        return AlertHandlerViewController()
    }
    
    func updateUIViewController(_ uiViewController: AlertHandlerViewController, context: Context) {
        // 不需要更新
    }
}
#endif 