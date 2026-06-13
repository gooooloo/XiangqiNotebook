import SwiftUI

extension ReviewQuality {
    /// 自评按钮文案
    var displayLabel: String {
        switch self {
        case .again: return "忘了"
        case .hard: return "困难"
        case .good: return "良好"
        case .easy: return "简单"
        }
    }

    /// 自评按钮配色
    var displayColor: Color {
        switch self {
        case .again: return .red
        case .hard: return .orange
        case .good: return .blue
        case .easy: return .green
        }
    }
}

/// 复习自评按钮组（忘了/困难/良好/简单）。
/// Mac/iPad 的 ReviewModeView 与 iPhone 的 iPhoneReviewModeView 原本各有一份
/// 完全相同的按钮 + reviewButton helper，统一到此（spacing 由调用方指定）
struct ReviewRatingButtons: View {
    @ObservedObject var viewModel: ViewModel
    var spacing: CGFloat = 8

    private let qualities: [ReviewQuality] = [.again, .hard, .good, .easy]

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(qualities, id: \.self) { quality in
                Button(quality.displayLabel) {
                    viewModel.submitReviewRating(quality)
                }
                .foregroundColor(quality.displayColor)
                .buttonStyle(.bordered)
            }
        }
    }
}
