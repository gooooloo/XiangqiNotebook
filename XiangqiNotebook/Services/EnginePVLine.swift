import Foundation

/// 单条主变（MultiPV 分析结果中的一条候选线路）。
///
/// macOS（`PikafishService`，子进程 + UCI 管道）与 iOS（`PikafishServiceIOS`，
/// 进程内 bridge）两套引擎实现共用这一形状，上层的 `AnalysisToolbox` 与远程 `/eval`
/// 因此不必按平台分叉。
/// Codable 是为了随引擎分数文件一起落盘（见 `CachedAnalysis`）：
/// 问棋会反复分析同一批局面，重算既慢又费电，iPhone 上尤其。
struct EnginePVLine: Equatable, Codable {
    /// 1-based 排名，1 即引擎首选
    let multipv: Int
    /// 分数（走子方视角，厘兵值；杀棋折算为 ±30000 附近）
    let scoreCp: Int
    /// 杀棋步数：正数为走子方 N 步成杀，负数为走子方 N 步被杀，非杀棋为 nil。
    ///
    /// 与 `scoreCp` 并存而非取代它：`scoreCp` 的折算值（±30000 附近）是数据库里
    /// 引擎分的既有存储形式，动不得；`mate` 是额外给出的明确语义，免得上层
    /// 从 29997 反推「3 步杀」——那既容易算错，也容易和「巨大优势」混为一谈。
    let mate: Int?
    let depth: Int?
    /// UCI 着法序列
    let moves: [String]
}
