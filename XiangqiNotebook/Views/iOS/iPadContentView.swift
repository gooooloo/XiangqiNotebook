#if os(iOS)
import SwiftUI
import Foundation
import UIKit

struct iPadContentView: View {
    @StateObject private var viewModel: ViewModel
    
    init() {
        let rootViewController = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap { $0 as? UIWindowScene }?.windows
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        _viewModel = StateObject(wrappedValue: ViewModel(
            platformService: IOSPlatformService(presentingViewController: rootViewController)
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                HStack() {
                    // 左侧区域：棋盘、状态栏、评论区
                    VStack() {
                        XiangqiBoard(viewModel: $viewModel.boardViewModel, onMove: { newFen in
                            viewModel.handleBoardMove(newFen)
                        })
                        .frame(height: geometry.size.height * 0.5)
                        
                        StatusBarView(viewModel: viewModel)
                        
                        CommentView(viewModel: viewModel)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // 中间区域：着法列表、变着列表
                    VStack {
                        MoveListView(viewModel: viewModel)
                            .frame(width: geometry.size.width * 0.2)
                        VariantListView(viewModel: viewModel)
                            .frame(height: geometry.size.height * 0.2)
                    }
                    .frame(width: geometry.size.width * 0.2)
                    
                    // 右侧区域：筛选、书签
                    VStack {
                        // 模式选择器
                        ModeSelectorView(viewModel: viewModel)

                        TogglesView(viewModel: viewModel)
                        BookmarkListView(viewModel: viewModel)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: geometry.size.width * 0.2)
                }
                // 按钮区
                iPadActionButtonsView(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("象棋笔记")
            
            // 添加AlertHandlerView，但不可见
            AlertHandlerView()
                .frame(width: 0, height: 0)
        }
        // sheet 弹窗
        .sheet(isPresented: $viewModel.showingBookmarkAlert) {
            BookmarkDialog(
                isPresented: $viewModel.showingBookmarkAlert,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $viewModel.showMarkPathView) {
            MarkPathView(viewModel: viewModel.boardViewModel) { updatedPathGroups in
                viewModel.updateCurrentFenPathGroups(updatedPathGroups)
            }
        }
        .sheet(isPresented: $viewModel.showingGameBrowserView) {
            GameBrowserView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingStepLimitationDialog) {
            StepLimitationDialog(isPresented: $viewModel.showingStepLimitationDialog, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingGameInputView) {
            GameInputView(
                viewModel: viewModel,
                onSave: { game in
                    return viewModel.addCurrentGameToMyRealGame(gameInfo: game)
                }
            )
        }
    }
}

#Preview {
    iPadContentView()
}
#endif 
