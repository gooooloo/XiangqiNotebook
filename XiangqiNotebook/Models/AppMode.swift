import Foundation

/// 应用模式枚举
/// 定义象棋笔记软件的两种工作模式，每种模式有各自的可见控件
enum AppMode: String, CaseIterable, Codable {
    /// 常规模式 - 完整功能模式，显示所有控件
    case normal = "normal"

    /// 练习模式 - 专注于练习功能，界面简洁
    case practice = "practice"

    /// 模式的显示名称
    var displayName: String {
        switch self {
        case .practice:
            return "练习模式"
        case .normal:
            return "常规模式"
        }
    }

    /// 模式的描述信息
    var description: String {
        switch self {
        case .practice:
            return "专注于练习功能，界面简洁，隐藏非核心控件"
        case .normal:
            return "完整功能模式，显示所有可用控件"
        }
    }
}