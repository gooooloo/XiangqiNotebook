import Foundation

/// AI 回答的极简 Markdown 处理。
///
/// 只覆盖讲解真正用得上的那几样：标题、无序 / 有序列表、行内加粗斜体与代码、空行分段。
/// 表格、代码块、链接、引用块一概不认——`AIChatPrompt` 里也明确要求模型别写。
/// 不引第三方 Markdown 库：项目一贯零依赖，而完整语法在这里纯属负担。
///
/// 放在 Models 层是因为有两个消费方，方向正好相反：
/// - 界面按块渲染，让结论和要点一眼能看见；
/// - 「存为局面注释」反过来把标记剥干净——注释区是纯文本，`**` 进去只是噪音。
enum AnswerMarkdown {

    enum Block: Equatable {
        case heading(String)
        case bullet(String)
        case ordered(number: Int, text: String)
        case paragraph(String)
    }

    // MARK: - 拆块

    static func blocks(_ markdown: String) -> [Block] {
        var result: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if let heading = headingText(line) {
                flushParagraph()
                result.append(.heading(heading))
            } else if let bullet = bulletText(line) {
                flushParagraph()
                result.append(.bullet(bullet))
            } else if let item = orderedItem(line) {
                flushParagraph()
                result.append(.ordered(number: item.number, text: item.text))
            } else {
                paragraphLines.append(line)
            }
        }
        flushParagraph()
        return result
    }

    /// `#` 到 `######`。层级不保留：讲解里的标题一律排成同一级，
    /// 一个对话气泡里分不出六层，留着只会诱导模型堆标题
    private static func headingText(_ line: String) -> String? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 {
            level += 1
            rest = rest.dropFirst()
        }
        guard level > 0, rest.first == " " else { return nil }
        return String(rest.drop(while: { $0 == " " }))
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// `1. ` 与中文习惯的 `1、`。
    /// 必须带分隔符才算列表项，否则「300 分以上是胜势」这种正文会被误判成编号
    private static func orderedItem(_ line: String) -> (number: Int, text: String)? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 2, let number = Int(digits) else { return nil }

        var rest = line.dropFirst(digits.count)
        if rest.hasPrefix(". ") {
            rest = rest.dropFirst(2)
        } else if rest.hasPrefix("、") {
            rest = rest.dropFirst()
        } else {
            return nil
        }
        let text = String(rest).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (number, text)
    }

    // MARK: - 行内标记

    /// `**加粗**`、`*斜体*`、`` `代码` `` → 带样式的 AttributedString。
    /// 用 Foundation 自带的解析器，只开行内模式——块级语法已经在 `blocks` 里拆过了。
    /// 解析失败（残缺标记等）就原样返回，绝不能因为一处语法问题让整段回答显示不出来
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    // MARK: - 剥成纯文本

    /// 剥掉全部标记，供「存为局面注释」使用。
    /// 列表项保留一个「· 」/「1. 」前缀：全去掉的话几条并列要点会糊成一段，反而更难读
    static func plainText(_ markdown: String) -> String {
        var pieces: [String] = []
        var previousWasListItem = false

        for block in blocks(markdown) {
            let line: String
            let isListItem: Bool
            switch block {
            case .heading(let text):
                line = String(inline(text).characters)
                isListItem = false
            case .bullet(let text):
                line = "· " + String(inline(text).characters)
                isListItem = true
            case .ordered(let number, let text):
                line = "\(number). " + String(inline(text).characters)
                isListItem = true
            case .paragraph(let text):
                line = String(inline(text).characters)
                isListItem = false
            }

            if !pieces.isEmpty {
                // 相邻要点之间只换一行，其余块之间空一行
                pieces.append(isListItem && previousWasListItem ? "\n" : "\n\n")
            }
            pieces.append(line)
            previousWasListItem = isListItem
        }
        return pieces.joined()
    }
}
