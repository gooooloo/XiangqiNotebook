#if os(iOS)
import SwiftUI
import UIKit

/// 「导入棋谱」Sheet：从剪贴板导入走真实 `importPGNFile`；文件/链接导入超出本次视图层重排范围，仅作 UI 占位。
struct iPhoneImportSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var resultMessage: String?

    var body: some View {
        iPhoneSheetShell(title: "导入棋谱") {
            VStack(alignment: .leading, spacing: 16) {
                Text("支持标准 PGN、DhtmlXQ 及东萍格式。可从剪贴板导入；文件与链接导入暂未接入。")
                    .font(.system(size: 13.5))
                    .foregroundColor(XiangqiTheme.sub)
                    .lineSpacing(4)

                if let resultMessage {
                    Text(resultMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(XiangqiTheme.good)
                }

                VStack(spacing: 10) {
                    primaryButton("从剪贴板粘贴", filled: true) { importFromClipboard() }
                    primaryButton("从文件选择", filled: false, color: XiangqiTheme.accent2) { }
                    primaryButton("从链接导入", filled: false, color: XiangqiTheme.sub) { }
                }
            }
        }
    }

    private func importFromClipboard() {
        guard let content = UIPasteboard.general.string, !content.isEmpty else {
            resultMessage = "剪贴板为空"
            return
        }
        let result = viewModel.importPGNFile(content: content, username: viewModel.pgnImportUsername)
        resultMessage = "已导入 \(result.imported) / \(result.totalParsed) 局"
    }

    private func primaryButton(_ title: String, filled: Bool, color: Color = XiangqiTheme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(XiangqiTheme.XFont.sans(15.5, weight: .bold))
                .foregroundColor(filled ? .white : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(filled ? color : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card).stroke(color, lineWidth: filled ? 0 : 1.5))
                .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
        }
    }
}

/// 「导出与分享」Sheet：导出 PGN 走真实 `exportPGNCurrentGameContent()` 并复制到剪贴板。
struct iPhoneExportSheet: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var toast: String?

    var body: some View {
        iPhoneSheetShell(title: "导出与分享") {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    XiangqiBoard(viewModel: .constant(viewModel.boardViewModel))
                        .frame(width: 150, height: 150)
                        .padding(8)
                        .background(XiangqiTheme.panel)
                        .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card).stroke(XiangqiTheme.line, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
                    Spacer()
                }

                if let toast {
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(XiangqiTheme.good)
                }

                VStack(spacing: 10) {
                    button("导出为 PGN", filled: true) {
                        UIPasteboard.general.string = viewModel.exportPGNCurrentGameContent()
                        toast = "已复制 PGN"
                    }
                    button("分享棋盘图片", filled: false, color: XiangqiTheme.accent2) {
                        viewModel.actionDefinitions.getActionInfo(.copyBoardImage)?.action()
                        toast = "已复制棋盘图片"
                    }
                    button("生成复习卡片", filled: false, color: XiangqiTheme.sub) {
                        viewModel.actionDefinitions.getActionInfo(.addToReview)?.action()
                        toast = "已加入复习库"
                    }
                }
            }
        }
    }

    private func button(_ title: String, filled: Bool, color: Color = XiangqiTheme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(XiangqiTheme.XFont.sans(15.5, weight: .bold))
                .foregroundColor(filled ? .white : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(filled ? color : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card).stroke(color, lineWidth: filled ? 0 : 1.5))
                .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
        }
    }
}
#endif
