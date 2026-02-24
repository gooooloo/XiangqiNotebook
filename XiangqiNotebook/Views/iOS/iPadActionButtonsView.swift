import SwiftUI

/// iPad 按钮区域组件
struct iPadActionButtonsView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            // 第一行按钮
            HStack() {
                Group {
                    LargeButton(viewModel: viewModel, actionKey: .toStart)
                    LargeButton(viewModel: viewModel, actionKey: .stepBack)
                    LargeButton(viewModel: viewModel, actionKey: .stepForward)
                    LargeButton(viewModel: viewModel, actionKey: .toEnd)
                    LargeButton(viewModel: viewModel, actionKey: .nextVariant)
                    LargeButton(viewModel: viewModel, actionKey: .practiceNewGame)
                    LargeButton(viewModel: viewModel, actionKey: .reviewThisGame)
                    LargeButton(viewModel: viewModel, actionKey: .practiceRedOpening)
                    LargeButton(viewModel: viewModel, actionKey: .practiceBlackOpening)
                    LargeButton(viewModel: viewModel, actionKey: .playRandomNextMove)
                    LargeButton(viewModel: viewModel, actionKey: .removeMoveFromGame)
                }
                .frame(maxWidth: .infinity)
            }
            
            // 第二行按钮
            HStack() {
                Group {
                    LargeButton(viewModel: viewModel, actionKey: .queryScore)
                    LargeButton(viewModel: viewModel, actionKey: .openYunku)
                    LargeButton(viewModel: viewModel, actionKey: .fix)
                    LargeButton(viewModel: viewModel, actionKey: .markPath)
                    LargeButton(viewModel: viewModel, actionKey: .referenceBoard)
                    LargeButton(viewModel: viewModel, actionKey: .previousPath)
                    LargeButton(viewModel: viewModel, actionKey: .nextPath)
                    LargeButton(viewModel: viewModel, actionKey: .random)
                }
                .frame(maxWidth: .infinity)
            }
            
            // 第三行按钮
            HStack() {
                Group {
                    LargeButton(viewModel: viewModel, actionKey: .save)
                    LargeButton(viewModel: viewModel, actionKey: .backup)
                    LargeButton(viewModel: viewModel, actionKey: .restore)
                    LargeButton(viewModel: viewModel, actionKey: .checkDataVersion)
                    LargeButton(viewModel: viewModel, actionKey: .deleteMove)
                    LargeButton(viewModel: viewModel, actionKey: .deleteScore)
                    LargeButton(viewModel: viewModel, actionKey: .inputGame)
                    LargeButton(viewModel: viewModel, actionKey: .browseGames)
                    LargeButton(viewModel: viewModel, actionKey: .searchCurrentMove)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .border(Color.gray)
    }
} 