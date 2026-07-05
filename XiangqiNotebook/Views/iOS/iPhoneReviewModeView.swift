#if os(iOS)
import SwiftUI

/// 「复习」标签：间隔重复答题流程，内联渲染（不再是 sheet）。
struct iPhoneReviewModeView: View {
    @ObservedObject var viewModel: ViewModel
    @State private var revealed = false
    @State private var showLibrary = false

    var body: some View {
        ScrollView {
            Group {
                if viewModel.isInVerificationMode {
                    verificationBody
                } else if viewModel.isReviewingInProgress {
                    inProgressBody
                } else if viewModel.isReviewComplete {
                    completeBody
                } else {
                    idleBody
                }
            }
        }
        .background(XiangqiTheme.bg.ignoresSafeArea())
        .onChange(of: viewModel.currentReviewIndex) { _, _ in revealed = false }
        .sheet(isPresented: $showLibrary) {
            iPhoneReviewListView(viewModel: viewModel, isPresented: $showLibrary)
        }
    }

    // MARK: - 复习进行中

    private var currentItem: (fenId: Int, srsData: SRSData)? { viewModel.currentReviewItem }

    private var answerCandidate: (moveString: String, move: Move)? {
        let items = viewModel.currentNextMovesListDisplay
        return items.first(where: { viewModel.isRecommendedMove($0.move) }) ?? items.first
    }

    private var inProgressBody: some View {
        VStack(spacing: 0) {
            header(title: "复习", subtitle: "间隔重复 · 巩固你记下的每一手")
            board(size: revealed ? 250 : 358)
                .padding(.top, 2)

            if !revealed {
                promptCard
                Button(action: revealAnswer) {
                    Text("揭晓答案")
                        .font(XiangqiTheme.XFont.sans(16.5, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            } else {
                answerCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeOut(duration: 0.34), value: revealed)
            }
        }
        .padding(.bottom, 20)
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(XiangqiTheme.XFont.serif(22, weight: .black))
                    .foregroundColor(XiangqiTheme.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(XiangqiTheme.sub)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(XiangqiTheme.accent).frame(width: 6, height: 6)
                Text(viewModel.reviewProgress)
                    .font(XiangqiTheme.XFont.sans(12.5, weight: .bold))
            }
            .foregroundColor(XiangqiTheme.sub)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(XiangqiTheme.inset, in: Capsule())

            Button(action: enterVerification) {
                Text("检验")
                    .font(XiangqiTheme.XFont.sans(12, weight: .semibold))
                    .foregroundColor(XiangqiTheme.sub)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(XiangqiTheme.card, in: Capsule())
                    .overlay(Capsule().stroke(XiangqiTheme.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func board(size: CGFloat) -> some View {
        HStack {
            Spacer()
            XiangqiBoard(viewModel: $viewModel.boardViewModel)
                .frame(width: size, height: size)
                .padding(5)
                .background(XiangqiTheme.panel)
                .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card + 2).stroke(XiangqiTheme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card + 2))
            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: size)
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let item = currentItem {
                Text(viewModel.reviewItemDescription(fenId: item.fenId))
                    .font(.system(size: 12.5))
                    .foregroundColor(XiangqiTheme.sub)
            }
            HStack(spacing: 8) {
                Text(viewModel.isRedTurn ? "红方先行" : "黑方先行")
                    .font(XiangqiTheme.XFont.sans(12.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: 6))
                Text("回忆此局面的走法")
                    .font(XiangqiTheme.XFont.sans(16.5, weight: .bold))
                    .foregroundColor(XiangqiTheme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .xqCard()
        .padding(.horizontal, 18)
    }

    private func revealAnswer() {
        if let answer = answerCandidate {
            viewModel.playNextMove(answer.move)
        }
        revealed = true
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("正确着法")
                        .font(.system(size: 12.5))
                        .foregroundColor(XiangqiTheme.sub)
                    Text(answerCandidate.map { viewModel.getMoveString(move: $0.move) } ?? "—")
                        .font(XiangqiTheme.XFont.serif(32, weight: .black))
                        .foregroundColor(XiangqiTheme.ink)
                }
                Spacer()
                if let answer = answerCandidate, viewModel.isRecommendedMove(answer.move) {
                    Text("★ 好棋")
                        .font(XiangqiTheme.XFont.sans(13.5, weight: .heavy))
                        .foregroundColor(XiangqiTheme.good)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(XiangqiTheme.good.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if let note = viewModel.currentFenComment, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundColor(XiangqiTheme.sub)
                    .lineSpacing(5)
                    .padding(.top, 9)
            }
            Divider().overlay(XiangqiTheme.line).padding(.vertical, 14)

            Text("这一步你记得多牢？")
                .font(XiangqiTheme.XFont.sans(12, weight: .bold))
                .tracking(0.6)
                .foregroundColor(XiangqiTheme.faint)
                .padding(.bottom, 9)

            iPhoneReviewRatingGrid(viewModel: viewModel)
        }
        .padding(17)
        .xqCard(radius: XiangqiTheme.Radius.card + 2)
        .padding(.horizontal, 18)
    }

    private func enterVerification() {
        guard let item = currentItem, let gamePath = item.srsData.gamePath else { return }
        viewModel.enterVerificationMode(fenId: item.fenId, srsData: item.srsData, gamePath: gamePath)
    }

    // MARK: - 检验模式

    private var verificationBody: some View {
        VStack(spacing: 0) {
            header(title: "检验模式", subtitle: "在棋盘上走出你认为的正确一手")
            board(size: 300)
            if let item = viewModel.verificationItem {
                Text(viewModel.reviewItemDescription(fenId: item.fenId))
                    .font(.system(size: 13))
                    .foregroundColor(XiangqiTheme.sub)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
            }
            Text("这一步你记得多牢？")
                .font(XiangqiTheme.XFont.sans(12, weight: .bold))
                .tracking(0.6)
                .foregroundColor(XiangqiTheme.faint)
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            iPhoneReviewRatingGrid(viewModel: viewModel)
                .padding(.horizontal, 18)
            Button(action: { viewModel.exitVerificationMode() }) {
                Text("隐藏答案")
                    .font(XiangqiTheme.XFont.sans(14, weight: .semibold))
                    .foregroundColor(XiangqiTheme.sub)
            }
            .padding(.top, 14)
        }
        .padding(.bottom, 20)
    }

    // MARK: - 本轮完成

    private var completeBody: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(XiangqiTheme.accent.opacity(0.35), lineWidth: 2)
                    .frame(width: 118, height: 118)
                RoundedRectangle(cornerRadius: 14)
                    .fill(XiangqiTheme.accent)
                    .frame(width: 100, height: 100)
                    .overlay(
                        Text("畢")
                            .font(XiangqiTheme.XFont.serif(38, weight: .black))
                            .foregroundColor(.white)
                    )
                    .shadow(color: XiangqiTheme.accent.opacity(0.5), radius: 14, x: 0, y: 8)
            }
            .padding(.top, 40)

            Text("本轮复习完成")
                .font(XiangqiTheme.XFont.serif(27, weight: .black))
                .foregroundColor(XiangqiTheme.ink)
                .padding(.top, 10)
            Text("所有到期局面都已巩固，明天还有新的等你。")
                .font(.system(size: 14))
                .foregroundColor(XiangqiTheme.sub)
                .multilineTextAlignment(.center)

            HStack(spacing: 26) {
                statItem(value: "\(viewModel.reviewQueue.count)", label: "已复习")
            }
            .padding(.top, 20)

            VStack(spacing: 10) {
                Button(action: { viewModel.exitReviewMode() }) {
                    Text("退出复习模式")
                        .font(XiangqiTheme.XFont.sans(16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
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

    // MARK: - 空态 / 未开始

    private var idleBody: some View {
        VStack(spacing: 14) {
            Text(viewModel.dueReviewItemsCount > 0 ? "有 \(viewModel.dueReviewItemsCount) 个局面到期" : "暂无到期复习项")
                .font(XiangqiTheme.XFont.serif(20, weight: .bold))
                .foregroundColor(XiangqiTheme.ink)
                .padding(.top, 60)
            if viewModel.dueReviewItemsCount > 0 {
                Button(action: { viewModel.setMode(.review) }) {
                    Text("开始复习")
                        .font(XiangqiTheme.XFont.sans(16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 13)
                        .background(XiangqiTheme.accent, in: RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                }
            }
            Button(action: { showLibrary = true }) {
                Text("查看复习库")
                    .font(.system(size: 14))
                    .foregroundColor(XiangqiTheme.sub)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
    }
}

/// 复习四档自评：忘了/困难/良好/简单
struct iPhoneReviewRatingGrid: View {
    @ObservedObject var viewModel: ViewModel
    private let qualities: [ReviewQuality] = [.again, .hard, .good, .easy]

    private func color(_ q: ReviewQuality) -> Color {
        switch q {
        case .again: return XiangqiTheme.bad
        case .hard: return XiangqiTheme.hard
        case .good: return XiangqiTheme.fine
        case .easy: return XiangqiTheme.good
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(qualities, id: \.self) { q in
                Button(action: { viewModel.submitReviewRating(q) }) {
                    Text(q.displayLabel)
                        .font(XiangqiTheme.XFont.sans(14.5, weight: .heavy))
                        .foregroundColor(color(q))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(color(q).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}
#endif
