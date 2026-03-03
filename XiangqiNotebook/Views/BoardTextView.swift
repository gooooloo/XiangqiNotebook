import SwiftUI

struct BoardTextView: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("局面文本")
                .font(.headline)

            Text(viewModel.generateBoardText())
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 20) {
                Button("拷贝") {
                    viewModel.copyBoardTextToClipboard()
                    dismiss()
                }
                Button("关闭") {
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 350, height: 320)
    }
}
