import SwiftUI

struct BookmarkDialog: View {
    @Binding var isPresented: Bool
    @State private var bookmarkName: String = ""
    @ObservedObject var viewModel: ViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("输入书签名称")
                .font(.headline)
            
            TextField("书签名称", text: $bookmarkName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
            
            HStack(spacing: 20) {
                Button("取消") {
                    bookmarkName = ""
                    isPresented = false
                }
                
                Button("保存") {
                    if viewModel.isBookmarked {
                        let success = viewModel.removeBookmark()
                        if !success {
                            print("书签删除失败")
                        }
                    } else {
                        let success = viewModel.addBookmark(bookmarkName)
                        if !success {
                            print("书签添加失败")
                        }
                    }
                    bookmarkName = ""
                    isPresented = false
                }
            }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
} 