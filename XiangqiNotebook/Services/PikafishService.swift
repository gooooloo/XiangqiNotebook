#if os(macOS)
import Foundation

/// Pikafish 引擎通信服务
/// 通过 Process + Pipe 以 UCI 协议与 Pikafish 引擎通信
class PikafishService: @unchecked Sendable {

    // MARK: - Properties

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputBuffer = ""
    private var isReady = false


    /// 引擎版本
    static let engineVersion = "Pikafish_dev-20260213-391d491a"

    /// 搜索深度
    static let searchDepth = 34

    /// 引擎 key，用于引擎分数独立存储的文件名（深度评分）
    static let engineKey = "Pikafish_dev-20260213-391d491a_d34"

    /// 快速估分 key，用于 3 秒限时评分的独立存储
    static let quickEngineKey = "Pikafish_dev-20260213-391d491a_t3s"

    // MARK: - FEN Conversion

    static func convertFenToUCI(_ fen: String) -> String {
        PikafishFenConversion.convertFenToUCI(fen)
    }

    // MARK: - Score Parsing

    /// 从 UCI info 行中解析分数
    /// 解析 "info depth 18 ... score cp 35 ..." 格式
    static func parseScore(from infoLine: String) -> Int? {
        let parts = infoLine.split(separator: " ")
        guard let scoreIndex = parts.firstIndex(of: "score"),
              scoreIndex + 2 < parts.count else {
            return nil
        }

        let scoreType = parts[scoreIndex + 1]
        let scoreValue = parts[scoreIndex + 2]

        if scoreType == "cp", let value = Int(scoreValue) {
            return value
        } else if scoreType == "mate", let moves = Int(scoreValue) {
            // 将杀棋转换为大分数值
            return moves > 0 ? 30000 - moves : -30000 - moves
        }

        return nil
    }

    // MARK: - Engine Lifecycle

    /// 启动引擎进程
    /// 进程引用存在但已死（引擎崩溃/上次启动失败残留）时清理后重新启动，
    /// 否则 evaluatePosition 的重启路径会拿着死管道反复超时，引擎永久失效
    func start() async throws {
        if let existing = process {
            if existing.isRunning { return }
            print("[Pikafish] 检测到引擎进程已退出，清理并重新启动")
            cleanup()
        }

        guard let executableURL = Bundle.main.url(forResource: "pikafish", withExtension: nil) else {
            throw PikafishError.engineNotFound
        }

        // Find NNUE file in bundle
        let nnueURL = Bundle.main.url(forResource: "pikafish", withExtension: "nnue")

        let proc = Process()
        proc.executableURL = executableURL
        // Set working directory to the directory containing the NNUE file
        if let nnueDir = nnueURL?.deletingLastPathComponent() {
            proc.currentDirectoryURL = nnueDir
        }

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        self.process = proc
        self.inputPipe = inPipe
        self.outputPipe = outPipe
        self.outputBuffer = ""
        self.isReady = false

        do {
            try proc.run()

            // Send UCI init
            sendCommand("uci")
            _ = try await waitForResponse(containing: "uciok", timeout: 5.0)

            // Set NNUE file if found
            if let nnuePath = nnueURL?.path {
                sendCommand("setoption name EvalFile value \(nnuePath)")
            }

            // 使用多线程加速搜索
            let threadCount = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
            sendCommand("setoption name Threads value \(threadCount)")
            sendCommand("setoption name Hash value 4096")

            sendCommand("isready")
            _ = try await waitForResponse(containing: "readyok", timeout: 5.0)
            isReady = true
        } catch {
            // 启动失败不留半初始化状态，下次 start() 可干净重试
            if proc.isRunning { proc.terminate() }
            cleanup()
            throw error
        }
    }

    /// 停止引擎进程。
    /// waitUntilExit 无超时会在引擎卡死时挂死 app 退出，
    /// 这里轮询等待最多 2 秒，超时强制 terminate
    func stop() {
        guard let proc = process, proc.isRunning else {
            cleanup()
            return
        }
        sendCommand("quit")
        let deadline = Date().addingTimeInterval(2.0)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            print("[Pikafish] quit 超时，强制终止引擎进程")
            proc.terminate()
        }
        cleanup()
    }

    private func cleanup() {
        process = nil
        inputPipe = nil
        outputPipe = nil
        outputBuffer = ""
        isReady = false
    }

    // MARK: - Evaluation Result

    struct EvaluationResult {
        let score: Int
        let depth: String?
        let timeMs: Int?
        let hashfull: Int?
        let timedOut: Bool
        let bestMove: String?
    }

    // MARK: - Best Move Parsing

    /// 从 bestmove 响应行解析 UCI 着法
    /// 解析 "bestmove h2e2 ponder ..." → "h2e2"
    /// "bestmove (none)" → nil
    static func parseBestMove(from response: String) -> String? {
        for line in response.split(separator: "\n") {
            let lineStr = String(line).trimmingCharacters(in: .whitespaces)
            guard lineStr.hasPrefix("bestmove") else { continue }
            let parts = lineStr.split(separator: " ")
            guard parts.count >= 2 else { return nil }
            let move = String(parts[1])
            if move == "(none)" { return nil }
            return move
        }
        return nil
    }

    // MARK: - Evaluation

    /// 中断当前搜索（用于取消评估）
    func stopCurrentSearch() {
        sendCommand("stop")
    }

    func evaluatePosition(fen: String, movetime: Int? = nil) async throws -> EvaluationResult? {

        // Start engine if needed
        if process == nil || !(process?.isRunning ?? false) {
            try await start()
        }

        let uciFen = Self.convertFenToUCI(fen)

        // 先停止可能正在进行的搜索，然后用 isready/readyok 同步引擎
        sendCommand("stop")
        outputBuffer = ""
        sendCommand("isready")
        _ = try await waitForResponse(containing: "readyok", timeout: 10.0)

        // 清空缓冲区，确保只包含本次评估的输出
        outputBuffer = ""

        sendCommand("position fen \(uciFen)")
        if let movetime = movetime {
            sendCommand("go movetime \(movetime)")
        } else {
            sendCommand("go depth \(Self.searchDepth)")
        }

        var response: String
        var timedOut = false
        do {
            response = try await waitForResponse(containing: "bestmove", timeout: 120.0)
        } catch PikafishError.timeout {
            // 超时：发 stop 让引擎立即返回 bestmove，解析已搜索到的最佳分数
            timedOut = true
            sendCommand("stop")
            response = try await waitForResponse(containing: "bestmove", timeout: 10.0)
        }

        // Parse the last "info" line with score, log search progress
        var lastScore: Int?
        var lastDepth: String?
        var lastHashfull: String?
        var lastTime: String?
        for line in response.split(separator: "\n") {
            let lineStr = String(line)
            if lineStr.contains("info") && lineStr.contains("depth") {
                let parts = lineStr.split(separator: " ")
                if let depthIdx = parts.firstIndex(of: "depth"), depthIdx + 1 < parts.count {
                    lastDepth = String(parts[depthIdx + 1])
                }
                if let hashIdx = parts.firstIndex(of: "hashfull"), hashIdx + 1 < parts.count {
                    lastHashfull = String(parts[hashIdx + 1])
                }
                if let timeIdx = parts.firstIndex(of: "time"), timeIdx + 1 < parts.count {
                    lastTime = String(parts[timeIdx + 1])
                }
                if lineStr.contains("score") {
                    if let score = Self.parseScore(from: lineStr) {
                        lastScore = score
                    }
                }
            }
        }

        let timeMsInt = lastTime.flatMap { Int($0) }
        let hashfullInt = lastHashfull.flatMap { Int($0) }

        let timeStr: String
        if let ms = timeMsInt {
            timeStr = String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            timeStr = "?"
        }
        print("[Pikafish] depth=\(lastDepth ?? "?") hashfull=\(lastHashfull ?? "?")/1000 time=\(timeStr) score=\(lastScore.map { String($0) } ?? "nil")\(timedOut ? " (timeout)" : "")")

        guard let score = lastScore else { return nil }
        let bestMove = Self.parseBestMove(from: response)
        return EvaluationResult(score: score, depth: lastDepth, timeMs: timeMsInt, hashfull: hashfullInt, timedOut: timedOut, bestMove: bestMove)
    }

    // MARK: - UCI Communication

    private func sendCommand(_ command: String) {
        guard let inputPipe = inputPipe else { return }
        let data = (command + "\n").data(using: .utf8)!
        inputPipe.fileHandleForWriting.write(data)
    }

    private func waitForResponse(containing keyword: String, timeout: TimeInterval) async throws -> String {
        guard let outputPipe = outputPipe else {
            throw PikafishError.notRunning
        }

        let fileHandle = outputPipe.fileHandleForReading
        let startTime = Date()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PikafishError.notRunning)
                    return
                }

                while true {
                    // Check timeout
                    if Date().timeIntervalSince(startTime) > timeout {
                        continuation.resume(throwing: PikafishError.timeout)
                        return
                    }

                    // 用 poll 检查是否有数据可读，避免 availableData 阻塞超时检查
                    var pollFd = pollfd(fd: fileHandle.fileDescriptor, events: Int16(POLLIN), revents: 0)
                    let pollResult = poll(&pollFd, 1, 100) // 100ms 超时
                    if pollResult <= 0 {
                        continue // 无数据或出错，回到循环检查超时
                    }

                    let availableData = fileHandle.availableData
                    if availableData.isEmpty {
                        // poll 报告可读但读到 0 字节 = EOF（POLLHUP），引擎进程已死。
                        // 立即报错，避免在此热循环空转直至超时
                        continuation.resume(throwing: PikafishError.engineTerminated)
                        return
                    }

                    if let text = String(data: availableData, encoding: .utf8) {
                        self.outputBuffer += text

                        // 只在完整行中匹配关键字：管道可能半行送达，
                        // 直接 contains 会在 "bestmove h2" 截断时提前返回并解析出残缺着法
                        if let completed = Self.completedPortion(of: self.outputBuffer, containing: keyword) {
                            continuation.resume(returning: completed)
                            return
                        }
                    }
                }
            }
        }
    }

    /// 返回缓冲区中以换行结尾的完整部分；仅当该部分包含关键字时返回，否则 nil。
    /// 关键字只在完整行中匹配，最后一段未换行的半行不参与匹配
    static func completedPortion(of buffer: String, containing keyword: String) -> String? {
        guard let lastNewline = buffer.range(of: "\n", options: .backwards) else { return nil }
        let completed = String(buffer[..<lastNewline.upperBound])
        return completed.contains(keyword) ? completed : nil
    }

    // MARK: - Error Types

    enum PikafishError: Error, LocalizedError {
        case engineNotFound
        case notRunning
        case timeout
        case evaluationFailed
        case engineTerminated

        var errorDescription: String? {
            switch self {
            case .engineNotFound: return "找不到 Pikafish 引擎文件"
            case .notRunning: return "引擎未运行"
            case .timeout: return "引擎响应超时"
            case .evaluationFailed: return "评估失败"
            case .engineTerminated: return "引擎进程已退出"
            }
        }
    }

    deinit {
        stop()
    }
}
#endif
