import AppKit
import Foundation

actor SumiFaviconResolver {
    static let shared = SumiFaviconResolver(usesPersistedNegativeCache: true)

    private let session: URLSession
    private let negativeCacheTTL: TimeInterval
    private let maxConcurrentNetworkRequests: Int
    private let maxDocumentBytes: Int
    private let usesPersistedNegativeCache: Bool
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var resolvedIconURLs: [String: URL] = [:]
    private var acceptedLowQualityKeys: Set<String> = []
    private var negativeCacheExpirations: [String: Date] = [:]
    private var activeNetworkRequests = 0
    private var queuedNetworkWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        session: URLSession = .shared,
        negativeCacheTTL: TimeInterval = 600,
        maxConcurrentNetworkRequests: Int = 6,
        maxDocumentBytes: Int = 65_536,
        usesPersistedNegativeCache: Bool = false
    ) {
        self.session = session
        self.negativeCacheTTL = negativeCacheTTL
        self.maxConcurrentNetworkRequests = max(1, maxConcurrentNetworkRequests)
        self.maxDocumentBytes = max(4_096, maxDocumentBytes)
        self.usesPersistedNegativeCache = usesPersistedNegativeCache
        if usesPersistedNegativeCache {
            self.negativeCacheExpirations = Self.loadPersistedNegativeCache(referenceDate: Date())
        }
    }

    nonisolated static func cacheKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }

        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host, !host.isEmpty {
            return host.lowercased()
        }

        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absolute.isEmpty ? nil : absolute.lowercased()
    }

    func image(for url: URL) async -> NSImage? {
        guard let cacheKey = Self.cacheKey(for: url) else {
            return nil
        }

        if let cached = TabFaviconStore.getCachedImage(for: cacheKey),
           acceptedLowQualityKeys.contains(cacheKey) || Self.isHighQualityEnough(cached)
        {
            return cached
        }

        pruneExpiredNegativeCacheEntries(referenceDate: Date())
        if let expiration = negativeCacheExpirations[cacheKey], expiration > Date() {
            return nil
        }

        if let resolvedIconURL = resolvedIconURLs[cacheKey] {
            if let image = await fetchAndCacheImage(
                at: resolvedIconURL,
                cacheKey: cacheKey,
                resolvedURL: resolvedIconURL
            ) {
                if acceptedLowQualityKeys.contains(cacheKey) || Self.isHighQualityEnough(image) {
                    return image
                }
            }
        }

        if let existingTask = inFlight[cacheKey] {
            return await existingTask.value
        }

        let task = Task { await self.resolveImage(for: url, cacheKey: cacheKey) }
        inFlight[cacheKey] = task

        let resolvedImage = await task.value
        inFlight.removeValue(forKey: cacheKey)
        return resolvedImage
    }

    func resetTransientState() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        resolvedIconURLs.removeAll()
        acceptedLowQualityKeys.removeAll()
        if usesPersistedNegativeCache {
            negativeCacheExpirations = Self.loadPersistedNegativeCache(referenceDate: Date())
        } else {
            negativeCacheExpirations.removeAll()
        }
    }

    private func resolveImage(for url: URL, cacheKey: String) async -> NSImage? {
        if Task.isCancelled {
            return nil
        }

        acceptedLowQualityKeys.remove(cacheKey)
        var bestFallbackCandidate: FaviconCandidate?

        if let directIcon = await fetchDirectImage(
            for: url,
            path: "/favicon.ico"
        ) {
            if Self.isHighQualityEnough(directIcon.decodedImage.bitmap.image) {
                acceptedLowQualityKeys.remove(cacheKey)
                cache(directIcon.decodedImage, cacheKey: cacheKey, resolvedURL: directIcon.url)
                return directIcon.decodedImage.bitmap.image
            }

            bestFallbackCandidate = directIcon
        }

        if let appleTouchIcon = await fetchDirectImage(
            for: url,
            path: "/apple-touch-icon.png"
        ) {
            if Self.isHighQualityEnough(appleTouchIcon.decodedImage.bitmap.image) {
                acceptedLowQualityKeys.remove(cacheKey)
                cache(appleTouchIcon.decodedImage, cacheKey: cacheKey, resolvedURL: appleTouchIcon.url)
                return appleTouchIcon.decodedImage.bitmap.image
            }

            bestFallbackCandidate = bestCandidate(bestFallbackCandidate, appleTouchIcon)
        }

        if let htmlCandidate = await fetchBestHTMLCandidate(for: url) {
            if Self.isHighQualityEnough(htmlCandidate.decodedImage.bitmap.image) {
                acceptedLowQualityKeys.remove(cacheKey)
            } else {
                acceptedLowQualityKeys.insert(cacheKey)
            }

            cache(htmlCandidate.decodedImage, cacheKey: cacheKey, resolvedURL: htmlCandidate.url)
            return htmlCandidate.decodedImage.bitmap.image
        }

        if let bestFallbackCandidate {
            acceptedLowQualityKeys.insert(cacheKey)
            cache(bestFallbackCandidate.decodedImage, cacheKey: cacheKey, resolvedURL: bestFallbackCandidate.url)
            return bestFallbackCandidate.decodedImage.bitmap.image
        }

        negativeCacheExpirations[cacheKey] = Date().addingTimeInterval(negativeCacheTTL)
        persistNegativeCacheIfNeeded()
        return nil
    }

    private func fetchDirectImage(
        for pageURL: URL,
        path: String
    ) async -> FaviconCandidate? {
        guard let iconURL = directURL(for: pageURL, path: path),
              let decodedImage = await fetchImage(at: iconURL)
        else {
            return nil
        }

        return FaviconCandidate(url: iconURL, decodedImage: decodedImage)
    }

    private func fetchBestHTMLCandidate(for pageURL: URL) async -> FaviconCandidate? {
        guard let response = await fetchDocument(at: pageURL) else {
            return nil
        }

        let candidates = HTMLHeadIconParser.candidates(
            from: response.html,
            pageURL: response.finalURL
        )

        guard let bestCandidate = candidates.first,
              let decodedImage = await fetchImage(at: bestCandidate.url)
        else {
            return nil
        }

        return FaviconCandidate(url: bestCandidate.url, decodedImage: decodedImage)
    }

    private func fetchAndCacheImage(
        at url: URL,
        cacheKey: String,
        resolvedURL: URL
    ) async -> NSImage? {
        guard let decodedImage = await fetchImage(at: url) else {
            return nil
        }

        cache(decodedImage, cacheKey: cacheKey, resolvedURL: resolvedURL)
        return decodedImage.bitmap.image
    }

    private func fetchImage(at url: URL) async -> DecodedFaviconImage? {
        guard Self.isSupportedNetworkURL(url) else {
            return nil
        }

        guard let response = await fetchResponse(at: url),
              response.isHTTPStatusSuccess,
              let bitmap = FaviconImageDecoder.decodedImage(from: response.data)
        else {
            return nil
        }

        return DecodedFaviconImage(bitmap: bitmap, rawData: response.data)
    }

    private func cache(
        _ decodedImage: DecodedFaviconImage,
        cacheKey: String,
        resolvedURL: URL
    ) {
        resolvedIconURLs[cacheKey] = resolvedURL
        if negativeCacheExpirations.removeValue(forKey: cacheKey) != nil {
            persistNegativeCacheIfNeeded()
        }
        TabFaviconStore.cacheImage(
            decodedImage.bitmap.image,
            rawData: decodedImage.rawData,
            for: cacheKey
        )
    }

    private func bestCandidate(
        _ lhs: FaviconCandidate?,
        _ rhs: FaviconCandidate
    ) -> FaviconCandidate {
        guard let lhs else {
            return rhs
        }

        let lhsArea = lhs.decodedImage.bitmap.pixelWidth * lhs.decodedImage.bitmap.pixelHeight
        let rhsArea = rhs.decodedImage.bitmap.pixelWidth * rhs.decodedImage.bitmap.pixelHeight
        return rhsArea > lhsArea ? rhs : lhs
    }

    private func fetchDocument(at url: URL) async -> HTMLDocumentResponse? {
        guard Self.isSupportedNetworkURL(url) else {
            return nil
        }

        await acquireNetworkPermit()
        if Task.isCancelled {
            releaseNetworkPermit()
            return nil
        }
        defer { releaseNetworkPermit() }

        do {
            let (bytes, urlResponse) = try await session.bytes(from: url)
            let partialResponse = NetworkResponse(data: Data(), response: urlResponse)
            guard partialResponse.isHTTPStatusSuccess else {
                return nil
            }

            var htmlData = Data()
            var recentLowercasedBytes: [UInt8] = []

            for try await byte in bytes {
                if Task.isCancelled || htmlData.count >= maxDocumentBytes {
                    break
                }

                htmlData.append(byte)

                let lowercasedByte = Self.lowercasedASCII(byte)
                recentLowercasedBytes.append(lowercasedByte)
                if recentLowercasedBytes.count > 24 {
                    recentLowercasedBytes.removeFirst(recentLowercasedBytes.count - 24)
                }

                if lowercasedByte == Self.asciiGreaterThan,
                   recentLowercasedBytes.containsSubsequence(Self.headCloseMarkerPrefix)
                {
                    break
                }
            }

            guard !htmlData.isEmpty else {
                return nil
            }

            let networkResponse = NetworkResponse(data: htmlData, response: urlResponse)
            guard let html = networkResponse.decodedString else {
                return nil
            }

            return HTMLDocumentResponse(html: html, finalURL: networkResponse.finalURL)
        } catch {
            return nil
        }
    }

    private func fetchResponse(at url: URL) async -> NetworkResponse? {
        guard Self.isSupportedNetworkURL(url) else {
            return nil
        }

        await acquireNetworkPermit()
        if Task.isCancelled {
            releaseNetworkPermit()
            return nil
        }
        defer { releaseNetworkPermit() }

        do {
            let (data, response) = try await session.data(from: url)
            return NetworkResponse(data: data, response: response)
        } catch {
            return nil
        }
    }

    private func directURL(for pageURL: URL, path: String) -> URL? {
        guard let host = pageURL.host else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func pruneExpiredNegativeCacheEntries(referenceDate: Date) {
        let pruned = negativeCacheExpirations.filter { $0.value > referenceDate }
        guard pruned.count != negativeCacheExpirations.count else { return }
        negativeCacheExpirations = pruned
        persistNegativeCacheIfNeeded()
    }

    private func persistNegativeCacheIfNeeded() {
        guard usesPersistedNegativeCache else { return }
        Self.persistNegativeCache(negativeCacheExpirations)
    }

    private nonisolated static let persistedNegativeCacheDefaultsKey = "favicon.resolver.negativeCache.v1"

    private nonisolated static func loadPersistedNegativeCache(referenceDate: Date) -> [String: Date] {
        guard let persisted = UserDefaults.standard.dictionary(forKey: persistedNegativeCacheDefaultsKey) as? [String: Double] else {
            return [:]
        }

        var expirations: [String: Date] = [:]
        for (cacheKey, expirationTimestamp) in persisted {
            let expiration = Date(timeIntervalSince1970: expirationTimestamp)
            if expiration > referenceDate {
                expirations[cacheKey] = expiration
            }
        }

        if expirations.count != persisted.count {
            persistNegativeCache(expirations)
        }

        return expirations
    }

    private nonisolated static func persistNegativeCache(_ expirations: [String: Date]) {
        guard !expirations.isEmpty else {
            UserDefaults.standard.removeObject(forKey: persistedNegativeCacheDefaultsKey)
            return
        }

        let encoded = expirations.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(encoded, forKey: persistedNegativeCacheDefaultsKey)
    }

    private func acquireNetworkPermit() async {
        if activeNetworkRequests < maxConcurrentNetworkRequests {
            activeNetworkRequests += 1
            return
        }

        await withCheckedContinuation { continuation in
            queuedNetworkWaiters.append(continuation)
        }
    }

    private func releaseNetworkPermit() {
        if !queuedNetworkWaiters.isEmpty {
            let waiter = queuedNetworkWaiters.removeFirst()
            waiter.resume()
            return
        }

        activeNetworkRequests = max(0, activeNetworkRequests - 1)
    }

    private nonisolated static func isSupportedNetworkURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private nonisolated static func isHighQualityEnough(_ image: NSImage) -> Bool {
        max(image.size.width, image.size.height) >= CGFloat(FaviconImageDecoder.preferredMinimumPixelSize)
    }

    private nonisolated static let headCloseMarkerPrefix = Array("</head".utf8)
    private nonisolated static let asciiGreaterThan = UInt8(ascii: ">")

    private nonisolated static func lowercasedASCII(_ byte: UInt8) -> UInt8 {
        switch byte {
        case 65...90:
            return byte + 32
        default:
            return byte
        }
    }
}

private struct HTMLDocumentResponse {
    let html: String
    let finalURL: URL
}

private struct DecodedFaviconImage {
    let bitmap: DecodedFaviconBitmap
    let rawData: Data
}

private struct FaviconCandidate {
    let url: URL
    let decodedImage: DecodedFaviconImage
}

private struct NetworkResponse {
    let data: Data
    let response: URLResponse

    var finalURL: URL {
        response.url ?? URL(fileURLWithPath: "/")
    }

    var isHTTPStatusSuccess: Bool {
        guard let http = response as? HTTPURLResponse else {
            return true
        }
        return (200..<400).contains(http.statusCode)
    }

    var decodedString: String? {
        if let encodingName = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                let stringEncoding = String.Encoding(rawValue: nsEncoding)
                if let decoded = String(data: data, encoding: stringEncoding) {
                    return decoded
                }
            }
        }

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        return String(data: data, encoding: .isoLatin1)
    }
}

private enum HTMLHeadIconParser {
    private static let headRegex = try! NSRegularExpression(
        pattern: "<head\\b[^>]*>(.*?)</head>",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let linkRegex = try! NSRegularExpression(
        pattern: "<link\\b[^>]*>",
        options: [.caseInsensitive]
    )

    private static let baseRegex = try! NSRegularExpression(
        pattern: "<base\\b[^>]*>",
        options: [.caseInsensitive]
    )

    private static let attributeRegex = try! NSRegularExpression(
        pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
        options: [.caseInsensitive]
    )

    static func candidates(from html: String, pageURL: URL) -> [HTMLIconCandidate] {
        let headHTML = extractHead(from: html)
        let baseURL = extractBaseURL(from: headHTML, pageURL: pageURL)

        let linkMatches = linkRegex.matches(
            in: headHTML,
            range: NSRange(headHTML.startIndex..., in: headHTML)
        )

        return linkMatches.compactMap { match in
            guard let range = Range(match.range, in: headHTML) else {
                return nil
            }

            let tag = String(headHTML[range])
            let attributes = parseAttributes(from: tag)
            guard let href = attributes["href"],
                  let relation = relationType(from: attributes["rel"]),
                  let resolvedURL = resolveURL(
                    href: decodeHTMLEntities(in: href),
                    baseURL: baseURL,
                    pageURL: pageURL
                  )
            else {
                return nil
            }

            return HTMLIconCandidate(
                url: resolvedURL,
                sizeScore: sizeScore(from: attributes["sizes"]),
                relationPriority: relation.priority
            )
        }
        .sorted { lhs, rhs in
            if lhs.sizeScore == rhs.sizeScore {
                if lhs.relationPriority == rhs.relationPriority {
                    return lhs.url.absoluteString < rhs.url.absoluteString
                }
                return lhs.relationPriority > rhs.relationPriority
            }
            return lhs.sizeScore > rhs.sizeScore
        }
    }

    private static func extractHead(from html: String) -> String {
        let searchRange = NSRange(html.startIndex..., in: html)
        guard let match = headRegex.firstMatch(in: html, range: searchRange),
              let range = Range(match.range(at: 1), in: html)
        else {
            return html
        }
        return String(html[range])
    }

    private static func extractBaseURL(from headHTML: String, pageURL: URL) -> URL? {
        let searchRange = NSRange(headHTML.startIndex..., in: headHTML)
        guard let match = baseRegex.firstMatch(in: headHTML, range: searchRange),
              let range = Range(match.range, in: headHTML)
        else {
            return pageURL
        }

        let tag = String(headHTML[range])
        let attributes = parseAttributes(from: tag)
        guard let href = attributes["href"] else {
            return pageURL
        }

        return resolveURL(href: decodeHTMLEntities(in: href), baseURL: pageURL, pageURL: pageURL)
            ?? pageURL
    }

    private static func parseAttributes(from tag: String) -> [String: String] {
        let searchRange = NSRange(tag.startIndex..., in: tag)
        var attributes: [String: String] = [:]

        for match in attributeRegex.matches(in: tag, range: searchRange) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else {
                continue
            }

            let key = String(tag[keyRange]).lowercased()
            let quotedDouble = Range(match.range(at: 2), in: tag).map { String(tag[$0]) }
            let quotedSingle = Range(match.range(at: 3), in: tag).map { String(tag[$0]) }
            let unquoted = Range(match.range(at: 4), in: tag).map { String(tag[$0]) }
            let value = quotedDouble ?? quotedSingle ?? unquoted ?? ""
            attributes[key] = value
        }

        return attributes
    }

    private static func relationType(from rawRelation: String?) -> IconRelation? {
        guard let rawRelation else {
            return nil
        }

        let relation = rawRelation.lowercased()
        if relation.contains("apple-touch-icon-precomposed") {
            return .appleTouchPrecomposed
        }
        if relation.contains("apple-touch-icon") {
            return .appleTouch
        }
        if relation.contains("shortcut icon") {
            return .shortcut
        }
        if relation.split(whereSeparator: \.isWhitespace).contains("icon") {
            return .icon
        }

        return nil
    }

    private static func sizeScore(from rawSize: String?) -> Int {
        guard let rawSize else {
            return 0
        }

        let normalized = rawSize.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "any" {
            return 1_048_576
        }

        let tokens = normalized.split(whereSeparator: \.isWhitespace)
        let scores = tokens.compactMap { token -> Int? in
            let dimensions = token.split(separator: "x")
            guard dimensions.count == 2,
                  let width = Int(dimensions[0]),
                  let height = Int(dimensions[1])
            else {
                return nil
            }
            return width * height
        }

        return scores.max() ?? 0
    }

    private static func resolveURL(href: String, baseURL: URL?, pageURL: URL) -> URL? {
        let base = baseURL ?? pageURL
        return URL(string: href, relativeTo: base)?.absoluteURL
    }

    private static func decodeHTMLEntities(in string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private struct HTMLIconCandidate {
    let url: URL
    let sizeScore: Int
    let relationPriority: Int
}

private enum IconRelation {
    case appleTouch
    case appleTouchPrecomposed
    case icon
    case shortcut

    var priority: Int {
        switch self {
        case .appleTouch:
            return 4
        case .appleTouchPrecomposed:
            return 3
        case .icon:
            return 2
        case .shortcut:
            return 1
        }
    }
}

private extension Array where Element == UInt8 {
    func containsSubsequence(_ candidate: [UInt8]) -> Bool {
        guard !candidate.isEmpty, count >= candidate.count else {
            return false
        }

        for startIndex in 0...(count - candidate.count) {
            if Array(self[startIndex..<(startIndex + candidate.count)]) == candidate {
                return true
            }
        }

        return false
    }
}
