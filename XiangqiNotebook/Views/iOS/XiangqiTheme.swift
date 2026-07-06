#if os(iOS)
import SwiftUI

/// iPhone「朱墨」视觉改版的设计令牌（颜色 / 字体 / 圆角 / 阴影）。
///
/// 取值来自设计稿 `design_handoff_iphone_review_practice`，为最终值。
/// 与 macOS 端 `Theme`（见 `Views/DesignTokens.swift`）配色体系完全独立，仅供 `Views/iOS` 使用；
/// 复用其中定义的全局 `Color(hex:alpha:)` 初始化器。
enum XiangqiTheme {
    // MARK: - 底色（宣纸暖底）
    static let bg = Color(hex: 0xEEE4CD)
    static let panel = Color(hex: 0xF6EFDC)
    static let card = Color(hex: 0xFBF6E9)
    static let inset = Color(hex: 0xF1E8D2)

    /// 分析页固定底部走子条的磨砂色，与全局暖米底色同色系
    static let boardNavBarMaterial = Color(hex: 0xF6EFDC, alpha: 0.94)

    // MARK: - 文字
    static let ink = Color(hex: 0x282219)
    static let sub = Color(hex: 0x7C7160)
    static let faint = Color(hex: 0xA99E86)

    // MARK: - 描边 / 分隔线
    static let line = Color(hex: 0x3C301C, alpha: 0.14)
    static let hair = Color(hex: 0x3C301C, alpha: 0.08)

    // MARK: - 强调
    /// 朱砂红：主强调 / 红方 / 选中态
    static let accent = Color(hex: 0xB4231F)
    /// 金褐：次强调
    static let accent2 = Color(hex: 0x8A6D3B)
    /// 河界文字色
    static let gold = Color(hex: 0x9A7C46)
    /// 手机边框 / 印章角标等深色元素
    static let frame = Color(hex: 0x2A241B)
    /// 棋盘分析页专用蓝：该页唯一的功能强调色（返回/更多按钮）
    static let blue = Color(hex: 0x0A6BB8)

    // MARK: - 评级 / 战绩配色
    static let good = Color(hex: 0x4C7A3F)   // 胜 / 正确 / 简单
    static let bad = Color(hex: 0xB4231F)    // 负 / 错误 / 忘了
    static let draw = Color(hex: 0x8A8272)   // 和棋
    static let hard = Color(hex: 0xC0801F)   // 复习「困难」
    static let fine = Color(hex: 0x3C6B84)   // 复习「良好」

    static let cardShadow = Color(hex: 0x46361C, alpha: 0.10)

    // MARK: - 圆角
    enum Radius {
        static let card: CGFloat = 14
        static let button: CGFloat = 12
        static let sheet: CGFloat = 24
        static let pill: CGFloat = 18
        static let inset: CGFloat = 11
    }

    // MARK: - 字体
    /// 工程内暂无内嵌宋体资源，标题/数字/棋子字沿用系统内置「STSongti-SC」（原型里 Noto Serif SC 的对应替代）。
    enum XFont {
        static func serif(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .custom("STSongti-SC", size: size).weight(weight)
        }
        static func sans(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
    }
}

extension View {
    /// 卡片：暖白底 + 细描边 + 轻投影（对应原型 `t.sh`）。
    func xqCard(radius: CGFloat = XiangqiTheme.Radius.card, background: Color = XiangqiTheme.card) -> some View {
        self
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(XiangqiTheme.line, lineWidth: 1)
            )
            .shadow(color: XiangqiTheme.cardShadow, radius: 11, x: 0, y: 8)
    }

    /// 内凹面：分段控件、搜索框、图标格背景。
    func xqInset(radius: CGFloat = XiangqiTheme.Radius.inset) -> some View {
        self
            .background(XiangqiTheme.inset)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
#endif
