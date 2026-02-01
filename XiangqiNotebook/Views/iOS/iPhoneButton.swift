#if os(iOS)
import SwiftUI

struct iPhoneButton: View {
    let viewModel: ViewModel
    let actionKey: ActionDefinitions.ActionKey?

    private func getAction() -> () -> Void {
        return {
            self.viewModel.showIOSMoreActionsView = false
            self.getActionInfo()?.action()
        }
    }

    private func getActionInfo() -> ActionDefinitions.ActionInfo? {
        return actionKey != nil ? viewModel.actionDefinitions.getActionInfo(actionKey!) : nil
    }

    private func formatButtonText(_ text: String) -> String {
        if text.count == 4 {
            let chars = Array(text)
            return "\(chars[0])\(chars[1])\n\(chars[2])\(chars[3])"
        }
        return text
    }

    var body: some View {
        Button(action: getAction()) {
            GeometryReader { geometry in
                Text(formatButtonText(getActionInfo()?.textIPhone ?? getActionInfo()?.text ?? ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .minimumScaleFactor(0.5)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
            .aspectRatio(1.4, contentMode: .fit)
        }
        .disabled(getActionInfo() == nil)
    }
}
#endif