import Foundation
import Network

/// Serves `SumiTests/Fixtures/AutofillPages/` over loopback HTTP for autofill integration tests.
final class AutofillPagesHTTPServer: @unchecked Sendable {
    static let preferredPort: UInt16 = 8765

    private let listener: NWListener
    private let fixturesRoot: URL
    private let queue = DispatchQueue(label: "sumi.autofill-pages.http-server")
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Error>?

    static func start(
        preferredPort: UInt16 = preferredPort
    ) async throws -> AutofillPagesHTTPServer {
        if preferredPort != 0 {
            do {
                let server = try AutofillPagesHTTPServer(preferredPort: preferredPort)
                try await server.start()
                return server
            } catch {
                guard Self.isAddressInUse(error) else { throw error }
            }
        }

        let server = try AutofillPagesHTTPServer(preferredPort: 0)
        try await server.start()
        return server
    }

    private static func isAddressInUse(_ error: Error) -> Bool {
        if let posix = error as? POSIXError, posix.code == .EADDRINUSE {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(POSIXErrorCode.EADDRINUSE.rawValue) {
            return true
        }
        if let nwError = error as? NWError, case .posix(let code) = nwError, code == .EADDRINUSE {
            return true
        }
        return false
    }

    static func fixturesRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/AutofillPages", isDirectory: true)
    }

    private init(preferredPort: UInt16) throws {
        fixturesRoot = Self.fixturesRootURL()
        let port = NWEndpoint.Port(rawValue: preferredPort) ?? NWEndpoint.Port(rawValue: 0)!
        listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    func pageURL(named filename: String, cacheBuster: String = UUID().uuidString) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/\(filename)"
        components.queryItems = [URLQueryItem(name: "cache", value: cacheBuster)]
        return components.url!
    }

    var loginBasicURL: URL {
        pageURL(named: "login-basic.html")
    }

    func stop() {
        listener.cancel()
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                startContinuation = continuation
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.finishStart(.success(()))
                case .failed(let error):
                    self?.finishStart(.failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func finishStart(_ result: Result<Void, Error>) {
        let continuation = lock.withLock {
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulatedData: Data())
    }

    private func receiveRequest(
        on connection: NWConnection,
        accumulatedData: Data
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }
            let headerTerminator = Data("\r\n\r\n".utf8)
            guard requestData.range(of: headerTerminator) != nil || isComplete || error != nil else {
                self.receiveRequest(on: connection, accumulatedData: requestData)
                return
            }
            self.respond(to: requestData, on: connection)
        }
    }

    private func respond(
        to requestData: Data,
        on connection: NWConnection
    ) {
        let requestText = String(decoding: requestData, as: UTF8.self)
        let requestTarget = requestText
            .split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"
        let path = requestTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestTarget
        let relativePath = String(path.drop(while: { $0 == "/" }))
        let fileURL: URL
        let contentType: String

        if relativePath.isEmpty {
            fileURL = fixturesRoot.appendingPathComponent("login-basic.html")
            contentType = "text/html; charset=utf-8"
        } else if relativePath.hasPrefix("shared/") {
            fileURL = fixturesRoot.appendingPathComponent(relativePath)
            contentType = relativePath.hasSuffix(".js")
                ? "application/javascript; charset=utf-8"
                : "application/octet-stream"
        } else {
            fileURL = fixturesRoot.appendingPathComponent(relativePath)
            contentType = relativePath.hasSuffix(".html")
                ? "text/html; charset=utf-8"
                : "application/octet-stream"
        }

        let body: Data
        if let fileData = try? Data(contentsOf: fileURL) {
            body = fileData
        } else {
            body = Data("Not Found".utf8)
            let header = Data([
                "HTTP/1.1 404 Not Found",
                "Content-Type: text/plain; charset=utf-8",
                "Content-Length: \(body.count)",
                "Cache-Control: no-store",
                "Connection: close",
                "",
                "",
            ].joined(separator: "\r\n").utf8)
            connection.send(content: header + body, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let header = Data([
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n").utf8)
        connection.send(content: header + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
