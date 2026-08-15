import Foundation

/// 一条缓存下来的 MultiPV 分析。
///
/// 与 `scores` 里那个单值分数并存而非取代它：单值是「这个局面值多少」，
/// 讲解还需要候选线路、主变着法、排名——那些从一个数字里变不出来。
struct CachedAnalysis: Codable, Equatable {
    /// 算的时候要了几条候选线路
    let multiPV: Int
    /// 算的时候给了多少毫秒
    let movetimeMs: Int
    /// 算出它的引擎标识。跨设备复用时要如实回报，
    /// 不能让 iPhone 拿着 Mac 算的数报成本机结果
    let engine: String
    let lines: [EnginePVLine]

    /// 能否用来回答一个 (multiPV, movetimeMs) 的请求。
    ///
    /// 「存的比要的宽、比要的久」就能用：top-5 里切得出 top-3，
    /// 算了 5 秒的结论拿去答 3 秒的请求只会更准。
    /// 这条规则是缓存能真正命中的关键——否则参数稍有出入就得重算
    func satisfies(multiPV: Int, movetimeMs: Int) -> Bool {
        self.multiPV >= multiPV && self.movetimeMs >= movetimeMs
    }

    /// 信息量是否不低于另一条。合并冲突时留信息量大的
    func supersedes(_ other: CachedAnalysis) -> Bool {
        satisfies(multiPV: other.multiPV, movetimeMs: other.movetimeMs)
    }

    /// 截取前 n 条，用来服务比缓存更窄的请求
    func lines(limitedTo multiPV: Int) -> [EnginePVLine] {
        Array(lines.prefix(multiPV))
    }
}

/// 引擎分数数据，独立于 DatabaseData 存储
/// 每个 engineKey 对应一个文件，支持多版本/配置并存
class EngineScoreData: Codable {
    var dataVersion: Int = 0
    var scores: [Int: Int] = [:]  // fenId → score
    /// fenId → 已缓存的 MultiPV 分析。
    ///
    /// 与 scores 同住一个文件、同一个 engineKey，因此白得 iCloud 同步：
    /// Mac 上算过的局面，iPhone 直接读，不必再烧一遍电。
    /// 按 fenId 索引还有个附带好处——缓存规模天然被笔记本封顶，不需要淘汰策略
    var analyses: [Int: CachedAnalysis] = [:]

    enum CodingKeys: String, CodingKey {
        case dataVersion = "data_version"
        case scores
        case analyses
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dataVersion = try container.decodeIfPresent(Int.self, forKey: .dataVersion) ?? 0

        // scores 的 key 在 JSON 中是 String，需要转换为 Int
        let stringKeyedScores = try container.decodeIfPresent([String: Int].self, forKey: .scores) ?? [:]
        self.scores = [:]
        for (key, value) in stringKeyedScores {
            if let intKey = Int(key) {
                self.scores[intKey] = value
            }
        }

        // 老文件没有这个字段，缺失即空——它是派生数据，丢了只是重算一次
        let stringKeyedAnalyses = try container
            .decodeIfPresent([String: CachedAnalysis].self, forKey: .analyses) ?? [:]
        self.analyses = [:]
        for (key, value) in stringKeyedAnalyses {
            if let intKey = Int(key) {
                self.analyses[intKey] = value
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dataVersion, forKey: .dataVersion)

        // 将 Int key 转换为 String key（JSON 要求）
        var stringKeyedScores: [String: Int] = [:]
        for (key, value) in scores {
            stringKeyedScores[String(key)] = value
        }
        try container.encode(stringKeyedScores, forKey: .scores)

        var stringKeyedAnalyses: [String: CachedAnalysis] = [:]
        for (key, value) in analyses {
            stringKeyedAnalyses[String(key)] = value
        }
        try container.encode(stringKeyedAnalyses, forKey: .analyses)
    }
}
