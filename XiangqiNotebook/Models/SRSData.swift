import Foundation

/// 间隔复习算法数据（Spaced Repetition System）
/// 每个复习项对应一个局面（fenId），存储在 DatabaseData.reviewItems 中
class SRSData: Codable {
    var gamePath: [Int]?
    var customName: String?
    var easeFactor: Double = 2.5
    var interval: Int = 0
    var repetitions: Int = 0
    var nextReviewDate: Date
    var lastReviewDate: Date?

    init(gamePath: [Int]? = nil, nextReviewDate: Date = Date()) {
        self.gamePath = gamePath
        self.nextReviewDate = nextReviewDate
    }

    /// 是否到期需要复习
    var isDue: Bool {
        return nextReviewDate <= Date()
    }

    /// SM-2 算法：根据自评等级更新间隔复习参数
    /// - Parameter quality: 自评等级
    ///   - .again (1): 完全不会，重置间隔
    ///   - .hard (2): 需要加强，重置间隔
    ///   - .good (4): 基本掌握，按间隔增长
    ///   - .easy (5): 完全掌握，按间隔增长
    func review(quality: ReviewQuality) {
        let q = quality.rawValue

        // 更新 easeFactor
        let newEF = easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        easeFactor = max(1.3, newEF)

        if q < 3 {
            // 失败：重置
            repetitions = 0
            interval = 0
        } else {
            // 成功：增长间隔
            repetitions += 1
            switch repetitions {
            case 1:
                interval = 1
            case 2:
                interval = 6
            default:
                interval = Int(round(Double(interval) * easeFactor))
            }
        }

        lastReviewDate = Date()
        nextReviewDate = Calendar.current.date(byAdding: .day, value: max(interval, 1), to: lastReviewDate!)!
    }
}

/// 复习自评等级
enum ReviewQuality: Int, Codable {
    case again = 1
    case hard = 2
    case good = 4
    case easy = 5
}
