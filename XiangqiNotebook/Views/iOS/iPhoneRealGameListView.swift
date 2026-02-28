#if os(iOS)
import SwiftUI

/// iPhone版本的实战列表视图
struct iPhoneRealGameListView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool

    private var games: [GameObject] {
        viewModel.relatedRealGamesForCurrentFen
    }

    private var hasMore: Bool {
        viewModel.hasMoreRelatedRealGames
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                if games.isEmpty {
                    Text("无相关实战")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    ScrollView(showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(games) { game in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.displayTitle)
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            if let date = game.gameDate {
                                                Text(date, style: .date)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Text(game.gameResult.rawValue)
                                                .font(.caption)
                                                .foregroundColor(resultColor(game.gameResult))
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(isCurrentlyLoaded(game) ? Color.blue.opacity(0.1) : Color.clear)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button {
                                        viewModel.loadGame(game.id)
                                        isPresented = false
                                    } label: {
                                        Label("筛选此棋局", systemImage: "line.3.horizontal.decrease.circle")
                                    }
                                }
                                Divider()
                            }
                            if hasMore {
                                Text("...")
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("实战 (\(games.count)\(hasMore ? "+" : ""))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func isCurrentlyLoaded(_ game: GameObject) -> Bool {
        viewModel.currentFilters.contains(Session.filterSpecificGame) &&
            viewModel.currentSpecificGameId == game.id
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
    iPhoneRealGameListView(
        viewModel: ViewModel(
            platformService: IOSPlatformService(presentingViewController: UIViewController())
        ),
        isPresented: .constant(true)
    )
}
#endif
