import Foundation
import Network

/// Minimal loopback transport for UI oracles that need a real WebKit page.
/// It has no app-side hooks and serves one immutable HTML response for every
/// request, keeping navigation deterministic and independent of runner/app
/// sandbox file access.
final class SumiUIOracleHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.sumi.ui-tests.oracle-http")
    let pageURL: URL

    init(path: String = "oracle.html", html: String) throws {
        let body = Data(html.utf8)
        let listener = try NWListener(using: .tcp, on: .any)
        let readiness = ListenerReadiness()

        listener.newConnectionHandler = { [queue, body] connection in
            Self.serve(connection, body: body, queue: queue)
        }
        listener.stateUpdateHandler = { [weak listener, readiness] state in
            switch state {
            case .ready:
                guard let port = listener?.port?.rawValue else {
                    readiness.resolve(.failure("Listener became ready without a bound port"))
                    return
                }
                readiness.resolve(.ready(port))
            case .failed(let error):
                readiness.resolve(.failure(error.localizedDescription))
            case .cancelled:
                readiness.resolve(.failure("Listener was cancelled before becoming ready"))
            case .setup, .waiting:
                break
            @unknown default:
                readiness.resolve(.failure("Listener entered an unknown startup state"))
            }
        }
        listener.start(queue: queue)

        guard let outcome = readiness.wait(timeout: 10) else {
            listener.cancel()
            throw ServerError.startupTimedOut
        }
        switch outcome {
        case .ready(let port):
            var components = URLComponents()
            components.scheme = "http"
            components.host = "127.0.0.1"
            components.port = Int(port)
            components.path = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let pageURL = components.url else {
                listener.cancel()
                throw ServerError.invalidURL(port)
            }
            self.listener = listener
            self.pageURL = pageURL
        case .failure(let reason):
            listener.cancel()
            throw ServerError.startupFailed(reason)
        }
    }

    deinit {
        listener.cancel()
    }

    func stop() {
        listener.cancel()
    }

    private static func serve(
        _ connection: NWConnection,
        body: Data,
        queue: DispatchQueue
    ) {
        connection.start(queue: queue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { _, _, _, error in
            guard error == nil else {
                connection.cancel()
                return
            }
            let header = Data([
                "HTTP/1.1 200 OK",
                "Content-Type: text/html; charset=utf-8",
                "Content-Length: \(body.count)",
                "Cache-Control: no-store",
                "Connection: close",
                "",
                "",
            ].joined(separator: "\r\n").utf8)
            connection.send(
                content: header + body,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if error != nil {
                        connection.cancel()
                    }
                }
            )
        }
    }

    private enum ServerError: LocalizedError {
        case startupTimedOut
        case startupFailed(String)
        case invalidURL(UInt16)

        var errorDescription: String? {
            switch self {
            case .startupTimedOut:
                "The loopback HTTP listener did not become ready"
            case .startupFailed(let reason):
                "The loopback HTTP listener failed: \(reason)"
            case .invalidURL(let port):
                "The loopback HTTP listener produced an invalid URL for port \(port)"
            }
        }
    }

    private final class ListenerReadiness: @unchecked Sendable {
        enum Outcome {
            case ready(UInt16)
            case failure(String)
        }

        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var outcome: Outcome?

        func resolve(_ outcome: Outcome) {
            lock.lock()
            guard self.outcome == nil else {
                lock.unlock()
                return
            }
            self.outcome = outcome
            lock.unlock()
            semaphore.signal()
        }

        func wait(timeout: TimeInterval) -> Outcome? {
            guard semaphore.wait(timeout: .now() + timeout) == .success else {
                return nil
            }
            lock.lock()
            defer { lock.unlock() }
            return outcome
        }
    }
}
