import Foundation

/// 把 AI 回答里的变着识别出来，解析成棋盘上走得通的着法序列，供问棋窗口的示意棋盘逐步摆出来。
///
/// 变着的写法由 `AIChatPrompt` 约定：编号列表、一回合一行，如「1. 黑炮5进4　红马六进四」。
/// 连续几行这样的编号项算一组变着。
///
/// 难点是起点：模型写的变着不一定从「正在讨论的局面」开始——讲「此招为何不好」时，
/// 正解是从上一步之前的局面走的；工具里探过的变化又是从某个假设局面走的。
/// 这里不要求模型标注起点，而是给一串候选局面，取第一个能把整组着法依次合法走完的。
/// 几个回合的着法连续合法本身就是很强的约束，认错起点的可能极小；
/// 全都走不通的，这组就不认作变着，界面照常显示文字。
enum AnswerVariations {

    /// 一组走得通的变着
    struct Line: Equatable {
        let startFen: String
        let plies: [AnalysisToolbox.AppliedMove]
    }

    /// 某个编号项对应变着里的哪几步
    struct Row: Equatable {
        let line: Int
        let firstPly: Int
        /// 模型写的原文，按着法切好；界面照原文显示，不换成规范写法
        let tokens: [String]
    }

    struct Result: Equatable {
        var lines: [Line] = []
        /// `AnswerMarkdown.blocks` 下标 → 该编号项的着法
        var rows: [Int: Row] = [:]

        static let empty = Result()
    }

    /// - Parameter candidateFens: 候选起点，按优先级排好；解析出的变着里每一步的局面
    ///   也会追加为后续组的候选（后一组常常接着前一组往下讲）
    static func resolve(markdown: String, candidateFens: [String], flipped: Bool) -> Result {
        var result = Result()
        var candidates = deduplicated(candidateFens)

        for group in moveRowGroups(AnswerMarkdown.blocks(markdown)) {
            let tokens = group.flatMap(\.tokens)
            guard let line = candidates.lazy.compactMap({
                play(tokens, from: $0, flipped: flipped)
            }).first else { continue }

            let lineIndex = result.lines.count
            result.lines.append(line)
            var ply = 0
            for row in group {
                result.rows[row.blockIndex] = Row(line: lineIndex, firstPly: ply, tokens: row.tokens)
                ply += row.tokens.count
            }
            candidates = deduplicated(candidates + line.plies.map(\.fen))
        }
        return result
    }

    // MARK: - 识别编号项

    private struct MoveRow {
        let blockIndex: Int
        let tokens: [String]
    }

    /// 相邻的、整行都是着法的编号项归成一组
    private static func moveRowGroups(_ blocks: [AnswerMarkdown.Block]) -> [[MoveRow]] {
        var groups: [[MoveRow]] = []
        var current: [MoveRow] = []
        for (index, block) in blocks.enumerated() {
            if case .ordered(_, let text) = block, let tokens = moveTokens(text) {
                current.append(MoveRow(blockIndex: index, tokens: tokens))
            } else if !current.isEmpty {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// 一行能切成一两步着法才返回；夹了别的字（讲解、分数）就不是变着行
    static func moveTokens(_ text: String) -> [String]? {
        let cleaned = text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        let tokens = cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard (1...2).contains(tokens.count),
              tokens.allSatisfy({ looksLikeMove(moveText($0)) }) else { return nil }
        return tokens
    }

    /// 去掉「红」「黑」前缀与句末标点，剩下的交给 `AnalysisToolbox.resolveMove`
    static func moveText(_ token: String) -> String {
        var text = Substring(token)
        while let last = text.last, "。，,；;".contains(last) { text = text.dropLast() }
        if text.hasPrefix("红方") || text.hasPrefix("黑方") {
            text = text.dropFirst(2)
        } else if text.hasPrefix("红") || text.hasPrefix("黑") {
            text = text.dropFirst()
        }
        return String(text)
    }

    /// 中文着法固定四个字，末字是路数或步数
    private static func looksLikeMove(_ text: String) -> Bool {
        let normalized = AnalysisToolbox.normalizedMoveText(text)
        guard normalized.count == 4, let last = normalized.last else { return false }
        return last.isASCII && last.isNumber
    }

    // MARK: - 走子

    private static func play(_ tokens: [String], from fen: String, flipped: Bool) -> Line? {
        var current = fen
        var plies: [AnalysisToolbox.AppliedMove] = []
        for token in tokens {
            if let side = side(of: token), side != AnalysisToolbox.sideToMove(fen: current) { return nil }
            guard case .resolved(let step) = AnalysisToolbox.resolveMove(
                moveText(token), fen: current, flipped: flipped) else { return nil }
            plies.append(step)
            current = step.fen
        }
        return Line(startFen: fen, plies: plies)
    }

    /// 这步是哪方走的。`resolveMove` 会把中文数字统一成阿拉伯数字，「炮二平五」与黑方的
    /// 「炮2平5」在它那里是同一步——给工具输入留余地是对的，拿来认起点却会认错：
    /// 一串红着能从黑走的局面「走通」。所以先按写法分红黑：明写「红」「黑」的按字面，
    /// 否则按标准记法，红方用中文数字、黑方用阿拉伯数字（含全角）
    static func side(of token: String) -> String? {
        if token.hasPrefix("红") { return "red" }
        if token.hasPrefix("黑") { return "black" }
        let hasChinese = token.contains { "一二三四五六七八九".contains($0) }
        let hasArabic = token.contains { $0.isNumber && !"一二三四五六七八九".contains($0) }
        switch (hasChinese, hasArabic) {
        case (true, false): return "red"
        case (false, true): return "black"
        default: return nil
        }
    }

    // MARK: - 工具结果里的局面

    /// 从工具参数或结果 JSON 里捞出所有局面，作为候选起点。
    /// 模型讲的假设变化，几乎都先用工具走过一遍
    static func fens(inToolJSON json: String) -> [String] {
        guard let object = AnalysisToolbox.parseArgumentsJSON(json) else { return [] }
        var found: [String] = []
        collectFens(object, into: &found)
        return found
    }

    private static let fenKeys: Set<String> = ["fen", "startFen", "finalFen", "fenBefore"]

    private static func collectFens(_ value: Any, into found: inout [String]) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if fenKeys.contains(key), let fen = child as? String,
                   AnalysisToolbox.isValidPositionFen(fen) {
                    found.append(fen)
                } else {
                    collectFens(child, into: &found)
                }
            }
        } else if let array = value as? [Any] {
            for child in array { collectFens(child, into: &found) }
        }
    }

    private static func deduplicated(_ fens: [String]) -> [String] {
        var seen: Set<String> = []
        return fens.filter { seen.insert($0).inserted }
    }
}
