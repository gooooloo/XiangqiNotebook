import SwiftUI

/// 书签列表组件
struct BookmarkListView: View {
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GroupHeader("书签")
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(viewModel.bookmarkList.enumerated()), id: \.element.game) { index, bookmark in
                    HStack(spacing: 8) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: Theme.fs(11)))
                            .foregroundColor(Color(hex: 0xE0A93B))
                        Text(bookmark.name)
                            .font(.system(size: Theme.fs(12.5)))
                            .foregroundColor(Theme.monoText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(viewModel.isBookmarkInCurrentGame(bookmark.game) ? Theme.accent.opacity(0.12) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.loadBookmark(bookmark.game)
                    }
                    if index < viewModel.bookmarkList.count - 1 {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
            .sectionCard()
        }
        .padding(8)
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
