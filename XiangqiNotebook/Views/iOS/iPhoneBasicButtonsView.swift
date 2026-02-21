#if os(iOS)
import SwiftUI

/// iPhone版本的按钮区域组件
struct iPhoneBasicButtonsView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(spacing: 15) {
            HStack(spacing: 15) {
                iPhoneButton(viewModel: viewModel, actionKey: .toStart)
                iPhoneButton(viewModel: viewModel, actionKey: .stepBack)
                iPhoneButton(viewModel: viewModel, actionKey: .stepForward)
                iPhoneButton(viewModel: viewModel, actionKey: viewModel.currentAppMode == .practice ?
                    (viewModel.isMyTurn ? .hintNextMove : .playRandomNextMove) :
                    .nextVariant)
            }
            .padding(.horizontal)
            
            HStack(spacing: 15) {
                iPhoneButton(viewModel: viewModel, actionKey: .showBookmarkListIOS)
                iPhoneButton(viewModel: viewModel, actionKey: .practiceNewGame)
                iPhoneButton(viewModel: viewModel, actionKey: .reviewThisGame)
                iPhoneButton(viewModel: viewModel, actionKey: .focusedPractice)
            }
            .padding(.horizontal)

            HStack(spacing: 15) {
                iPhoneButton(viewModel: viewModel, actionKey: .save)
                iPhoneButton(viewModel: viewModel, actionKey: .showMoreActionsIOS)
                iPhoneButton(viewModel: viewModel, actionKey: .showMoreActionsIOS)
                iPhoneButton(viewModel: viewModel, actionKey: .showMoreActionsIOS)
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    iPhoneBasicButtonsView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
}
#endif 
