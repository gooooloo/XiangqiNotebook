import Foundation

// MARK: - 局面快照

/// 走到当前局面的那一步棋
struct LastMove: Equatable {
    /// 中文着法名。按未翻转的棋盘生成，与工具层其他地方口径一致
    let chinese: String
    /// 走这步之前的局面。评估这一步必须以它为准，而不是当前 fen
    let fenBefore: String
}

/// 当前局面与笔记的只读快照。
///
/// 两个消费方共用它，语义因此不会漂移：
/// - `RemoteControlServer./state`（macOS，供 MCP 桥接给外部 Claude）
/// - `AnalysisToolbox` 的 `get_position` 工具（app 内 AI 问棋，三端）
///
/// 字段是两者的并集：远程 `/state` 还要报 UI 开关状态，AI 只关心棋和笔记，
/// 因此各有一个序列化方法，取各自需要的子集。
struct PositionSnapshot {
    let fen: String
    let displayFen: String
    let mode: String
    let step: Int
    let maxStep: Int
    /// "red" / "black"，指棋盘朝向而非走子方
    let orientation: String
    let isHorizontalFlipped: Bool
    let comment: String?
    let moveComment: String?
    /// 用户给这一步写的「不好的原因」。是他自己的判断，不是定论——
    /// 给模型看是为了让它核对或补充，不是让它照抄
    let badReason: String?
    /// 走到当前局面的那一步。
    ///
    /// 「刚走完一步，问这步为什么不好」是最常见的用法之一，而那时 `fen` 已经是
    /// 走完之后的局面了——没有这个字段，模型既不知道走的是哪步，也拿不到走之前的
    /// 局面，根本无从评估。
    let lastMove: LastMove?
    /// 云库分（字符串，可能为空或非数字占位）
    let score: String
    /// 皮卡鱼引擎分
    let engineScore: String
    let showPath: Bool
    let showAllNextMoves: Bool
    let showLastMove: Bool
    let isLocked: Bool
    let isBookmarked: Bool
    let isInReview: Bool
    let filters: [String]
    /// 笔记本里已记录的后续着法（中文）
    let nextMoves: [String]
    /// 本步变招（中文）
    let variants: [String]
    let windowTitle: String

    /// 走子方，由 fen 第二段推导："red" / "black"
    var sideToMove: String {
        AnalysisToolbox.sideToMove(fen: fen)
    }

    /// 远程操控 `/state` 的响应体字段集（保持既有契约，MCP 依赖它）
    func remoteStateDictionary() -> [String: Any] {
        [
            "fen": fen,
            "displayFen": displayFen,
            "mode": mode,
            "step": step,
            "maxStep": maxStep,
            "orientation": orientation,
            "isHorizontalFlipped": isHorizontalFlipped,
            "comment": comment as Any? ?? NSNull(),
            "moveComment": moveComment as Any? ?? NSNull(),
            "score": score,
            "engineScore": engineScore,
            "showPath": showPath,
            "showAllNextMoves": showAllNextMoves,
            "showLastMove": showLastMove,
            "isLocked": isLocked,
            "isBookmarked": isBookmarked,
            "isInReview": isInReview,
            "filters": filters,
            "nextMoves": nextMoves,
            "variants": variants,
            "windowTitle": windowTitle,
        ]
    }

    /// `get_position` 工具的返回字段集——只给 AI 与下棋有关的信息。
    /// UI 开关（showPath、isLocked 等）对讲解毫无价值，塞进去只会浪费 token
    /// 并诱导模型去谈论界面而不是棋。
    func toolDictionary() -> [String: Any] {
        [
            "fen": fen,
            "sideToMove": sideToMove,
            "step": step,
            "maxStep": maxStep,
            "comment": comment as Any? ?? NSNull(),
            "moveComment": moveComment as Any? ?? NSNull(),
            "badReason": badReason as Any? ?? NSNull(),
            "lastMove": lastMove.map {
                ["chinese": $0.chinese, "fenBefore": $0.fenBefore]
            } as Any? ?? NSNull(),
            "nextMoves": nextMoves,
            "variants": variants,
            "score": score,
            "engineScore": engineScore,
        ]
    }
}

// MARK: - 工具宿主

/// `AnalysisToolbox` 向外索取局面与引擎能力的接口。
///
/// 定义在 Models 层、由 ViewModel 实现（依赖倒置），这样工具层不反向依赖具体
/// ViewModel，单测里可以塞一个假宿主，不必启动真引擎。
/// 一次分析的结果，连同它的来路。
///
/// 来路必须跟着结果走：命中缓存时算它的可能是另一台设备上的另一个引擎配置，
/// 拿本机的 `engineVersionDescription` 去标注就成了假话
struct EngineAnalysis {
    let lines: [EnginePVLine]
    /// 算出这批线路的引擎标识
    let engine: String
    /// 这批线路实际用了多少毫秒算出来的（命中缓存时是当初那次的时长）
    let movetimeMs: Int
    let fromCache: Bool
}

@MainActor
protocol AnalysisToolHost: AnyObject {
    /// 当前局面与笔记快照
    func currentPositionSnapshot() -> PositionSnapshot
    /// MultiPV 引擎分析；引擎忙或不可用时抛错。
    /// 实现方负责查缓存与回写，工具层不关心结果是算的还是取的
    func analyzePosition(fen: String, multiPV: Int, movetime: Int) async throws -> EngineAnalysis
}

// MARK: - 工具箱

/// AI 问棋的工具层：定义暴露给模型的三个工具，并负责参数校验与执行分发。
///
/// 与 `mcp/xiangqi-notebook-mcp.mjs` 暴露给外部 Claude 的工具一一对应、参数同名，
/// 两条路（MCP、app 内 AI）共用同一份语义。
///
/// 类型本身不绑 actor：静态部分全是纯函数，`RemoteControlServer` 会在自己的连接队列上
/// 直接调用它们；只有需要读 ViewModel 与引擎的 `execute` 标了 `@MainActor`。
final class AnalysisToolbox {

    private weak var host: AnalysisToolHost?

    init(host: AnalysisToolHost) {
        self.host = host
    }

    // MARK: 参数取值范围

    /// 候选线路数上下限
    static let multiPVRange = 1...10
    /// 默认候选线路数
    static let defaultMultiPV = 3

    /// 引擎思考时长上限。
    /// 远程 `/eval` 允许到 60 秒（人手动发一次请求），这里收紧：AI 会在一轮问答里
    /// 连着调好几次，且 iOS 端跑在电池上。
    #if os(iOS)
    static let movetimeRange = 500...8000
    static let defaultMovetime = 3000
    #else
    static let movetimeRange = 500...15000
    static let defaultMovetime = 5000
    #endif

    // MARK: - 工具定义（OpenAI function calling 格式）

    static var toolSpecs: [[String: Any]] {
        [
            function(
                name: "get_position",
                description: """
                读取象棋笔记本当前打开的局面：FEN、轮谁走、第几步、用户在这个局面/这步棋上写的笔记，\
                以及笔记本里已记录的后续着法与本步变招。回答任何与「当前局面」有关的问题前都应先调用它。
                lastMove 是走到当前局面的那一步（chinese 着法名 + fenBefore 走之前的局面）：\
                用户问「这一步为什么不好」指的就是它，评估时 fen 要传 fenBefore 而不是当前局面。\
                badReason 是用户自己写的「不好的原因」，属于他的判断而非定论，你要用引擎核对，\
                对就印证、不对就指出，别照抄。
                """,
                properties: [:],
                required: []
            ),
            function(
                name: "evaluate",
                description: """
                用皮卡鱼引擎分析一个局面，返回前 N 条候选线路，每条含分数、搜索深度、主变（UCI 与中文两种记法）。\
                分数是走子方视角的厘兵值，100 约等于一个兵，杀棋折算到 ±30000 附近。\
                省略 fen 则分析当前局面。这是判断着法好坏的唯一可靠依据，不要凭印象下结论。
                """,
                properties: [
                    "fen": [
                        "type": "string",
                        "description": "要分析的局面，格式「棋盘 r|b」。省略则用当前局面。",
                    ],
                    "multipv": [
                        "type": "integer",
                        "description": "返回的候选线路数，\(multiPVRange.lowerBound)-\(multiPVRange.upperBound)，默认 \(defaultMultiPV)。",
                    ],
                    "movetime_ms": [
                        "type": "integer",
                        "description": "引擎思考时长（毫秒），\(movetimeRange.lowerBound)-\(movetimeRange.upperBound)，默认 \(defaultMovetime)。要更硬的结论就调大。",
                    ],
                ],
                required: []
            ),
            function(
                name: "evaluate_move",
                description: """
                评估某一具体着法的好坏——要评点「为什么走X不好」时用这个，不要自己拿 evaluate 加 apply_moves 拼。\
                它会跑两次引擎（走之前、走之后），并把所有分数统一换算到**走这步的一方**的视角：\
                scoreBefore 是走最佳能得到的分，scoreAfter 是走了这步之后实际能得到的分，lossCp 是两者之差（正数=亏）。\
                同时给出引擎首选（bestInstead）、对手最强反击（opponentBestReplies），\
                以及这步在候选里的排名（rankAmongCandidates，null 表示连前几名都没进）。\
                杀棋看 mate 字段：正数为该方 N 步成杀，负数为 N 步被杀。
                """,
                properties: [
                    "fen": [
                        "type": "string",
                        "description": "要评估的局面，格式「棋盘 r|b」。省略则用当前局面。",
                    ],
                    "move": [
                        "type": "string",
                        "description": "要评估的着法。UCI（h2e2）或中文着法（炮二平五、车9平6）都行——"
                            + "**推荐直接传中文**，省得自己换算坐标算错。"
                            + "必须是当前走子方的着法；若传了对方的子会报错。",
                    ],
                    "multipv": [
                        "type": "integer",
                        "description": "对比用的候选线路数，\(multiPVRange.lowerBound)-\(multiPVRange.upperBound)，默认 \(defaultMultiPV)。",
                    ],
                    "movetime_ms": [
                        "type": "integer",
                        "description": "单次引擎思考时长（毫秒），\(movetimeRange.lowerBound)-\(movetimeRange.upperBound)，默认 \(defaultMovetime)。本工具会跑两次，总耗时约两倍。",
                    ],
                ],
                required: ["move"]
            ),
            function(
                name: "apply_moves",
                description: """
                把一串 UCI 着法依次走到指定局面上，返回每一步的中文着法名与走完后的新 FEN。\
                要评点某步棋时，用它把这步走出来，再对新局面调 evaluate 看后果。\
                只做机械移动，不校验象棋规则。UCI 坐标系：列 a–i 自红方左侧起，行 0–9 自红方底线起。
                """,
                properties: [
                    "fen": [
                        "type": "string",
                        "description": "起始局面，格式「棋盘 r|b」。",
                    ],
                    "moves": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "UCI 着法序列，按走棋顺序（红黑交替），如 [\"h2e2\", \"h9g7\"]。",
                    ],
                ],
                required: ["fen", "moves"]
            ),
        ]
    }

    private static func function(name: String, description: String,
                                properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }

    // MARK: - 参数解析（纯函数，便于单测）

    struct EvalArgs: Equatable {
        var fen: String?
        var multiPV: Int
        var movetime: Int
    }

    /// 越界一律钳到合法区间而非报错——模型填错参数是常态，为此中断一轮问答不值得
    static func parseEvalArgs(_ json: [String: Any]?) -> EvalArgs {
        let fen = (json?["fen"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let multiPV = clamp(intValue(json?["multipv"]) ?? defaultMultiPV, to: multiPVRange)
        // 兼容模型偶尔写成 movetime 而非 movetime_ms
        let rawMovetime = intValue(json?["movetime_ms"]) ?? intValue(json?["movetime"]) ?? defaultMovetime
        return EvalArgs(fen: fen, multiPV: multiPV, movetime: clamp(rawMovetime, to: movetimeRange))
    }

    struct ApplyArgs: Equatable {
        var fen: String
        var moves: [String]
    }

    static func parseApplyArgs(_ json: [String: Any]?) -> ApplyArgs? {
        guard let fen = json?["fen"] as? String, !fen.isEmpty else { return nil }
        guard let moves = json?["moves"] as? [String] else { return nil }
        return ApplyArgs(fen: fen, moves: moves)
    }

    /// 模型可能把数字写成字符串或浮点，都接住
    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    // MARK: - 局面校验

    /// FEN 是否为「棋盘 + 走子方」的合法形式
    static func isValidPositionFen(_ fen: String) -> Bool {
        let parts = fen.split(separator: " ")
        return XiangqiBoardUtils.isValidBoardFen(fen)
            && parts.count >= 2
            && ["r", "b", "w"].contains(String(parts[1]))
    }

    /// 由 fen 第二段推导走子方
    static func sideToMove(fen: String) -> String {
        let parts = fen.split(separator: " ")
        guard parts.count >= 2 else { return "red" }
        return String(parts[1]) == "b" ? "black" : "red"
    }

    // MARK: - 走子（纯函数，便于单测）

    struct AppliedMove: Equatable {
        let uci: String
        let chinese: String
        let fen: String
    }

    /// 把一串 UCI 着法依次应用到局面上。
    /// 只做机械移动（起点须有子），不校验象棋规则合法性。
    /// 返回成功应用的着法列表；failedIndex 指向首个无法应用的着法（全部成功则为 nil）
    static func applyUCIMoves(fen: String, uciMoves: [String]) -> (applied: [AppliedMove], failedIndex: Int?) {
        var currentFen = fen
        var applied: [AppliedMove] = []
        for (index, uci) in uciMoves.enumerated() {
            guard let nextFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: uci, fen: currentFen) else {
                return (applied, index)
            }
            let chinese = Move.stringifyMove(fen1: currentFen, fen2: nextFen, backup: uci, isHorizontalFlipped: false)
            applied.append(AppliedMove(uci: uci, chinese: chinese, fen: nextFen))
            currentFen = nextFen
        }
        return (applied, nil)
    }

    // MARK: - 着法解析

    /// 枚举当前走子方在该局面下的全部合法着法。
    ///
    /// `applyUCIMoves` 只做机械搬子、不问规则也不问归属，`getNewFenAfterUCIMove` 还会
    /// 按**被移动棋子的颜色**决定下一手轮谁走——两者叠加的后果是：在黑走的局面传一个
    /// 红方着法能「成功」执行，且走完之后仍然是黑走。评估着法时必须先过这一关。
    static func legalMoves(fen: String) -> [AppliedMove] {
        let pieces = XiangqiBoardUtils.fenToPiecesBySquare(fen)
        let redToMove = sideToMove(fen: fen) == "red"
        var result: [AppliedMove] = []

        for (square, piece) in pieces where piece.hasPrefix(redToMove ? "r" : "b") {
            for target in MoveRules.getLegalDestinationSquares(fromSquare: square, piecesBySquare: pieces) {
                let uci = square + target
                guard let nextFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: uci, fen: fen) else {
                    continue
                }
                let chinese = Move.stringifyMove(fen1: fen, fen2: nextFen, backup: uci,
                                                 isHorizontalFlipped: false)
                result.append(AppliedMove(uci: uci, chinese: chinese, fen: nextFen))
            }
        }
        return result.sorted { $0.uci < $1.uci }
    }

    /// 归一化着法文本，让中文着法的各种写法都能对上：
    /// 去空白、全角数字转半角、异体字统一
    static func normalizedMoveText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        // Move.stringifyMove 给黑方着法用全角数字（车９平６），模型多半打半角
        for (index, halfWidth) in "0123456789".enumerated() {
            let fullWidth = Character(UnicodeScalar(0xFF10 + index)!)
            result = result.replacingOccurrences(of: String(fullWidth), with: String(halfWidth))
        }
        // 中文数字与阿拉伯数字混用也接住
        let chineseDigits = ["一": "1", "二": "2", "三": "3", "四": "4", "五": "5",
                             "六": "6", "七": "7", "八": "8", "九": "9"]
        for (chinese, arabic) in chineseDigits {
            result = result.replacingOccurrences(of: chinese, with: arabic)
        }
        return result
    }

    enum MoveResolution {
        case resolved(AppliedMove)
        /// 着法能在棋盘上搬动，但属于对方——最隐蔽的一类错，必须单独报
        case notSideToMove(mover: String)
        case notLegal
        case ambiguous([AppliedMove])
    }

    /// 把 UCI 或中文着法解析成本局面下合法的一步。
    ///
    /// 支持中文是因为：用户问的是「炮八进五」，模型得自己换算成 UCI 才能调工具，
    /// 而这个换算（列的方向、红黑各自的路数、进退的正负）极易出错，
    /// 错了就变成在评估另一步棋，且表面上看不出来。
    static func resolveMove(_ input: String, fen: String) -> MoveResolution {
        let legal = legalMoves(fen: fen)
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = legal.first(where: { $0.uci.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .resolved(match)
        }

        let normalized = normalizedMoveText(trimmed)
        let chineseMatches = legal.filter { normalizedMoveText($0.chinese) == normalized }
        if chineseMatches.count == 1 { return .resolved(chineseMatches[0]) }
        if chineseMatches.count > 1 { return .ambiguous(chineseMatches) }

        // 走不了：分清是「对方的子」还是「这步本身不合规则」。
        // 前者说明模型把走子方搞反了，值得单独提示
        let pieces = XiangqiBoardUtils.fenToPiecesBySquare(fen)
        if trimmed.count == 4, let piece = pieces[String(trimmed.prefix(2))] {
            let pieceSide = piece.hasPrefix("r") ? "red" : "black"
            if pieceSide != sideToMove(fen: fen) {
                return .notSideToMove(mover: pieceSide)
            }
        }
        return .notLegal
    }

    /// 把 UCI 主变序列转成中文着法序列（逐步应用到局面上；遇到非法着法截断）
    static func chinesePV(fen: String, uciMoves: [String]) -> [String] {
        var currentFen = fen
        var result: [String] = []
        for uci in uciMoves {
            guard let nextFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: uci, fen: currentFen) else { break }
            result.append(Move.stringifyMove(fen1: currentFen, fen2: nextFen, backup: uci, isHorizontalFlipped: false))
            currentFen = nextFen
        }
        return result
    }

    // MARK: - 执行分发

    /// 描述某次工具调用正在做什么，供界面显示进度
    static func progressDescription(toolName: String, arguments: [String: Any]?) -> String {
        switch toolName {
        case "get_position":
            return "正在读取当前局面…"
        case "evaluate":
            return (arguments?["fen"] as? String)?.isEmpty == false
                ? "正在用引擎分析指定局面…"
                : "正在用引擎分析当前局面…"
        case "evaluate_move":
            // 这个工具要跑两次引擎，明说一下，免得用户以为卡住了
            let move = (arguments?["move"] as? String) ?? ""
            return move.isEmpty
                ? "正在评估这步棋（走前走后各分析一次）…"
                : "正在评估 \(move)（走前走后各分析一次）…"
        case "apply_moves":
            let count = (arguments?["moves"] as? [String])?.count ?? 0
            return count > 0 ? "正在把 \(count) 步着法走出来…" : "正在走子…"
        default:
            return "正在调用 \(toolName)…"
        }
    }

    /// 一次工具调用做出了什么，供界面在进度区留痕（「✓ 引擎分析当前局面 — 首选 炮八平七 +226」）。
    /// 解析失败或没什么可说的就返回 nil，界面只显示步骤名。
    static func resultSummary(toolName: String, resultJSON: String) -> String? {
        guard let json = parseArgumentsJSON(resultJSON) else { return nil }
        if let error = json["error"] as? [String: Any] {
            return "失败：\(error["message"] as? String ?? "未知错误")"
        }

        switch toolName {
        case "get_position":
            guard let step = json["step"] as? Int else { return nil }
            let side = (json["sideToMove"] as? String) == "black" ? "黑方" : "红方"
            let recorded = (json["nextMoves"] as? [String])?.count ?? 0
            let tail = recorded > 0 ? "，笔记本里已记录 \(recorded) 个后续着法" : ""
            return "第 \(step) 步，轮\(side)走\(tail)"

        case "evaluate":
            guard let lines = json["lines"] as? [[String: Any]], let best = lines.first else { return nil }
            let score = best["scoreCp"] as? Int
            let move = (best["pvChinese"] as? [String])?.first
            switch (move, score) {
            case let (move?, score?): return "\(lines.count) 条候选，首选 \(move) \(signed(score))"
            case let (nil, score?): return "\(lines.count) 条候选，最佳 \(signed(score))"
            default: return "\(lines.count) 条候选"
            }

        case "evaluate_move":
            guard let move = (json["move"] as? [String: Any])?["chinese"] as? String else { return nil }
            let loss = json["lossCp"] as? Int
            let rank = json["rankAmongCandidates"] as? Int
            let position = rank.map { "候选第 \($0)" } ?? "不在候选内"
            guard let loss else { return "\(move)：\(position)" }
            return loss > 0
                ? "\(move) 比最佳亏 \(loss) 厘兵（\(position)）"
                : "\(move)：\(position)，未亏分"

        case "apply_moves":
            guard let steps = json["steps"] as? [[String: Any]], !steps.isEmpty else { return nil }
            return steps.compactMap { $0["chinese"] as? String }.joined(separator: "、")

        default:
            return nil
        }
    }

    /// 引擎分带正负号显示，一眼能看出优劣方
    private static func signed(_ score: Int) -> String {
        score > 0 ? "+\(score)" : "\(score)"
    }

    /// 执行一次工具调用，返回给模型的 JSON 字符串。
    ///
    /// 任何失败都以 `{"ok":false,"error":{...}}` 返回而不是抛出：模型看到错误可以改参数
    /// 重试、换个思路或如实告诉用户，比中断整轮问答有用。
    @MainActor
    func execute(toolName: String, argumentsJSON: String) async -> String {
        let arguments = Self.parseArgumentsJSON(argumentsJSON)
        guard let host else {
            return Self.toolErrorJSON(.hostUnavailable, "界面已关闭，无法读取局面")
        }

        switch toolName {
        case "get_position":
            return Self.toolSuccessJSON(host.currentPositionSnapshot().toolDictionary())

        case "evaluate":
            let args = Self.parseEvalArgs(arguments)
            let fen = args.fen ?? host.currentPositionSnapshot().fen
            guard Self.isValidPositionFen(fen) else { return Self.invalidFenError() }
            do {
                let result = try await host.analyzePosition(
                    fen: fen, multiPV: args.multiPV, movetime: args.movetime)
                return Self.toolSuccessJSON([
                    "fen": fen,
                    "sideToMove": Self.sideToMove(fen: fen),
                    "scorePerspective": "sideToMove",
                    "engine": result.engine,
                    "movetimeMs": result.movetimeMs,
                    // 命中缓存时结果是秒回的，且可能来自另一台设备的引擎——
                    // 说清楚，免得模型把「这次没花时间」当成分析不够扎实
                    "cached": result.fromCache,
                    "lines": result.lines.map { Self.lineDictionary($0, fen: fen) },
                ])
            } catch {
                return Self.toolErrorJSON(forEngineError: error)
            }

        case "evaluate_move":
            return await executeEvaluateMove(arguments: arguments, host: host)

        case "apply_moves":
            guard let args = Self.parseApplyArgs(arguments) else {
                return Self.toolErrorJSON(
                    .badArguments, "参数不全，需要 fen（字符串）与 moves（UCI 着法字符串数组）")
            }
            guard Self.isValidPositionFen(args.fen) else { return Self.invalidFenError() }
            let result = Self.applyUCIMoves(fen: args.fen, uciMoves: args.moves)
            if let failedIndex = result.failedIndex {
                return Self.toolErrorJSON(
                    .illegalMove,
                    "第 \(failedIndex + 1) 步 \(args.moves[failedIndex]) 走不了（格式错误，或起点无子）")
            }
            return Self.toolSuccessJSON([
                "startFen": args.fen,
                "steps": result.applied.map { ["uci": $0.uci, "chinese": $0.chinese, "fen": $0.fen] },
                "finalFen": result.applied.last?.fen ?? args.fen,
            ])

        default:
            return Self.toolErrorJSON(.unknownTool, "未知工具 \(toolName)")
        }
    }

    private static func invalidFenError() -> String {
        toolErrorJSON(.fenInvalid, "FEN 格式不对，应为「棋盘 r|b」，例如 '.../RNBAKABNR r'")
    }

    /// 一条候选线路的返回形状，`evaluate` 与 `evaluate_move` 共用
    private static func lineDictionary(_ line: EnginePVLine, fen: String) -> [String: Any] {
        [
            "rank": line.multipv,
            "scoreCp": line.scoreCp,
            "mate": line.mate as Any? ?? NSNull(),
            "depth": line.depth as Any? ?? NSNull(),
            "pvUci": line.moves,
            "pvChinese": chinesePV(fen: fen, uciMoves: line.moves),
        ]
    }

    // MARK: - evaluate_move

    /// 把一条线路的分数从「该局面走子方视角」翻到对手视角（纯函数，便于单测）。
    ///
    /// 这个符号翻转是整套分析里最容易出错、错了又最致命的一步——搞反会把失着说成好棋，
    /// 而且理由编得头头是道。所以它必须在代码里做，不能留给模型心算。
    static func negatedScore(cp: Int, mate: Int?) -> (cp: Int, mate: Int?) {
        (-cp, mate.map { -$0 })
    }

    private static func scoreDictionary(cp: Int, mate: Int?) -> [String: Any] {
        ["cp": cp, "mate": mate as Any? ?? NSNull()]
    }

    @MainActor
    private func executeEvaluateMove(arguments: [String: Any]?, host: AnalysisToolHost) async -> String {
        let evalArgs = Self.parseEvalArgs(arguments)
        guard let move = (arguments?["move"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !move.isEmpty else {
            return Self.toolErrorJSON(.badArguments, "缺少 move 参数（UCI 着法，如 h2e2）")
        }

        let fen = evalArgs.fen ?? host.currentPositionSnapshot().fen
        guard Self.isValidPositionFen(fen) else { return Self.invalidFenError() }

        let mover = Self.sideToMove(fen: fen)
        let step: AppliedMove
        switch Self.resolveMove(move, fen: fen) {
        case .resolved(let resolved):
            step = resolved
        case .notSideToMove(let pieceSide):
            // 最隐蔽的一类错：着法能在棋盘上搬动，但走的是对方的子。
            // 不拦住的话分数会全部锚错方，结论正好反过来
            let side = pieceSide == "red" ? "红方" : "黑方"
            let current = mover == "red" ? "红方" : "黑方"
            return Self.toolErrorJSON(
                .illegalMove,
                "\(move) 走的是\(side)的子，但当前局面轮\(current)走。"
                    + "若要评估\(side)的着法，请先把\(current)的应手走出来（apply_moves），再对新局面评估。")
        case .ambiguous(let candidates):
            return Self.toolErrorJSON(
                .badArguments,
                "\(move) 有歧义，可能是：" + candidates.map(\.uci).joined(separator: "、")
                    + "。请改用 UCI 着法指明。")
        case .notLegal:
            return Self.toolErrorJSON(
                .illegalMove, "\(move) 在这个局面下不是合法着法（可用 UCI 或中文着法，如 h2e2 或 炮二平五）")
        }
        do {
            // 走之前：mover 走最好棋能得到什么
            let before = try await host.analyzePosition(
                fen: fen, multiPV: evalArgs.multiPV, movetime: evalArgs.movetime)
            // 走之后：轮对手，分数天然是对手视角
            let after = try await host.analyzePosition(
                fen: step.fen, multiPV: min(evalArgs.multiPV, 3), movetime: evalArgs.movetime)

            guard let best = before.lines.first, let reply = after.lines.first else {
                return Self.toolErrorJSON(.engineUnavailable, "引擎没有给出候选线路")
            }

            // 统一锚定到 mover 视角：本工具返回的每一个分数都是「对 mover 而言」，
            // 模型完全不需要再做符号运算
            let scoreAfter = Self.negatedScore(cp: reply.scoreCp, mate: reply.mate)
            // 按解析出的 UCI 比对，而不是模型传进来的原文——传中文时对不上
            let rank = before.lines.first { $0.moves.first == step.uci }?.multipv

            // 对手线路的分数同样翻到 mover 视角，全表一个口径
            let replies: [[String: Any]] = after.lines.map { line in
                let negated = Self.negatedScore(cp: line.scoreCp, mate: line.mate)
                return [
                    "rank": line.multipv,
                    "scoreCp": negated.cp,
                    "mate": negated.mate as Any? ?? NSNull(),
                    "depth": line.depth as Any? ?? NSNull(),
                    "pvUci": line.moves,
                    "pvChinese": Self.chinesePV(fen: step.fen, uciMoves: line.moves),
                ]
            }

            var payload: [String: Any] = [
                "mover": mover,
                "scorePerspective": "mover",
                "scoreUnit": "centipawn",
                "engine": before.engine,
                "movetimeMs": before.movetimeMs,
                // 两轮里只要有一轮是取的缓存就算命中——用来解释这次为什么快
                "cached": before.fromCache || after.fromCache,
                "fen": fen,
                "fenAfter": step.fen,
            ]
            payload["move"] = ["uci": step.uci, "chinese": step.chinese]
            payload["scoreBefore"] = Self.scoreDictionary(cp: best.scoreCp, mate: best.mate)
            payload["scoreAfter"] = Self.scoreDictionary(cp: scoreAfter.cp, mate: scoreAfter.mate)
            // 正数表示这步比走最佳亏了多少厘兵；涉及杀棋时看 mate 字段更靠谱
            payload["lossCp"] = best.scoreCp - scoreAfter.cp
            // null 表示这步连引擎候选前 N 名都没进——本身就是它不好的强信号
            payload["rankAmongCandidates"] = rank as Any? ?? NSNull()
            payload["bestInstead"] = Self.lineDictionary(best, fen: fen)
            payload["opponentBestReplies"] = replies
            return Self.toolSuccessJSON(payload)
        } catch {
            return Self.toolErrorJSON(forEngineError: error)
        }
    }

    // MARK: - JSON 工具

    /// 模型返回的 arguments 是 JSON 字符串；空串按无参数处理
    static func parseArgumentsJSON(_ raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// 排序输出键，让返回值稳定可测
    static func json(_ dictionary: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"error":"序列化失败"}"#
        }
        return text
    }

    /// 远程 `/state`、`/eval`、`/apply` 的错误体。
    ///
    /// **必须保持 `{"error": "字符串"}` 这个形状**——`mcp/xiangqi-notebook-mcp.mjs`
    /// 读的是 `JSON.parse(text).error` 并当字符串用（见其第 72 行）。工具层给模型的
    /// 错误是另一套结构（`toolErrorJSON`），两者不能合并。
    static func errorJSON(_ message: String) -> String {
        json(["error": message])
    }

    // MARK: - 工具层错误

    /// 给模型的错误分类。有了 code，模型能可靠分支——引擎忙就等一等重试、
    /// 着法非法就换一步、FEN 不对就重新 get_position——而不是去猜中文措辞。
    enum ToolErrorCode: String {
        case engineBusy = "ENGINE_BUSY"
        case engineUnavailable = "ENGINE_UNAVAILABLE"
        case fenInvalid = "FEN_INVALID"
        case illegalMove = "ILLEGAL_MOVE"
        case badArguments = "BAD_ARGUMENTS"
        case unknownTool = "UNKNOWN_TOOL"
        case hostUnavailable = "HOST_UNAVAILABLE"
    }

    static func toolErrorJSON(_ code: ToolErrorCode, _ message: String) -> String {
        json(["ok": false, "error": ["code": code.rawValue, "message": message]])
    }

    /// 成功返回统一带 `ok: true`，让模型只看一个字段就能分支
    static func toolSuccessJSON(_ payload: [String: Any]) -> String {
        var dictionary = payload
        dictionary["ok"] = true
        return json(dictionary)
    }

    /// 把引擎抛出的错误映射到错误码。忙碌与不可用要分开——前者值得重试，后者不值得
    static func toolErrorJSON(forEngineError error: Error) -> String {
        #if os(macOS) || os(iOS)
        if let analyzeError = error as? ViewModel.RemoteAnalyzeError {
            switch analyzeError {
            case .engineBusy:
                return toolErrorJSON(.engineBusy, analyzeError.localizedDescription)
            case .engineUnavailable:
                return toolErrorJSON(.engineUnavailable, analyzeError.localizedDescription)
            }
        }
        #endif
        return toolErrorJSON(.engineUnavailable, error.localizedDescription)
    }
}
