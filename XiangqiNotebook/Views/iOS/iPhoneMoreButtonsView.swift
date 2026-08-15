#if os(iOS)
import SwiftUI

/// 「更多」页：从「今日」首页右上角印章按钮进入，个人信息 + 分组功能列表。
struct iPhoneMoreOptionsView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool
    @Binding var selectedTab: IPhoneTab
    @Binding var practiceRoute: PracticeRoute

    @State private var sheet: MoreSheet?

    private enum MoreSheet: Identifiable {
        case openings, bookmarks, importPGN, exportPGN, boardAppearance, engine
        case aiChat, aiSettings
        var id: Self { self }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profileHeader
                    group(title: "开局与收藏", rows: [
                        row(icon: "❖", title: "开局库", subtitle: "按布局体系浏览棋谱") { sheet = .openings },
                        row(icon: "☆", title: "书签", subtitle: "\(viewModel.bookmarkList.count) 个收藏局面", value: "\(viewModel.bookmarkList.count)") { sheet = .bookmarks },
                    ])
                    group(title: "AI 问棋", rows: [
                        row(icon: "☷", title: "问棋", subtitle: "就当前局面向 AI 提问") { sheet = .aiChat },
                        row(icon: "⚙", title: "AI 设置", subtitle: "服务地址 · 模型 · API key") { sheet = .aiSettings },
                    ])
                    group(title: "训练数据", rows: [
                        row(icon: "▤", title: "学习统计", subtitle: "复习库总览") { viewModel.showReviewListIOS = true },
                        row(icon: "△", title: "错误统计", subtitle: "最常走错的局面") {
                            practiceRoute = .mistakes
                            selectedTab = .practice
                            isPresented = false
                        },
                    ])
                    group(title: "棋谱文件", rows: [
                        row(icon: "⇩", title: "导入 PGN / DhtmlXQ", subtitle: "从文件或剪贴板导入") { sheet = .importPGN },
                        row(icon: "⇧", title: "导出当前棋谱", subtitle: "分享为 PGN 或图片") { sheet = .exportPGN },
                    ])
                    group(title: "设置", rows: [
                        row(icon: "◱", title: "棋盘与棋子", subtitle: "传统红黑 · 木纹底") { sheet = .boardAppearance },
                        row(icon: "⚙", title: "引擎与云库", subtitle: "ChessDB 云库") { sheet = .engine },
                        row(icon: "❋", title: "复习算法", subtitle: "SM-2 间隔重复", showChevron: false, action: nil),
                        row(icon: "ⓘ", title: "关于", subtitle: "象棋笔记", showChevron: false, action: nil),
                    ])
                }
                .padding(20)
            }
            .background(XiangqiTheme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { isPresented = false }
                }
            }
        }
        .sheet(item: $sheet) { s in
            switch s {
            case .openings: iPhoneOpeningsSheet(viewModel: viewModel, selectedTab: $selectedTab, isMorePresented: $isPresented)
            case .bookmarks:
                iPhoneBookmarkListView(
                    viewModel: viewModel,
                    isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })
                )
            case .importPGN: iPhoneImportSheet(viewModel: viewModel)
            case .exportPGN: iPhoneExportSheet(viewModel: viewModel)
            case .boardAppearance: iPhoneBoardAppearanceSheet()
            case .engine: iPhoneEngineSheet(viewModel: viewModel)
            case .aiChat: iPhoneAIChatSheet(viewModel: viewModel)
            case .aiSettings:
                AISettingsView(
                    isPresented: Binding(get: { sheet != nil }, set: { if !$0 { sheet = nil } })
                )
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16)
                .fill(XiangqiTheme.accent)
                .frame(width: 56, height: 56)
                .overlay(
                    Text("帥")
                        .font(XiangqiTheme.XFont.serif(28, weight: .heavy))
                        .foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("我的棋艺")
                    .font(XiangqiTheme.XFont.serif(20, weight: .bold))
                    .foregroundColor(XiangqiTheme.ink)
                Text("复习库 \(viewModel.reviewItemList.count) 局面")
                    .font(.system(size: 13))
                    .foregroundColor(XiangqiTheme.sub)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.bottom, 12)
    }

    private struct Row {
        let icon: String
        let title: String
        let subtitle: String?
        let value: String?
        let showChevron: Bool
        let action: (() -> Void)?
    }

    private func row(icon: String, title: String, subtitle: String? = nil, value: String? = nil, showChevron: Bool = true, action: (() -> Void)?) -> Row {
        Row(icon: icon, title: title, subtitle: subtitle, value: value, showChevron: showChevron, action: action)
    }

    private func group(title: String, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(XiangqiTheme.XFont.sans(11.5, weight: .bold))
                .tracking(1.5)
                .foregroundColor(XiangqiTheme.faint)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    Button(action: { r.action?() }) {
                        HStack(spacing: 13) {
                            Text(r.icon)
                                .font(XiangqiTheme.XFont.serif(16))
                                .foregroundColor(XiangqiTheme.accent)
                                .frame(width: 32, height: 32)
                                .xqInset(radius: 9)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.title)
                                    .font(XiangqiTheme.XFont.sans(15, weight: .semibold))
                                    .foregroundColor(XiangqiTheme.ink)
                                if let subtitle = r.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(XiangqiTheme.sub)
                                }
                            }
                            Spacer()
                            if let value = r.value {
                                Text(value)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(XiangqiTheme.sub)
                            }
                            if r.showChevron {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13))
                                    .foregroundColor(XiangqiTheme.faint)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    .disabled(r.action == nil)
                    if i < rows.count - 1 {
                        Divider().overlay(XiangqiTheme.hair).padding(.leading, 61)
                    }
                }
            }
            .xqCard()
        }
        .padding(.bottom, 20)
    }
}
#endif
