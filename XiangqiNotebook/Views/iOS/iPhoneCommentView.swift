#if os(iOS)
import SwiftUI

/// 评论显示组件
struct iPhoneCommentView: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private var verticalPadding: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium:
            return 6
        case .large, .xLarge:
            return 8
        default:
            return 10
        }
    }
    
    private var commentText: String {
        if viewModel.session.sessionData.currentMode == .practice {
            return ""
        }

        return viewModel.currentCombinedComment ?? ""
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(commentText)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, verticalPadding)
                .padding(.horizontal)
        }
        .frame(height: 80)  // 大约4行文字的高度
        // .border(Color.gray)
        .minimumScaleFactor(0.75)
    }
}

#Preview {
    iPhoneCommentView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
} 
#endif 
