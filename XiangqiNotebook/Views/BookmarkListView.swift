import SwiftUI

/// 书签列表组件
struct BookmarkListView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("书签")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.bookmarkList, id: \.game) { bookmark in
                        Text(bookmark.name)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(viewModel.isBookmarkInCurrentGame(bookmark.game) ? Color.blue.opacity(0.2) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.loadBookmark(bookmark.game)
                            }
                        Divider()
                    }
                }
            }
        }
        .padding(8)
        .border(Color.gray)
    }
}

#Preview {
    #if os(macOS)
    BookmarkListView(viewModel: ViewModel(
        platformService: MacOSPlatformService()
    ))
    #else
    BookmarkListView(viewModel: ViewModel(
        platformService: IOSPlatformService(presentingViewController: UIViewController())
    ))
    #endif
} 
