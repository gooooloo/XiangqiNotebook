import Foundation

/// 练习模式中一次走错的累计记录
///
/// 一个 fenId（走错时所在的源局面）可能对应多条不同的 PracticeMistakeRecord，
/// 每一条对应一种"错招"——以走出的 wrongFen 区分。
struct PracticeMistakeRecord: Codable, Equatable {
    /// 用户走出的（错误）目标局面 FEN（标准化后的字符串）
    var wrongFen: String
    /// 该错招的累计走错次数
    var count: Int
    /// 首次走错的时间
    var firstWrongAt: Date
    /// 最近一次走错的时间
    var lastWrongAt: Date

    init(wrongFen: String, count: Int = 1, firstWrongAt: Date, lastWrongAt: Date) {
        self.wrongFen = wrongFen
        self.count = count
        self.firstWrongAt = firstWrongAt
        self.lastWrongAt = lastWrongAt
    }
}
