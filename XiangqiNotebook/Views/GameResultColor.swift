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
