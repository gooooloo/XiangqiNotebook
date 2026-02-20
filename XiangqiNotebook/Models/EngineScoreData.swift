import Foundation

/// 引擎分数数据，独立于 DatabaseData 存储
/// 每个 engineKey 对应一个文件，支持多版本/配置并存
class EngineScoreData: Codable {
    var dataVersion: Int = 0
    var scores: [Int: Int] = [:]  // fenId → score

    enum CodingKeys: String, CodingKey {
        case dataVersion = "data_version"
        case scores
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
    }
}
