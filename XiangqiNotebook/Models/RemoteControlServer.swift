#if os(macOS)
import Foundation
import Network
import AppKit
import Security

/// 本地操控 / 分析 HTTP 服务（localhost:9214）。
///
/// 接口按能力分两类，编译门禁不同：
/// - **只读分析接口**（Release 也启用）：/state、/eval、/apply、/screenshot——
///   供 MCP server 桥接给 Claude，只读局面/引擎分析/走子计算/截图，不改数据。
/// - **驱动接口**（仅 DEBUG）：/action、/actions——能触发 app 内任意操作，
///   属开发/自动化测试专用，不随正式版发行，以缩小攻击面。
///
/// 两类都要求 X-RemoteControl-Token 头鉴权（防本机浏览器 CSRF）。
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

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // 端口绑定成功后才写 token 文件。
                // 若在 start() 里无条件写：单元测试的宿主 app 实例（端口被占、绑定失败）
                // 也会覆写 token，导致正在运行实例的 token 与磁盘文件不一致，外部工具全部 403
                self?.writeTokenFile()
            case .failed(let error):
                print("RemoteControlServer listener failed: \(error)")
            default:
                break
            }
        }

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
        // 只读分析接口（Release 也启用）
        case ("GET", "/screenshot"):
            handleScreenshot(connection: connection)
        case ("GET", "/state"):
            handleState(connection: connection)
        case ("POST", "/eval"):
            handleEval(body: body, connection: connection)
        case ("POST", "/apply"):
            handleApply(body: body, connection: connection)
        // 驱动接口（仅 DEBUG）：能触发 app 内任意操作，不随正式版发行
        #if DEBUG
        case ("POST", "/action"):
            handleAction(body: body, connection: connection)
        case ("GET", "/actions"):
            handleListActions(connection: connection)
        #endif
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

    // MARK: - Action（仅 DEBUG：能驱动 app 内任意操作）

    #if DEBUG
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
    #endif

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

    // MARK: - Eval (Pikafish MultiPV)

    /// /eval 请求参数（纯函数解析 + 范围钳制，便于单测）
    struct EvalParams: Equatable {
        var fen: String?
        var multiPV: Int
        var movetime: Int
    }

    static func parseEvalParams(json: [String: Any]?) -> EvalParams {
        let fen = json?["fen"] as? String
        let multiPV = min(10, max(1, json?["multipv"] as? Int ?? 3))
        let movetime = min(60000, max(500, json?["movetime"] as? Int ?? 5000))
        return EvalParams(fen: fen, multiPV: multiPV, movetime: movetime)
    }

    /// 把 UCI 主变序列转成中文着法序列（逐步应用到局面上；遇到非法着法截断）
    static func chinesePV(fen: String, uciMoves: [String]) -> [String] {
        var currentFen = fen
        var result: [String] = []
        for uci in uciMoves {
            guard let nextFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: uci, fen: currentFen) else { break }
            result.append(Move.stringifyMove(fen1: currentFen, fen2: nextFen, backup: uci, isHorizontalFlipped: false))
            currentFen = nextFen
        }
        return result
    }

    // MARK: - Apply Moves

    struct AppliedMove: Equatable {
        let uci: String
        let chinese: String
        let fen: String
    }

    /// 把一串 UCI 着法依次应用到局面上（纯函数，便于单测）。
    /// 只做机械移动（起点须有子），不校验象棋规则合法性。
    /// 返回成功应用的着法列表；failedIndex 指向首个无法应用的着法（全部成功则为 nil）
    static func applyUCIMoves(fen: String, uciMoves: [String]) -> (applied: [AppliedMove], failedIndex: Int?) {
        var currentFen = fen
        var applied: [AppliedMove] = []
        for (index, uci) in uciMoves.enumerated() {
            guard let nextFen = XiangqiBoardUtils.getNewFenAfterUCIMove(uciMove: uci, fen: currentFen) else {
                return (applied, index)
            }
            let chinese = Move.stringifyMove(fen1: currentFen, fen2: nextFen, backup: uci, isHorizontalFlipped: false)
            applied.append(AppliedMove(uci: uci, chinese: chinese, fen: nextFen))
            currentFen = nextFen
        }
        return (applied, nil)
    }

    private func handleApply(body: String, connection: NWConnection) {
        guard let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let fen = json["fen"] as? String,
              let moves = json["moves"] as? [String] else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"Expect JSON body {\"fen\":\"...\",\"moves\":[\"h2e2\",...]}"}"#)
            return
        }

        let fenParts = fen.split(separator: " ")
        guard XiangqiBoardUtils.isValidBoardFen(fen),
              fenParts.count >= 2, ["r", "b", "w"].contains(String(fenParts[1])) else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"Invalid fen (expect board + side, e.g. '.../RNBAKABNR r')"}"#)
            return
        }

        let result = Self.applyUCIMoves(fen: fen, uciMoves: moves)
        if let failedIndex = result.failedIndex {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: "{\"error\":\"Cannot apply move at index \(failedIndex): "
                                + "\(escapeJSON(moves[failedIndex])) (malformed or no piece at source)\"}")
            return
        }

        let steps = result.applied.map { step in
            "{\"uci\":\"\(escapeJSON(step.uci))\",\"chinese\":\"\(escapeJSON(step.chinese))\",\"fen\":\"\(escapeJSON(step.fen))\"}"
        }.joined(separator: ",")
        let finalFen = result.applied.last?.fen ?? fen
        sendJSONResponse(connection: connection, status: "200 OK",
                         body: "{\"startFen\":\"\(escapeJSON(fen))\",\"steps\":[\(steps)],"
                            + "\"finalFen\":\"\(escapeJSON(finalFen))\"}")
    }

    private func handleEval(body: String, connection: NWConnection) {
        let json = body.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let params = Self.parseEvalParams(json: json)

        guard let vm = viewModel else {
            sendJSONResponse(connection: connection, status: "503 Service Unavailable",
                             body: #"{"error":"ViewModel not available"}"#)
            return
        }

        // 引擎分析耗时数秒，不能像其他端点一样在 server 队列上 main.sync 等待；
        // 丢进 MainActor Task，评估的 await 挂起期间不阻塞主线程，完成后再发响应
        Task { @MainActor [weak self] in
            guard let self else { return }

            let fen = params.fen ?? vm.currentFen
            let fenParts = fen.split(separator: " ")
            guard XiangqiBoardUtils.isValidBoardFen(fen),
                  fenParts.count >= 2, ["r", "b", "w"].contains(String(fenParts[1])) else {
                self.sendJSONResponse(connection: connection, status: "400 Bad Request",
                                      body: #"{"error":"Invalid fen (expect board + side, e.g. '.../RNBAKABNR r')"}"#)
                return
            }

            do {
                let lines = try await vm.remoteEngineAnalyze(
                    fen: fen, multiPV: params.multiPV, movetime: params.movetime)
                let sideToMove = String(fenParts[1]) == "b" ? "black" : "red"
                let lineJSONs = lines.map { line -> String in
                    let uci = line.moves.map { "\"\(self.escapeJSON($0))\"" }.joined(separator: ",")
                    let chinese = Self.chinesePV(fen: fen, uciMoves: line.moves)
                        .map { "\"\(self.escapeJSON($0))\"" }.joined(separator: ",")
                    let depth = line.depth.map(String.init) ?? "null"
                    return "{\"rank\":\(line.multipv),\"scoreCp\":\(line.scoreCp),\"depth\":\(depth),"
                        + "\"pvUci\":[\(uci)],\"pvChinese\":[\(chinese)]}"
                }.joined(separator: ",")
                let responseBody = "{\"fen\":\"\(self.escapeJSON(fen))\",\"sideToMove\":\"\(sideToMove)\","
                    + "\"scorePerspective\":\"sideToMove\","
                    + "\"engine\":\"\(self.escapeJSON(PikafishService.engineVersion))\","
                    + "\"movetimeMs\":\(params.movetime),\"lines\":[\(lineJSONs)]}"
                self.sendJSONResponse(connection: connection, status: "200 OK", body: responseBody)
            } catch let error as ViewModel.RemoteAnalyzeError {
                self.sendJSONResponse(connection: connection, status: "409 Conflict",
                                      body: "{\"error\":\"\(self.escapeJSON(error.localizedDescription))\"}")
            } catch {
                self.sendJSONResponse(connection: connection, status: "500 Internal Server Error",
                                      body: "{\"error\":\"\(self.escapeJSON(error.localizedDescription))\"}")
            }
        }
    }

    // MARK: - List Actions（仅 DEBUG：配合 /action）

    #if DEBUG
    private func handleListActions(connection: NWConnection) {
        let actions = ActionDefinitions.ActionKey.allCases.map { key in
            "\"\(key.rawValue)\""
        }.joined(separator: ",")
        sendJSONResponse(connection: connection, status: "200 OK",
                         body: "{\"actions\":[\(actions)]}")
    }
    #endif

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
