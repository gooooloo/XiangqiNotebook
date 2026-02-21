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
