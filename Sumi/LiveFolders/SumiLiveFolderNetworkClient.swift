import Foundation

struct SumiLiveFolderHTTPResponse: Sendable {
    var data: Data
    var statusCode: Int
    var mimeType: String?
    var etag: String?
    var lastModified: String?
    var retryAfter: Date?
}

final class SumiLiveFolderNetworkClient: @unchecked Sendable {
    enum FetchError: Error {
        case invalidURL
        case oversizedResponse
        case unsupportedResponse
        case network
    }

    private let session: URLSession
    private let maxPayloadBytes: Int

    init(
        session: URLSession = SumiLiveFolderNetworkClient.makeSession(),
        maxPayloadBytes: Int = 2 * 1024 * 1024
    ) {
        self.session = session
        self.maxPayloadBytes = maxPayloadBytes
    }

    func fetch(
        url: URL,
        accept: String,
        etag: String?,
        lastModified: String?,
        cookies: [HTTPCookie] = []
    ) async throws -> SumiLiveFolderHTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Sumi Live Folders", forHTTPHeaderField: "User-Agent")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let matchingCookies = Self.cookies(cookies, matching: url)
        if !matchingCookies.isEmpty,
           let cookieHeader = HTTPCookie.requestHeaderFields(with: matchingCookies)["Cookie"] {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= maxPayloadBytes else {
                throw FetchError.oversizedResponse
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FetchError.unsupportedResponse
            }
            return SumiLiveFolderHTTPResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                mimeType: httpResponse.mimeType,
                etag: httpResponse.value(forHTTPHeaderField: "ETag"),
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified"),
                retryAfter: Self.retryAfterDate(from: httpResponse)
            )
        } catch let error as FetchError {
            throw error
        } catch {
            throw FetchError.network
        }
    }

    static func cookies(_ cookies: [HTTPCookie], matching url: URL) -> [HTTPCookie] {
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

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    private static func retryAfterDate(from response: HTTPURLResponse) -> Date? {
        guard let retryAfter = response.value(forHTTPHeaderField: "Retry-After") else {
            if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let interval = TimeInterval(reset) {
                return Date(timeIntervalSince1970: interval)
            }
            return nil
        }

        if let seconds = TimeInterval(retryAfter) {
            return Date().addingTimeInterval(seconds)
        }
        return HTTPDateParser.parse(retryAfter)
    }
}

enum HTTPDateParser {
    static func parse(_ string: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    private static let formatters: [DateFormatter] = {
        let formats = [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
            "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
            "EEE MMM d HH':'mm':'ss yyyy",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}
