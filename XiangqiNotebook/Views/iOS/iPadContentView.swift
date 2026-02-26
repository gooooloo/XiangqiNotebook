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
                        // 变着列表 + 下一步招法列表（左右并排）
                    HStack(spacing: 0) {
                        VariantListView(viewModel: viewModel)
                        NextMovesListView(viewModel: viewModel)
                    }
                    .frame(height: geometry.size.height * 0.25)
                    }
                    .frame(width: geometry.size.width * 0.2)
                    
                    // 右侧区域：筛选、书签
                    VStack {
                        // 模式选择器
                        ModeSelectorView(viewModel: viewModel)

                        if viewModel.isInReviewMode {
                            // 复习模式：复习面板 + 复习库列表（填满） + 棋盘操作（底部）
                            ReviewModeView(viewModel: viewModel)
                            ScrollView {
                                ReviewListView(viewModel: viewModel)
                            }
                            .border(Color.gray)
                            .frame(maxHeight: .infinity)
                            BoardOperationTogglesView(viewModel: viewModel)
                        } else {
                            // 常规/练习模式：棋局筛选 + 书签 + 实战列表
                            ScrollView {
                                VStack(spacing: 0) {
                                    TogglesView(viewModel: viewModel)
                                    BookmarkListView(viewModel: viewModel)
                                    RealGameListView(viewModel: viewModel)
                                }
                            }
                            .frame(maxHeight: .infinity)
                        }
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
        .sheet(isPresented: $viewModel.showingReviewListView) {
            ReviewListView(viewModel: viewModel)
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}

#Preview {
    iPadContentView()
}
#endif 
