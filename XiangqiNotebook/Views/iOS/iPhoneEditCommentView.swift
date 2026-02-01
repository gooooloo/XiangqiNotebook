#if os(iOS)
import SwiftUI

/// 评论显示组件
struct iPhoneEditCommentView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        NavigationView {
            VStack() {
                Text("局面评论区")
                TextEditor(text: .init(
                    get: { viewModel.currentFenComment ?? "" },
                    set: { newValue in
                        viewModel.updateCurrentFenComment(newValue)
                    }
                ))
                .padding()
                .border(Color.gray)

                Spacer()

                Text("招法评论区")
                TextEditor(text: .init(
                    get: { viewModel.currentMoveComment ?? "" },
                    set: { newValue in
                        viewModel.updateCurrentMoveComment(newValue)
                    }
                ))
                .padding()
                .border(Color.gray)

                Spacer()

                VStack() {
                    Text("不好的原因")
                    TextEditor(text: .init(
                        get: { viewModel.currentMoveBadReason ?? "" },
                        set: { newValue in
                            viewModel.updateCurrentMoveBadReason(newValue)
                        }
                    ))
                    .padding()
                    .border(Color.gray)
                }
                .opacity(!viewModel.isCurrentMoveBad ? 0 : 1)
            }
        }
        .presentationDetents([.height(600), .large])
    }
}
#endif 
