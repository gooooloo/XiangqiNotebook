#if os(iOS)
import SwiftUI

/// 「练习」标签首页/答题/完成三态。
struct iPhonePracticeView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var route: PracticeRoute

    private enum ViewState { case home, session, mistakes }

    @State private var view: ViewState = .home
    @State private var frozenCandidates: [(moveString: String, move: Move)] = []
    @State private var answered = false
    @State private var correctMove: Move?
    @State private var wrongMove: Move?
    @State private var mistakeCount = 0
    @State private var stepsPlayed = 0

    var body: some View {
        ScrollView {
            switch view {
            case .home: homeBody
            case .session: sessionBody
            case .mistakes:
                iPhoneMistakeListView(viewModel: viewModel, onBack: { view = .home })
            }
        }
        .background(XiangqiTheme.bg.ignoresSafeArea())
        .onChange(of: route) { _, newValue in applyRoute(newValue) }
        .onAppear { applyRoute(route) }
    }

    private func applyRoute(_ r: PracticeRoute) {
        guard r == .mistakes else { return }
        view = .mistakes
        route = .home
    }

    // MARK: - 首页

    private var homeBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("练习")
                    .font(XiangqiTheme.XFont.serif(26, weight: .black))
                    .foregroundColor(XiangqiTheme.ink)
                Text("走对每一手，把记忆变成本能")
                    .font(.system(size: 13))
                    .foregroundColor(XiangqiTheme.sub)
            }

            if viewModel.isInFocusedPractice {
                continueCard
            }

            HStack(spacing: 12) {
                homeCard(title: "随机测验", subtitle: "从当前局面出发答题", cta: "开始") { startSession() }
                homeCard(title: "错题重练", subtitle: "只练你走错的局面", cta: "查看", accent: XiangqiTheme.accent2) { view = .mistakes }
            }

            Button(action: { view = .mistakes }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("错误统计")
                            .font(XiangqiTheme.XFont.sans(16.5, weight: .bold))
                            .foregroundColor(XiangqiTheme.ink)
                        Text("查看你最常走错的局面与趋势")
                            .font(.system(size: 12.5))
                            .foregroundColor(XiangqiTheme.sub)
                    }
                    Spacer()
                    Text("查看统计 →")
                        .font(XiangqiTheme.XFont.sans(13.5, weight: .bold))
                        .foregroundColor(XiangqiTheme.sub)
                }
                .padding(16)
                .xqCard()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }

    private var continueCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: 0xB4231F), Color(hex: 0x8F1A17)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color.white.opacity(0.06)).frame(width: 140, height: 140).offset(x: 60, y: -60)
            VStack(alignment: .leading, spacing: 6) {
                Text("继续练习")
                    .font(XiangqiTheme.XFont.sans(12.5, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.85))
                Text(viewModel.lastSpecificGameName ?? "专项练习")
                    .font(XiangqiTheme.XFont.serif(20, weight: .heavy))
                    .foregroundColor(.white)
                Text("第 \(viewModel.currentGameStepDisplay) / \(viewModel.maxGameStepDisplay) 手")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                Button(action: { startSession() }) {
                    Text("继续练习")
                        .font(XiangqiTheme.XFont.sans(15.5, weight: .heavy))
                        .foregroundColor(XiangqiTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 11))
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card + 4))
        .shadow(color: Color(hex: 0x78281B, alpha: 0.35), radius: 16, x: 0, y: 10)
    }

    private func homeCard(title: String, subtitle: String, cta: String, accent: Color = XiangqiTheme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(XiangqiTheme.XFont.serif(16.5, weight: .bold))
                    .foregroundColor(XiangqiTheme.ink)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundColor(XiangqiTheme.sub)
                Text("\(cta) →")
                    .font(XiangqiTheme.XFont.sans(13.5, weight: .bold))
                    .foregroundColor(accent)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .xqCard()
        }
    }

    private func startSession() {
        stepsPlayed = 0
        mistakeCount = 0
        loadQuestion()
        view = .session
    }

    // MARK: - 答题

    /// 出题时把候选着法冻结下来，避免答对后 `playNextMove` 改变当前局面导致列表提前刷新
    private func loadQuestion() {
        frozenCandidates = viewModel.currentNextMovesListDisplay
        answered = false
        correctMove = nil
        wrongMove = nil
    }

    private var sessionBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: { view = .home }) {
                    Text("‹").font(.system(size: 22)).foregroundColor(XiangqiTheme.accent)
                }
                Text("练习")
                    .font(XiangqiTheme.XFont.sans(18, weight: .bold))
                    .foregroundColor(XiangqiTheme.ink)
                Spacer()
                Text("第 \(stepsPlayed + 1) 手")
                    .font(XiangqiTheme.XFont.sans(12.5, weight: .semibold))
                    .foregroundColor(XiangqiTheme.sub)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(XiangqiTheme.inset, in: Capsule())
                Text("错 \(mistakeCount)")
                    .font(XiangqiTheme.XFont.sans(12.5, weight: .semibold))
                    .foregroundColor(XiangqiTheme.bad)
                    .opacity(mistakeCount > 0 ? 1 : 0.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(XiangqiTheme.bad.opacity(0.09), in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)

            if frozenCandidates.isEmpty {
                sessionCompleteBody
            } else {
                HStack {
                    Spacer()
                    XiangqiBoard(viewModel: $viewModel.boardViewModel)
                        .frame(width: 320, height: 320)
                        .padding(5)
                        .background(XiangqiTheme.panel)
                        .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card + 2).stroke(answered ? XiangqiTheme.good : XiangqiTheme.line, lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card + 2))
                    Spacer()
                }
                .padding(.top, 2)

                HStack(spacing: 8) {
                    Text(viewModel.isRedTurn ? "红方走子" : "黑方走子")
                        .font(XiangqiTheme.XFont.sans(12.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: 6))
                    Text("选出这一步最合适的走法")
                        .font(XiangqiTheme.XFont.sans(16, weight: .bold))
                        .foregroundColor(XiangqiTheme.ink)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)

                if answered || wrongMove != nil {
                    feedbackBanner
                }

                VStack(spacing: 9) {
                    ForEach(frozenCandidates, id: \.move) { item in
                        candidateButton(item)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                if answered {
                    Button(action: nextStep) {
                        Text("下一手 →")
                            .font(XiangqiTheme.XFont.sans(16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if answered {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 14))
                Text("正确！")
                    .font(XiangqiTheme.XFont.sans(13.5, weight: .heavy))
            }
            .foregroundColor(XiangqiTheme.good)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(XiangqiTheme.good.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 18)
            .padding(.top, 12)
        } else if let wrong = wrongMove {
            VStack(alignment: .leading, spacing: 4) {
                Text("『\(viewModel.getMoveString(move: wrong))』不是最佳")
                    .font(XiangqiTheme.XFont.sans(13.5, weight: .heavy))
                    .foregroundColor(XiangqiTheme.bad)
                if let reason = wrong.badReason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 12.5))
                        .foregroundColor(XiangqiTheme.sub)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(hex: 0xFDF2F3))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(XiangqiTheme.bad.opacity(0.25), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
    }

    private func candidateButton(_ item: (moveString: String, move: Move)) -> some View {
        let isWrongPick = wrongMove == item.move
        let isRightPick = answered && correctMove == item.move
        var bg = XiangqiTheme.card
        var border = XiangqiTheme.line
        var fg = XiangqiTheme.ink
        if isWrongPick { bg = XiangqiTheme.bad.opacity(0.08); border = XiangqiTheme.bad; fg = XiangqiTheme.bad }
        if isRightPick { bg = XiangqiTheme.good.opacity(0.1); border = XiangqiTheme.good; fg = XiangqiTheme.good }

        return Button(action: { pick(item) }) {
            HStack {
                Text(viewModel.getMoveString(move: item.move))
                    .font(XiangqiTheme.XFont.serif(17.5, weight: .bold))
                Spacer()
                if isRightPick { Image(systemName: "checkmark") }
                if isWrongPick { Image(systemName: "xmark") }
            }
            .foregroundColor(fg)
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card).stroke(border, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
        }
        .disabled(answered)
    }

    private func pick(_ item: (moveString: String, move: Move)) {
        guard !answered else { return }
        if viewModel.isBadMove(item.move) {
            wrongMove = item.move
            mistakeCount += 1
            viewModel.recordPracticeMistake(wrongMove: item.move)
        } else {
            wrongMove = nil
            correctMove = item.move
            answered = true
        }
    }

    /// 答对后才真正落子推进局面，避免棋盘提前刷新导致候选列表与反馈不一致
    private func nextStep() {
        if let correctMove {
            viewModel.playNextMove(correctMove)
        }
        stepsPlayed += 1
        loadQuestion()
    }

    private var sessionCompleteBody: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(XiangqiTheme.good.opacity(0.12))
                .frame(width: 92, height: 92)
                .overlay(Image(systemName: "checkmark").font(.system(size: 40)).foregroundColor(XiangqiTheme.good))
                .padding(.top, 40)
            Text("本局练习完成")
                .font(XiangqiTheme.XFont.serif(25, weight: .black))
                .foregroundColor(XiangqiTheme.ink)
                .padding(.top, 18)

            HStack(spacing: 26) {
                statItem(value: "\(stepsPlayed)", label: "手")
                statItem(value: "\(stepsPlayed > 0 ? max(0, 100 - mistakeCount * 100 / max(stepsPlayed, 1)) : 100)%", label: "正确率")
                statItem(value: "\(mistakeCount)", label: "错手")
            }
            .padding(.top, 22)

            VStack(spacing: 10) {
                Button(action: startSession) {
                    Text("再练一局")
                        .font(XiangqiTheme.XFont.sans(16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
                Button(action: { view = .home }) {
                    Text("返回练习首页")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(XiangqiTheme.sub)
                }
                .padding(.top, 4)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 30)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(XiangqiTheme.XFont.serif(29, weight: .black))
                .foregroundColor(XiangqiTheme.ink)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(XiangqiTheme.sub)
        }
    }
}
#endif
