#if os(iOS)
import SwiftUI
import Foundation
import UIKit

/// 底部 5 标签
enum IPhoneTab: Hashable {
    case home, library, board, review, practice
}

/// 「练习」标签的跳转目的地，供「今日」首页/「更多」页等外部入口发起跨标签导航
enum PracticeRoute: Equatable {
    case home, mistakes
}

struct iPhoneContentView: View {
    @StateObject private var viewModel: ViewModel
    @State private var selectedTab: IPhoneTab = .home
    /// 「棋盘」是沉浸式分析页，进入前所在的标签，供其「‹ 返回」按钮回退
    @State private var prevTab: IPhoneTab = .home
    @State private var practiceRoute: PracticeRoute = .home
    @State private var showMore = false

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
        ZStack {
            TabView(selection: $selectedTab) {
                iPhoneHomeView(
                    viewModel: viewModel,
                    selectedTab: $selectedTab,
                    practiceRoute: $practiceRoute,
                    showMore: $showMore
                )
                .tag(IPhoneTab.home)
                .tabItem { Label("今日", systemImage: "sun.max.fill") }

                iPhoneLibraryView(viewModel: viewModel, selectedTab: $selectedTab)
                    .tag(IPhoneTab.library)
                    .tabItem { Label("棋谱", systemImage: "list.bullet") }

                iPhoneBoardView(viewModel: viewModel, selectedTab: $selectedTab, practiceRoute: $practiceRoute, prevTab: prevTab)
                    .tag(IPhoneTab.board)
                    .tabItem { Label("棋盘", systemImage: "square.grid.3x3.fill") }
                    .toolbar(.hidden, for: .tabBar)

                iPhoneReviewModeView(viewModel: viewModel)
                    .tag(IPhoneTab.review)
                    .tabItem { Label("复习", systemImage: "arrow.triangle.2.circlepath") }

                iPhonePracticeView(viewModel: viewModel, route: $practiceRoute)
                    .tag(IPhoneTab.practice)
                    .tabItem { Label("练习", systemImage: "target") }
            }
            .tint(XiangqiTheme.accent)
            .onChange(of: selectedTab) { oldValue, newValue in
                if newValue == .board && oldValue != .board {
                    prevTab = oldValue
                }
            }

            AlertHandlerView()
                .frame(width: 0, height: 0)
        }
        .fullScreenCover(isPresented: $showMore) {
            iPhoneMoreOptionsView(
                viewModel: viewModel,
                isPresented: $showMore,
                selectedTab: $selectedTab,
                practiceRoute: $practiceRoute
            )
        }
        .sheet(isPresented: $viewModel.showingBookmarkAlert) {
            BookmarkDialog(
                isPresented: $viewModel.showingBookmarkAlert,
                viewModel: viewModel
            )
        }
        .sheet(isPresented: $viewModel.showIOSBookMarkListView) {
            iPhoneBookmarkListView(viewModel: viewModel, isPresented: $viewModel.showIOSBookMarkListView)
        }
        .sheet(isPresented: $viewModel.showingStepLimitationDialog) {
            StepLimitationDialog(isPresented: $viewModel.showingStepLimitationDialog, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showReviewListIOS) {
            iPhoneReviewListView(viewModel: viewModel, isPresented: $viewModel.showReviewListIOS)
        }
        .sheet(isPresented: $viewModel.showRealGameListIOS) {
            iPhoneRealGameListView(viewModel: viewModel, isPresented: $viewModel.showRealGameListIOS)
        }
        .sheet(isPresented: $viewModel.showingShortcutUsageStatsView) {
            ShortcutUsageStatsView(viewModel: viewModel)
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
