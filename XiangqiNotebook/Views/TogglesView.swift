import SwiftUI

/// 棋局筛选组件
struct TogglesView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack {
            // 棋局筛选
            VStack(alignment: .leading) {
                Text("棋局筛选")

                MyToggle(viewModel: viewModel, actionKey: .setFilterNone)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterRedOpeningOnly)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterBlackOpeningOnly)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterRedRealGameOnly)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterBlackRealGameOnly)
                MyToggle(viewModel: viewModel, actionKey: .setFilterFocusedPractice)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterSpecificGame)
                MyToggle(viewModel: viewModel, actionKey: .toggleFilterSpecificBook)
            }
            .padding(8) // 添加内边距，让内容不贴边
            .border(Color.gray)
            
            // 开局库设置区域
            VStack(alignment: .leading) {
                MyToggle(viewModel: viewModel, actionKey: .inRedOpening)
                MyToggle(viewModel: viewModel, actionKey: .inBlackOpening)
                MyToggle(viewModel: viewModel, actionKey: .toggleBookmark)
            }
            .padding(8) // 添加内边距，让内容不贴边
            .border(Color.gray)
            
            // 开局库设置区域
            VStack(alignment: .leading) {
                MyToggle(viewModel: viewModel, actionKey: .toggleLock)
                MyToggle(viewModel: viewModel, actionKey: .toggleCanNavigateBeforeLockedStep)
            }
            .padding(8) // 添加内边距，让内容不贴边
            .border(Color.gray)

            // 棋盘操作
            VStack(alignment: .leading) {
                MyToggle(viewModel: viewModel, actionKey: .flip)
                MyToggle(viewModel: viewModel, actionKey: .flipHorizontal)
                MyToggle(viewModel: viewModel, actionKey: .toggleAutoExtendGameWhenPlayingBoardFen)
                MyToggle(viewModel: viewModel, actionKey: .toggleShowPath)
                MyToggle(viewModel: viewModel, actionKey: .toggleShowAllNextMoves)
                MyToggle(viewModel: viewModel, actionKey: .togglePracticeMode)
                MyToggle(viewModel: viewModel, actionKey: .toggleIsCommentEditing)
                MyToggle(viewModel: viewModel, actionKey: .toggleAllowAddingNewMoves)
            }
            .padding(8) // 添加内边距，让内容不贴边
            .border(Color.gray)
        }
    }
}

struct MyToggle: View {
    // 没有这个，就不会自动更新
    @ObservedObject var viewModel: ViewModel

    let toggleActionInfo: ActionDefinitions.ToggleActionInfo
    let actionKey: ActionDefinitions.ActionKey

    init(viewModel: ViewModel, actionKey: ActionDefinitions.ActionKey) {
        self.viewModel = viewModel
        self.actionKey = actionKey
        self.toggleActionInfo = viewModel.actionDefinitions.getToggleActionInfo(actionKey)!
    }

    var displayText: String {
        var text = toggleActionInfo.text

        // 为特定棋局/棋书筛选添加名称
        if actionKey == .toggleFilterSpecificGame,
           let gameName = viewModel.lastSpecificGameName, !gameName.isEmpty {
            text += ": \(gameName)"
        } else if actionKey == .toggleFilterSpecificBook,
                  let bookName = viewModel.lastSpecificBookName, !bookName.isEmpty {
            text += ": \(bookName)"
        }

        if let shortcut = toggleActionInfo.shortcut {
            return "\(text) (\(shortcut.getDisplayText()))"
        }
        return text
    }

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { toggleActionInfo.isOn() },
                set: { toggleActionInfo.action($0) }
            )) {
                Text(displayText)
            }
            .disabled(!viewModel.isActionVisible(actionKey) || !toggleActionInfo.isEnabled())
            Spacer()
        }
    }
}   

#Preview {
    #if os(macOS)
    TogglesView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    TogglesView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 