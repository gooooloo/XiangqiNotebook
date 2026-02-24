#if os(macOS)
import Foundation
import Network

class PGNHttpServer {
    private var listener: NWListener?
    private let port: UInt16 = 9213
    private let queue = DispatchQueue(label: "PGNHttpServer")

    var onPGNReceived: ((String) -> PGNImportResult)?

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
                print("PGNHttpServer listener failed: \(error)")
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
                print("PGNHttpServer receive error: \(error)")
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

    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let str = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request",
                         body: #"{"error":"Invalid request encoding"}"#)
            return
        }

        let firstLine = str.prefix(while: { $0 != "\r" && $0 != "\n" })
        guard firstLine.hasPrefix("POST ") else {
            sendResponse(connection: connection, status: "405 Method Not Allowed",
                         body: #"{"error":"Only POST method is accepted"}"#)
            return
        }

        var body = ""
        if let headerEnd = str.range(of: "\r\n\r\n") {
            body = String(str[headerEnd.upperBound...])
        }

        guard !body.isEmpty else {
            sendResponse(connection: connection, status: "400 Bad Request",
                         body: #"{"error":"Empty request body"}"#)
            return
        }

        guard let callback = onPGNReceived else {
            sendResponse(connection: connection, status: "503 Service Unavailable",
                         body: #"{"error":"Server not ready"}"#)
            return
        }

        let result = callback(body)
        let jsonBody = resultToJSON(result)
        sendResponse(connection: connection, status: "200 OK", body: jsonBody)
    }

    private func resultToJSON(_ result: PGNImportResult) -> String {
        let errorsJSON = result.errors.map { error in
            let escaped = error
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }.joined(separator: ",")

        return """
        {"imported":\(result.imported),"skippedDuplicate":\(result.skippedDuplicate),"skippedError":\(result.skippedError),"redGameCount":\(result.redGameCount),"blackGameCount":\(result.blackGameCount),"othersGameCount":\(result.othersGameCount),"totalParsed":\(result.totalParsed),"errors":[\(errorsJSON)]}
        """
    }

    private func sendResponse(connection: NWConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
#endif
