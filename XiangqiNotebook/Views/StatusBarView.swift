import SwiftUI

/// 状态栏组件
///
/// 视觉改版：原先 3 个独立灰边框合并为一张圆角状态卡（`#FAFAFA` + 0.5px 细边），
/// 内部 3 行用细分隔线分隔；第 2、3 行的信息项两端均匀分布（space-between）铺满整行。
struct StatusBarView: View {
    @ObservedObject var viewModel: ViewModel

    // MARK: - 颜色

    /// 当前着法分数着色：坏棋红、荐着绿、其余主色
    private var currentScoreColor: Color {
        viewModel.isCurrentMoveBad ? Theme.bad : (viewModel.isCurrentMoveRecommended ? Theme.good : Theme.textPrimary)
    }

    // MARK: - 文本构件

    /// 信息项：次要色标签 + 主色（或着色）数值，等宽数字、单行。
    private func stat(_ label: String, _ value: Text) -> some View {
        (Text(label + " ")
            .font(.system(size: Theme.fs(11.5)))
            .foregroundColor(Theme.textSecondary)
            + value)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func value(_ string: String, color: Color = Theme.textPrimary) -> Text {
        Text(string)
            .font(.system(size: Theme.fs(11.5), weight: .semibold))
            .foregroundColor(color)
    }

    /// 引擎评分数值（带评估中 / 等待中状态）
    private func engineValue(idle: String) -> Text {
        value(idle, color: currentScoreColor)
    }

    private var quickEngineValue: Text {
        #if os(macOS)
        switch viewModel.currentFenQuickEvalStatus {
        case .evaluating: return value("评估中…", color: .orange)
        case .queued: return value("等待中…", color: Theme.textSecondary)
        case .idle: return engineValue(idle: viewModel.displayQuickEngineScore)
        }
        #else
        return engineValue(idle: viewModel.displayQuickEngineScore)
        #endif
    }

    private var deepEngineValue: Text {
        #if os(macOS)
        switch viewModel.currentFenDeepEvalStatus {
        case .evaluating: return value("评估中…", color: .orange)
        case .queued: return value("等待中…", color: Theme.textSecondary)
        case .idle: return engineValue(idle: viewModel.displayDeepEngineScore)
        }
        #else
        return engineValue(idle: viewModel.displayDeepEngineScore)
        #endif
    }

    /// 战绩：执红 / 执黑 一行，胜数用绿色，其余主色。
    private func gameStat(_ label: String, total: Int, wins: Int, draws: Int, losses: Int) -> some View {
        (Text(label + " ").font(.system(size: Theme.fs(11.5))).foregroundColor(Theme.textSecondary)
            + Text("总").font(.system(size: Theme.fs(11.5))).foregroundColor(Theme.textSecondary)
            + value("\(total)")
            + Text(" 胜").font(.system(size: Theme.fs(11.5))).foregroundColor(Theme.textSecondary)
            + value("\(wins)", color: wins > 0 ? Theme.good : Theme.textPrimary)
            + Text(" 和").font(.system(size: Theme.fs(11.5))).foregroundColor(Theme.textSecondary)
            + value("\(draws)")
            + Text(" 负").font(.system(size: Theme.fs(11.5))).foregroundColor(Theme.textSecondary)
            + value("\(losses)", color: losses > 0 ? Theme.bad : Theme.textPrimary))
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - 行

    /// 行 1：FEN（等宽，超出省略）+ 右侧 UCCI
    private var fenRow: some View {
        HStack(spacing: 7) {
            Text("FEN")
                .font(.system(size: Theme.fs(9.5), weight: .bold))
                .foregroundColor(Theme.groupHeader)
            Text(viewModel.displayFen)
                .font(.system(size: Theme.fs(10.5), design: .monospaced))
                .foregroundColor(Theme.monoText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !viewModel.currentMoveUCCI.isEmpty {
                Text("UCCI")
                    .font(.system(size: Theme.fs(9.5), weight: .bold))
                    .foregroundColor(Theme.groupHeader)
                Text(viewModel.currentMoveUCCI)
                    .font(.system(size: Theme.fs(10.5), design: .monospaced))
                    .foregroundColor(Theme.monoText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    /// 行 2：下步走子 / 云库 / 快估 / 深评 / 步数 / 本变 / 路径，space-between
    private var evalRow: some View {
        HStack(spacing: 8) {
            stat("下步走子", value(viewModel.isRedTurn ? "红方" : "黑方"))
            Spacer(minLength: 6)
            stat("云库", value(viewModel.displayScore, color: currentScoreColor))
            Spacer(minLength: 6)
            stat("快估", quickEngineValue)
            Spacer(minLength: 6)
            stat("深评", deepEngineValue)
            Spacer(minLength: 6)
            stat("步数", value("\(viewModel.currentGameStepDisplay)/\(viewModel.maxGameStepDisplay)\(viewModel.gameStepLimitation.map { "/\($0)" } ?? "")"))
            Spacer(minLength: 6)
            stat("本变", value("\(viewModel.currentVariationIndex + 1)/\(viewModel.totalVariationsCount)"))
            Spacer(minLength: 6)
            if viewModel.currentAppMode == .practice {
                stat("局数", value(viewModel.totalPathsCountFromCurrentFen.map { String($0) } ?? "?"))
            } else {
                stat("路径", value("\(viewModel.currentPathIndexDisplay.map { String($0 + 1) } ?? "?")/\(viewModel.totalPathsCount.map { String($0) } ?? "?")"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// 行 3：执红 / 执黑 战绩 / 练习 / 数据 + 右端已保存指示
    private var statsRow: some View {
        HStack(spacing: 8) {
            gameStat("执红", total: viewModel.currentFenInRealRedGameTotalCount, wins: viewModel.currentFenInRealRedGameWinCount, draws: viewModel.currentFenInRealRedGameDrawCount, losses: viewModel.currentFenInRealRedGameLossCount)
            Spacer(minLength: 6)
            gameStat("执黑", total: viewModel.currentFenInRealBlackGameTotalCount, wins: viewModel.currentFenInRealBlackGameWinCount, draws: viewModel.currentFenInRealBlackGameDrawCount, losses: viewModel.currentFenInRealBlackGameLossCount)
            Spacer(minLength: 6)
            stat("练习", value("\(viewModel.currentFenPracticeCount)"))
            Spacer(minLength: 6)
            stat("数据", value(String(viewModel.currentDataVersion)))
            Spacer(minLength: 6)
            #if os(macOS)
            if let queue = viewModel.evaluationQueue, !queue.state.isIdle {
                evaluationProgress(queue)
                Spacer(minLength: 6)
            }
            #endif
            savedIndicator
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// 已保存 / 未保存指示
    private var savedIndicator: some View {
        let dirty = viewModel.currentDatabaseDirty
        return HStack(spacing: 4) {
            Circle()
                .fill(dirty ? Theme.bad : Theme.savedDot)
                .frame(width: 5, height: 5)
            Text(dirty ? "未保存" : "已保存")
                .font(.system(size: Theme.fs(11.5)))
                .foregroundColor(dirty ? Theme.bad : Theme.good)
        }
        .fixedSize()
    }

    #if os(macOS)
    @ViewBuilder
    private func evaluationProgress(_ queue: EvaluationQueue) -> some View {
        HStack(spacing: 4) {
            Text("评估 \(queue.state.completedCount)/\(queue.state.totalEnqueued)")
                .font(.system(size: Theme.fs(11.5)))
                .foregroundColor(Theme.textSecondary)
                .monospacedDigit()
            if let detail = queue.state.currentDetail {
                Text(detail)
                    .font(.system(size: Theme.fs(11.5)))
                    .foregroundStyle(.tertiary)
            }
            Button("取消") {
                viewModel.cancelEvaluation()
            }
            .font(.system(size: Theme.fs(11.5)))
            .buttonStyle(.plain)
            .foregroundColor(Theme.bad)
        }
        .lineLimit(1)
        .fixedSize()
    }
    #endif

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            fenRow
            Divider().overlay(Theme.hairline)
            evalRow
            Divider().overlay(Theme.hairline)
            statsRow
        }
        .background(Theme.statusCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.statusCard))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.statusCard)
                .stroke(Color.black.opacity(0.16), lineWidth: 1)
        )
        // 卡底色与中间栏底色几乎一致，靠极淡投影把卡片“托”起来，避免读不出边界
        .shadow(color: Color.black.opacity(0.05), radius: 1.5, y: 0.5)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

#Preview {
    #if os(macOS)
    StatusBarView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    StatusBarView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
}
