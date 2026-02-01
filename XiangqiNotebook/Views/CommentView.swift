import SwiftUI

/// 评论区组件
struct CommentView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        HStack() {
            // 第一列：局面评论区
            VStack() {
                Text("局面评论区")
                if viewModel.isCommentEditing {
                    TextEditor(text: .init(
                        get: { viewModel.currentFenComment ?? "" },
                        set: { newValue in
                            viewModel.updateCurrentFenComment(newValue)
                        }
                    ))
                    .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                } else {
                    Text(viewModel.currentFenComment ?? "")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.gray.opacity(0.1))
                        .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                }
            }

            // 第二列：招法评论区
            VStack() {
                Text("招法评论区")
                if viewModel.isCommentEditing {
                    TextEditor(text: .init(
                        get: { viewModel.currentMoveComment ?? "" },
                        set: { newValue in
                            viewModel.updateCurrentMoveComment(newValue)
                        }
                    ))
                    .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                } else {
                    Text(viewModel.currentMoveComment ?? "")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.gray.opacity(0.1))
                        .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                }
            }

            // 第三列：相关课程 + 不好的原因
            VStack(spacing: 0) {
                // 上半部分：相关课程
                VStack(alignment: .leading, spacing: 0) {
                    Text("相关课程")
                    ScrollView {
                        FlowLayout(items: viewModel.relatedCoursesForCurrentFen) { game in
                            Text(game.name ?? "未命名游戏")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .padding(.top, 8)
                    }
                }
                .frame(maxHeight: .infinity)
                .opacity(viewModel.currentAppMode == .practice ? 0 : 1)

                // 下半部分：不好的原因
                if viewModel.currentAppMode != .practice && viewModel.isCurrentMoveBad {
                    VStack() {
                        Text("不好的原因")
                        if viewModel.isCommentEditing {
                            TextEditor(text: .init(
                                get: { viewModel.currentMoveBadReason ?? "" },
                                set: { newValue in
                                    viewModel.updateCurrentMoveBadReason(newValue)
                                }
                            ))
                        } else {
                            Text(viewModel.currentMoveBadReason ?? "")
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(Color.gray.opacity(0.1))
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding()
        .border(Color.gray)
    }
}

#Preview {
    #if os(macOS)
    CommentView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    CommentView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 
