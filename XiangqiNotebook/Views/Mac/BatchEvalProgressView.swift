#if os(macOS)
import SwiftUI

struct BatchEvalProgressView: View {
    let progress: BatchEvalProgress
    let onCancel: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(progress.isCompleted ? "评估完成" : "皮卡鱼评估")
                .font(.headline)

            if !progress.isCompleted {
                ProgressView(value: Double(progress.current), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 240)
            }

            Text("\(progress.current) / \(progress.total)  已评估 \(progress.evaluatedCount) 个局面")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let detail = progress.lastDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let elapsed = progress.elapsedSeconds, elapsed >= 1 {
                Text("总耗时 \(formatElapsed(elapsed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if progress.isCompleted {
                Button("关闭") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8)
    }

    private func formatElapsed(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return "\(minutes)m\(secs)s"
    }
}
#endif
