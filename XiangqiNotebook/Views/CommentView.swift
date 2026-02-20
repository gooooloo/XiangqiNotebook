import SwiftUI

/// 评论区组件
struct CommentView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        HStack() {
            // 第一列：局面评论区
            VStack() {
                Text("局面评论区")
                if viewModel.isCommentEditing {
                    TextEditor(text: .init(
                        get: { viewModel.currentFenComment ?? "" },
                        set: { newValue in
                            viewModel.updateCurrentFenComment(newValue)
                        }
                    ))
                    .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                } else {
                    Text(viewModel.currentFenComment ?? "")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.gray.opacity(0.1))
                        .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                }
            }

            // 第二列：招法评论区
            VStack() {
                Text("招法评论区")
                if viewModel.isCommentEditing {
                    TextEditor(text: .init(
                        get: { viewModel.currentMoveComment ?? "" },
                        set: { newValue in
                            viewModel.updateCurrentMoveComment(newValue)
                        }
                    ))
                    .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                } else {
                    Text(viewModel.currentMoveComment ?? "")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color.gray.opacity(0.1))
                        .opacity(viewModel.currentAppMode == .practice ? 0 : 1)
                }
            }

            // 第三列：相关课程 + 不好的原因
            VStack(spacing: 0) {
                // 上半部分：相关课程
                VStack(alignment: .leading, spacing: 0) {
                    Text("相关课程")
                    ScrollView {
                        FlowLayout(items: viewModel.relatedCoursesForCurrentFen) { game in
                            Text(game.name ?? "未命名游戏")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                                #if os(macOS)
                                .contextMenu {
                                    CourseVideoContextMenu(gameId: game.id, currentFenId: viewModel.currentFenId)
                                }
                                #endif
                        }
                        .padding(.top, 8)
                    }
                }
                .frame(maxHeight: .infinity)
                .opacity(viewModel.currentAppMode == .practice ? 0 : 1)

                // 下半部分：不好的原因
                if viewModel.currentAppMode != .practice && viewModel.isCurrentMoveBad {
                    VStack() {
                        Text("不好的原因")
                        if viewModel.isCommentEditing {
                            TextEditor(text: .init(
                                get: { viewModel.currentMoveBadReason ?? "" },
                                set: { newValue in
                                    viewModel.updateCurrentMoveBadReason(newValue)
                                }
                            ))
                        } else {
                            Text(viewModel.currentMoveBadReason ?? "")
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(Color.gray.opacity(0.1))
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding()
        .border(Color.gray)
    }
}

#if os(macOS)
import AppKit

/// 课程项目的右键菜单：关联/显示/更换/清除视频文件，时间戳管理
struct CourseVideoContextMenu: View {
    let gameId: UUID
    let currentFenId: Int
    @State private var hasVideo: Bool

    init(gameId: UUID, currentFenId: Int) {
        self.gameId = gameId
        self.currentFenId = currentFenId
        self._hasVideo = State(initialValue: CourseVideoStorage.shared.videoPath(for: gameId) != nil)
    }

    private var currentTimestamp: String? {
        CourseVideoStorage.shared.timestamp(for: gameId, fenId: currentFenId)
    }

    var body: some View {
        if hasVideo {
            Button("在 Finder 中显示") {
                if let path = CourseVideoStorage.shared.videoPath(for: gameId) {
                    let url = URL(fileURLWithPath: path)
                    if FileManager.default.fileExists(atPath: path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        CourseVideoStorage.shared.removeVideoPath(for: gameId)
                        hasVideo = false
                    }
                }
            }
            Button("更换视频") {
                selectVideoFile()
            }
            Button("清除关联") {
                CourseVideoStorage.shared.removeVideoPath(for: gameId)
                hasVideo = false
            }
            Divider()
            if let ts = currentTimestamp {
                Button("编辑时间戳 (\(ts))") {
                    showTimestampAlert(existing: ts)
                }
                Button("清除时间戳") {
                    CourseVideoStorage.shared.removeTimestamp(for: gameId, fenId: currentFenId)
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
            CourseVideoStorage.shared.setVideoPath(url.path, for: gameId)
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
                CourseVideoStorage.shared.setTimestamp(value, for: gameId, fenId: currentFenId)
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
