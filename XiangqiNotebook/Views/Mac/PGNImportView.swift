#if os(macOS)
import SwiftUI
import AppKit

struct PGNImportView: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = UserDefaults.standard.string(forKey: "pgnImportUsername") ?? ""
    @State private var importResult: PGNImportResult?
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入PGN棋局")
                .font(.headline)

            HStack {
                Text("用户名:")
                TextField("输入你的对弈用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            HStack {
                Button("选择PGN文件") {
                    selectAndImportFile()
                }
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)

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
            }
        }
        .padding()
        .frame(width: 420, height: 350)
    }

    @ViewBuilder
    private func resultView(_ result: PGNImportResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("导入结果")
                .font(.subheadline)
                .bold()

            Text("解析棋局: \(result.totalParsed)")
            Text("成功导入: \(result.imported) (执红 \(result.redGameCount), 执黑 \(result.blackGameCount))")
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

    private func selectAndImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择PGN文件"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmedUsername, forKey: "pgnImportUsername")

        isImporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let result = viewModel.importPGNFile(content: content, username: trimmedUsername)
                DispatchQueue.main.async {
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
