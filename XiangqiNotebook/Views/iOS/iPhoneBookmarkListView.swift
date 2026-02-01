#if os(iOS)
import SwiftUI

/// iPhone版本的书签列表视图
struct iPhoneBookmarkListView: View {
    @ObservedObject var viewModel: ViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.bookmarkList, id: \.game) { bookmark in
                            HStack {
                                Text(bookmark.name)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                Spacer()
                                
                                if viewModel.isBookmarkInCurrentGame(bookmark.game) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(viewModel.isBookmarkInCurrentGame(bookmark.game) ? Color.blue.opacity(0.1) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.loadBookmark(bookmark.game)
                                isPresented = false
                            }
                            Divider()  // 添加分隔线
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle("书签列表")
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
}

#Preview {
    iPhoneBookmarkListView(
        viewModel: ViewModel(
            platformService: IOSPlatformService(presentingViewController: UIViewController())
        ),
        isPresented: .constant(true)
    )
}
#endif 