#if os(iOS)
import SwiftUI
import Foundation
import UIKit

/// 主导航入口，由侧边栏切换
enum IPhoneTab: Hashable {
    case home, library, board, aiChat, review, practice
}

/// 「练习」标签的跳转目的地，供「今日」首页/「更多」页等外部入口发起跨标签导航
enum PracticeRoute: Equatable {
    case home, mistakes
}

struct iPhoneContentView: View {
    @StateObject private var viewModel: ViewModel
    @StateObject private var chat: ChatViewModel
    @State private var selectedTab: IPhoneTab = .home
    @State private var practiceRoute: PracticeRoute = .home
    @State private var showFilterSheet = false
    @State private var showReviewLibrary = false
    @State private var practiceScreen: IPhonePracticeScreen = .home
    @State private var practiceMistakeCount = 0
    @State private var practiceStepsPlayed = 0
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
        _chat = StateObject(wrappedValue: ChatViewModel(viewModel: viewModel))
    }

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = min(190.0, geometry.size.width)
            ZStack(alignment: .leading) {
                XiangqiTheme.bg.ignoresSafeArea()
                sidebar
                    .frame(width: sidebarWidth)
                    .accessibilityHidden(!showSidebar)

                // 用实际布局分配菜单栏高度，避免 TabView 内的页面忽略外部 safeAreaInset。
                VStack(spacing: 0) {
                    navigationHeader
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
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
                                    if value.translation.width < -45,
                                       abs(value.translation.width) > abs(value.translation.height) {
                                        setSidebar(false)
                                    }
                                })
                                .accessibilityLabel("收起侧边栏")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .accessibilityHidden(showSidebar)
                    .accessibilityAction(named: "打开侧边栏") { setSidebar(true) }
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
        .onChange(of: selectedTab) { _, _ in
            setSidebar(false)
        }
        .onChange(of: viewModel.showingAIChat) { _, showing in
            guard showing else { return }
            viewModel.showingAIChat = false
            viewModel.showIOSMoreActionsView = false
            showMore = false
            selectedTab = .aiChat
            chat.reloadConfig()
            if let question = viewModel.pendingAIQuestion {
                viewModel.pendingAIQuestion = nil
                chat.ask(question)
            }
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

            iPhoneLibraryView(viewModel: viewModel, selectedTab: $selectedTab, showFilterSheet: $showFilterSheet)
                .tag(IPhoneTab.library)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("棋谱", systemImage: "list.bullet") }

            iPhoneBoardView(viewModel: viewModel, selectedTab: $selectedTab, practiceRoute: $practiceRoute)
                .tag(IPhoneTab.board)
                .tabItem { Label("棋盘", systemImage: "square.grid.3x3.fill") }
                .toolbar(.hidden, for: .tabBar)

            AIChatView(chat: chat)
                .onAppear { chat.reloadConfig() }
                .tag(IPhoneTab.aiChat)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("问棋", systemImage: "bubble.left.and.bubble.right") }

            iPhoneReviewModeView(viewModel: viewModel, showLibrary: $showReviewLibrary)
                .tag(IPhoneTab.review)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("复习", systemImage: "arrow.triangle.2.circlepath") }

            iPhonePracticeView(viewModel: viewModel, route: $practiceRoute, view: $practiceScreen, mistakeCount: $practiceMistakeCount, stepsPlayed: $practiceStepsPlayed)
                .tag(IPhoneTab.practice)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("练习", systemImage: "target") }
        }
        .tint(XiangqiTheme.accent)
        .toolbar(.hidden, for: .tabBar)
    }

    private var navigationTitle: String {
        switch selectedTab {
        case .aiChat: return "问棋"
        case .home: return "今日"
        case .library: return "棋谱"
        case .board: return "棋盘"
        case .review: return viewModel.isInVerificationMode ? "检验模式" : "复习"
        case .practice: return practiceScreen == .mistakes ? "错误统计" : "练习"
        }
    }

    private var navigationHeader: some View {
        HStack(spacing: 8) {
            Button { setSidebar(true) } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("打开侧边栏")
            if selectedTab == .board {
                boardStatus
                Spacer(minLength: 0)
                Button { viewModel.showIOSMoreActionsView = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多棋盘操作")
            } else {
                if selectedTab == .practice && practiceScreen != .home {
                    Button { practiceScreen = .home } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 32, height: 44)
                    }
                    .accessibilityLabel("返回练习首页")
                }
                Text(navigationTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                navigationActions
            }
        }
        .foregroundStyle(XiangqiTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(XiangqiTheme.bg)
        .overlay(alignment: .bottom) {
            Divider().overlay(XiangqiTheme.hair)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var navigationActions: some View {
        switch selectedTab {
        case .home:
            Text(Date(), format: .dateTime.month().day())
                .font(.system(size: 12))
                .foregroundStyle(XiangqiTheme.sub)
            Button { showMore = true } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多与设置")
        case .library:
            headerButton("筛选", icon: "line.3.horizontal.decrease") { showFilterSheet = true }
        case .review:
            if viewModel.isReviewingInProgress || viewModel.isInVerificationMode {
                Text(viewModel.reviewProgress)
                    .font(.system(size: 12))
                    .foregroundStyle(XiangqiTheme.sub)
                if !viewModel.isInVerificationMode {
                    headerButton("检验") {
                        guard let item = viewModel.currentReviewItem,
                              let path = item.srsData.gamePath else { return }
                        viewModel.enterVerificationMode(fenId: item.fenId, srsData: item.srsData, gamePath: path)
                    }
                }
            } else {
                headerButton("复习库") { showReviewLibrary = true }
            }
        case .practice:
            if practiceScreen == .session {
                Text("第 \(practiceStepsPlayed + 1) 手")
                    .font(.system(size: 12))
                    .foregroundStyle(XiangqiTheme.sub)
                Text("错 \(practiceMistakeCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(XiangqiTheme.bad)
            }
        case .board, .aiChat:
            EmptyView()
        }
    }

    private func headerButton(_ title: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(XiangqiTheme.card, in: Capsule())
            .overlay(Capsule().stroke(XiangqiTheme.line, lineWidth: 1))
            .frame(minHeight: 44)
        }
    }

    private var boardStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isRedTurn ? Color(hex: 0xA15750) : Color(hex: 0x3A3A3D))
                .frame(width: 9, height: 9)
            Text((viewModel.isRedTurn ? "红方" : "黑方") + "走子")
                .font(.system(size: 17, weight: .semibold))
            Text("· 第 \(viewModel.currentGameStepDisplay)/\(viewModel.maxGameStepDisplay) 手")
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(XiangqiTheme.ink)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
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
                    sidebarItem(.aiChat, title: "问棋", icon: "bubble.left.and.bubble.right")
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
