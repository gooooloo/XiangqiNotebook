import Foundation

class IO {
    enum IOError: Error {
        case quotaExceeded
        case networkError(String)
        case invalidResponse
        case unauthorized
        case fileOperationFailed
    }
    
    private static func triggerQueueScore(_ fen: String) {
        Task.detached {
            let baseUrl = "http://api.chessdb.cn:81/chessdb.php"
            var components = URLComponents(string: baseUrl)!
            components.queryItems = [
                URLQueryItem(name: "action", value: "queue"),
                URLQueryItem(name: "board", value: fen)
            ]
            _ = try? await URLSession.shared.data(from: components.url!)
        }
    }
    
    static func queryFenScore(_ fen: String, silentMode: Bool = false) async throws -> Int? {
        let baseUrl = "http://api.chessdb.cn:81/chessdb.php"
        var components = URLComponents(string: baseUrl)!
        
        components.queryItems = [
            URLQueryItem(name: "action", value: "queryscore"),
            URLQueryItem(name: "board", value: fen)
        ]
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IOError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            throw IOError.unauthorized
        }
        
        guard httpResponse.statusCode == 200,
              let responseText = String(data: data, encoding: .utf8) else {
            if !silentMode {
                throw IOError.networkError("查询分数失败")
            }
            return nil
        }
        
        if responseText.contains("unknown") {
            triggerQueueScore(fen)
        }
        
        // 解析响应文本，格式类似 "eval:123"
        if let match = responseText.range(of: #"eval:(-?\d+)"#, options: .regularExpression) {
            let scoreStr = responseText[match].dropFirst(5) // 去掉 "eval:"
            return Int(scoreStr)
        }
        
        if !silentMode {
            throw IOError.networkError("云库返回格式错误：\(responseText)")
        }
        return nil
    }
} 
