import AppKit
import Combine
import Network
import WebKit
import XCTest

@testable import Sumi


/// Loopback "account.proton.me" stand-in: serves the account page with a
/// session cookie and a single-use fork-selector pull endpoint that requires
/// that cookie — mirroring Proton's `GET /auth/v4/sessions/forks/{selector}`
/// semantics ("Invalid selector" on re-use).
final class AccountForkHTTPServer: @unchecked Sendable {
    static let sessionCookieName = "sumi_probe_session"
    static let sessionCookieValue = "account-session-ok"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "sumi.account-fork.http-server")
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var pullCounts: [String: Int] = [:]
    private var pageHitsByCacheToken: [String: Int] = [:]
    private var missingCookiePulls = 0

    static func start() async throws -> AccountForkHTTPServer {
        let server = try AccountForkHTTPServer()
        try await server.start()
        return server
    }

    private init() throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    var accountPageURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/account.html"
        components.queryItems = [URLQueryItem(name: "cache", value: UUID().uuidString)]
        return components.url!
    }

    func pullCount(for selector: String) -> Int {
        lock.withLock { pullCounts[selector] ?? 0 }
    }

    /// How many times the account page identified by its cache-busting token
    /// was served — more than one means the same tab loaded the page twice
    /// (e.g. a web-view replacement re-navigation).
    func pageHits(for cacheToken: String) -> Int {
        lock.withLock { pageHitsByCacheToken[cacheToken] ?? 0 }
    }

    var pullsMissingSessionCookie: Int {
        lock.withLock { missingCookiePulls }
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
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) { [weak self] data, _, isComplete, error in
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
        let lines = requestText.components(separatedBy: "\r\n")
        let requestTarget = lines.first?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"
        let path = requestTarget.split(separator: "?", maxSplits: 1).first
            .map(String.init) ?? requestTarget
        let query = requestTarget.split(separator: "?", maxSplits: 1)
            .dropFirst()
            .first
            .map(String.init) ?? ""
        let cookieHeader = lines
            .first { $0.lowercased().hasPrefix("cookie:") }?
            .dropFirst("cookie:".count)
            .trimmingCharacters(in: .whitespaces) ?? ""

        switch path {
        case "/account.html", "/":
            let cacheToken = query
                .split(separator: "&")
                .compactMap { pair -> String? in
                    let parts = pair.split(separator: "=", maxSplits: 1)
                    guard parts.first == "cache", parts.count == 2 else { return nil }
                    return String(parts[1]).removingPercentEncoding
                }
                .first
            if let cacheToken {
                lock.withLock {
                    pageHitsByCacheToken[cacheToken, default: 0] += 1
                }
            }
            let body = Data(
                "<!doctype html><meta charset=\"utf-8\"><title>account-fork-probe</title><h1>Account</h1>".utf8
            )
            send(
                status: "200 OK",
                headers: [
                    "Content-Type: text/html; charset=utf-8",
                    "Set-Cookie: \(Self.sessionCookieName)=\(Self.sessionCookieValue); Path=/",
                ],
                body: body,
                on: connection
            )
        case "/pull":
            respondToPull(query: query, cookieHeader: cookieHeader, on: connection)
        default:
            send(
                status: "404 Not Found",
                headers: ["Content-Type: text/plain; charset=utf-8"],
                body: Data("Not Found".utf8),
                on: connection
            )
        }
    }

    private func respondToPull(
        query: String,
        cookieHeader: String,
        on connection: NWConnection
    ) {
        let selector = query
            .split(separator: "&")
            .compactMap { pair -> String? in
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.first == "selector", parts.count == 2 else { return nil }
                return String(parts[1]).removingPercentEncoding
            }
            .first ?? ""

        let hasSessionCookie = cookieHeader
            .contains("\(Self.sessionCookieName)=\(Self.sessionCookieValue)")

        let previousPulls: Int = lock.withLock {
            if hasSessionCookie == false {
                missingCookiePulls += 1
                return -1
            }
            let count = pullCounts[selector] ?? 0
            pullCounts[selector] = count + 1
            return count
        }

        if previousPulls == -1 {
            send(
                status: "401 Unauthorized",
                headers: ["Content-Type: application/json; charset=utf-8"],
                body: Data("{\"ok\":false,\"error\":\"Missing session cookie\"}".utf8),
                on: connection
            )
            return
        }

        if previousPulls > 0 {
            send(
                status: "422 Unprocessable Entity",
                headers: ["Content-Type: application/json; charset=utf-8"],
                body: Data("{\"ok\":false,\"error\":\"Invalid selector\"}".utf8),
                on: connection
            )
            return
        }

        send(
            status: "200 OK",
            headers: ["Content-Type: application/json; charset=utf-8"],
            body: Data("{\"ok\":true}".utf8),
            on: connection
        )
    }

    private func send(
        status: String,
        headers: [String],
        body: Data,
        on connection: NWConnection
    ) {
        let head = ([
            "HTTP/1.1 \(status)",
        ] + headers + [
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ]).joined(separator: "\r\n")
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
