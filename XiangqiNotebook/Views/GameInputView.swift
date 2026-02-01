import SwiftUI

struct GameInputView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ViewModel
    var onSave: (GameObject) -> Bool

    @State private var creationDate = Date()
    @State private var gameDate = Date()
    @State private var hasGameDate = false
    @State private var gameName = ""
    @State private var redPlayerName = ""
    @State private var blackPlayerName = ""
    @State private var iAmRed = false
    @State private var iAmBlack = false
    @State private var gameResult: GameResult = .unknown
    @State private var saveResultMessage = ""
    @State private var showingSaveResultAlert = false
    
    var body: some View {
            Form {
                DatePicker("创建时间", selection: $creationDate)

                Toggle("记录对弈时间", isOn: $hasGameDate)
                DatePicker("对弈时间", selection: $gameDate)
                    .opacity(hasGameDate ? 1 : 0)
                    .disabled(!hasGameDate)

                TextField("名字（可选）", text: $gameName)
                TextField("红方姓名", text: $redPlayerName)
                TextField("黑方姓名", text: $blackPlayerName)

                HStack {
                    Toggle("我是红方", isOn: $iAmRed)
                    Toggle("我是黑方", isOn: $iAmBlack)
                }
                
                Picker("结果", selection: $gameResult) {
                    ForEach(GameResult.allCases, id: \.self) { result in
                        Text(result.rawValue).tag(result)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveGame()
                    }
                }
            }
            .alert("保存结果", isPresented: $showingSaveResultAlert) {
                Button("确定") {
                    dismiss()
                }
            } message: {
                Text(saveResultMessage)
            }
        .frame(width: 480, height: 420)
        .padding(40)
    }
    
    private func saveGame() {
        let game = GameObject(id: UUID())
        game.name = gameName.isEmpty ? nil : gameName
        game.creationDate = creationDate
        game.gameDate = gameDate
        game.redPlayerName = redPlayerName
        game.blackPlayerName = blackPlayerName
        game.iAmRed = iAmRed
        game.iAmBlack = iAmBlack
        game.gameResult = gameResult
        if onSave(game) {
            saveResultMessage = "保存成功"
        } else {
            saveResultMessage = "保存失败"
        }
        showingSaveResultAlert = true
    }
}

#Preview {
    #if os(macOS)
    GameInputView(
        viewModel: ViewModel(
            platformService: MacOSPlatformService()
        ),
        onSave: { _ in true }
    )
    #else
    GameInputView(
        viewModel: ViewModel(
            platformService: IOSPlatformService(presentingViewController: UIViewController())
        ),
        onSave: { _ in true }
    )
    #endif
} 