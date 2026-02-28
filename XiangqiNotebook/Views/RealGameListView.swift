import SwiftUI

/// 实战列表组件：显示包含当前局面的实战对局
struct RealGameListView: View {
    @ObservedObject var viewModel: ViewModel
    @State private var selectedGameId: UUID? = nil

    private var games: [GameObject] {
        viewModel.relatedRealGamesForCurrentFen
    }

    private var hasMore: Bool {
        viewModel.hasMoreRelatedRealGames
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("实战 (\(games.count)\(hasMore ? "+" : ""))")

            if games.isEmpty {
                Text("无相关实战")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(games) { game in
                        RealGameListItemView(game: game, viewModel: viewModel, isSelected: selectedGameId == game.id)
                            .onTapGesture { toggleSelection(game.id) }
                        Divider()
                    }
                    if hasMore {
                        Text("...")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
        .padding(8)
        .border(Color.gray)
    }

    private func toggleSelection(_ id: UUID) {
        selectedGameId = selectedGameId == id ? nil : id
    }
}

private struct RealGameListItemView: View {
    let game: GameObject
    @ObservedObject var viewModel: ViewModel
    var isSelected: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy年MM月dd日"
        return f
    }()

    private var isCurrentlyLoaded: Bool {
        viewModel.currentFilters.contains(Session.filterSpecificGame) &&
            viewModel.currentSpecificGameId == game.id
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(game.displayTitle)
                .lineLimit(1)
            Spacer()
            if let date = game.gameDate {
                Text(Self.dateFormatter.string(from: date))
                    .monospacedDigit()
            }
            Text(game.gameResult.rawValue)
                .foregroundColor(resultColor(game.gameResult))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isSelected || isCurrentlyLoaded) ? Color.blue.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                viewModel.loadGame(game.id)
            } label: {
                Label("筛选此棋局", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func resultColor(_ result: GameResult) -> Color {
        switch result {
        case .redWin: return .red
        case .blackWin: return .primary
        case .draw: return .blue
        case .notFinished, .unknown: return .secondary
        }
    }
}

#Preview {
    #if os(macOS)
    RealGameListView(viewModel: ViewModel(platformService: MacOSPlatformService()))
    #else
    RealGameListView(viewModel: ViewModel(platformService: IOSPlatformService(presentingViewController: UIViewController())))
    #endif
}
