#if os(iOS)
import SwiftUI

/// 「更多」Sheet（棋盘分析页顶栏 ⋯，长尾操作总入口）。
/// 已与棋盘主界面去重：翻转棋盘/云库查分/加入复习/书签/编辑评论等主界面已有的操作不在此重复。
struct iPhoneBoardActionsSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedTab: IPhoneTab
    @Binding var practiceRoute: PracticeRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        iPhoneSheetShell(title: "更多") {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("应用模式")
                modeSegment
                    .padding(.bottom, 16)

                sectionLabel("棋局筛选")
                    .padding(.top, 4)
                chipsRow(filterChips)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                sectionLabel("开局库 / 书签")
                chipsRow(openingChips)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                sectionLabel("棋盘操作")
                chipsRow(boardToggleChips)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                sectionLabel("操作")
                actionGrid
                    .padding(.top, 8)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(XiangqiTheme.XFont.sans(11.5, weight: .bold))
            .tracking(1.5)
            .foregroundColor(XiangqiTheme.faint)
    }

    // MARK: - 应用模式（单选）

    private var modeSegment: some View {
        HStack(spacing: 2) {
            modeButton("常规", on: viewModel.currentAppMode == .normal) { viewModel.setMode(.normal); dismiss() }
            modeButton("练习", on: viewModel.currentAppMode == .practice) { viewModel.setMode(.practice); selectedTab = .practice; dismiss() }
            modeButton("复习", on: viewModel.currentAppMode == .review) { viewModel.setMode(.review); selectedTab = .review; dismiss() }
        }
    }

    private func modeButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(XiangqiTheme.XFont.sans(14, weight: on ? .bold : .regular))
                .foregroundColor(on ? .white : XiangqiTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(on ? XiangqiTheme.blue : XiangqiTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Color.clear : XiangqiTheme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }

    // MARK: - 棋局筛选 / 开局库 / 棋盘操作（多选 chips，均为已有 ToggleAction）

    private struct Chip: Identifiable {
        let id: ActionDefinitions.ActionKey
        let label: String
    }

    private var filterChips: [Chip] {
        [
            .init(id: .setFilterNone, label: "不筛选"),
            .init(id: .toggleFilterRedOpeningOnly, label: "只筛选红方开局"),
            .init(id: .toggleFilterBlackOpeningOnly, label: "只筛选黑方开局"),
            .init(id: .toggleFilterRedRealGameOnly, label: "只筛选红方实战"),
            .init(id: .toggleFilterBlackRealGameOnly, label: "只筛选黑方实战"),
            .init(id: .toggleFilterSpecificGame, label: "只筛选特定棋局"),
            .init(id: .toggleFilterSpecificBook, label: "只筛选特定棋书"),
            .init(id: .toggleStepLimitation, label: "步数限制"),
            .init(id: .toggleLock, label: "锁定"),
        ]
    }

    private var openingChips: [Chip] {
        [
            .init(id: .inRedOpening, label: "列入红方开局库"),
            .init(id: .inBlackOpening, label: "列入黑方开局库"),
        ]
    }

    private var boardToggleChips: [Chip] {
        [
            .init(id: .flip, label: "黑方视角"),
            .init(id: .toggleAutoExtendGameWhenPlayingBoardFen, label: "自动往后拓展"),
            .init(id: .toggleCanNavigateBeforeLockedStep, label: "锁定区可前进后退"),
            .init(id: .toggleShowPath, label: "显示路径"),
            .init(id: .toggleShowAllNextMoves, label: "显示所有下一步"),
            .init(id: .toggleShowLastMove, label: "显示来源招法"),
            .init(id: .toggleShowRealGameList, label: "显示实战列表"),
            .init(id: .toggleAllowAddingNewMoves, label: "允许增加新走法"),
        ]
    }

    private func chipsRow(_ chips: [Chip]) -> some View {
        FlowLayout(items: chips) { chip in
            let info = viewModel.actionDefinitions.getToggleActionInfo(chip.id)
            let on = info?.isOn() ?? false
            Button(action: { info?.action(!on) }) {
                Text(chip.label)
                    .font(.system(size: 12.5, weight: on ? .semibold : .medium))
                    .foregroundColor(on ? .white : XiangqiTheme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(on ? XiangqiTheme.blue : XiangqiTheme.card)
                    .overlay(Capsule().stroke(on ? Color.clear : XiangqiTheme.line, lineWidth: 1))
                    .clipShape(Capsule())
            }
            .disabled(info == nil || !(info?.isEnabled() ?? true))
        }
    }

    // MARK: - 操作（按钮网格）

    private struct ActionItem: Identifiable {
        let id = UUID()
        let label: String
        let danger: Bool
        let action: () -> Void
    }

    private var actionItems: [ActionItem] {
        [
            ActionItem(label: "打开云库", danger: false) { viewModel.actionDefinitions.getActionInfo(.openYunku)?.action() },
            ActionItem(label: "终局", danger: false) { viewModel.actionDefinitions.getActionInfo(.toEnd)?.action() },
            ActionItem(label: "更新数据", danger: false) { viewModel.actionDefinitions.getActionInfo(.checkDataVersion)?.action() },
            ActionItem(label: "上局", danger: false) { viewModel.actionDefinitions.getActionInfo(.previousPath)?.action() },
            ActionItem(label: "下局", danger: false) { viewModel.actionDefinitions.getActionInfo(.nextPath)?.action() },
            ActionItem(label: "随机一局", danger: false) { viewModel.actionDefinitions.getActionInfo(.random)?.action() },
            ActionItem(label: "随机走子", danger: false) { viewModel.actionDefinitions.getActionInfo(.playRandomNextMove)?.action() },
            ActionItem(label: "标记路径", danger: false) { viewModel.actionDefinitions.getActionInfo(.markPath)?.action() },
            ActionItem(label: "参考棋谱", danger: false) { viewModel.actionDefinitions.getActionInfo(.referenceBoard)?.action() },
            ActionItem(label: "录入棋局", danger: false) { viewModel.actionDefinitions.getActionInfo(.inputGame)?.action() },
            ActionItem(label: "修复", danger: false) { viewModel.actionDefinitions.getActionInfo(.fix)?.action() },
            ActionItem(label: "删招", danger: true) { viewModel.actionDefinitions.getActionInfo(.deleteMove)?.action() },
            ActionItem(label: "删分", danger: true) { viewModel.actionDefinitions.getActionInfo(.deleteScore)?.action() },
            ActionItem(label: "从局中删除此招", danger: true) { viewModel.actionDefinitions.getActionInfo(.removeMoveFromGame)?.action() },
            ActionItem(label: "复习库", danger: false) { selectedTab = .review; dismiss() },
            ActionItem(label: "实战", danger: false) { selectedTab = .library; dismiss() },
            ActionItem(label: "快捷键统计", danger: false) { viewModel.showingShortcutUsageStatsView = true },
            ActionItem(label: "练习错误统计", danger: false) {
                practiceRoute = .mistakes
                selectedTab = .practice
                dismiss()
            },
        ]
    }

    private var actionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(actionItems) { item in
                Button(action: item.action) {
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(item.danger ? XiangqiTheme.bad : XiangqiTheme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 10)
                        .background(XiangqiTheme.card)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(XiangqiTheme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

/// Sheet 外壳：磨砂遮罩 + 顶部抓手条 + 标题行，统一各 Sheet 用。
struct iPhoneSheetShell<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(XiangqiTheme.line)
                .frame(width: 38, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)
            HStack {
                Text(title)
                    .font(XiangqiTheme.XFont.sans(18, weight: .heavy))
                    .foregroundColor(XiangqiTheme.ink)
                Spacer()
                Button(action: { dismiss() }) {
                    Text("✕")
                        .font(.system(size: 15))
                        .foregroundColor(XiangqiTheme.sub)
                        .frame(width: 30, height: 30)
                        .xqInset(radius: 15)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
            }
        }
        .background(XiangqiTheme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
#endif
