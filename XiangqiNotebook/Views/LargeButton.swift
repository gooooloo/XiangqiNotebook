import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LargerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray, lineWidth: 1)
            )
    }
}

struct LargeButton: View {
    @ObservedObject var viewModel: ViewModel
    let actionKey: ActionDefinitions.ActionKey?

    init(viewModel: ViewModel, actionKey: ActionDefinitions.ActionKey?) {
        self.viewModel = viewModel
        self.actionKey = actionKey
    }

    var body: some View {
        let finalActionInfo: ActionDefinitions.ActionInfo? = {
            if let actionKey = actionKey {
                if viewModel.isActionVisible(actionKey) {
                    return viewModel.actionDefinitions.getActionInfo(actionKey)
                } else {
                    return nil  // 不可见时显示占位符保持布局
                }
            } else {
                return nil
            }
        }()

        Button(action: {
            finalActionInfo?.action()
        }) {
            HStack(spacing: 4) {
                Text(finalActionInfo?.text ?? "")
                    .font(.system(size: 14))

                if let shortcut = finalActionInfo?.shortcut {
                    Text("[\(shortcut.getDisplayText())]")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
        }
        .buttonStyle(LargerButtonStyle())
        .disabled(finalActionInfo == nil)
    }
} 