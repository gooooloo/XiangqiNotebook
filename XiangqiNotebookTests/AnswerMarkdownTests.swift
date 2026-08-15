import Testing
import Foundation
@testable import XiangqiNotebook

/// AI 回答的 Markdown 处理测试。
///
/// 两个方向都要覆盖：渲染方向拆错块只是排版难看，而剥离方向漏了标记会把 `**` 一路写进
/// 用户的局面注释里——那是持久化的脏数据，比显示问题严重。
struct AnswerMarkdownTests {

    // MARK: - 拆块

    @Test func testBlocks_splitsParagraphsOnBlankLines() {
        let blocks = AnswerMarkdown.blocks("第一段。\n\n第二段。")
        #expect(blocks == [.paragraph("第一段。"), .paragraph("第二段。")])
    }

    @Test func testBlocks_joinsConsecutiveLinesIntoOneParagraph() {
        let blocks = AnswerMarkdown.blocks("上半句\n下半句\n\n另一段")
        #expect(blocks == [.paragraph("上半句\n下半句"), .paragraph("另一段")])
    }

    @Test func testBlocks_readsHeadingsAtAnyLevel() {
        #expect(AnswerMarkdown.blocks("# 结论") == [.heading("结论")])
        #expect(AnswerMarkdown.blocks("### 变化分析") == [.heading("变化分析")])
    }

    @Test func testBlocks_hashWithoutSpaceIsNotAHeading() {
        // 「#5」这种写法不该被当标题吃掉井号
        #expect(AnswerMarkdown.blocks("#5 号变化") == [.paragraph("#5 号变化")])
    }

    @Test func testBlocks_readsBulletMarkers() {
        for marker in ["-", "*", "+", "•"] {
            #expect(AnswerMarkdown.blocks("\(marker) 要点") == [.bullet("要点")],
                    "\(marker) 应识别为列表项")
        }
    }

    @Test func testBlocks_readsOrderedItems() {
        #expect(AnswerMarkdown.blocks("1. 先手") == [.ordered(number: 1, text: "先手")])
        // 中文习惯的顿号写法
        #expect(AnswerMarkdown.blocks("2、再看变化") == [.ordered(number: 2, text: "再看变化")])
    }

    @Test func testBlocks_plainNumberIsNotAnOrderedItem() {
        // 讲解里满是「300 分以上是胜势」这种句子，不能被误判成编号列表
        #expect(AnswerMarkdown.blocks("300 分以上是胜势") == [.paragraph("300 分以上是胜势")])
        #expect(AnswerMarkdown.blocks("8路炮沉底") == [.paragraph("8路炮沉底")])
    }

    @Test func testBlocks_mixedDocumentKeepsOrder() {
        let markdown = """
        ## 结论

        **炮8进5 是失着。**

        - 没有形成强制手
        - 把先手交了出去

        引擎首选是马2进1。
        """
        #expect(AnswerMarkdown.blocks(markdown) == [
            .heading("结论"),
            .paragraph("**炮8进5 是失着。**"),
            .bullet("没有形成强制手"),
            .bullet("把先手交了出去"),
            .paragraph("引擎首选是马2进1。"),
        ])
    }

    @Test func testBlocks_emptyInputYieldsNothing() {
        #expect(AnswerMarkdown.blocks("").isEmpty)
        #expect(AnswerMarkdown.blocks("\n\n  \n").isEmpty)
    }

    // MARK: - 行内标记

    @Test func testInline_stripsMarkersFromCharacters() {
        #expect(String(AnswerMarkdown.inline("**炮8进5** 是失着").characters) == "炮8进5 是失着")
        #expect(String(AnswerMarkdown.inline("*略优*").characters) == "略优")
        #expect(String(AnswerMarkdown.inline("`h2e2`").characters) == "h2e2")
    }

    @Test func testInline_survivesBrokenMarkup() {
        // 标记残缺时宁可原样显示，也不能让整段回答消失
        let text = "未闭合的 **加粗"
        #expect(!String(AnswerMarkdown.inline(text).characters).isEmpty)
    }

    // MARK: - 剥成纯文本（存为局面注释走这条路）

    @Test func testPlainText_removesEmphasisMarkers() {
        #expect(AnswerMarkdown.plainText("**炮8进5** 是失着。") == "炮8进5 是失着。")
    }

    @Test func testPlainText_removesHeadingHashes() {
        #expect(AnswerMarkdown.plainText("## 结论\n\n正文") == "结论\n\n正文")
    }

    @Test func testPlainText_keepsListsReadable() {
        // 前缀不能全去掉：几条并列要点糊成一段反而更难读
        let result = AnswerMarkdown.plainText("- 第一条\n- 第二条")
        #expect(result == "· 第一条\n· 第二条")
    }

    @Test func testPlainText_separatesListFromSurroundingBlocks() {
        let result = AnswerMarkdown.plainText("开头\n\n- 甲\n- 乙\n\n结尾")
        #expect(result == "开头\n\n· 甲\n· 乙\n\n结尾")
    }

    @Test func testPlainText_keepsOrderedNumbers() {
        #expect(AnswerMarkdown.plainText("1. 先手\n2. 再看") == "1. 先手\n2. 再看")
    }

    @Test func testPlainText_leavesNoMarkdownSyntaxBehind() {
        // 存进注释的东西必须干净——这是持久化数据，脏了要用户手工改
        let markdown = """
        ## 结论

        **炮8进5** 亏了 *61* 分，见 `h7h2`。

        - 没有强制手
        1. 先出子
        """
        let plain = AnswerMarkdown.plainText(markdown)
        #expect(!plain.contains("**"))
        #expect(!plain.contains("##"))
        #expect(!plain.contains("`"))
        #expect(plain.contains("炮8进5"))
        #expect(plain.contains("61"))
        #expect(plain.contains("h7h2"))
    }

    @Test func testPlainText_passesThroughPlainAnswer() {
        // 模型不写 markdown 时，结果应与原文一致（除了段落归一化）
        let text = "炮8进5 不好，主要不是炮会立刻丢掉。\n\n红方最有力的是炮八退一。"
        #expect(AnswerMarkdown.plainText(text) == text)
    }
}
