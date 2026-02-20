#if os(macOS)
import Foundation

/// Pikafish 引擎通信服务
/// 通过 Process + Pipe 以 UCI 协议与 Pikafish 引擎通信
class PikafishService {

    // MARK: - Properties

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputBuffer = ""
    private var isReady = false

    /// 串行化评估请求，防止并发访问引擎
    private let evaluationLock = NSLock()

    /// 引擎版本
    static let engineVersion = "Pikafish_dev-20260213-391d491a"

    /// 搜索深度
    static let searchDepth = 34

    /// 引擎 key，用于引擎分数独立存储的文件名
    static let engineKey = "Pikafish_dev-20260213-391d491a_d34"

    // MARK: - FEN Conversion

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
        let uciSide = sideChar == "r" ? "w" : "b"

        // If already has enough fields, just fix the side
        if parts.count >= 6 {
            var mutableParts = parts.map { String($0) }
            mutableParts[1] = uciSide
            return mutableParts.joined(separator: " ")
        }

        // Otherwise build full UCI FEN
        return "\(board) \(uciSide) - - 0 1"
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
    func start() async throws {
        guard process == nil else { return }

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
    }

    /// 停止引擎进程
    func stop() {
        guard let proc = process, proc.isRunning else {
            cleanup()
            return
        }
        sendCommand("quit")
        proc.waitUntilExit()
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
    }

    // MARK: - Evaluation

    /// 评估指定局面
    /// - Parameter fen: App 内部 FEN 格式
    /// - Returns: 评估结果（含分数、深度、耗时等），nil 表示评估失败
    func evaluatePosition(fen: String) async throws -> EvaluationResult? {
        // 如果已有评估在进行中，直接返回 nil（不阻塞等待）
        guard evaluationLock.try() else { return nil }
        defer { evaluationLock.unlock() }

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
        sendCommand("go depth \(Self.searchDepth)")

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
        return EvaluationResult(score: score, depth: lastDepth, timeMs: timeMsInt, hashfull: hashfullInt, timedOut: timedOut)
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
                        continue
                    }

                    if let text = String(data: availableData, encoding: .utf8) {
                        self.outputBuffer += text

                        if self.outputBuffer.contains(keyword) {
                            continuation.resume(returning: self.outputBuffer)
                            return
                        }
                    }
                }
            }
        }
    }

    // MARK: - Error Types

    enum PikafishError: Error, LocalizedError {
        case engineNotFound
        case notRunning
        case timeout
        case evaluationFailed

        var errorDescription: String? {
            switch self {
            case .engineNotFound: return "找不到 Pikafish 引擎文件"
            case .notRunning: return "引擎未运行"
            case .timeout: return "引擎响应超时"
            case .evaluationFailed: return "评估失败"
            }
        }
    }

    deinit {
        stop()
    }
}
#endif
