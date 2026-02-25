#if os(iOS)
import SwiftUI
import Foundation
import UIKit

struct iPhoneContentView: View {
    @StateObject private var viewModel: ViewModel
    
    init() {
        // 在iOS上，我们需要一个UIViewController来显示文件选择器
        // 使用更现代的方式获取rootViewController
        let rootViewController = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap { $0 as? UIWindowScene }?.windows
            .first(where: \.isKeyWindow)?
            .rootViewController
            
        let platformService = IOSPlatformService(presentingViewController: rootViewController)
        let viewModel = ViewModel(platformService: platformService)
        platformService.setViewModel(viewModel)
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    // 棋盘视图 - 占据大部分屏幕空间
                    XiangqiBoard(viewModel: $viewModel.boardViewModel, onMove: { newFen in
                        viewModel.handleBoardMove(newFen)
                    })
                    .aspectRatio(1, contentMode: .fit)

                    // 添加状态栏 - 显示分数、步数和版本信息
                    iPhoneStatusBarView(viewModel: viewModel)

                    // 添加评论文本显示
                    // iPhoneCommentView(viewModel: viewModel)

                    Spacer()
                        .frame(height: 15)

                    // 添加前进后退按钮
                    iPhoneBasicButtonsView(viewModel: viewModel)
                }
                .navigationTitle("象棋笔记")
                
                // 添加AlertHandlerView，但不可见
                AlertHandlerView()
                    .frame(width: 0, height: 0)
            }
        }
        .ignoresSafeArea(.all, edges: [.bottom])
        .sheet(isPresented: $viewModel.showingBookmarkAlert) {
            BookmarkDialog(
                isPresented: $viewModel.showingBookmarkAlert,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $viewModel.showIOSBookMarkListView) {
            iPhoneBookmarkListView(viewModel: viewModel, isPresented: $viewModel.showIOSBookMarkListView)
        }
        .sheet(isPresented: $viewModel.showIOSMoreActionsView) {
            iPhoneMoreOptionsView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingStepLimitationDialog) {
            StepLimitationDialog(isPresented: $viewModel.showingStepLimitationDialog, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showEditCommentIOS) {
            iPhoneEditCommentView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showReviewListIOS) {
            iPhoneReviewListView(viewModel: viewModel, isPresented: $viewModel.showReviewListIOS)
        }
        .alert(viewModel.globalAlertTitle, isPresented: $viewModel.showingGlobalAlert) {
            Button("确定") { }
        } message: {
            Text(viewModel.globalAlertMessage)
        }
    }
}

#Preview {
    iPhoneContentView()
}
#endif 
