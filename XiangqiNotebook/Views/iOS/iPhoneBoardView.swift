#if os(iOS)
import SwiftUI

/// 「棋盘」标签：沉浸式分析页（detail 页）。进入时隐藏底部标签栏；
/// 固定头（返回/走子方/⋯）+ 固定棋盘（近满宽，四周靠发丝线卡片界定边界，不靠底色对比、不加阴影/描边）
/// + 可滚动分析区 + 固定底部走子条。页面底色与其余标签页统一为暖米 `XiangqiTheme.bg`。
/// 卡片文字一律常规字重，靠深墨/浅灰颜色分主次；全屏唯一强调色是「更多」蓝按钮。
struct iPhoneBoardView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedTab: IPhoneTab
    @Binding var practiceRoute: PracticeRoute
    let prevTab: IPhoneTab
    @State private var didApplyDefaultToggles = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            // VStack 里棋盘和下面的 ScrollView 都是弹性子视图，不设优先级的话
            // 高度会被两者对半分掉，棋盘因此被"高度"卡住而不是撑满宽度。
            // 用 layoutPriority 让棋盘先按自身宽度确定理想的正方形尺寸，
            // 剩余高度再全部留给 ScrollView。
            boardBlock
                .layoutPriority(1)
            ScrollView {
                VStack(spacing: 10) {
                    analysisCard
                    metaCard
                    actionGrid
                }
                .padding(.top, 10)
            }
            navBar
        }
        .background(XiangqiTheme.bg.ignoresSafeArea())
        .onAppear {
            // 分析页默认关闭路径/下一步/来源招法箭头叠加：棋子多的局面全是箭头太乱，
            // 保留在「更多」里可手动开；只在本页首次出现时纠正一次，不会覆盖用户之后的手动选择。
            guard !didApplyDefaultToggles else { return }
            didApplyDefaultToggles = true
            if viewModel.showPath { viewModel.toggleShowPath() }
            if viewModel.showAllNextMoves { viewModel.toggleShowAllNextMoves() }
            if viewModel.showLastMove { viewModel.toggleShowLastMove() }
        }
        .sheet(isPresented: $viewModel.showIOSMoreActionsView) {
            iPhoneBoardActionsSheet(viewModel: viewModel, selectedTab: $selectedTab, practiceRoute: $practiceRoute)
        }
        .sheet(isPresented: $viewModel.showEditCommentIOS) {
            iPhoneEditCommentView(viewModel: viewModel)
        }
    }

    // MARK: - 固定顶栏

    private var topBar: some View {
        HStack(spacing: 6) {
            Button(action: { selectedTab = prevTab }) {
                Text("‹ 返回")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundColor(XiangqiTheme.blue)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isRedTurn ? Color(hex: 0xA15750) : Color(hex: 0x3A3A3D))
                    .frame(width: 9, height: 9)
                Text((viewModel.isRedTurn ? "红方" : "黑方") + "走子")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(XiangqiTheme.ink)
                Text("· 第 \(viewModel.currentGameStepDisplay)/\(viewModel.maxGameStepDisplay) 手")
                    .font(.system(size: 12))
                    .foregroundColor(XiangqiTheme.sub)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: { viewModel.showIOSMoreActionsView = true }) {
                Text("⋯")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(XiangqiTheme.ink)
                    .frame(width: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(XiangqiTheme.bg)
        .overlay(Divider().overlay(XiangqiTheme.hair), alignment: .bottom)
    }

    // MARK: - 固定棋盘（不滚动，满宽，靠下方卡片的发丝线边界，不加阴影/描边）

    private var boardBlock: some View {
        // 边长≈屏宽：不用固定尺寸（不同设备宽度不同，固定值无法保证"全屏最宽元素"），
        // 让 XiangqiBoard 用 aspectRatio 撑满可用宽度，只留 2pt 安全区级别的细边，
        // 比下方分析卡/数据卡的 14pt 边距更宽，天然成为全屏最宽的元素。
        XiangqiBoard(viewModel: $viewModel.boardViewModel, onMove: { newFen in
            viewModel.handleBoardMove(newFen)
        })
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 2)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    // MARK: - 分析卡：分数行 + 评论

    private var analysisCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                scoreCell(label: "云库", value: viewModel.displayScore)
                scoreCell(label: "快估", value: viewModel.displayQuickEngineScore)
                scoreCell(label: "深评", value: viewModel.displayDeepEngineScore)
            }
            .padding(.vertical, 9)

            Divider().overlay(XiangqiTheme.hair)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("评论")
                        .font(.system(size: 11.5))
                        .tracking(0.6)
                        .foregroundColor(XiangqiTheme.sub)
                    Spacer()
                    Button(action: { viewModel.showEditCommentIOS = true }) {
                        Text((viewModel.currentCombinedComment?.isEmpty == false) ? "编辑" : "＋ 添加")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(XiangqiTheme.sub)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if let comment = viewModel.currentCombinedComment, !comment.isEmpty {
                    HStack(alignment: .top, spacing: 11) {
                        Rectangle()
                            .fill(Color(hex: 0xC9B79A))
                            .frame(width: 3)
                        Text(comment)
                            .font(.system(size: 14))
                            .foregroundColor(XiangqiTheme.ink)
                            .lineSpacing(6)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 5)
                    .padding(.bottom, 12)
                } else {
                    Text("此局面暂无评论")
                        .font(.system(size: 12.5))
                        .foregroundColor(XiangqiTheme.faint)
                        .padding(.horizontal, 14)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                }
            }
        }
        .background(XiangqiTheme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(XiangqiTheme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
    }

    private func scoreCell(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(XiangqiTheme.sub)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(XiangqiTheme.ink)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 参考数据卡：战绩 + 3x2 网格

    private var metaCard: some View {
        VStack(spacing: 0) {
            recordSection
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider().overlay(XiangqiTheme.hair)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 8) {
                metaKV("数据", "\(viewModel.currentDataVersion)")
                metaKV("练习", "\(viewModel.currentFenPracticeCount) 次")
                metaKV("本变", "\(viewModel.currentVariationIndex + 1)/\(viewModel.totalVariationsCount)")
                metaKV("红库", viewModel.currentFenIsInRedOpening ? "是" : "否")
                metaKV("黑库", viewModel.currentFenIsInBlackOpening ? "是" : "否")
                metaKV("锁定", viewModel.isAnyMoveLocked ? "是" : "否")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(XiangqiTheme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(XiangqiTheme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 14)
    }

    /// 自适应密度：双方胜/和/负都 ＜100 时一行两栏并排；只要任一 ≥100（真机常态）
    /// 就拆成执红/执黑各一行——三位数战绩挤在一行会挤压/换行错位，拆行后每行仍是
    /// 完整「标签+局数+胜/和/负」，一律左对齐（不用 flex 推到最右，避免中间留大片空白）。
    private var recordUsesTwoRows: Bool {
        [viewModel.currentFenInRealRedGameWinCount, viewModel.currentFenInRealRedGameDrawCount, viewModel.currentFenInRealRedGameLossCount,
         viewModel.currentFenInRealBlackGameWinCount, viewModel.currentFenInRealBlackGameDrawCount, viewModel.currentFenInRealBlackGameLossCount]
            .contains { $0 >= 100 }
    }

    @ViewBuilder
    private var recordSection: some View {
        Group {
            if recordUsesTwoRows {
                VStack(alignment: .leading, spacing: 6) {
                    redRecordLine
                    blackRecordLine
                }
            } else {
                HStack(spacing: 20) {
                    redRecordLine
                    blackRecordLine
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var redRecordLine: some View {
        recordLine(label: "执红",
                   total: viewModel.currentFenInRealRedGameTotalCount,
                   win: viewModel.currentFenInRealRedGameWinCount,
                   draw: viewModel.currentFenInRealRedGameDrawCount,
                   loss: viewModel.currentFenInRealRedGameLossCount)
    }

    private var blackRecordLine: some View {
        recordLine(label: "执黑",
                   total: viewModel.currentFenInRealBlackGameTotalCount,
                   win: viewModel.currentFenInRealBlackGameWinCount,
                   draw: viewModel.currentFenInRealBlackGameDrawCount,
                   loss: viewModel.currentFenInRealBlackGameLossCount)
    }

    private func recordLine(label: String, total: Int, win: Int, draw: Int, loss: Int) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(XiangqiTheme.ink)
            recordUnit(total, "局")
            recordUnit(win, "胜")
            recordUnit(draw, "和")
            recordUnit(loss, "负")
        }
        .fixedSize()
        .lineLimit(1)
    }

    private func recordUnit(_ value: Int, _ unit: String) -> some View {
        HStack(spacing: 1) {
            Text("\(value)").font(.system(size: 12)).foregroundColor(XiangqiTheme.ink)
            Text(unit).font(.system(size: 12)).foregroundColor(XiangqiTheme.sub)
        }
    }

    private func metaKV(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 12)).foregroundColor(XiangqiTheme.sub)
            Text(value).font(.system(size: 12)).foregroundColor(XiangqiTheme.ink)
        }
    }

    // MARK: - 操作按钮：4 列 x 2 行

    private var actionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            actionButton("翻转棋盘") { viewModel.flipOrientation() }
            actionButton("记录变招") { viewModel.toggleAllowAddingNewMoves() }
            actionButton("云库查分") { Task { await viewModel.queryFenScore() } }
            actionButton("加入复习") { viewModel.actionDefinitions.getActionInfo(.addToReview)?.action() }
            actionButton("书签") {
                if viewModel.isBookmarked { _ = viewModel.removeBookmark() } else { viewModel.showingBookmarkAlert = true }
            }
            actionButton("练习本局") { viewModel.startFocusedPractice() }
            actionButton("保存") { viewModel.actionDefinitions.getActionInfo(.save)?.action() }
            actionButton("更多", accent: true) { viewModel.showIOSMoreActionsView = true }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private func actionButton(_ label: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(accent ? .white : XiangqiTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(accent ? XiangqiTheme.blue : XiangqiTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent ? Color.clear : XiangqiTheme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - 固定底部走子条

    private var navBar: some View {
        let step = viewModel.currentGameStepDisplay
        let total = viewModel.maxGameStepDisplay
        return HStack(spacing: 8) {
            navCell("开局", disabled: step == 0) { viewModel.actionDefinitions.getActionInfo(.toStart)?.action() }
            navCell("上一步", disabled: step == 0, primary: true) { viewModel.actionDefinitions.getActionInfo(.stepBack)?.action() }
            navCell("下一步", disabled: step == total, primary: true) { viewModel.actionDefinitions.getActionInfo(.stepForward)?.action() }
            navCell("下一变", disabled: viewModel.totalVariationsCount <= 1) { viewModel.actionDefinitions.getActionInfo(.nextVariant)?.action() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 22)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(XiangqiTheme.boardNavBarMaterial)
            }
        )
        .overlay(Divider().overlay(XiangqiTheme.line), alignment: .top)
    }

    private func navCell(_ label: String, disabled: Bool, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundColor(disabled ? XiangqiTheme.faint : XiangqiTheme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(disabled ? Color.clear : (primary ? XiangqiTheme.card : XiangqiTheme.inset))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(disabled ? Color.clear : (primary ? XiangqiTheme.line : Color.clear), lineWidth: 1)
                )
                .shadow(color: (primary && !disabled) ? .black.opacity(0.06) : .clear, radius: 2, x: 0, y: 1)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(disabled)
    }
}
#endif
