#if os(macOS)
import Foundation
import Network
import AppKit
import Security

/// 本地操控 / 分析 HTTP 服务（localhost:9214）。
///
/// 接口按能力分两类，编译门禁不同：
/// - **只读分析接口**（Release 也启用）：/state、/eval、/eval_move、/apply、/screenshot——
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
            // 仅本用户可读（默认 0644）；与 claude-bridge 写 token 的权限一致
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
        // 明确只绑 IPv6 回环：此前 listener 实际只在 IPv6 可达，而 127.0.0.1 的 v4-mapped 连接
        // 会把监听队列打进假死态（所有后续请求超时，只能重启 app）。绑死 ::1 后 v4 连接直接被拒
        params.requiredLocalEndpoint = .hostPort(host: "::1", port: nwPort)
        listener = try NWListener(using: params)

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

    /// 单个请求（头 + body）上限。/import_course 一节课的线路也远小于此；
    /// 没有上限的话任何本机进程不带 token 也能让 app 无限吞 body
    static let maxRequestBytes = 1 << 20
    private static let headerTerminator = Data("\r\n\r\n".utf8)

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

            if data.count > Self.maxRequestBytes {
                self.sendJSONResponse(connection: connection, status: "413 Payload Too Large",
                                      body: #"{"error":"Request too large"}"#)
                return
            }

            // 头部一到齐就先鉴权，再决定要不要继续收 body。按字节找头尾而不是先整体转字符串：
            // body 若含非法 UTF-8，String(data:) 会失败，连接就会一直挂到对端关闭
            if let headerEnd = data.range(of: Self.headerTerminator) {
                let header = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
                guard Self.extractToken(from: header) == self.authToken else {
                    self.sendJSONResponse(connection: connection, status: "403 Forbidden",
                                          body: #"{"error":"Missing or invalid X-RemoteControl-Token header"}"#)
                    return
                }
                let bodyReceived = data.count - headerEnd.upperBound
                if bodyReceived >= (Self.contentLength(inHeader: header) ?? 0) {
                    self.processHTTPRequest(data: data, connection: connection)
                    return
                }
            }

            if isComplete {
                self.processHTTPRequest(data: data, connection: connection)
            } else {
                self.receiveHTTPRequest(connection: connection, accumulated: data)
            }
        }
    }

    /// 从头部文本解析 Content-Length（纯函数，便于单测）；没有该头返回 nil
    static func contentLength(inHeader header: String) -> Int? {
        // 注意 Swift 把 "\r\n" 视为一个 Character，不能按 "\r"/"\n" 逐字符拆；按 scalar 级换行集拆
        for rawLine in header.components(separatedBy: .newlines) where !rawLine.isEmpty {
            guard let colon = rawLine.firstIndex(of: ":") else { continue }
            let name = rawLine[rawLine.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if name == "content-length" {
                return Int(rawLine[rawLine.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
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
        case ("POST", "/eval_move"):
            handleEvalMove(body: body, connection: connection)
        case ("POST", "/apply"):
            handleApply(body: body, connection: connection)
        // 驱动接口（仅 DEBUG）：能触发 app 内任意操作，不随正式版发行
        #if DEBUG
        case ("POST", "/action"):
            handleAction(body: body, connection: connection)
        case ("GET", "/actions"):
            handleListActions(connection: connection)
        case ("POST", "/import_course"):
            handleImportCourse(body: body, connection: connection)
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
                             body: AnalysisToolbox.errorJSON("Unknown action: \(actionName)"))
            return
        }

        guard let vm = viewModel else {
            sendJSONResponse(connection: connection, status: "503 Service Unavailable",
                             body: #"{"error":"ViewModel not available"}"#)
            return
        }

        // async 而非 sync：action 可能弹模态（NSAlert.runModal），sync 会把 server 串行队列
        // 卡到用户点掉弹窗为止，期间连 Release 也有的 /state 都超时
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
            if let actionInfo = vm.actionDefinitions.getActionInfo(actionKey) {
                actionInfo.action()
                self.sendJSONResponse(connection: connection, status: "200 OK",
                                      body: AnalysisToolbox.json(["success": true, "action": actionName]))
            } else if let toggleInfo = vm.actionDefinitions.getToggleActionInfo(actionKey) {
                let newValue: Bool
                if let explicitValue = json["value"] as? Bool {
                    newValue = explicitValue
                } else {
                    newValue = !toggleInfo.isOn()
                }
                toggleInfo.action(newValue)
                self.sendJSONResponse(connection: connection, status: "200 OK",
                                      body: AnalysisToolbox.json(["success": true, "action": actionName, "isOn": toggleInfo.isOn()]))
            } else {
                self.sendJSONResponse(connection: connection, status: "400 Bad Request",
                                      body: AnalysisToolbox.errorJSON("Action not registered: \(actionName)"))
            }
            }
        }
    }
    #endif

    // MARK: - Import Course（仅 DEBUG：把课程视频识别出的棋谱线路导入课程棋书）

    #if DEBUG
    private func handleImportCourse(body: String, connection: NWConnection) {
        guard let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let name = json["name"] as? String,
              let bookPath = json["bookPath"] as? [String],
              let linesJson = json["lines"] as? [[String: Any]] else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"需要 name、bookPath、lines 字段"}"#)
            return
        }
        var lines: [CourseImportService.LineInput] = []
        for lineJson in linesJson {
            guard let moves = lineJson["moves"] as? [String] else {
                sendJSONResponse(connection: connection, status: "400 Bad Request",
                                 body: #"{"error":"lines 各项需要 moves 字段"}"#)
                return
            }
            lines.append(CourseImportService.LineInput(
                startFen: lineJson["startFen"] as? String,
                moves: moves,
                times: lineJson["times"] as? [Double] ?? []))
        }
        let videoPath = json["videoPath"] as? String

        guard let vm = viewModel else {
            sendJSONResponse(connection: connection, status: "503 Service Unavailable",
                             body: #"{"error":"ViewModel not available"}"#)
            return
        }

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do {
                    let result = try vm.importCourseGame(
                        bookPath: bookPath, name: name, lines: lines, videoPath: videoPath)
                    self.sendJSONResponse(connection: connection, status: "200 OK",
                                          body: AnalysisToolbox.json([
                                            "ok": true, "gameId": result.gameId.uuidString,
                                            "lines": result.lineCount, "moves": result.moveCount,
                                            "timestamps": result.fenTimestamps.count]))
                } catch {
                    // 业务失败也回 200，错误语义在 body 里（与 /eval_move 的约定一致）
                    self.sendJSONResponse(connection: connection, status: "200 OK",
                                          body: AnalysisToolbox.json(["ok": false, "error": String(describing: error)]))
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

    /// 字段与 app 内 AI 的 get_position 工具同源（见 `PositionSnapshot`），
    /// 两条路不会漂移。改用 JSONSerialization 顺带修掉了手写转义漏掉控制字符的问题——
    /// 注释里若含  之类，旧的字符串拼接会产出非法 JSON。
    @MainActor
    private func buildStateJSON(_ vm: ViewModel) -> String {
        AnalysisToolbox.json(vm.currentPositionSnapshot().remoteStateDictionary())
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

    // MARK: - Eval Move

    /// evaluate_move 工具的远程入口，语义与 app 内 AI 的同名工具完全一致——
    /// 直接复用 `AnalysisToolbox.execute`，中文着法解析、mover 视角换算、
    /// rank 判断都不重复实现，两条路（MCP、app 内）永不漂移。
    ///
    /// 响应恒为 200：成功 `{"ok":true,...}`，业务失败 `{"ok":false,"error":{code,message}}`。
    /// 与 /eval 的「HTTP 状态码 + {"error":字符串}」不同——本端点面向模型而非人，
    /// 沿用工具层契约，让模型按 ok 字段分支（引擎忙就重试、着法非法就换一步）。
    private func handleEvalMove(body: String, connection: NWConnection) {
        guard let vm = viewModel else {
            sendJSONResponse(connection: connection, status: "503 Service Unavailable",
                             body: #"{"error":"ViewModel not available"}"#)
            return
        }
        // 同 handleEval：引擎分析耗时数秒，丢进 MainActor Task，不阻塞 server 队列
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await AnalysisToolbox(host: vm)
                .execute(toolName: "evaluate_move", argumentsJSON: body)
            self.sendJSONResponse(connection: connection, status: "200 OK", body: result)
        }
    }

    // MARK: - Apply Moves

    private func handleApply(body: String, connection: NWConnection) {
        guard let jsonData = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let fen = json["fen"] as? String,
              let moves = json["moves"] as? [String] else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"Expect JSON body {\"fen\":\"...\",\"moves\":[\"h2e2\",...]}"}"#)
            return
        }

        guard AnalysisToolbox.isValidPositionFen(fen) else {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: #"{"error":"Invalid fen (expect board + side, e.g. '.../RNBAKABNR r')"}"#)
            return
        }

        let result = AnalysisToolbox.applyUCIMoves(fen: fen, uciMoves: moves)
        if let failedIndex = result.failedIndex {
            sendJSONResponse(connection: connection, status: "400 Bad Request",
                             body: AnalysisToolbox.errorJSON(
                                "Cannot apply move at index \(failedIndex): "
                                + "\(moves[failedIndex]) (malformed or no piece at source)"))
            return
        }

        sendJSONResponse(connection: connection, status: "200 OK",
                         body: AnalysisToolbox.json([
                            "startFen": fen,
                            "steps": result.applied.map {
                                ["uci": $0.uci, "chinese": $0.chinese, "fen": $0.fen]
                            },
                            "finalFen": result.applied.last?.fen ?? fen,
                         ]))
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
            guard AnalysisToolbox.isValidPositionFen(fen) else {
                self.sendJSONResponse(connection: connection, status: "400 Bad Request",
                                      body: #"{"error":"Invalid fen (expect board + side, e.g. '.../RNBAKABNR r')"}"#)
                return
            }

            do {
                let lines = try await vm.remoteEngineAnalyze(
                    fen: fen, multiPV: params.multiPV, movetime: params.movetime)
                self.sendJSONResponse(connection: connection, status: "200 OK",
                                      body: AnalysisToolbox.json([
                                        "fen": fen,
                                        "sideToMove": AnalysisToolbox.sideToMove(fen: fen),
                                        "scorePerspective": "sideToMove",
                                        "engine": vm.engineVersionDescription,
                                        "movetimeMs": params.movetime,
                                        "lines": lines.map { line in
                                            [
                                                "rank": line.multipv,
                                                "scoreCp": line.scoreCp,
                                                "mate": line.mate as Any? ?? NSNull(),
                                                "depth": line.depth as Any? ?? NSNull(),
                                                "pvUci": line.moves,
                                                "pvChinese": AnalysisToolbox.chinesePV(
                                                    fen: fen, uciMoves: line.moves),
                                            ] as [String: Any]
                                        },
                                      ]))
            } catch let error as ViewModel.RemoteAnalyzeError {
                self.sendJSONResponse(connection: connection, status: "409 Conflict",
                                      body: AnalysisToolbox.errorJSON(error.localizedDescription))
            } catch {
                self.sendJSONResponse(connection: connection, status: "500 Internal Server Error",
                                      body: AnalysisToolbox.errorJSON(error.localizedDescription))
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

}
#endif
