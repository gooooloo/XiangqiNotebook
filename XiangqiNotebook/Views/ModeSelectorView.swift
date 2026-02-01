import SwiftUI

/// 模式选择器组件
/// 显示当前模式，支持模式切换
struct ModeSelectorView: View {
    @ObservedObject var viewModel: ViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("应用模式")

            ForEach(AppMode.allCases, id: \.self) { mode in
                HStack {
                    Toggle(isOn: Binding(
                        get: { viewModel.currentAppMode == mode },
                        set: { isOn in
                            if isOn {
                                viewModel.setMode(mode)
                            }
                        }
                    )) {
                        Text(mode.displayName)
                    }
                    Spacer()
                }
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