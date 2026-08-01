import SwiftUI

/// 评论区组件
struct CommentView: View {
    @ObservedObject var viewModel: ViewModel

    private var isPractice: Bool { viewModel.currentAppMode == .practice }

    /// 是否显示「不好的原因」：劣手时才有，练习模式下不剧透。
    private var showsBadReason: Bool {
        !isPractice && viewModel.isCurrentMoveBad
    }

    /// 第二列是否显示招法评论区。
    ///
    /// 有内容就永远显示（内容不能被藏起来），与「不好的原因」上下分栏；
    /// 只有在它为空、且有「不好的原因」要显示时才隐藏，把整列让给原因——原因往往很长，需要整列才看得全。
    /// 编辑态例外：始终显示，否则空的招法评论无从填写。
    private var showsMoveComment: Bool {
        guard showsBadReason, !viewModel.isCommentEditing else { return true }
        return !(viewModel.currentMoveComment ?? "").isEmpty
    }

    /// 评论文本块：编辑态用 TextEditor，浏览态用只读文本；统一浅底内嵌框。
    @ViewBuilder
    private func commentBox(
        text: String,
        isEditing: Bool,
        disabled: Bool = false,
        background: Color = Theme.insetBackground,
        border: Color = Theme.cardBorder,
        onChange: @escaping (String) -> Void
    ) -> some View {
        Group {
            if isEditing {
                TextEditor(text: .init(get: { text }, set: onChange))
                    .font(.system(size: Theme.fs(12.5)))
                    // 框底色是固定的浅色，文字色必须一并固定：否则深色外观下会取到白色，
                    // 落在浅灰／粉红底上看不清
                    .foregroundColor(Theme.monoText)
                    .scrollContentBackground(.hidden)
                    .disabled(disabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            } else {
                Text(text)
                    .font(.system(size: Theme.fs(12.5)))
                    .foregroundColor(Theme.monoText)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .insetBox(background: background, border: border)
    }

    var body: some View {
        HStack(spacing: 8) {
            // 第一列：局面评论区
            VStack(alignment: .leading, spacing: 5) {
                GroupHeader("局面评论区")
                commentBox(
                    text: viewModel.currentFenComment ?? "",
                    isEditing: viewModel.isCommentEditing,
                    onChange: { viewModel.updateCurrentFenComment($0) }
                )
            }
            .opacity(isPractice ? 0 : 1)

            // 第二列：招法评论区 + 不好的原因（红色框；招法评论为空时原因独占整列）
            VStack(spacing: 7) {
                if showsMoveComment {
                    VStack(alignment: .leading, spacing: 5) {
                        GroupHeader("招法评论区")
                        commentBox(
                            text: viewModel.currentMoveComment ?? "",
                            isEditing: viewModel.isCommentEditing,
                            disabled: !viewModel.hasCurrentMove,
                            onChange: { viewModel.updateCurrentMoveComment($0) }
                        )
                    }
                    .frame(maxHeight: .infinity)
                }

                if showsBadReason {
                    VStack(alignment: .leading, spacing: 5) {
                        GroupHeader("不好的原因", color: Theme.bad)
                        commentBox(
                            text: viewModel.currentMoveBadReason ?? "",
                            isEditing: viewModel.isCommentEditing,
                            background: Theme.reasonBackground,
                            border: Theme.reasonBorder,
                            onChange: { viewModel.updateCurrentMoveBadReason($0) }
                        )
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .opacity(isPractice ? 0 : 1)

            // 第三列：相关课程
            VStack(alignment: .leading, spacing: 5) {
                GroupHeader("相关课程")
                ScrollView {
                    FlowLayout(items: viewModel.relatedCoursesForCurrentFen) { game in
                        Text(game.name ?? "未命名游戏")
                            .font(.system(size: Theme.fs(11)))
                            .foregroundColor(Theme.variant)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(hex: 0xE7EEFC))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
                            #if os(macOS)
                            .contextMenu {
                                CourseVideoContextMenu(viewModel: viewModel, gameId: game.id, currentFenId: viewModel.currentFenId)
                            }
                            #endif
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .insetBox()
            }
            .opacity(isPractice ? 0 : 1)
        }
        .padding(12)
    }
}

#if os(macOS)
import AppKit

/// 课程项目的右键菜单：关联/显示/更换/清除视频文件，时间戳管理。
/// 数据操作经 ViewModel 转发（不直接触碰 Storage 层）；面板与弹窗是 macOS 专属 UI，留在视图内
struct CourseVideoContextMenu: View {
    @ObservedObject var viewModel: ViewModel
    let gameId: UUID
    let currentFenId: Int
    @State private var hasVideo: Bool

    init(viewModel: ViewModel, gameId: UUID, currentFenId: Int) {
        self.viewModel = viewModel
        self.gameId = gameId
        self.currentFenId = currentFenId
        self._hasVideo = State(initialValue: viewModel.courseVideoPath(for: gameId) != nil)
    }

    private var currentTimestamp: String? {
        viewModel.courseVideoTimestamp(for: gameId, fenId: currentFenId)
    }

    var body: some View {
        if hasVideo {
            Button("在 Finder 中显示") {
                if let path = viewModel.courseVideoPath(for: gameId) {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        viewModel.removeCourseVideoPath(for: gameId)
                        hasVideo = false
                    }
                }
            }
            Button("更换视频") {
                selectVideoFile()
            }
            Button("清除关联") {
                viewModel.removeCourseVideoPath(for: gameId)
                hasVideo = false
            }
            Divider()
            if let ts = currentTimestamp {
                Button("编辑时间戳 (\(ts))") {
                    showTimestampAlert(existing: ts)
                }
                Button("清除时间戳") {
                    viewModel.removeCourseVideoTimestamp(for: gameId, fenId: currentFenId)
                }
            } else {
                Button("设置时间戳") {
                    showTimestampAlert(existing: nil)
                }
            }
        } else {
            Button("关联视频文件") {
                selectVideoFile()
            }
        }
    }

    private func selectVideoFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.setCourseVideoPath(url.path, for: gameId)
            hasVideo = true
        }
    }

    private func showTimestampAlert(existing: String?) {
        let alert = NSAlert()
        alert.messageText = existing != nil ? "编辑时间戳" : "设置时间戳"
        alert.informativeText = "请输入视频时间位置（如 15:30）"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = existing ?? ""
        textField.placeholderString = "例如 15:30"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField
        if alert.runModal() == .alertFirstButtonReturn {
            let value = textField.stringValue.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                viewModel.setCourseVideoTimestamp(value, for: gameId, fenId: currentFenId)
            }
        }
    }
}
#endif

#Preview {
    #if os(macOS)
    CommentView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    CommentView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 
