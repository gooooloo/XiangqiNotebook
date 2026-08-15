import SwiftUI

/// 问棋界面的配色适配层。
///
/// Mac 用 `Theme`（冷灰底 + 蓝强调），iOS 用 `XiangqiTheme`（宣纸暖底 + 朱红强调）——
/// 两套色板本来就是各自独立演进的，这里只做映射，让 `AIChatView` 一份代码三端复用，
/// 而不必在视图里到处写 `#if os(...)`。
enum AIChatPalette {

    /// 把整棵子树钉在浅色外观。
    ///
    /// `Theme` / `XiangqiTheme` 的底色全是硬编码浅色，而系统处于深色外观时，
    /// 未显式指定颜色的文字、输入框 placeholder 与光标会取到白色系——白字落在白底上，
    /// 内容看着像没填。同类问题在评论区已经踩过一次（commit 043cc70）。
    ///
    /// 只补 `foregroundColor` 救不了 placeholder 和光标，所以整体固定外观，
    /// 让所有系统绘制的部件跟这套浅色底一致。
    struct LightAppearance: ViewModifier {
        func body(content: Content) -> some View {
            content.environment(\.colorScheme, .light)
        }
    }

    #if os(macOS)
    static let background = Theme.centerBackground
    static let barBackground = Theme.sidebarBackground
    static let insetBackground = Theme.insetBackground
    static let bubbleBackground = Theme.cardBackground
    static let accent = Theme.accent
    static let textPrimary = Theme.textPrimary
    static let textSecondary = Theme.textSecondary
    static let textFaint = Theme.placeholder
    static let hairline = Theme.hairline
    static let border = Theme.cardBorder
    static let bad = Theme.bad
    static let bubbleRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    #else
    static let background = XiangqiTheme.bg
    static let barBackground = XiangqiTheme.panel
    static let insetBackground = XiangqiTheme.inset
    static let bubbleBackground = XiangqiTheme.card
    static let accent = XiangqiTheme.accent
    static let textPrimary = XiangqiTheme.ink
    static let textSecondary = XiangqiTheme.sub
    static let textFaint = XiangqiTheme.faint
    static let hairline = XiangqiTheme.hair
    static let border = XiangqiTheme.line
    static let bad = XiangqiTheme.bad
    static let bubbleRadius: CGFloat = 14
    static let controlRadius: CGFloat = 12
    #endif
}

extension View {
    /// 见 `AIChatPalette.LightAppearance`：这套界面的底色是硬编码浅色，
    /// 外观必须一并固定，否则深色外观下输入框里的字看不见
    func aiChatLightAppearance() -> some View {
        modifier(AIChatPalette.LightAppearance())
    }
}
