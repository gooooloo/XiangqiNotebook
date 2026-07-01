import SwiftUI

extension GameResult {
    /// 棋局结果配色（深色模式友好方案）。
    /// 原本散在 RealGameListView / iPhoneRealGameListView / GameBrowserView 四处，
    /// 且棋谱浏览器用 .black/.orange、实战列表用 .primary/.secondary 两套不一致方案，
    /// 统一为：黑胜 .primary（随深浅色自适应）、未完 .secondary
    var displayColor: Color {
        switch self {
        case .redWin: return .red
        case .blackWin: return .primary
        case .draw: return .blue
        case .notFinished: return .secondary
        case .unknown: return .secondary
        }
    }
}

/// 从用户视角（执红/执黑）看的战绩结果，用于棋谱行右侧的胜/负/和 chip。
enum UserOutcome {
    case win, loss, draw

    var label: String {
        switch self {
        case .win: return "胜"
        case .loss: return "负"
        case .draw: return "和"
        }
    }

    var foreground: Color {
        switch self {
        case .win: return Theme.good
        case .loss: return Theme.bad
        case .draw: return Theme.textSecondary
        }
    }

    var background: Color {
        switch self {
        case .win: return Color(hex: 0x34C759, alpha: 0.14)
        case .loss: return Color(hex: 0xFF3B30, alpha: 0.13)
        case .draw: return Color(hex: 0x787880, alpha: 0.16)
        }
    }
}

extension GameObject {
    /// 用户在该实战棋局中的结果；非实战或结果未知时为 nil。
    var userOutcome: UserOutcome? {
        guard iAmRed || iAmBlack else { return nil }
        switch gameResult {
        case .draw: return .draw
        case .redWin: return iAmRed ? .win : .loss
        case .blackWin: return iAmBlack ? .win : .loss
        case .notFinished, .unknown: return nil
        }
    }
}

/// 胜/负/和 战绩 chip。
struct OutcomeChip: View {
    let outcome: UserOutcome

    var body: some View {
        Text(outcome.label)
            .font(.system(size: Theme.fs(10), weight: .semibold))
            .foregroundColor(outcome.foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(outcome.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}
