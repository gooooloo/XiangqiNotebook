#if os(iOS)
import SwiftUI

/// 「今日」首页：进 App 首屏，汇总到期复习、继续练习与快捷入口。
struct iPhoneHomeView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedTab: IPhoneTab
    @Binding var practiceRoute: PracticeRoute
    @Binding var showMore: Bool

    /// DateFormatter 创建成本高（要加载 locale），静态复用；本视图每次数据变化都会重算 body
    private static let greetingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter
    }()

    private var greetingDate: String {
        Self.greetingDateFormatter.string(from: Date())
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好，继续精进"
        case 12..<18: return "午后好，继续精进"
        default: return "晚上好，继续精进"
        }
    }

    private var hasFocusedPractice: Bool {
        viewModel.isInFocusedPractice
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greetingRow
                reviewHeroCard
                if hasFocusedPractice {
                    continuePracticeCard
                }
                statRow
                quickEntries
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(XiangqiTheme.bg.ignoresSafeArea())
    }

    private var greetingRow: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingDate)
                    .font(XiangqiTheme.XFont.sans(11.5, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(XiangqiTheme.faint)
                Text(greetingTitle)
                    .font(XiangqiTheme.XFont.serif(26, weight: .black))
                    .foregroundColor(XiangqiTheme.ink)
            }
            Spacer()
            Button(action: { showMore = true }) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(XiangqiTheme.accent)
                        .frame(width: 46, height: 46)
                        .overlay(
                            Text("帥")
                                .font(XiangqiTheme.XFont.serif(23, weight: .heavy))
                                .foregroundColor(.white)
                        )
                    Circle()
                        .fill(XiangqiTheme.frame)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("⋯")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        )
                        .overlay(Circle().stroke(XiangqiTheme.bg, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }
            }
        }
    }

    private var reviewHeroCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: 0xB4231F), Color(hex: 0x8F1A17)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 160, height: 160)
                .offset(x: 70, y: -80)
            Text("炮")
                .font(XiangqiTheme.XFont.serif(74, weight: .heavy))
                .foregroundColor(.white.opacity(0.09))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("今日复习")
                    .font(XiangqiTheme.XFont.sans(12.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.85))
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(viewModel.dueReviewItemsCount)")
                        .font(XiangqiTheme.XFont.serif(60, weight: .black))
                        .foregroundColor(.white)
                    Text("个局面到期")
                        .font(.system(size: 15.5))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text("间隔重复 · 保持你辛苦记下的每一手")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.82))

                Button(action: {
                    if viewModel.currentAppMode != .review { viewModel.setMode(.review) }
                    selectedTab = .review
                }) {
                    Text("开始复习")
                        .font(XiangqiTheme.XFont.sans(16, weight: .bold))
                        .foregroundColor(XiangqiTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 8)
            }
            .padding(22)
        }
        .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card + 4))
        .shadow(color: Color(hex: 0x78281B, alpha: 0.35), radius: 18, x: 0, y: 10)
    }

    private var continuePracticeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("继续练习")
                    .font(XiangqiTheme.XFont.sans(11.5, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(XiangqiTheme.faint)
                Spacer()
                Text("第 \(viewModel.currentGameStepDisplay) / \(viewModel.maxGameStepDisplay) 手")
                    .font(.system(size: 12.5))
                    .foregroundColor(XiangqiTheme.sub)
            }
            Text(viewModel.lastSpecificGameName ?? viewModel.lastSpecificBookName ?? "专项练习")
                .font(XiangqiTheme.XFont.serif(17.5, weight: .bold))
                .foregroundColor(XiangqiTheme.ink)

            GeometryReader { geo in
                let total = max(viewModel.maxGameStepDisplay, 1)
                let ratio = min(1, max(0, CGFloat(viewModel.currentGameStepDisplay) / CGFloat(total)))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(XiangqiTheme.inset)
                    RoundedRectangle(cornerRadius: 4).fill(XiangqiTheme.accent2)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 7)
            .padding(.top, 6)

            Button(action: {
                practiceRoute = .home
                selectedTab = .practice
            }) {
                Text("继续练习")
                    .font(XiangqiTheme.XFont.sans(15, weight: .bold))
                    .foregroundColor(XiangqiTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(XiangqiTheme.accent, lineWidth: 1.5)
                    )
            }
            .padding(.top, 8)
        }
        .padding(17)
        .xqCard()
    }

    private var statRow: some View {
        HStack(spacing: 10) {
            statTile(value: "\(viewModel.reviewItemList.count)", label: "复习库", color: XiangqiTheme.ink)
            statTile(value: "\(viewModel.dueReviewItemsCount)", label: "今日到期", color: XiangqiTheme.accent)
        }
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(XiangqiTheme.XFont.serif(24, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(XiangqiTheme.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .xqCard(radius: 12)
    }

    private var quickEntries: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("快捷入口")
                .font(XiangqiTheme.XFont.sans(11.5, weight: .bold))
                .tracking(1.5)
                .foregroundColor(XiangqiTheme.faint)

            HStack(spacing: 10) {
                quickEntry(icon: "☰", title: "棋谱库", subtitle: "课程 · 实战") { selectedTab = .library }
                quickEntry(icon: "◆", title: "最近棋谱", subtitle: viewModel.lastSpecificGameName ?? "继续上次") { selectedTab = .board }
            }
            HStack(spacing: 10) {
                quickEntry(icon: "△", title: "错误统计", subtitle: "最常走错的局面") {
                    practiceRoute = .mistakes
                    selectedTab = .practice
                }
                quickEntry(icon: "❖", title: "开局库", subtitle: "按体系浏览") { showMore = true }
            }
        }
    }

    private func quickEntry(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                Text(icon)
                    .font(XiangqiTheme.XFont.serif(17))
                    .foregroundColor(XiangqiTheme.accent)
                    .frame(width: 34, height: 34)
                    .xqInset(radius: 9)
                Text(title)
                    .font(XiangqiTheme.XFont.serif(15, weight: .bold))
                    .foregroundColor(XiangqiTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(XiangqiTheme.sub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .xqCard()
        }
    }
}
#endif
