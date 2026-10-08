#if os(iOS)
import SwiftUI
import Foundation
import UIKit

/// 五个主导航入口，由侧边栏切换
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
    @State private var showSidebar = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            let sidebarWidth = min(320.0, geometry.size.width * 0.82)
            ZStack(alignment: .leading) {
                XiangqiTheme.bg.ignoresSafeArea()
                sidebar
                    .frame(width: sidebarWidth)
                    .accessibilityHidden(!showSidebar)

                mainContent
                    .safeAreaInset(edge: .top, spacing: 0) {
                        navigationHeader
                    }
                    .background(XiangqiTheme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: showSidebar ? 28 : 0))
                    .shadow(color: .black.opacity(showSidebar ? 0.15 : 0), radius: 24, x: -8)
                    .overlay {
                        if showSidebar {
                            Color.black.opacity(0.04)
                                .contentShape(Rectangle())
                                .onTapGesture { setSidebar(false) }
                                .gesture(DragGesture().onEnded { value in
                                    if value.translation.width < -45 { setSidebar(false) }
                                })
                                .accessibilityLabel("收起侧边栏")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .accessibilityHidden(showSidebar)
                    .offset(x: showSidebar ? sidebarWidth : 0)

                if !showSidebar {
                    Color.clear
                        .frame(width: 20)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onEnded { value in
                            if value.translation.width > 45,
                               abs(value.translation.width) > abs(value.translation.height) {
                                setSidebar(true)
                            }
                        })
                        .accessibilityHidden(true)
                }
                AlertHandlerView()
                    .frame(width: 0, height: 0)
            }
            .clipped()
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == .board && oldValue != .board {
                prevTab = oldValue
            }
            setSidebar(false)
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
            BookmarkDialog(isPresented: $viewModel.showingBookmarkAlert, viewModel: viewModel)
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

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            iPhoneHomeView(
                viewModel: viewModel,
                selectedTab: $selectedTab,
                practiceRoute: $practiceRoute,
                showMore: $showMore
            )
            .tag(IPhoneTab.home)
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("今日", systemImage: "sun.max.fill") }

            iPhoneLibraryView(viewModel: viewModel, selectedTab: $selectedTab)
                .tag(IPhoneTab.library)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("棋谱", systemImage: "list.bullet") }

            iPhoneBoardView(viewModel: viewModel, selectedTab: $selectedTab, practiceRoute: $practiceRoute, prevTab: prevTab)
                .tag(IPhoneTab.board)
                .tabItem { Label("棋盘", systemImage: "square.grid.3x3.fill") }
                .toolbar(.hidden, for: .tabBar)

            iPhoneReviewModeView(viewModel: viewModel)
                .tag(IPhoneTab.review)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("复习", systemImage: "arrow.triangle.2.circlepath") }

            iPhonePracticeView(viewModel: viewModel, route: $practiceRoute)
                .tag(IPhoneTab.practice)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("练习", systemImage: "target") }
        }
        .tint(XiangqiTheme.accent)
        .toolbar(.hidden, for: .tabBar)
    }

    private var navigationHeader: some View {
        HStack {
            Button { setSidebar(true) } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("打开侧边栏")
            Spacer()
        }
        .foregroundStyle(XiangqiTheme.ink)
        .padding(.horizontal, 12)
        .background(XiangqiTheme.bg)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("象棋笔记")
                    .font(XiangqiTheme.XFont.serif(26, weight: .bold))
                Spacer()
                Button { setSidebar(false) } label: {
                    Image(systemName: "sidebar.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("收起侧边栏")
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 6) {
                    sidebarItem(.home, title: "今日", icon: "sun.max")
                    sidebarItem(.library, title: "棋谱", icon: "list.bullet")
                    sidebarItem(.board, title: "棋盘", icon: "square.grid.3x3")
                    sidebarItem(.review, title: "复习", icon: "arrow.triangle.2.circlepath")
                    sidebarItem(.practice, title: "练习", icon: "target")
                }
                .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
            Button {
                setSidebar(false)
                showMore = true
            } label: {
                Label("更多与设置", systemImage: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .foregroundStyle(XiangqiTheme.ink)
        .background(XiangqiTheme.bg)
    }

    private func sidebarItem(_ tab: IPhoneTab, title: String, icon: String) -> some View {
        Button {
            selectedTab = tab
            setSidebar(false)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 19, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .foregroundStyle(selectedTab == tab ? XiangqiTheme.accent : XiangqiTheme.ink)
            .background(selectedTab == tab ? XiangqiTheme.accent.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private func setSidebar(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            showSidebar = visible
        }
    }
}

#Preview {
    iPhoneContentView()
}
#endif
