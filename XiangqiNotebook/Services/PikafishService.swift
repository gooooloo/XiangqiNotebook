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

    // MARK: - Serialization

    /// 引擎只有一条 UCI 管道，同一时刻只能跑一个搜索。评估队列、快速应招、远程 /eval
    /// 三个入口并发调用时在这里排队：后到者等前一个结束再发命令。否则两个
    /// waitForResponse 会在两条线程上抢读同一管道、无锁拼 outputBuffer，
    /// 后到者开头的 stop 还会偷走前者的 bestmove。
    /// `tail` 用锁保护——调用方目前都在主线程，但服务本身不应依赖这一点
    private let serialLock = NSLock()
    private var tail: Task<Void, Never>?

    private func serialized<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        serialLock.lock()
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        serialLock.unlock()
        return try await task.value
    }

    /// 引擎进程若已退出（崩溃 / NNUE 校验失败自行 exit），再向管道写入会收到 SIGPIPE，
    /// 默认动作是杀掉整个 app。进程级只需忽略一次；写入失败由 sendCommand 自行吞掉
    private static let ignoreSIGPIPE: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()


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

    /// 从 UCI info 行中解析杀棋步数。
    /// `score mate 3` → 3（走子方 3 步成杀）；`score mate -2` → -2（走子方 2 步被杀）；
    /// 非杀棋行返回 nil
    static func parseMate(from infoLine: String) -> Int? {
        let parts = infoLine.split(separator: " ")
        guard let scoreIndex = parts.firstIndex(of: "score"),
              scoreIndex + 2 < parts.count,
              parts[scoreIndex + 1] == "mate" else {
            return nil
        }
        return Int(parts[scoreIndex + 2])
    }

    /// 置换表大小：物理内存的 1/8，钳在 256MB～4GB。
    /// 固定 4GB 在 8GB 内存的 Mac 上深评一局就会把系统压进 swap
    static func hashSizeMB(physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Int {
        let eighth = Int(physicalMemoryBytes / (1024 * 1024)) / 8
        return min(4096, max(256, eighth))
    }

    // MARK: - Engine Lifecycle

    /// 启动引擎进程
    /// 进程引用存在但已死（引擎崩溃/上次启动失败残留）时清理后重新启动，
    /// 否则 evaluatePosition 的重启路径会拿着死管道反复超时，引擎永久失效
    func start() async throws {
        _ = Self.ignoreSIGPIPE
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
            sendCommand("setoption name Hash value \(Self.hashSizeMB())")

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

    // MARK: - MultiPV Analysis

    /// 单条主变。形状与 iOS 内嵌引擎共用（见 `EngineAnalyzing.swift`），
    /// 保留这个别名是为了不动既有调用点与测试。
    typealias PVLine = EnginePVLine

    /// 从引擎响应中解析 MultiPV 各线路。
    /// 同一 multipv 序号取最后一次出现（搜索更深的结果覆盖浅的）；
    /// 无 multipv 字段的 info 行按序号 1 处理
    static func parsePVLines(from response: String) -> [PVLine] {
        var linesByIndex: [Int: PVLine] = [:]
        for rawLine in response.split(separator: "\n") {
            let line = String(rawLine)
            guard line.hasPrefix("info"), line.contains(" score "), line.contains(" pv ") else { continue }
            let parts = line.split(separator: " ").map(String.init)
            guard let pvIdx = parts.firstIndex(of: "pv"), pvIdx + 1 < parts.count,
                  let score = parseScore(from: line) else { continue }
            var multipv = 1
            if let mpvIdx = parts.firstIndex(of: "multipv"), mpvIdx + 1 < parts.count,
               let v = Int(parts[mpvIdx + 1]) {
                multipv = v
            }
            var depth: Int?
            if let dIdx = parts.firstIndex(of: "depth"), dIdx + 1 < parts.count {
                depth = Int(parts[dIdx + 1])
            }
            let moves = Array(parts[(pvIdx + 1)...])
            linesByIndex[multipv] = PVLine(multipv: multipv, scoreCp: score,
                                           mate: parseMate(from: line), depth: depth, moves: moves)
        }
        return linesByIndex.keys.sorted().compactMap { linesByIndex[$0] }
    }

    /// MultiPV 多变着分析：返回前 N 条候选线路及各自分数与主变。
    /// 只读分析，不涉及数据库；供远程操控 /eval 端点使用
    func analyzePosition(fen: String, multiPV: Int, movetime: Int) async throws -> [PVLine] {
        try await serialized { try await self.analyzePositionUnserialized(fen: fen, multiPV: multiPV, movetime: movetime) }
    }

    private func analyzePositionUnserialized(fen: String, multiPV: Int, movetime: Int) async throws -> [PVLine] {
        if process == nil || !(process?.isRunning ?? false) {
            try await start()
        }

        let uciFen = Self.convertFenToUCI(fen)

        // 与 evaluatePosition 相同的同步序：停掉残留搜索，isready 对齐
        sendCommand("stop")
        outputBuffer = ""
        sendCommand("isready")
        _ = try await waitForResponse(containing: "readyok", timeout: 10.0)

        outputBuffer = ""
        sendCommand("setoption name MultiPV value \(multiPV)")
        // 结束后必须恢复单线路：evaluatePosition 的分数解析取"最后一条 info 行"，
        // MultiPV 残留会让它解析到排名靠后的差着分数
        defer { sendCommand("setoption name MultiPV value 1") }

        sendCommand("position fen \(uciFen)")
        sendCommand("go movetime \(movetime)")

        var response: String
        do {
            response = try await waitForResponse(containing: "bestmove", timeout: Double(movetime) / 1000.0 + 30.0)
        } catch PikafishError.timeout {
            // 超时：发 stop 让引擎立即返回，解析已有结果
            sendCommand("stop")
            response = try await waitForResponse(containing: "bestmove", timeout: 10.0)
        }

        return Self.parsePVLines(from: response)
    }

    // MARK: - Evaluation

    /// 中断当前搜索（用于取消评估）
    func stopCurrentSearch() {
        sendCommand("stop")
    }

    func evaluatePosition(fen: String, movetime: Int? = nil) async throws -> EvaluationResult? {
        try await serialized { try await self.evaluatePositionUnserialized(fen: fen, movetime: movetime) }
    }

    private func evaluatePositionUnserialized(fen: String, movetime: Int?) async throws -> EvaluationResult? {
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
        // 进程已死时管道写端对面无人读，直接丢弃命令；write(contentsOf:) 出错（EPIPE）
        // 以 throws 形式返回而不是抛 ObjC 异常，配合忽略 SIGPIPE 才不会带崩 app
        guard let inputPipe = inputPipe, process?.isRunning == true else { return }
        let data = (command + "\n").data(using: .utf8)!
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            print("[Pikafish] 写入引擎管道失败：\(error)")
        }
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
