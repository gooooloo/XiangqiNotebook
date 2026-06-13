#if DEBUG
#if os(macOS)
import Foundation
import Network
import AppKit
import Security

class RemoteControlServer {
    private var listener: NWListener?
    private let port: UInt16 = 9214
    private let queue = DispatchQueue(label: "RemoteControlServer")

    /// 每次启动生成的随机鉴权 token。
    /// acceptLocalOnly 只挡局域网，挡不住本机浏览器里的恶意网页向 localhost 发请求；
    /// 要求每个请求携带自定义头 X-RemoteControl-Token 才能防 CSRF：
    /// 1) 网页跨域无法读到 token（写在本地文件/控制台）；
    /// 2) 自定义头会触发 CORS 预检，本服务不返回 CORS 头，浏览器据此直接拦截请求。
    let authToken: String = RemoteControlServer.generateToken()

    /// HTTP 头名（小写比较）
    static let tokenHeaderName = "x-remotecontrol-token"

    weak var viewModel: ViewModel?

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // 退化兜底：拼接 UUID（DEBUG 工具，极端情况下可接受）
            return (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// token 文件路径：本地工具读它来构造请求头；远程网页读不到本地文件
    static func tokenFileURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("XiangqiNotebook") else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("remote-control-token.txt")
    }

    private func writeTokenFile() {
        guard let url = Self.tokenFileURL() else { return }
        do {
            try authToken.write(to: url, atomically: true, encoding: .utf8)
            print("[RemoteControlServer] 鉴权 token 已写入 \(url.path)")
        } catch {
            print("[RemoteControlServer] token 文件写入失败：\(error)")
        }
    }

    /// 从原始 HTTP 请求文本中提取 X-RemoteControl-Token 头的值（纯函数，便于单测）
    static func extractToken(from requestString: String) -> String? {
        // 只在头部（首个空行之前）查找，避免 body 里的同名串被误读
        let head: Substring
        if let headerEnd = requestString.range(of: "\r\n\r\n") {
            head = requestString[requestString.startIndex..<headerEnd.lowerBound]
        } else {
            head = Substring(requestString)
        }
        for rawLine in head.split(separator: "\r\n", omittingEmptySubsequences: true) {
            guard let colon = rawLine.firstIndex(of: ":") else { continue }
            let name = rawLine[rawLine.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if name == tokenHeaderName {
                return rawLine[rawLine.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    func start() throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("RemoteControlServer listener failed: \(error)")
            }
        }

        writeTokenFile()
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection, accumulated: Data())
    }

    private func receiveHTTPRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            var data = accumulated
            if let content { data.append(content) }

            if let error {
                print("RemoteControlServer receive error: \(error)")
                connection.cancel()
                return
            }

            if self.hasCompleteHTTPRequest(data) || isComplete {
                self.processHTTPRequest(data: data, connection: connection)
            } else {
                self.receiveHTTPRequest(connection: connection, accumulated: data)
            }
        }
    }

    private func hasCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8) else { return false }
        guard let headerEnd = str.range(of: "\r\n\r\n") else { return false }

        let headerPart = str[str.startIndex..<headerEnd.lowerBound]
        if let clRange = headerPart.range(of: "Content-Length: ", options: .caseInsensitive) {
            let afterCL = headerPart[clRange.upperBound...]
            if let lineEnd = afterCL.firstIndex(of: "\r") ?? afterCL.firstIndex(of: "\n"),
               let contentLength = Int(afterCL[afterCL.startIndex..<lineEnd]) {
                let bodyStart = str[headerEnd.upperBound...]
                return bodyStart.utf8.count >= contentLength
            }
        }

        return true
    }

    // MARK: - Routing

    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let str = String(data: data, encoding: .utf8) else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"Invalid request encoding"}"#)
            return
        }

        let firstLine = str.prefix(while: { $0 != "\r" && $0 != "\n" })
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"Malformed request line"}"#)
            return
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // 鉴权：所有端点都要求正确的 token，防本机浏览器 CSRF
        guard Self.extractToken(from: str) == authToken else {
            sendJSONResponse(connection: connection, status: "403 Forbidden",
                             body: #"{"error":"Missing or invalid X-RemoteControl-Token header"}"#)
            return
        }

        var body = ""
        if let headerEnd = str.range(of: "\r\n\r\n") {
            body = String(str[headerEnd.upperBound...])
        }

        switch (method, path) {
        case ("GET", "/screenshot"):
            handleScreenshot(connection: connection)
        case ("POST", "/action"):
            handleAction(body: body, connection: connection)
        case ("GET", "/state"):
            handleState(connection: connection)
        case ("GET", "/actions"):
            handleListActions(connection: connection)
        default:
            sendJSONResponse(connection: connection, status: "404 Not Found",
                             body: #"{"error":"Unknown endpoint"}"#)
        }
    }

    // MARK: - Screenshot

    private func handleScreenshot(connection: NWConnection) {
        DispatchQueue.main.sync {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow
                    ?? NSApplication.shared.windows.first,
                  let view = window.contentView else {
                sendJSONResponse(connection: connection, status: "503 Service Unavailable",
                                 body: #"{"error":"No window available"}"#)
                return
            }

            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                sendJSONResponse(connection: connection, status: "500 Internal Server Error",
                                 body: #"{"error":"Failed to create bitmap rep"}"#)
                return
            }

            view.cacheDisplay(in: view.bounds, to: rep)

            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                sendJSONResponse(connection: connection, status: "500 Internal Server Error",
                                 body: #"{"error":"Failed to encode PNG"}"#)
                return
            }

            sendBinaryResponse(connection: connection, status: "200 OK",
                               contentType: "image/png", data: pngData)
        }
    }

    // MARK: - Action

    private func handleAction(body: String, connection: NWConnection) {
        guard let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let actionName = json["action"] as? String else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"Missing or invalid 'action' field"}"#)
            return
        }

        guard let actionKey = ActionDefinitions.ActionKey(rawValue: actionName) else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: "{\"error\":\"Unknown action: \(escapeJSON(actionName))\"}")
            return
        }

        guard let vm = viewModel else {
            sendJSONResponse(connection: connection, status: "503 Service Unavailable",
                             body: #"{"error":"ViewModel not available"}"#)
            return
        }

        DispatchQueue.main.sync {
            // 已在主队列同步执行，向编译器声明 MainActor 隔离成立
            MainActor.assumeIsolated {
            if let actionInfo = vm.actionDefinitions.getActionInfo(actionKey) {
                actionInfo.action()
                sendJSONResponse(connection: connection, status: "200 OK",
                                 body: "{\"success\":true,\"action\":\"\(escapeJSON(actionName))\"}")
            } else if let toggleInfo = vm.actionDefinitions.getToggleActionInfo(actionKey) {
                let newValue: Bool
                if let explicitValue = json["value"] as? Bool {
                    newValue = explicitValue
                } else {
                    newValue = !toggleInfo.isOn()
                }
                toggleInfo.action(newValue)
                sendJSONResponse(connection: connection, status: "200 OK",
                                 body: "{\"success\":true,\"action\":\"\(escapeJSON(actionName))\",\"isOn\":\(toggleInfo.isOn())}")
            } else {
                sendJSONResponse(connection: connection, status: "400 Bad Request",
                                 body: "{\"error\":\"Action not registered: \(escapeJSON(actionName))\"}")
            }
            }
        }
    }

    // MARK: - State

    private func handleState(connection: NWConnection) {
        guard let vm = viewModel else {
            sendJSONResponse(connection: connection, status: "503 Service Unavailable",
                             body: #"{"error":"ViewModel not available"}"#)
            return
        }

        DispatchQueue.main.sync {
            // 已在主队列同步执行，向编译器声明 MainActor 隔离成立
            let state = MainActor.assumeIsolated { buildStateJSON(vm) }
            sendJSONResponse(connection: connection, status: "200 OK", body: state)
        }
    }

    @MainActor
    private func buildStateJSON(_ vm: ViewModel) -> String {
        let fen = escapeJSON(vm.currentFen)
        let displayFen = escapeJSON(vm.displayFen)
        let mode = escapeJSON(vm.currentAppMode.rawValue)
        let comment = vm.currentFenComment.map { "\"\(escapeJSON($0))\"" } ?? "null"
        let moveComment = vm.currentMoveComment.map { "\"\(escapeJSON($0))\"" } ?? "null"
        let score = escapeJSON(vm.displayScore)
        let engineScore = escapeJSON(vm.displayEngineScore)
        let orientation = vm.isCurrentBlackOrientation ? "black" : "red"
        let windowTitle = escapeJSON(vm.windowTitle)

        let nextMoves = vm.currentNextMovesListDisplay.map { item in
            "\"\(escapeJSON(item.moveString))\""
        }.joined(separator: ",")

        let variants = vm.currentGameVariantListDisplay.map { item in
            "\"\(escapeJSON(item.moveString))\""
        }.joined(separator: ",")

        let filters = vm.currentFilters.map { "\"\(escapeJSON($0))\"" }.joined(separator: ",")

        return "{\"fen\":\"\(fen)\",\"displayFen\":\"\(displayFen)\",\"mode\":\"\(mode)\","
            + "\"step\":\(vm.currentGameStepDisplay),\"maxStep\":\(vm.maxGameStepDisplay),"
            + "\"orientation\":\"\(orientation)\",\"isHorizontalFlipped\":\(vm.isCurrentHorizontalFlipped),"
            + "\"comment\":\(comment),\"moveComment\":\(moveComment),"
            + "\"score\":\"\(score)\",\"engineScore\":\"\(engineScore)\","
            + "\"showPath\":\(vm.showPath),\"showAllNextMoves\":\(vm.showAllNextMoves),"
            + "\"showLastMove\":\(vm.showLastMove),\"isLocked\":\(vm.isAnyMoveLocked),"
            + "\"isBookmarked\":\(vm.isBookmarked),\"isInReview\":\(vm.isCurrentFenInReview),"
            + "\"filters\":[\(filters)],\"nextMoves\":[\(nextMoves)],"
            + "\"variants\":[\(variants)],\"windowTitle\":\"\(windowTitle)\"}"
    }

    // MARK: - List Actions

    private func handleListActions(connection: NWConnection) {
        let actions = ActionDefinitions.ActionKey.allCases.map { key in
            "\"\(key.rawValue)\""
        }.joined(separator: ",")
        sendJSONResponse(connection: connection, status: "200 OK",
                         body: "{\"actions\":[\(actions)]}")
    }

    // MARK: - Response Helpers

    private func sendJSONResponse(connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendBinaryResponse(connection: NWConnection, status: String,
                                     contentType: String, data: Data) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data(header.utf8)
        responseData.append(data)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func escapeJSON(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
#endif
#endif
