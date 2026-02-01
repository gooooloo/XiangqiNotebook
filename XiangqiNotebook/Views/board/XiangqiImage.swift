import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// 平台无关的图片加载和显示扩展
extension Image {
    #if os(macOS)
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
    #else
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
    #endif
}

extension Image {

    // MARK: - 静态属性：缓存图片
    private static let cachedImages: [String: PlatformImage] = {
        var images: [String: PlatformImage] = [:]
        
        // 棋子列表
        let pieces = ["rR", "rN", "rB", "rA", "rK", "rC", "rP",
                     "bR", "bN", "bB", "bA", "bK", "bC", "bP"]
        
        #if os(macOS)
        // 缓存棋盘背景
        if let boardURL = Bundle.main.url(forResource: "xiangqiboard", withExtension: "svg"),
           let image = NSImage(contentsOf: boardURL) {
            images["board"] = image
        }
        
        // 缓存所有棋子图片
        for piece in pieces {
            if let pieceURL = Bundle.main.url(forResource: piece, withExtension: "svg"),
               let image = NSImage(contentsOf: pieceURL) {
                images[piece] = image
            }
        }
        #else
        // iOS: 从 Assets.xcassets 加载图片
        if let boardImage = UIImage(named: "Boards") {
            print("Successfully loaded board PNG from Assets.xcassets")
            images["board"] = boardImage
        }
        
        // 加载棋子图片
        for piece in pieces {
            if let pieceImage = UIImage(named: piece) {
                print("Successfully loaded piece PNG for \(piece) from Assets.xcassets")
                images[piece] = pieceImage
            }
        }
        #endif
        
        return images
    }()
  
    public static func getCachedImage(_ piece: String) -> Image? {
        guard let pieceImage = Image.cachedImages[piece] else {
            print("Warning: Image not found for piece: \(piece)")
            return nil
        }
        return Image(platformImage: pieceImage)
    }
}
