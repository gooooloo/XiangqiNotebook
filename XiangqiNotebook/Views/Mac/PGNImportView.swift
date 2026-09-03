#if os(macOS)
import SwiftUI
import AppKit

struct PGNImportView: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var importResult: PGNImportResult?
    @State private var isImporting = false
    @State private var isListening = false
    @State private var httpServer: PGNHttpServer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入PGN棋局")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("我的棋手名:")
                    TextField("留空表示导入他人对局", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                Text("若棋手名与对局中红方或黑方一致，则该局作为我的执红/执黑实战导入；否则作为他人对局导入。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("选择PGN文件") {
                    selectAndImportFile()
                }
                .disabled(isImporting || isListening)

                Button(isListening ? "停止HTTP监听 (localhost:9213)" : "从HTTP端口获取") {
                    if isListening {
                        stopHTTPServer()
                    } else {
                        startHTTPServer()
                    }
                }
                .disabled(isImporting)

                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let result = importResult {
                Divider()
                resultView(result)
            }

            Spacer()

            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .disabled(isListening)
            }
        }
        .padding()
        .frame(width: 420, height: 350)
        .onAppear {
            // 先把记忆的棋手名填进输入框，startHTTPServer 会把当前输入框内容回写
            username = viewModel.pgnImportUsername
            startHTTPServer()
        }
        .onDisappear {
            stopHTTPServer()
        }
    }

    @ViewBuilder
    private func resultView(_ result: PGNImportResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("导入结果")
                .font(.subheadline)
                .bold()

            Text("解析棋局: \(result.totalParsed)")
            if result.redGameCount > 0 || result.blackGameCount > 0 || result.othersGameCount > 0 {
                let parts = [
                    result.redGameCount > 0 ? "执红\(result.redGameCount)" : nil,
                    result.blackGameCount > 0 ? "执黑\(result.blackGameCount)" : nil,
                    result.othersGameCount > 0 ? "他人\(result.othersGameCount)" : nil,
                ].compactMap { $0 }.joined(separator: ", ")
                Text("成功导入: \(result.imported) (\(parts))")
            }
            if result.skippedDuplicate > 0 {
                Text("跳过重复: \(result.skippedDuplicate)")
                    .foregroundColor(.secondary)
            }
            if result.skippedError > 0 {
                Text("跳过错误: \(result.skippedError)")
                    .foregroundColor(.orange)
            }
            if !result.errors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.errors, id: \.self) { error in
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .frame(maxHeight: 80)
            }
        }
    }

    private func startHTTPServer() {
        let server = PGNHttpServer()
        viewModel.pgnImportUsername = username
        let trimmedUsername = viewModel.pgnImportUsername

        server.onPGNReceived = { pgnContent in
            // 回调运行在 PGNHttpServer 的私有队列上；导入会修改 Database 并
            // 切换 @Published 状态，必须回主线程执行。用 sync 等待结果以便
            // 服务器把导入结果写回 HTTP 响应
            let result = DispatchQueue.main.sync {
                viewModel.importPGNFile(content: pgnContent, username: trimmedUsername)
            }
            DispatchQueue.main.async {
                self.importResult = result
            }
            return result
        }

        do {
            try server.start()
            httpServer = server
            isListening = true
        } catch {
            var result = PGNImportResult()
            result.errors.append("HTTP服务器启动失败: \(error.localizedDescription)")
            importResult = result
        }
    }

    private func stopHTTPServer() {
        httpServer?.stop()
        httpServer = nil
        isListening = false
    }

    private func selectAndImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择PGN文件"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        viewModel.pgnImportUsername = username
        let trimmedUsername = viewModel.pgnImportUsername

        isImporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 文件读取留在后台；导入修改 Database 与 @Published 状态，回主线程执行
                let content = try String(contentsOf: url, encoding: .utf8)
                DispatchQueue.main.async {
                    let result = viewModel.importPGNFile(content: content, username: trimmedUsername)
                    self.importResult = result
                    self.isImporting = false
                }
            } catch {
                DispatchQueue.main.async {
                    var result = PGNImportResult()
                    result.errors.append("文件读取失败: \(error.localizedDescription)")
                    self.importResult = result
                    self.isImporting = false
                }
            }
        }
    }
}
#endif
