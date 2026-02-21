import SwiftUI

extension Color {
    static var adaptiveBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }
}

struct GameBrowserView: View {
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBookId: UUID?
    @State private var selectedGameId: UUID?
    @State private var showingAddBookSheet = false
    @State private var showingAddGameSheet = false
    @State private var showingPGNImportSheet = false
    

    
    var body: some View {
        HStack(spacing: 0) {
            // 左栏：BookObject树形选择器
            BookTreeSidebarView(
                viewModel: viewModel,
                selectedBookId: $selectedBookId,
                showingPGNImportSheet: $showingPGNImportSheet
            )
            .frame(minWidth: 250, maxWidth: 300)
            
            Divider()
            
            // 中栏：Game列表
            GameListView(
                viewModel: viewModel,
                selectedBookId: selectedBookId,
                selectedGameId: $selectedGameId,
                onDismiss: {
                    dismiss()
                }
            )
            .frame(minWidth: 300, maxWidth: 400)
            
            Divider()
            
            // 右栏：GameObject详情
            GameDetailView(
                viewModel: viewModel,
                selectedGameId: selectedGameId
            )
            .frame(minWidth: 350)
        }
        .frame(minWidth: 1000, idealWidth: 1200, maxWidth: .infinity, minHeight: 600, idealHeight: 700, maxHeight: .infinity)
        .sheet(isPresented: $showingAddBookSheet) {
            AddBookView(viewModel: viewModel, isPresented: $showingAddBookSheet)
        }
        .sheet(isPresented: $showingPGNImportSheet) {
            PGNImportView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddGameSheet) {
            if let selectedBookId = selectedBookId {
                AddGameView(viewModel: viewModel, bookId: selectedBookId, isPresented: $showingAddGameSheet, onDismissParent: {
                    dismiss()
                })
            }
        }
        .onAppear {
            // 自动定位到当前特定棋局（只在首次显示且未选中任何棋局时执行）
            if selectedGameId == nil,
               viewModel.currentFilters.contains(Session.filterSpecificGame),
               let gameId = viewModel.currentSpecificGameId {

                // 设置选中的棋局
                selectedGameId = gameId

                // 查找这个棋局所属的棋谱
                for book in viewModel.allBookObjects {
                    if book.gameIds.contains(gameId) {
                        selectedBookId = book.id
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Add Book/Game Forms
struct AddBookView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool
    var parentBookId: UUID? = nil
    @State private var bookName = ""

    var body: some View {
        VStack {
            Text(parentBookId == nil ? "添加新棋谱" : "添加子棋谱")
                .font(.headline)
                .padding()

            TextField("棋谱名称", text: $bookName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            HStack {
                Button("取消") {
                    isPresented = false
                }
                Button("添加") {
                    _ = viewModel.addBook(name: bookName, parentBookId: parentBookId)
                    isPresented = false
                }
                .disabled(bookName.isEmpty)
            }
            .padding()
        }
        .frame(width: 300, height: 200)
    }
}

struct AddGameView: View {
    @ObservedObject var viewModel: ViewModel
    let bookId: UUID
    @Binding var isPresented: Bool
    var onDismissParent: (() -> Void)? = nil
    @State private var gameName = ""
    @State private var redPlayerName = ""
    @State private var blackPlayerName = ""
    @State private var gameDate = Date()
    @State private var gameResult = GameResult.unknown
    @State private var iAmRed = false
    @State private var iAmBlack = false
    @State private var isFullyRecorded = false
    @State private var useCurrentPositionAsStart = true
    @State private var startingFenId: Int? = nil

    var body: some View {
        VStack {
            Text("添加新棋局")
                .font(.headline)
                .padding()

            Form {
                TextField("名字（可选）", text: $gameName)
                TextField("红方选手", text: $redPlayerName)
                TextField("黑方选手", text: $blackPlayerName)
                DatePicker("对局日期", selection: $gameDate, displayedComponents: .date)
                Picker("对局结果", selection: $gameResult) {
                    ForEach([GameResult.redWin, .blackWin, .draw, .notFinished, .unknown], id: \.self) { result in
                        Text(result.rawValue).tag(result)
                    }
                }
                Toggle("我是红方", isOn: $iAmRed)
                Toggle("我是黑方", isOn: $iAmBlack)
                Toggle("已经完整录入", isOn: $isFullyRecorded)
                Toggle("设置当前局面作为起始局面", isOn: $useCurrentPositionAsStart)
            }
            .padding()

            HStack {
                Button("取消") {
                    isPresented = false
                }
                Button("添加") {
                    _ = viewModel.addGame(
                        to: bookId,
                        name: gameName.isEmpty ? nil : gameName,
                        redPlayerName: redPlayerName,
                        blackPlayerName: blackPlayerName,
                        gameDate: gameDate,
                        gameResult: gameResult,
                        iAmRed: iAmRed,
                        iAmBlack: iAmBlack,
                        startingFenId: useCurrentPositionAsStart ? startingFenId : nil,
                        isFullyRecorded: isFullyRecorded
                    )
                    isPresented = false
                }
                .disabled(gameName.isEmpty && (redPlayerName.isEmpty || blackPlayerName.isEmpty))

                Button("添加并加载到棋盘") {
                    let gameId = viewModel.addGame(
                        to: bookId,
                        name: gameName.isEmpty ? nil : gameName,
                        redPlayerName: redPlayerName,
                        blackPlayerName: blackPlayerName,
                        gameDate: gameDate,
                        gameResult: gameResult,
                        iAmRed: iAmRed,
                        iAmBlack: iAmBlack,
                        startingFenId: useCurrentPositionAsStart ? startingFenId : nil,
                        isFullyRecorded: isFullyRecorded
                    )
                    viewModel.loadGame(gameId)
                    isPresented = false
                    onDismissParent?()
                }
                .disabled(gameName.isEmpty && (redPlayerName.isEmpty || blackPlayerName.isEmpty))
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            // 初始化起始局面为当前棋盘位置
            startingFenId = viewModel.currentFenId
        }
        .onChange(of: useCurrentPositionAsStart) { newValue in
            if newValue {
                startingFenId = viewModel.currentFenId
            } else {
                startingFenId = nil
            }
        }
    }
}

struct EditBookView: View {
    @ObservedObject var viewModel: ViewModel
    let bookId: UUID
    @Binding var isPresented: Bool
    @State private var bookName = ""

    var body: some View {
        VStack {
            Text("编辑棋谱")
                .font(.headline)
                .padding()

            TextField("棋谱名称", text: $bookName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            HStack {
                Button("取消") {
                    isPresented = false
                }
                Button("保存") {
                    viewModel.updateBook(bookId, name: bookName)
                    isPresented = false
                }
                .disabled(bookName.isEmpty)
            }
            .padding()
        }
        .frame(width: 300, height: 200)
        .onAppear {
            if let book = viewModel.getBookObjectUnfiltered(bookId) {
                bookName = book.name
            }
        }
    }
}

struct EditGameView: View {
    @ObservedObject var viewModel: ViewModel
    let gameId: UUID
    @Binding var isPresented: Bool
    @State private var gameName = ""
    @State private var redPlayerName = ""
    @State private var blackPlayerName = ""
    @State private var gameDate = Date()
    @State private var gameResult = GameResult.unknown
    @State private var iAmRed = false
    @State private var iAmBlack = false
    @State private var startingFenId: Int?
    @State private var isFullyRecorded = false

    var body: some View {
        VStack {
            Text("编辑棋局")
                .font(.headline)
                .padding()

            Form {
                TextField("名字（可选）", text: $gameName)
                TextField("红方选手", text: $redPlayerName)
                TextField("黑方选手", text: $blackPlayerName)
                DatePicker("对局日期", selection: $gameDate, displayedComponents: .date)
                Picker("对局结果", selection: $gameResult) {
                    ForEach([GameResult.redWin, .blackWin, .draw, .notFinished, .unknown], id: \.self) { result in
                        Text(result.rawValue).tag(result)
                    }
                }
                Toggle("我是红方", isOn: $iAmRed)
                Toggle("我是黑方", isOn: $iAmBlack)
                Toggle("已经完整录入", isOn: $isFullyRecorded)

                VStack(alignment: .leading, spacing: 8) {
                    if let fenId = startingFenId {
                        Text("起始局面: FEN ID \(fenId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("起始局面: 标准开局")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        startingFenId = viewModel.currentGamePositionFenId
                    }) {
                        Label("设置当前局面为起始局面", systemImage: "pin.circle")
                    }
                }
            }
            .padding()

            HStack {
                Button("取消") {
                    isPresented = false
                }
                Button("保存") {
                    viewModel.updateGame(
                        gameId,
                        name: gameName.isEmpty ? nil : gameName,
                        redPlayerName: redPlayerName,
                        blackPlayerName: blackPlayerName,
                        gameDate: gameDate,
                        gameResult: gameResult,
                        iAmRed: iAmRed,
                        iAmBlack: iAmBlack,
                        startingFenId: startingFenId,
                        isFullyRecorded: isFullyRecorded
                    )
                    isPresented = false
                }
                .disabled(gameName.isEmpty && (redPlayerName.isEmpty || blackPlayerName.isEmpty))
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .onAppear {
            if let game = viewModel.getGameObjectUnfiltered(gameId) {
                gameName = game.name ?? ""
                redPlayerName = game.redPlayerName
                blackPlayerName = game.blackPlayerName
                gameDate = game.gameDate ?? Date()
                gameResult = game.gameResult
                iAmRed = game.iAmRed
                iAmBlack = game.iAmBlack
                startingFenId = game.startingFenId
                isFullyRecorded = game.isFullyRecorded
            }
        }
    }
}

// MARK: - 左栏：BookObject树形选择器
struct BookTreeSidebarView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedBookId: UUID?
    @Binding var showingPGNImportSheet: Bool
    @State private var showingAddBookSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                Text("棋谱列表")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top)
                Spacer()
                Button(action: { showingPGNImportSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .padding(.top)
                .help("导入PGN")
                Button(action: { showingAddBookSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top)
            }

            // 树形列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.allTopLevelBookObjects) { book in
                        BookTreeNodeView(
                            book: book,
                            viewModel: viewModel,
                            selectedBookId: $selectedBookId,
                            level: 0
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color.adaptiveBackground)
        .sheet(isPresented: $showingAddBookSheet) {
            AddBookView(viewModel: viewModel, isPresented: $showingAddBookSheet)
        }
    }
}

struct BookTreeNodeView: View {
    let book: BookObject
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedBookId: UUID?
    let level: Int
    @State private var isExpanded: Bool = true
    @State private var showingEditBookSheet = false
    @State private var showingAddSubBookSheet = false
    @State private var showingDeleteAlert = false

    private var subBooks: [BookObject] {
        book.subBookIds.compactMap { subBookId in
            viewModel.allBookObjects.first { $0.id == subBookId }
        }
    }

    private var gameCount: Int {
        viewModel.getGamesInBook(book.id).count
    }

    private var totalGameCount: Int {
        let directGames = gameCount
        let subBooksGames = subBooks.reduce(0) { total, subBook in
            total + getTotalGameCountForBook(subBook)
        }
        return directGames + subBooksGames
    }

    private func getTotalGameCountForBook(_ book: BookObject) -> Int {
        let directGames = viewModel.getGamesInBook(book.id).count
        let subBooks = book.subBookIds.compactMap { subBookId in
            viewModel.allBookObjects.first { $0.id == subBookId }
        }
        let subBooksGames = subBooks.reduce(0) { total, subBook in
            total + getTotalGameCountForBook(subBook)
        }
        return directGames + subBooksGames
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 当前节点
            HStack {
                // 缩进
                HStack(spacing: 0) {
                    ForEach(0..<level, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 20)
                    }
                }
                
                // 展开/收起按钮
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: subBooks.isEmpty ? "circle" : (isExpanded ? "chevron.down" : "chevron.right"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(subBooks.isEmpty)
                
                // 文件夹图标
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
                
                // 棋谱名称和统计
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.name)
                        .font(.system(size: 13, weight: selectedBookId == book.id ? .semibold : .regular))
                        .foregroundColor(selectedBookId == book.id ? .primary : .primary)
                    
                    if totalGameCount > 0 {
                        Text("\(totalGameCount) 局棋")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                Rectangle()
                    .fill(selectedBookId == book.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selectedBookId = book.id
            }
            .contextMenu {
                Button(action: {
                    viewModel.loadBook(book.id)
                }) {
                    Label("加载棋谱", systemImage: "arrow.right.circle")
                }

                Divider()

                Button(action: {
                    showingEditBookSheet = true
                }) {
                    Label("编辑棋谱", systemImage: "pencil")
                }

                Button(action: {
                    showingAddSubBookSheet = true
                }) {
                    Label("添加子棋谱", systemImage: "folder.badge.plus")
                }

                Divider()

                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("删除棋谱", systemImage: "trash")
                }
            }

            // 子节点
            if isExpanded && !subBooks.isEmpty {
                ForEach(subBooks) { subBook in
                    BookTreeNodeView(
                        book: subBook,
                        viewModel: viewModel,
                        selectedBookId: $selectedBookId,
                        level: level + 1
                    )
                }
            }
        }
        .sheet(isPresented: $showingEditBookSheet) {
            EditBookView(viewModel: viewModel, bookId: book.id, isPresented: $showingEditBookSheet)
        }
        .sheet(isPresented: $showingAddSubBookSheet) {
            AddBookView(viewModel: viewModel, isPresented: $showingAddSubBookSheet, parentBookId: book.id)
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                viewModel.deleteBook(book.id)
                if selectedBookId == book.id {
                    selectedBookId = nil
                }
            }
        } message: {
            Text("确定要删除这个棋谱吗？此操作将删除所有子棋谱和关联棋局，且不可撤销。")
        }
    }
}

// MARK: - 中栏：Game列表
struct GameListView: View {
    @ObservedObject var viewModel: ViewModel
    let selectedBookId: UUID?
    @Binding var selectedGameId: UUID?
    var onDismiss: (() -> Void)? = nil
    @State private var showingAddGameSheet = false

    private var selectedBook: BookObject? {
        guard let bookId = selectedBookId else { return nil }
        return viewModel.allBookObjects.first { $0.id == bookId }
    }

    private var games: [GameObject] {
        guard let bookId = selectedBookId else { return [] }
        let allGames = viewModel.getGamesInBook(bookId)
        // 实战棋局按时间降序排列，棋书棋局保持原顺序
        let hasRealGames = allGames.contains { $0.iAmRed || $0.iAmBlack }
        if hasRealGames {
            return allGames.sorted { g1, g2 in
                let d1 = g1.gameDate ?? g1.creationDate ?? .distantPast
                let d2 = g2.gameDate ?? g2.creationDate ?? .distantPast
                return d1 > d2
            }
        }
        return allGames
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                if let book = selectedBook {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.name)
                            .font(.headline)
                        Text("\(games.count) 局棋")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("请选择棋谱")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if selectedBookId != nil {
                    Button(action: { showingAddGameSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            
            Divider()
            
            // 棋局列表
            if games.isEmpty {
                Spacer()
                VStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无棋局")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(games) { game in
                                GameListItemView(
                                    game: game,
                                    viewModel: viewModel,
                                    selectedGameId: $selectedGameId
                                )
                                .id(game.id)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .onAppear {
                        // 当列表首次出现时，滚动到选中的棋局
                        if let gameId = selectedGameId {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo(gameId, anchor: .center)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedGameId) { newGameId in
                        // 当选中的棋局改变时，滚动到新选中的棋局
                        if let gameId = newGameId {
                            withAnimation {
                                proxy.scrollTo(gameId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.adaptiveBackground)
        .sheet(isPresented: $showingAddGameSheet) {
            if let selectedBookId = selectedBookId {
                AddGameView(viewModel: viewModel, bookId: selectedBookId, isPresented: $showingAddGameSheet, onDismissParent: onDismiss)
            }
        }
    }
}

struct GameListItemView: View {
    let game: GameObject
    @ObservedObject var viewModel: ViewModel
    @Binding var selectedGameId: UUID?
    @State private var showingDeleteAlert = false
    
    private var displayTitle: String {
        if let name = game.name, !name.isEmpty {
            return name
        }
        let redName = game.iAmRed ? "我" : (game.redPlayerName.isEmpty ? "红方" : game.redPlayerName)
        let blackName = game.iAmBlack ? "我" : (game.blackPlayerName.isEmpty ? "黑方" : game.blackPlayerName)
        return "\(redName) vs \(blackName)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 对局双方
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text(displayTitle)
                    .font(.system(size: 14, weight: selectedGameId == game.id ? .semibold : .regular))
                    .lineLimit(1)
            }
            
            // 详细信息
            HStack {
                // 日期
                if let date = game.gameDate {
                    HStack(spacing: 4) {
                        Text(date, style: .date)
                        Text(date, style: .time)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 执子标识
                if game.iAmRed {
                    Text("我红")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                } else if game.iAmBlack {
                    Text("我黑")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.1))
                        .foregroundColor(.black)
                        .cornerRadius(4)
                }
                
                // 结果
                Text(game.gameResult.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(getResultColor(game.gameResult).opacity(0.1))
                    .foregroundColor(getResultColor(game.gameResult))
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(selectedGameId == game.id ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedGameId = game.id
        }
        .contextMenu {
            Button(action: {
                viewModel.loadGame(game.id)
            }) {
                Label("加载棋局", systemImage: "arrow.right.circle")
            }
            
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                viewModel.deleteGame(game.id)
                if selectedGameId == game.id {
                    selectedGameId = nil
                }
            }
        } message: {
            Text("确定要删除这局棋吗？此操作不可撤销。")
        }
    }
    
    private func getResultColor(_ result: GameResult) -> Color {
        switch result {
        case .redWin:
            return .red
        case .blackWin:
            return .black
        case .draw:
            return .blue
        case .notFinished:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}

// MARK: - 右栏：GameObject详情
struct GameDetailView: View {
    @ObservedObject var viewModel: ViewModel
    let selectedGameId: UUID?

    private var selectedGame: GameObject? {
        guard let gameId = selectedGameId else { return nil }
        return viewModel.getGameObjectUnfiltered(gameId)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题
            HStack {
                Text("棋局详情")
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            Divider()
            
            if let game = selectedGame {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 对局信息
                        GameInfoSection(game: game)
                        
                        Divider()
                        
                        // 玩家信息
                        PlayerInfoSection(game: game)
                        
                        Divider()
                        
                        // 对局结果
                        GameResultSection(game: game)
                        
                        Divider()
                        
                        // 操作按钮
                        GameActionSection(game: game, viewModel: viewModel)
                        
                        Spacer()
                    }
                    .padding()
                }
            } else {
                Spacer()
                VStack {
                    Image(systemName: "checkerboard.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("请选择棋局")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(.top)
                }
                Spacer()
            }
        }
        .background(Color.adaptiveBackground)
    }
}

struct GameInfoSection: View {
    let game: GameObject

    private var displayTitle: String {
        if let name = game.name, !name.isEmpty {
            return name
        }
        let redName = game.iAmRed ? "我" : (game.redPlayerName.isEmpty ? "红方" : game.redPlayerName)
        let blackName = game.iAmBlack ? "我" : (game.blackPlayerName.isEmpty ? "黑方" : game.blackPlayerName)
        return "\(redName) vs \(blackName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("对局信息", systemImage: "info.circle")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("棋局名称：")
                        .foregroundColor(.secondary)
                    Text(displayTitle)
                    Spacer()
                }

                HStack {
                    Text("创建时间：")
                        .foregroundColor(.secondary)
                    if let date = game.creationDate {
                        Text(date, style: .date)
                        Text(date, style: .time)
                    } else {
                        Text("未知")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                HStack {
                    Text("对局时间：")
                        .foregroundColor(.secondary)
                    if let date = game.gameDate {
                        Text(date, style: .date)
                        Text(date, style: .time)
                    } else {
                        Text("未设置")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                HStack {
                    Text("棋局ID：")
                        .foregroundColor(.secondary)
                    Text(game.id.uuidString.prefix(8) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                HStack {
                    Text("已经完整录入：")
                        .foregroundColor(.secondary)
                    Image(systemName: game.isFullyRecorded ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(game.isFullyRecorded ? .green : .secondary)
                    Text(game.isFullyRecorded ? "是" : "否")
                        .foregroundColor(game.isFullyRecorded ? .green : .secondary)
                    Spacer()
                }
            }
            .font(.system(size: 13))
        }
    }
}

struct PlayerInfoSection: View {
    let game: GameObject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("玩家信息", systemImage: "person.2")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                    Text("红方：")
                        .foregroundColor(.secondary)
                    Text(game.iAmRed ? "我" : (game.redPlayerName.isEmpty ? "未知" : game.redPlayerName))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(game.iAmRed ? .red : .primary)
                    Spacer()
                }
                
                HStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 12, height: 12)
                    Text("黑方：")
                        .foregroundColor(.secondary)
                    Text(game.iAmBlack ? "我" : (game.blackPlayerName.isEmpty ? "未知" : game.blackPlayerName))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(game.iAmBlack ? .black : .primary)
                    Spacer()
                }
            }
            .font(.system(size: 13))
        }
    }
}

struct GameResultSection: View {
    let game: GameObject
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("对局结果", systemImage: "flag")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack {
                Text(game.gameResult.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(getResultColor(game.gameResult).opacity(0.1))
                    .foregroundColor(getResultColor(game.gameResult))
                    .cornerRadius(8)
                Spacer()
            }
        }
    }
    
    private func getResultColor(_ result: GameResult) -> Color {
        switch result {
        case .redWin:
            return .red
        case .blackWin:
            return .black
        case .draw:
            return .blue
        case .notFinished:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}

struct GameActionSection: View {
    let game: GameObject
    @ObservedObject var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditGameSheet = false
    @State private var showingDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("操作", systemImage: "gear")
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                Button(action: {
                    viewModel.loadGame(game.id)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("加载到棋盘")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: {
                    showingEditGameSheet = true
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("编辑棋局信息")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: {
                    showingDeleteAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("删除棋局")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showingEditGameSheet) {
            EditGameView(viewModel: viewModel, gameId: game.id, isPresented: $showingEditGameSheet)
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                viewModel.deleteGame(game.id)
                dismiss()
            }
        } message: {
            Text("确定要删除这局棋吗？此操作不可撤销。")
        }
    }
}

#Preview {
    #if os(macOS)
    GameBrowserView(viewModel: ViewModel(platformService: MacOSPlatformService()))
    #else
    GameBrowserView(viewModel: ViewModel(platformService: IOSPlatformService(presentingViewController: UIViewController())))
    #endif
}
