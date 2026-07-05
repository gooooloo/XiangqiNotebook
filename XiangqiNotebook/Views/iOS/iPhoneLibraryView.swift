#if os(iOS)
import SwiftUI

/// 「棋谱」标签：按真实 `BookObject` 树形结构（课程/我的实战/他人实战 等顶层棋书及其子棋书）浏览棋局。
struct iPhoneLibraryView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedTab: IPhoneTab

    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var openBookIds: Set<UUID> = []

    private enum Row: Identifiable {
        case folder(bookId: UUID, name: String, level: Int, gameCount: Int, record: String?)
        case game(game: GameObject, level: Int)

        var id: String {
            switch self {
            case .folder(let bookId, _, _, _, _): return "f-\(bookId)"
            case .game(let game, _): return "g-\(game.id)"
            }
        }
    }

    private func recordSubtitle(for games: [GameObject]) -> String? {
        let outcomes = games.compactMap { $0.userOutcome }
        guard !outcomes.isEmpty else { return nil }
        let win = outcomes.filter { $0 == .win }.count
        let draw = outcomes.filter { $0 == .draw }.count
        let loss = outcomes.filter { $0 == .loss }.count
        return "\(outcomes.count) 局 · \(win) 胜 \(draw) 和 \(loss) 负"
    }

    private func rows(nodes: [BookObject], level: Int) -> [Row] {
        var result: [Row] = []
        for book in nodes {
            let allGames = viewModel.getGamesInBookRecursively(book.id)
            result.append(.folder(bookId: book.id, name: book.name, level: level, gameCount: allGames.count, record: recordSubtitle(for: allGames)))
            if openBookIds.contains(book.id) {
                result.append(contentsOf: rows(nodes: viewModel.getSubBooksInBook(book), level: level + 1))
                for game in viewModel.getGamesInBook(book.id) {
                    result.append(.game(game: game, level: level + 1))
                }
            }
        }
        return result
    }

    private var treeRows: [Row] { rows(nodes: viewModel.allTopLevelBookObjects, level: 0) }

    private var searchResults: [GameObject] {
        viewModel.allTopLevelBookObjects
            .flatMap { viewModel.getGamesInBookRecursively($0.id) }
            .filter {
                $0.displayTitle.localizedCaseInsensitiveContains(searchText)
                    || $0.redPlayerName.localizedCaseInsensitiveContains(searchText)
                    || $0.blackPlayerName.localizedCaseInsensitiveContains(searchText)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                searchBox
                if searchText.isEmpty {
                    treeList
                    hint
                } else {
                    searchResultsList
                }
            }
        }
        .background(XiangqiTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showFilterSheet) {
            iPhoneFilterSheet(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("棋谱")
                .font(XiangqiTheme.XFont.serif(26, weight: .black))
                .foregroundColor(XiangqiTheme.ink)
            Spacer()
            Button(action: { showFilterSheet = true }) {
                Text("⚑ 筛选")
                    .font(XiangqiTheme.XFont.sans(12.5, weight: .semibold))
                    .foregroundColor(XiangqiTheme.sub)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .overlay(Capsule().stroke(XiangqiTheme.line, lineWidth: 1))
                    .background(XiangqiTheme.card, in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchBox: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(XiangqiTheme.faint)
                .font(.system(size: 14))
            TextField("搜索棋谱、对手、开局…", text: $searchText)
                .font(XiangqiTheme.XFont.sans(14))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .xqInset()
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - 树形列表

    private var treeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(treeRows.enumerated()), id: \.element.id) { i, row in
                rowView(row)
                if i < treeRows.count - 1 {
                    Divider().overlay(XiangqiTheme.hair)
                }
            }
        }
        .background(XiangqiTheme.card)
        .overlay(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card).stroke(XiangqiTheme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: XiangqiTheme.Radius.card))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var hint: some View {
        Text("点击文件夹展开 / 折叠")
            .font(.system(size: 11.5))
            .foregroundColor(XiangqiTheme.faint)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .folder(let bookId, let name, let level, let gameCount, let record):
            let open = openBookIds.contains(bookId)
            Button(action: {
                if open { openBookIds.remove(bookId) } else { openBookIds.insert(bookId) }
            }) {
                HStack(spacing: 9) {
                    Text("▶")
                        .font(.system(size: 11))
                        .foregroundColor(XiangqiTheme.faint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 14)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(open ? XiangqiTheme.accent2 : XiangqiTheme.gold)
                        .frame(width: 22, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(XiangqiTheme.XFont.sans(15, weight: .bold))
                            .foregroundColor(XiangqiTheme.ink)
                        if let record {
                            Text(record)
                                .font(.system(size: 11.5))
                                .foregroundColor(XiangqiTheme.sub)
                        }
                    }
                    Spacer()
                    Text("\(gameCount) 局")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(XiangqiTheme.faint)
                }
                .padding(.leading, CGFloat(20 + level * 17))
                .padding(.trailing, 16)
                .padding(.vertical, 12)
            }
        case .game(let game, let level):
            Button(action: {
                viewModel.loadGame(game.id)
                selectedTab = .board
            }) {
                HStack(spacing: 10) {
                    Text("車")
                        .font(XiangqiTheme.XFont.serif(14, weight: .heavy))
                        .foregroundColor(XiangqiTheme.accent)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(XiangqiTheme.accent, lineWidth: 1.5))
                        .background(Color(hex: 0xF4E6C4), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.displayTitle)
                            .font(XiangqiTheme.XFont.sans(14.5, weight: .semibold))
                            .foregroundColor(XiangqiTheme.ink)
                            .lineLimit(1)
                        if let date = game.gameDate {
                            Text(dateString(date))
                                .font(.system(size: 12))
                                .foregroundColor(XiangqiTheme.sub)
                        }
                    }
                    Spacer()
                    resultBadge(game)
                }
                .padding(.leading, CGFloat(20 + level * 17 + 14))
                .padding(.trailing, 16)
                .padding(.vertical, 10)
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func resultBadge(_ game: GameObject) -> some View {
        if let outcome = game.userOutcome {
            let (text, color): (String, Color) = {
                switch outcome {
                case .win: return ("胜", XiangqiTheme.good)
                case .loss: return ("负", XiangqiTheme.bad)
                case .draw: return ("和", XiangqiTheme.draw)
                }
            }()
            Text(text)
                .font(XiangqiTheme.XFont.sans(13, weight: .heavy))
                .foregroundColor(color)
        } else if game.gameResult != .unknown {
            let color: Color = {
                switch game.gameResult {
                case .redWin: return XiangqiTheme.accent
                case .blackWin: return XiangqiTheme.ink
                case .draw: return XiangqiTheme.draw
                default: return XiangqiTheme.sub
                }
            }()
            Text(game.gameResult.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(XiangqiTheme.inset, in: Capsule())
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundColor(XiangqiTheme.faint)
        }
    }

    // MARK: - 搜索结果（扁平列表）

    private var searchResultsList: some View {
        LazyVStack(spacing: 10) {
            ForEach(searchResults) { game in
                Button(action: {
                    viewModel.loadGame(game.id)
                    selectedTab = .board
                }) {
                    HStack(spacing: 13) {
                        Text("車")
                            .font(XiangqiTheme.XFont.serif(19, weight: .heavy))
                            .foregroundColor(XiangqiTheme.accent)
                            .frame(width: 44, height: 48)
                            .background(Color(hex: 0xE5D3A8))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: 0xD0B885), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.displayTitle)
                                .font(XiangqiTheme.XFont.sans(15, weight: .bold))
                                .foregroundColor(XiangqiTheme.ink)
                                .lineLimit(1)
                            if let date = game.gameDate {
                                Text(dateString(date))
                                    .font(.system(size: 12.5))
                                    .foregroundColor(XiangqiTheme.sub)
                            }
                        }
                        Spacer()
                        resultBadge(game)
                    }
                    .padding(14)
                    .xqCard()
                }
            }
            if searchResults.isEmpty {
                Text("没有找到匹配的棋谱")
                    .font(.system(size: 13))
                    .foregroundColor(XiangqiTheme.faint)
                    .padding(.top, 30)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
#endif
