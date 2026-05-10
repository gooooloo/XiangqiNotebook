import SwiftUI

/// 模式选择器组件
/// 显示当前模式，支持模式切换
struct ModeSelectorView: View {
    @ObservedObject var viewModel: ViewModel

    private static let modeActionKeys: [ActionDefinitions.ActionKey] = [
        .setNormalMode,
        .setPracticeMode,
        .setReviewMode,
    ]

    var body: some View {
        VStack(alignment: .leading) {
            Text("应用模式")

            ForEach(Self.modeActionKeys, id: \.self) { key in
                MyToggle(viewModel: viewModel, actionKey: key)
            }
        }
        .padding(8)
        .border(Color.gray)
    }
}

#Preview {
    #if os(macOS)
    ModeSelectorView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    ModeSelectorView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
}
