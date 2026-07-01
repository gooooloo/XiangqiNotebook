import SwiftUI

/// macOS 主界面视觉改版的设计令牌（颜色 / 圆角）。
///
/// 取值来自设计稿 `design_handoff_mac_redesign`，为最终值，跨平台共享。
/// 仅承载“视觉细节”，不参与布局结构与棋盘渲染。
enum Theme {
    // MARK: - 文字
    /// 正文主色
    static let textPrimary = Color(hex: 0x1D1D1F)
    /// 次要文字
    static let textSecondary = Color(hex: 0x86868B)
    /// 分组小标题（大写灰）
    static let groupHeader = Color(hex: 0x9B9BA1)
    /// 占位 / 弱文字
    static let placeholder = Color(hex: 0xB0B0B6)
    /// 等宽信息（FEN / UCCI 等）文字色
    static let monoText = Color(hex: 0x3C3C43)

    // MARK: - 强调
    /// 主强调色（选中 / 复选开 / 当前着 / 主按钮）
    static let accent = Color(hex: 0x0A84FF)
    /// 当前变招蓝
    static let variant = Color(hex: 0x2A6FDB)

    // MARK: - 底色
    /// 侧栏 / 右栏底色
    static let sidebarBackground = Color(hex: 0xF4F4F7)
    /// 中间栏底色
    static let centerBackground = Color(hex: 0xFBFBFC)
    /// 卡片底色
    static let cardBackground = Color(hex: 0xFFFFFF)
    /// 内嵌框底色
    static let insetBackground = Color(hex: 0xF7F7F8)
    /// 状态卡底色
    static let statusCardBackground = Color(hex: 0xFAFAFA)

    // MARK: - 评分 / 战绩
    /// 好棋 / 分数正
    static let good = Color(hex: 0x248A3D)
    /// 坏棋 / 分数负
    static let bad = Color(hex: 0xD7263D)
    /// 已保存指示点
    static let savedDot = Color(hex: 0x34C759)

    // MARK: - 不好的原因框
    static let reasonBorder = Color(hex: 0xD7263D, alpha: 0.3)
    static let reasonBackground = Color(hex: 0xFDF2F3)

    // MARK: - 分隔线 / 边框
    /// 细分隔线（行间）
    static let hairline = Color.black.opacity(0.08)
    /// 卡片 / 控件描边
    static let cardBorder = Color.black.opacity(0.13)

    // MARK: - 字号
    /// 全局字号缩放：界面整体偏小/偏大时，只调这一个值。
    /// 设计稿基准字号偏小（为网页原型设定），在真实 macOS 上整体放大。
    static let fontScale: CGFloat = 1.15
    /// 把设计稿基准字号按全局缩放换算为实际点数。
    static func fs(_ base: CGFloat) -> CGFloat { base * fontScale }

    // MARK: - 圆角
    enum Radius {
        static let card: CGFloat = 9
        static let row: CGFloat = 6
        static let chip: CGFloat = 5
        static let statusCard: CGFloat = 8
        static let inset: CGFloat = 7
        static let keycap: CGFloat = 4
    }
}

/// 快捷键键帽：等宽小字、浅底细边圆角。
///
/// 用于右侧面板各行与底部按钮，显式展示现有快捷键。
struct Keycap: View {
    let text: String
    /// 主按钮上的键帽用半透明白色，其余用默认灰。
    var onAccent: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: Theme.fs(9.5), weight: .semibold, design: .monospaced))
            .foregroundColor(onAccent ? Color.white.opacity(0.9) : Color(hex: 0x5B5B60))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.keycap)
                    .fill(onAccent ? Color.white.opacity(0.18) : Color.black.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.keycap)
                    .stroke(onAccent ? Color.white.opacity(0.3) : Color.black.opacity(0.1), lineWidth: 0.5)
            )
    }
}

/// 分组小标题：大写灰色细标签，用于右栏 / 评论区各块上方。
struct GroupHeader: View {
    let text: String
    var color: Color = Theme.groupHeader

    init(_ text: String, color: Color = Theme.groupHeader) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: Theme.fs(9.5), weight: .bold))
            .foregroundColor(color)
            .textCase(.uppercase)
    }
}

extension View {
    /// 白色圆角卡 + 细描边（右栏分组、列表容器用）。
    func sectionCard(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
    }

    /// 浅底内嵌框：圆角 7 + 细边（评论区各块、着法/变招列表区域用）。
    func insetBox(background: Color = Theme.insetBackground, border: Color = Theme.cardBorder) -> some View {
        self
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inset))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.inset)
                    .stroke(border, lineWidth: 1)
            )
    }
}

extension String {
    /// 把 ASCII 阿拉伯数字转成全角（０-９），让着法记谱每步等宽、纵向成列。
    var fullwidthDigits: String {
        String(unicodeScalars.map { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                ? Unicode.Scalar(scalar.value - 48 + 0xFF10)!
                : scalar
        }.map(Character.init))
    }
}

extension Color {
    /// 用 0xRRGGBB 形式的整型十六进制构造颜色，可选透明度。
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
