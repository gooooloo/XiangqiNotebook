import Foundation

/// FEN 转换逻辑，Mac(子进程)和 iOS(内嵌引擎)两条 Pikafish 集成路径共用
enum PikafishFenConversion {

    /// 将 App 内部 FEN 格式转换为 UCI 标准 FEN
    /// App: "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r"
    /// UCI: "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"
    static func convertFenToUCI(_ fen: String) -> String {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return fen }

        let board = String(parts[0])
        let sideChar = parts[1]
        // App uses "r" for red-to-move, UCI uses "w"
        // App uses "b" for black-to-move, UCI uses "b"
        let uciSide = (sideChar == "r" || sideChar == "w") ? "w" : "b"

        // If already has enough fields, just fix the side
        if parts.count >= 6 {
            var mutableParts = parts.map { String($0) }
            mutableParts[1] = uciSide
            return mutableParts.joined(separator: " ")
        }

        // Otherwise build full UCI FEN
        return "\(board) \(uciSide) - - 0 1"
    }
}
