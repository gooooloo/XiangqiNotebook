#if os(iOS)
import SwiftUI

struct iPhoneMoreOptionsView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 15) {
                        // 模式选择器
                        ModeSelectorView(viewModel: viewModel)
                            .padding(.bottom, 10)

                        // 添加 TogglesView 到最上方
                        TogglesView(viewModel: viewModel)
                            .padding(.bottom, 20)

                        HStack(spacing: 15) {
                            iPhoneButton(viewModel: viewModel, actionKey: .showBookmarkListIOS)
                            iPhoneButton(viewModel: viewModel, actionKey: .queryScore)
                            iPhoneButton(viewModel: viewModel, actionKey: .openYunku)
                            iPhoneButton(viewModel: viewModel, actionKey: viewModel.session.sessionData.currentMode == .practice ? .nextVariant : .playRandomNextMove)
                        }
                        .frame(maxWidth: .infinity)

                        HStack(spacing: 15) {
                            iPhoneButton(viewModel: viewModel, actionKey: .toEnd)
                            iPhoneButton(viewModel: viewModel, actionKey: .checkDataVersion)
                            iPhoneButton(viewModel: viewModel, actionKey: .previousPath)
                            iPhoneButton(viewModel: viewModel, actionKey: .stepLimitation)
                        }
                        .frame(maxWidth: .infinity)

                        HStack(spacing: 15) {
                            iPhoneButton(viewModel: viewModel, actionKey: .markPath)
                            iPhoneButton(viewModel: viewModel, actionKey: .referenceBoard)
                            iPhoneButton(viewModel: viewModel, actionKey: .inputGame)
                            iPhoneButton(viewModel: viewModel, actionKey: .fix)
                        }
                        .frame(maxWidth: .infinity)

                        HStack(spacing: 15) {
                            iPhoneButton(viewModel: viewModel, actionKey: .deleteMove)
                            iPhoneButton(viewModel: viewModel, actionKey: .deleteScore)
                            iPhoneButton(viewModel: viewModel, actionKey: .nextPath)
                            iPhoneButton(viewModel: viewModel, actionKey: .random)
                        }
                        .frame(maxWidth: .infinity)

                        HStack(spacing: 15) {
                            iPhoneButton(viewModel: viewModel, actionKey: .showEditCommentIOS)
                            iPhoneButton(viewModel: viewModel, actionKey: .removeMoveFromGame)
                            iPhoneButton(viewModel: viewModel, actionKey: nil)
                            iPhoneButton(viewModel: viewModel, actionKey: nil)
                        }
                        .frame(maxWidth: .infinity)

                        // 滚动到底部锚点
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        viewModel.showIOSMoreActionsView = false
                    }
                }
            }
        }
        .presentationDetents([.height(600), .large])
    }
}

#Preview {
    iPhoneBasicButtonsView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
}
#endif 
