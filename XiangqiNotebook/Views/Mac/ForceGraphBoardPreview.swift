import SwiftUI

#if os(macOS)

struct ForceGraphBoardPreview: View {
    let boardViewModel: BoardViewModel
    let fenId: Int
    let edgeCount: Int

    var body: some View {
        VStack(spacing: 4) {
            XiangqiBoard(viewModel: .constant(boardViewModel))
                .disabled(true)
                .aspectRatio(1.0, contentMode: .fit)

            Text("关联: \(edgeCount)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(6)
    }
}

#endif
