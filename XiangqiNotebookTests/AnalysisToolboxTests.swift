import Testing
import Foundation
@testable import XiangqiNotebook

/// AI 问棋工具层的纯逻辑测试。
/// 跨平台编译——这一层本身就是为了三端共用而抽出来的。
struct AnalysisToolboxTests {

    private let startFen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"

    // MARK: - 工具定义

    @Test func testToolSpecs_exposesFourTools() throws {
        let specs = AnalysisToolbox.toolSpecs
        let names = specs.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        #expect(names == ["get_position", "evaluate", "evaluate_move", "apply_moves"])
        // 每个都必须是 OpenAI function calling 的形状，否则模型侧直接报错
        #expect(specs.allSatisfy { $0["type"] as? String == "function" })
    }

    @Test func testToolSpecs_evaluateMoveRequiresOnlyMove() throws {
        // fen 可省（默认当前局面），move 不可省
        let spec = try #require(AnalysisToolbox.toolSpecs.first {
            ($0["function"] as? [String: Any])?["name"] as? String == "evaluate_move"
        })
        let function = try #require(spec["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["required"] as? [String] == ["move"])
    }

    @Test func testToolSpecs_isJSONSerializable() throws {
        // 会被塞进请求体，含不可序列化的值会在运行时才炸
        let data = try JSONSerialization.data(withJSONObject: AnalysisToolbox.toolSpecs)
        #expect(!data.isEmpty)
    }

    @Test func testToolSpecs_applyMovesRequiresFenAndMoves() throws {
        let applyMoves = try #require(AnalysisToolbox.toolSpecs.first {
            ($0["function"] as? [String: Any])?["name"] as? String == "apply_moves"
        })
        let function = try #require(applyMoves["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect(parameters["required"] as? [String] == ["fen", "moves"])
    }

    @Test func testToolSpecs_getPositionTakesNoArguments() throws {
        let getPosition = try #require(AnalysisToolbox.toolSpecs.first {
            ($0["function"] as? [String: Any])?["name"] as? String == "get_position"
        })
        let function = try #require(getPosition["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        #expect((parameters["properties"] as? [String: Any])?.isEmpty == true)
        #expect((parameters["required"] as? [String])?.isEmpty == true)
    }

    // MARK: - evaluate 参数解析

    @Test func testParseEvalArgs_defaults() {
        let args = AnalysisToolbox.parseEvalArgs(nil)
        #expect(args.fen == nil)
        #expect(args.multiPV == AnalysisToolbox.defaultMultiPV)
        #expect(args.movetime == AnalysisToolbox.defaultMovetime)
    }

    @Test func testParseEvalArgs_readsProvidedValues() {
        let args = AnalysisToolbox.parseEvalArgs([
            "fen": startFen, "multipv": 5, "movetime_ms": 2000,
        ])
        #expect(args.fen == startFen)
        #expect(args.multiPV == 5)
        #expect(args.movetime == 2000)
    }

    @Test func testParseEvalArgs_clampsOutOfRange() {
        let low = AnalysisToolbox.parseEvalArgs(["multipv": 0, "movetime_ms": 1])
        #expect(low.multiPV == AnalysisToolbox.multiPVRange.lowerBound)
        #expect(low.movetime == AnalysisToolbox.movetimeRange.lowerBound)

        let high = AnalysisToolbox.parseEvalArgs(["multipv": 99, "movetime_ms": 999_999])
        #expect(high.multiPV == AnalysisToolbox.multiPVRange.upperBound)
        #expect(high.movetime == AnalysisToolbox.movetimeRange.upperBound)
    }

    @Test func testParseEvalArgs_coercesStringAndDoubleNumbers() {
        // 模型把数字写成字符串或浮点是常态，不该因此退回默认值
        let args = AnalysisToolbox.parseEvalArgs(["multipv": "5", "movetime_ms": 2000.0])
        #expect(args.multiPV == 5)
        #expect(args.movetime == 2000)
    }

    @Test func testParseEvalArgs_acceptsMovetimeAlias() {
        // 工具 schema 写的是 movetime_ms，但模型常按远程接口的习惯写成 movetime
        let args = AnalysisToolbox.parseEvalArgs(["movetime": 2000])
        #expect(args.movetime == 2000)
    }

    @Test func testParseEvalArgs_treatsEmptyFenAsAbsent() {
        // 空串要落到「分析当前局面」，不能当成一个非法 FEN 去校验
        #expect(AnalysisToolbox.parseEvalArgs(["fen": ""]).fen == nil)
    }

    // MARK: - apply_moves 参数解析

    @Test func testParseApplyArgs_readsProvidedValues() throws {
        let args = try #require(AnalysisToolbox.parseApplyArgs([
            "fen": startFen, "moves": ["h2e2", "h9g7"],
        ]))
        #expect(args.fen == startFen)
        #expect(args.moves == ["h2e2", "h9g7"])
    }

    @Test func testParseApplyArgs_rejectsMissingOrEmptyFields() {
        #expect(AnalysisToolbox.parseApplyArgs(nil) == nil)
        #expect(AnalysisToolbox.parseApplyArgs(["moves": ["h2e2"]]) == nil)
        #expect(AnalysisToolbox.parseApplyArgs(["fen": startFen]) == nil)
        #expect(AnalysisToolbox.parseApplyArgs(["fen": "", "moves": ["h2e2"]]) == nil)
    }

    // MARK: - 局面校验

    private let startFenBlackToMove = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR b"

    @Test func testIsValidPositionFen() {
        #expect(AnalysisToolbox.isValidPositionFen(startFen))
        #expect(AnalysisToolbox.isValidPositionFen(startFenBlackToMove))
        // 缺走子方
        #expect(!AnalysisToolbox.isValidPositionFen("rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR"))
        #expect(!AnalysisToolbox.isValidPositionFen("garbage r"))
        #expect(!AnalysisToolbox.isValidPositionFen(""))
    }

    @Test func testSideToMove() {
        #expect(AnalysisToolbox.sideToMove(fen: startFen) == "red")
        #expect(AnalysisToolbox.sideToMove(fen: startFenBlackToMove) == "black")
        // 缺走子方时兜底为红，不崩
        #expect(AnalysisToolbox.sideToMove(fen: "rnbakabnr") == "red")
    }

    // MARK: - JSON

    @Test func testParseArgumentsJSON() {
        #expect(AnalysisToolbox.parseArgumentsJSON("") == nil)
        #expect(AnalysisToolbox.parseArgumentsJSON("   ") == nil)
        #expect(AnalysisToolbox.parseArgumentsJSON("not json") == nil)
        let parsed = AnalysisToolbox.parseArgumentsJSON(#"{"multipv": 5}"#)
        #expect(parsed?["multipv"] as? Int == 5)
    }

    @Test func testJSON_escapesControlCharacters() throws {
        // 旧的手写转义只处理 \n \r \t，注释里含别的控制字符会产出非法 JSON。
        // 换 JSONSerialization 顺带修掉了这个坑，这里锁住它。
        let text = "退\u{0008}半步\u{000B}再说"
        let encoded = AnalysisToolbox.json(["comment": text])
        let data = try #require(encoded.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["comment"] as? String == text)
    }

    @Test func testJSON_sortsKeysForStableOutput() {
        #expect(AnalysisToolbox.json(["b": 1, "a": 2]) == #"{"a":2,"b":1}"#)
    }

    // MARK: - 局面快照

    private func snapshot(fen: String, comment: String? = nil,
                          badReason: String? = nil,
                          lastMove: LastMove? = nil) -> PositionSnapshot {
        PositionSnapshot(
            fen: fen, displayFen: fen, mode: "normal", step: 3, maxStep: 20,
            orientation: "red", isHorizontalFlipped: false,
            comment: comment, moveComment: nil, badReason: badReason, lastMove: lastMove,
            score: "12", engineScore: "34",
            showPath: true, showAllNextMoves: false, showLastMove: true,
            isLocked: false, isBookmarked: true, isInReview: false,
            filters: ["先手开局"], nextMoves: ["炮二平五"], variants: ["马八进七"],
            windowTitle: "象棋笔记本"
        )
    }

    @Test func testSnapshot_toolDictionaryOmitsUIState() {
        let dict = snapshot(fen: startFen).toolDictionary()
        #expect(dict["fen"] as? String == startFen)
        #expect(dict["sideToMove"] as? String == "red")
        #expect(dict["nextMoves"] as? [String] == ["炮二平五"])
        // UI 开关对讲解无用，不该出现在给模型的上下文里
        for uiKey in ["showPath", "isLocked", "windowTitle", "orientation", "filters"] {
            #expect(dict[uiKey] == nil, "\(uiKey) 不该出现在工具返回值里")
        }
    }

    @Test func testSnapshot_remoteStateDictionaryKeepsExistingContract() {
        // MCP 依赖这组字段，少一个都会让外部 Claude 拿不到信息
        let dict = snapshot(fen: startFen).remoteStateDictionary()
        let expected = [
            "fen", "displayFen", "mode", "step", "maxStep", "orientation",
            "isHorizontalFlipped", "comment", "moveComment", "score", "engineScore",
            "showPath", "showAllNextMoves", "showLastMove", "isLocked",
            "isBookmarked", "isInReview", "filters", "nextMoves", "variants", "windowTitle",
        ]
        #expect(Set(dict.keys) == Set(expected))
    }

    @Test func testSnapshot_toolDictionaryCarriesLastMove() throws {
        // 「这一步为什么不好」全靠这两个字段：走完之后 fen 已经是新局面，
        // 没有 fenBefore 模型只能去评估对方的下一手，答非所问
        let dict = snapshot(fen: startFen,
                            lastMove: LastMove(chinese: "炮8进5", fenBefore: "before-fen"))
            .toolDictionary()
        let lastMove = try #require(dict["lastMove"] as? [String: String])
        #expect(lastMove["chinese"] == "炮8进5")
        #expect(lastMove["fenBefore"] == "before-fen")
    }

    @Test func testSnapshot_toolDictionaryCarriesBadReason() {
        let dict = snapshot(fen: startFen, badReason: "没有强制手").toolDictionary()
        #expect(dict["badReason"] as? String == "没有强制手")
    }

    @Test func testSnapshot_nilLastMoveSerializesAsJSONNull() throws {
        // 停在起始局面时必须是 null，不能是空对象——
        // 空对象会让模型以为有上一步，去评估一个不存在的着法
        let encoded = AnalysisToolbox.json(snapshot(fen: startFen).toolDictionary())
        let data = try #require(encoded.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["lastMove"] is NSNull)
        #expect(decoded?["badReason"] is NSNull)
    }

    @Test func testSnapshot_nilCommentSerializesAsJSONNull() throws {
        let encoded = AnalysisToolbox.json(snapshot(fen: startFen, comment: nil).toolDictionary())
        let data = try #require(encoded.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["comment"] is NSNull)
    }

    // MARK: - 走子

    @Test func testApplyUCIMoves_appliesSequence() {
        let result = AnalysisToolbox.applyUCIMoves(fen: startFen, uciMoves: ["h2e2", "h9g7"])
        #expect(result.failedIndex == nil)
        #expect(result.applied.map(\.chinese) == ["炮二平五", "马８进７"])
        #expect(result.applied.last?.fen.hasSuffix(" r") == true)
    }

    @Test func testApplyUCIMoves_reportsFailedIndex() {
        // 第二着起点无子
        let result = AnalysisToolbox.applyUCIMoves(fen: startFen, uciMoves: ["h2e2", "e5e4", "h9g7"])
        #expect(result.failedIndex == 1)
        #expect(result.applied.count == 1)
    }

    @Test func testChinesePV_truncatesAtInvalidMove() {
        #expect(AnalysisToolbox.chinesePV(fen: startFen, uciMoves: ["h2e2", "e5e4"]) == ["炮二平五"])
    }

    // MARK: - 着法解析与归属校验

    @Test func testLegalMoves_onlyForSideToMove() {
        let redMoves = AnalysisToolbox.legalMoves(fen: startFen)
        #expect(!redMoves.isEmpty)
        // 开局红方合法着法数是定值，多了少了都说明枚举有问题
        #expect(redMoves.count == 44)

        // 起点必须都是红子
        let pieces = XiangqiBoardUtils.fenToPiecesBySquare(startFen)
        for move in redMoves {
            let from = String(move.uci.prefix(2))
            #expect(pieces[from]?.hasPrefix("r") == true, "\(move.uci) 的起点不是红子")
        }
    }

    @Test func testResolveMove_acceptsUCI() {
        guard case .resolved(let move) = AnalysisToolbox.resolveMove("h2e2", fen: startFen) else {
            Issue.record("h2e2 应能解析")
            return
        }
        #expect(move.uci == "h2e2")
        #expect(move.chinese == "炮二平五")
    }

    @Test func testResolveMove_acceptsChinese() {
        // 让模型传中文，省得它自己换算坐标——换算错了等于评了另一步棋，还看不出来
        guard case .resolved(let move) = AnalysisToolbox.resolveMove("炮二平五", fen: startFen) else {
            Issue.record("炮二平五 应能解析")
            return
        }
        #expect(move.uci == "h2e2")
    }

    @Test func testResolveMove_acceptsChineseWithDigitVariants() {
        // 全角、半角、中文数字混写都要接住
        for text in ["炮二平五", "炮2平5", "炮２平５"] {
            guard case .resolved(let move) = AnalysisToolbox.resolveMove(text, fen: startFen) else {
                Issue.record("\(text) 应能解析")
                continue
            }
            #expect(move.uci == "h2e2", "\(text) 解析错了")
        }
    }

    @Test func testResolveMove_rejectsOpponentPiece() {
        // 这是最隐蔽的一类错，也是实测撞到的那个：
        // applyUCIMoves 只机械搬子不问归属，getNewFenAfterUCIMove 又按棋子颜色定下一手，
        // 于是黑走局面挪红子能「成功」且走子方不翻转，分数全部锚错方、结论正好反过来
        let blackToMove = startFen.replacingOccurrences(of: "RNBAKABNR r", with: "RNBAKABNR b")
        guard case .notSideToMove(let side) = AnalysisToolbox.resolveMove("h2e2", fen: blackToMove) else {
            Issue.record("黑走局面下红方着法必须被拒")
            return
        }
        #expect(side == "red")
    }

    @Test func testResolveMove_rejectsRuleViolatingMove() {
        // 起点有子但走法不合规则（帅横跨半个棋盘），applyUCIMoves 会照搬，这里必须拦下
        guard case .notLegal = AnalysisToolbox.resolveMove("e0a5", fen: startFen) else {
            Issue.record("不合规则的着法必须被拒")
            return
        }
    }

    @Test func testResolveMove_rejectsEmptySource() {
        guard case .notLegal = AnalysisToolbox.resolveMove("e5e4", fen: startFen) else {
            Issue.record("起点无子必须被拒")
            return
        }
    }

    @Test func testResolveMove_resolvedMoveFlipsSideToMove() {
        // 校验通过后走子方必须翻转——这正是原来出错的地方
        guard case .resolved(let move) = AnalysisToolbox.resolveMove("炮二平五", fen: startFen) else {
            Issue.record("应能解析")
            return
        }
        #expect(AnalysisToolbox.sideToMove(fen: startFen) == "red")
        #expect(AnalysisToolbox.sideToMove(fen: move.fen) == "black")
    }

    // MARK: - 记谱规范

    /// 路数各数各的：都从自己这一方的右手边数起，同一列红黑两个数相加为 10。
    /// 且红方用中文数字、黑方用阿拉伯数字。
    /// `AIChatPrompt` 里给模型的对照表就是照这套写的——这里叫错，模型的讲解会整体叫错子
    @Test func testChineseNotation_filesAreNumberedPerSide() {
        // h 列：红方数作二路，黑方数作 8 路
        let red = AnalysisToolbox.applyUCIMoves(fen: startFen, uciMoves: ["h2e2"]).applied
        #expect(red.first?.chinese == "炮二平五")

        let blackToMove = startFen.replacingOccurrences(of: "RNBAKABNR r", with: "RNBAKABNR b")
        let black = AnalysisToolbox.applyUCIMoves(fen: blackToMove, uciMoves: ["h7e7"]).applied
        #expect(black.first?.chinese == "炮８平５")

        // b 列反过来：红方八路、黑方 2 路
        #expect(AnalysisToolbox.applyUCIMoves(fen: startFen, uciMoves: ["b0c2"])
            .applied.first?.chinese == "马八进七")
        #expect(AnalysisToolbox.applyUCIMoves(fen: blackToMove, uciMoves: ["b9c7"])
            .applied.first?.chinese == "马２进３")
    }

    @Test func testNormalizedMoveText() {
        #expect(AnalysisToolbox.normalizedMoveText(" 车９平６ ") == "车9平6")
        #expect(AnalysisToolbox.normalizedMoveText("炮二平五") == "炮2平5")
        #expect(AnalysisToolbox.normalizedMoveText("马 8 进 7") == "马8进7")
    }

    // MARK: - 视角换算

    @Test func testNegatedScore_flipsBothCpAndMate() {
        // 整套分析里最容易错、错了最致命的一步：符号翻转。
        // 搞反会把失着说成好棋，理由还编得头头是道
        let flipped = AnalysisToolbox.negatedScore(cp: 226, mate: nil)
        #expect(flipped.cp == -226)
        #expect(flipped.mate == nil)

        // 「我 3 步成杀」翻到对手视角是「对手 3 步被杀」
        let mateFlipped = AnalysisToolbox.negatedScore(cp: 29997, mate: 3)
        #expect(mateFlipped.cp == -29997)
        #expect(mateFlipped.mate == -3)

        // 被杀翻过来是成杀
        #expect(AnalysisToolbox.negatedScore(cp: -29998, mate: -2).mate == 2)
    }

    @Test func testNegatedScore_isInvolutive() {
        // 翻两次必须回到原值，否则来回换算会漂移
        let original = (cp: 137, mate: Int?.none)
        let twice = AnalysisToolbox.negatedScore(
            cp: AnalysisToolbox.negatedScore(cp: original.cp, mate: original.mate).cp,
            mate: AnalysisToolbox.negatedScore(cp: original.cp, mate: original.mate).mate)
        #expect(twice.cp == original.cp)
        #expect(twice.mate == original.mate)
    }

    @Test func testNegatedScore_zeroStaysZero() {
        // 均势不该因为换算变成 -0 之类的怪值
        #expect(AnalysisToolbox.negatedScore(cp: 0, mate: nil).cp == 0)
    }

    // MARK: - 结构化错误

    @Test func testToolErrorJSON_carriesCodeAndMessage() throws {
        let encoded = AnalysisToolbox.toolErrorJSON(.engineBusy, "引擎忙碌中")
        let data = try #require(encoded.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(decoded["ok"] as? Bool == false)
        let error = try #require(decoded["error"] as? [String: Any])
        // code 是给模型分支用的：忙碌值得重试，不可用不值得
        #expect(error["code"] as? String == "ENGINE_BUSY")
        #expect(error["message"] as? String == "引擎忙碌中")
    }

    @Test func testToolSuccessJSON_alwaysCarriesOkTrue() throws {
        let encoded = AnalysisToolbox.toolSuccessJSON(["fen": startFen])
        let data = try #require(encoded.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["ok"] as? Bool == true)
        #expect(decoded["fen"] as? String == startFen)
    }

    @Test func testRemoteErrorJSON_staysAFlatStringForMCP() throws {
        // mcp/xiangqi-notebook-mcp.mjs 读的是 JSON.parse(text).error 并当字符串用。
        // 这里若跟着工具层改成对象，MCP 那条路会静默拿到 [object Object]
        let encoded = AnalysisToolbox.errorJSON("引擎忙碌中")
        let data = try #require(encoded.data(using: .utf8))
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["error"] as? String == "引擎忙碌中")
        #expect(decoded["ok"] == nil)
    }

    // MARK: - 进度文案

    @Test func testProgressDescription_distinguishesToolsAndFallsBack() {
        #expect(AnalysisToolbox.progressDescription(toolName: "get_position", arguments: nil)
                == "正在读取当前局面…")
        #expect(AnalysisToolbox.progressDescription(toolName: "evaluate", arguments: nil)
                == "正在用引擎分析当前局面…")
        #expect(AnalysisToolbox.progressDescription(toolName: "evaluate", arguments: ["fen": startFen])
                == "正在用引擎分析指定局面…")
        #expect(AnalysisToolbox.progressDescription(toolName: "apply_moves",
                                                   arguments: ["moves": ["h2e2", "h9g7"]])
                == "正在把 2 步着法走出来…")
        // 未知工具也要有话说，不能空着
        #expect(!AnalysisToolbox.progressDescription(toolName: "whatever", arguments: nil).isEmpty)
    }

    @Test func testProgressDescription_evaluateMoveWarnsAboutTwoRuns() {
        // 这个工具跑两次引擎，界面要明说，否则用户以为卡住了
        let text = AnalysisToolbox.progressDescription(
            toolName: "evaluate_move", arguments: ["move": "h2e2"])
        #expect(text.contains("h2e2"))
        #expect(text.contains("两次") || text.contains("走前走后"))
    }

    @Test func testResultSummary_readsStructuredError() {
        // 错误结构变成对象后，摘要要还能读出 message
        let summary = AnalysisToolbox.resultSummary(
            toolName: "evaluate",
            resultJSON: AnalysisToolbox.toolErrorJSON(.engineBusy, "引擎忙碌中"))
        #expect(summary == "失败：引擎忙碌中")
    }

    @Test func testResultSummary_evaluateMoveReportsLossAndRank() {
        let json = AnalysisToolbox.toolSuccessJSON([
            "move": ["uci": "h2e2", "chinese": "炮二平五"],
            "lossCp": 226,
            "rankAmongCandidates": NSNull(),
        ])
        let summary = AnalysisToolbox.resultSummary(toolName: "evaluate_move", resultJSON: json)
        #expect(summary?.contains("炮二平五") == true)
        #expect(summary?.contains("226") == true)
        // 不在候选内本身就是强信号，摘要里要看得见
        #expect(summary?.contains("不在候选内") == true)
    }
}
