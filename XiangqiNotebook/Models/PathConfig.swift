import Foundation
import SwiftUI

/// 棋盘路径配置，用于控制路径的显示方式
public struct PathConfig: Codable, Equatable {
    /// 路径上的坐标点
    public var points: [String]
    /// 是否显示箭头和圆点
    public var showArrow: Bool
    /// 是否为虚线
    public var isDashed: Bool
    
    public init(points: [String], showArrow: Bool = true, isDashed: Bool = false) {
        self.points = points
        self.isDashed = isDashed
        self.showArrow = showArrow
    }
    
    public static func == (lhs: PathConfig, rhs: PathConfig) -> Bool {
        return lhs.points == rhs.points &&
               lhs.showArrow == rhs.showArrow &&
               lhs.isDashed == rhs.isDashed
    }
}

/// 路径组，包含一组共享相同颜色的路径配置
public struct PathGroup: Codable, Equatable {
    /// 组内的路径配置数组
    public var paths: [PathConfig]
    /// 组的名称（可选）
    public let name: String?
    
    public init(paths: [PathConfig], name: String? = nil) {
        self.paths = paths
        self.name = name
    }
    
    public static func == (lhs: PathGroup, rhs: PathGroup) -> Bool {
        return lhs.paths == rhs.paths &&
               lhs.name == rhs.name
    }
} 
