import Foundation
import WebKit

// The wrapped WKWebView is weak and can only be read from the main actor.
final class SumiFaviconWebViewReference: @unchecked Sendable {
    @MainActor weak var webView: WKWebView?

    @MainActor
    init(_ webView: WKWebView?) {
        self.webView = webView
    }
}

struct SumiFaviconFetchContext: Sendable {
    enum Kind: Sendable {
        case sessionProfileAware
        case publicRootFallback
    }

    let kind: Kind
    let webViewReference: SumiFaviconWebViewReference?
    let sourceDocumentURL: URL?

    static func session(webView: WKWebView?, sourceDocumentURL: URL) -> SumiFaviconFetchContext {
        MainActor.assumeIsolated {
            SumiFaviconFetchContext(
                kind: .sessionProfileAware,
                webViewReference: SumiFaviconWebViewReference(webView),
                sourceDocumentURL: sourceDocumentURL
            )
        }
    }

    static let publicRootFallback = SumiFaviconFetchContext(
        kind: .publicRootFallback,
        webViewReference: nil,
        sourceDocumentURL: nil
    )
}

struct SumiFaviconFetchResponse: Sendable {
    let data: Data
    let mimeType: String?
    let statusCode: Int?
}

enum SumiFaviconFetchResult: Sendable {
    case success(SumiFaviconFetchResponse)
    case failure(SumiFaviconValidationFailureKind)
    case cancelled
}

protocol SumiFaviconNetworkFetching: Sendable {
    func fetch(url: URL, context: SumiFaviconFetchContext) async -> SumiFaviconFetchResult
}

actor SumiFaviconFetchScheduler {
    struct Configuration: Sendable {
        var globalConcurrencyLimit = 6
        var perOriginConcurrencyLimit = 2
    }

    private struct FetchKey: Hashable, Sendable {
        let partition: SumiFaviconPartition
        let url: URL
    }

    private struct ScheduledFetch {
        let token: UUID
        let task: Task<SumiFaviconFetchResult?, Never>
    }

    private let fetcher: any SumiFaviconNetworkFetching
    private let limiter: SumiFaviconFetchLimiter
    private var inFlight: [FetchKey: ScheduledFetch] = [:]
    private var negativeUntilByKey: [FetchKey: Date] = [:]

    init(
        fetcher: any SumiFaviconNetworkFetching,
        configuration: Configuration = Configuration()
    ) {
        self.fetcher = fetcher
        self.limiter = SumiFaviconFetchLimiter(
            globalLimit: configuration.globalConcurrencyLimit,
            perOriginLimit: configuration.perOriginConcurrencyLimit
        )
    }

    func fetch(
        candidate: SumiFaviconCandidate,
        context: SumiFaviconFetchContext,
        priority: SumiFaviconFetchPriority,
        now: Date = Date()
    ) async -> SumiFaviconFetchResult {
        _ = priority
        let key = FetchKey(partition: candidate.partition, url: candidate.iconURL)
        if let negativeUntil = negativeUntilByKey[key], negativeUntil > now {
            return .failure(.transport)
        }
        if let scheduledFetch = inFlight[key] {
            return await scheduledFetch.task.value ?? .cancelled
        }

        let origin = originKey(for: candidate.iconURL)
        let token = UUID()
        let task = Task<SumiFaviconFetchResult?, Never> { [fetcher, limiter] in
            let acquired = await limiter.acquire(origin: origin, priority: priority)
            guard acquired else {
                return nil
            }
            guard !Task.isCancelled else {
                await limiter.release(origin: origin)
                return nil
            }
            let result = await fetcher.fetch(url: candidate.iconURL, context: context)
            await limiter.release(origin: origin)
            guard !Task.isCancelled else {
                return nil
            }
            return result
        }
        inFlight[key] = ScheduledFetch(token: token, task: task)
        let result = await task.value
        if inFlight[key]?.token == token {
            inFlight.removeValue(forKey: key)
        }

        if let result, case .failure(let failureKind) = result {
            negativeUntilByKey[key] = now.addingTimeInterval(ttl(for: failureKind))
        }
        return result ?? .cancelled
    }

    func cancelColdFetches() async {
        for scheduledFetch in inFlight.values {
            scheduledFetch.task.cancel()
        }
        inFlight.removeAll()
        await limiter.cancelQueuedFetches()
    }

    #if DEBUG
        func drainInFlightFetchesForTests(cancel: Bool = true) async {
            while !inFlight.isEmpty {
                let scheduledFetches = Array(inFlight.map { ($0.key, $0.value) })
                if cancel {
                    for (_, scheduledFetch) in scheduledFetches {
                        scheduledFetch.task.cancel()
                    }
                    await limiter.cancelQueuedFetches()
                }
                for (key, scheduledFetch) in scheduledFetches {
                    _ = await scheduledFetch.task.value
                    if inFlight[key]?.token == scheduledFetch.token {
                        inFlight.removeValue(forKey: key)
                    }
                }
            }
        }
    #endif

    private func ttl(for failureKind: SumiFaviconValidationFailureKind) -> TimeInterval {
        switch failureKind {
        case .transport:
            return SumiFaviconTTL.transientTransportFailure
        case .notFound, .invalidPayload, .oversizedPayload, .oversizedPixels, .htmlPayload, .unsafeSVG, .unsupported:
            return SumiFaviconTTL.verifiedInvalidPayload
        case .noIconFound:
            return SumiFaviconTTL.noIconFound
        }
    }

    private func originKey(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? url.absoluteString.lowercased()
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}

actor SumiFaviconFetchLimiter {
    private struct Waiter {
        let id: UUID
        let origin: String
        let priority: SumiFaviconFetchPriority
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let globalLimit: Int
    private let perOriginLimit: Int
    private var activeGlobal = 0
    private var activeByOrigin: [String: Int] = [:]
    private var waiters: [Waiter] = []

    init(globalLimit: Int, perOriginLimit: Int) {
        self.globalLimit = max(1, globalLimit)
        self.perOriginLimit = max(1, perOriginLimit)
    }

    func acquire(origin: String, priority: SumiFaviconFetchPriority) async -> Bool {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }

                if canAcquire(origin: origin) {
                    markAcquired(origin: origin)
                    continuation.resume(returning: true)
                    return
                }

                waiters.append(
                    Waiter(
                        id: waiterID,
                        origin: origin,
                        priority: priority,
                        continuation: continuation
                    )
                )
                waiters.sort {
                    if $0.priority != $1.priority {
                        return $0.priority > $1.priority
                    }
                    return $0.origin < $1.origin
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
    }

    func cancelQueuedFetches() {
        let queuedWaiters = waiters
        waiters.removeAll()
        for waiter in queuedWaiters {
            waiter.continuation.resume(returning: false)
        }
    }

    func release(origin: String) {
        activeGlobal = max(0, activeGlobal - 1)
        activeByOrigin[origin] = max(0, (activeByOrigin[origin] ?? 1) - 1)
        if activeByOrigin[origin] == 0 {
            activeByOrigin[origin] = nil
        }
        drainWaiters()
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func drainWaiters() {
        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            guard canAcquire(origin: waiter.origin) else {
                index += 1
                continue
            }
            waiters.remove(at: index)
            markAcquired(origin: waiter.origin)
            waiter.continuation.resume(returning: true)
        }
    }

    private func canAcquire(origin: String) -> Bool {
        activeGlobal < globalLimit && (activeByOrigin[origin] ?? 0) < perOriginLimit
    }

    private func markAcquired(origin: String) {
        activeGlobal += 1
        activeByOrigin[origin, default: 0] += 1
    }
}

// Immutable URLSession-backed fetcher; WebKit fetches are delegated to a main-actor downloader.
final class SumiFaviconNetworkClient: SumiFaviconNetworkFetching, @unchecked Sendable {
    private let publicSession: URLSession

    init(publicSession: URLSession = URLSession(configuration: .ephemeral)) {
        self.publicSession = publicSession
    }

    func fetch(url: URL, context: SumiFaviconFetchContext) async -> SumiFaviconFetchResult {
        switch context.kind {
        case .publicRootFallback:
            return await fetchPublic(url: url)
        case .sessionProfileAware:
            if let reference = context.webViewReference,
               let webView = await reference.webView
            {
                let result = await fetchSessionAware(
                    url: url,
                    webView: webView,
                    sourceDocumentURL: context.sourceDocumentURL
                )
                if case .success = result {
                    return result
                }
                return await SumiFaviconWebKitDownloader.shared.download(url: url, webView: webView)
            }
            return await fetchPublic(url: url)
        }
    }

    private func fetchPublic(url: URL) async -> SumiFaviconFetchResult {
        let request = baseRequest(url: url)
        return await perform(request: request)
    }

    private func fetchSessionAware(
        url: URL,
        webView: WKWebView,
        sourceDocumentURL: URL?
    ) async -> SumiFaviconFetchResult {
        var request = baseRequest(url: url)
        let cookies = await sessionCookies(for: webView)
        let matchingCookies = Self.cookies(
            cookies,
            matching: url,
            sourceDocumentURL: sourceDocumentURL
        )
        if !matchingCookies.isEmpty {
            for (header, value) in HTTPCookie.requestHeaderFields(with: matchingCookies) {
                request.setValue(value, forHTTPHeaderField: header)
            }
        }
        return await perform(request: request)
    }

    private func baseRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "image/avif,image/webp,image/png,image/svg+xml,image/*,*/*;q=0.5",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    private func perform(request: URLRequest) async -> SumiFaviconFetchResult {
        do {
            let (data, response) = try await publicSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .success(SumiFaviconFetchResponse(data: data, mimeType: response.mimeType, statusCode: nil))
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                return .failure(httpResponse.statusCode == 404 ? .notFound : .transport)
            }
            return .success(
                SumiFaviconFetchResponse(
                    data: data,
                    mimeType: httpResponse.mimeType,
                    statusCode: httpResponse.statusCode
                )
            )
        } catch {
            return .failure(.transport)
        }
    }

    @MainActor
    private func sessionCookies(for webView: WKWebView) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    static func cookies(
        _ cookies: [HTTPCookie],
        matching url: URL,
        sourceDocumentURL: URL?
    ) -> [HTTPCookie] {
        guard shouldAttachSessionCookies(to: url, sourceDocumentURL: sourceDocumentURL) else {
            return []
        }
        guard let host = url.host?.lowercased() else { return [] }
        let requestPath = url.path.isEmpty ? "/" : url.path
        let isSecureRequest = url.scheme?.lowercased() == "https"

        return cookies.filter { cookie in
            let cookieDomain = cookie.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            let domainMatches = host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
            let pathMatches = requestPath.hasPrefix(cookie.path.isEmpty ? "/" : cookie.path)
            let secureMatches = !cookie.isSecure || isSecureRequest
            return domainMatches && pathMatches && secureMatches
        }
    }

    static func shouldAttachSessionCookies(to url: URL, sourceDocumentURL: URL?) -> Bool {
        guard let sourceDocumentURL,
              let targetSite = schemefulSite(for: url),
              let sourceSite = schemefulSite(for: sourceDocumentURL)
        else {
            return false
        }
        return targetSite == sourceSite
    }

    private static func schemefulSite(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let rawHost = url.host
        else {
            return nil
        }
        let host = rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !host.isEmpty else { return nil }
        let siteHost = SumiRegistrableDomainResolver().registrableDomain(forHost: host) ?? host
        return "\(scheme)://\(siteHost)"
    }
}

@MainActor
private final class SumiFaviconWebKitDownloader: NSObject, WKDownloadDelegate {
    static let shared = SumiFaviconWebKitDownloader()

    private struct PendingDownload {
        let url: URL
        let continuation: CheckedContinuation<SumiFaviconFetchResult, Never>
        var destinationURL: URL?
        var mimeType: String?
        var statusCode: Int?
    }

    private var pendingDownloads: [WKDownload: PendingDownload] = [:]

    func download(url: URL, webView: WKWebView) async -> SumiFaviconFetchResult {
        let request = URLRequest(url: url)
        let download = await webView.startDownload(using: request)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingDownloads[download] = PendingDownload(
                    url: url,
                    continuation: continuation
                )
                download.delegate = self
            }
        } onCancel: {
            Task { @MainActor [weak self, weak download] in
                guard let download else { return }
                self?.cancel(download)
            }
        }
    }

    private func cancel(_ download: WKDownload) {
        let pending = pendingDownloads.removeValue(forKey: download)
        download.delegate = nil
        Task {
            _ = await download.cancel()
        }
        try? pending?.destinationURL.map(FileManager.default.removeItem(at:))
        pending?.continuation.resume(returning: .failure(.transport))
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        guard var pending = pendingDownloads[download] else { return nil }
        if let httpResponse = response as? HTTPURLResponse {
            pending.statusCode = httpResponse.statusCode
            guard (200..<300).contains(httpResponse.statusCode) else {
                pendingDownloads[download] = pending
                return nil
            }
        }
        if response.expectedContentLength > SumiFaviconConstants.maxPayloadBytes {
            pendingDownloads[download] = pending
            return nil
        }
        pending.mimeType = response.mimeType
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
        pending.destinationURL = destinationURL
        pendingDownloads[download] = pending
        return destinationURL
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let pending = pendingDownloads.removeValue(forKey: download) else { return }
        defer {
            pending.destinationURL.flatMap { try? FileManager.default.removeItem(at: $0) }
        }
        guard let destinationURL = pending.destinationURL,
              let data = try? Data(contentsOf: destinationURL)
        else {
            pending.continuation.resume(returning: .failure(.transport))
            return
        }
        pending.continuation.resume(
            returning: .success(
                SumiFaviconFetchResponse(
                    data: data,
                    mimeType: pending.mimeType,
                    statusCode: pending.statusCode
                )
            )
        )
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let pending = pendingDownloads.removeValue(forKey: download) else { return }
        pending.destinationURL.flatMap { try? FileManager.default.removeItem(at: $0) }
        let failure: SumiFaviconValidationFailureKind = pending.statusCode == 404 ? .notFound : .transport
        pending.continuation.resume(returning: .failure(failure))
    }
}
