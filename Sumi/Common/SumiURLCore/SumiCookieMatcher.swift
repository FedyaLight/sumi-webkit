import Foundation

enum SumiCookieMatcher {
    static func cookies(_ cookies: [HTTPCookie], matching url: URL) -> [HTTPCookie] {
        guard let host = normalizedHost(for: url) else { return [] }
        let requestPath = url.path.isEmpty ? "/" : url.path
        let isSecureRequest = url.scheme?.lowercased() == "https"

        return cookies.filter { cookie in
            guard let cookieDomain = normalizedCookieDomain(cookie.domain) else { return false }
            let domainMatches = host == cookieDomain || host.hasSuffix(".\(cookieDomain)")
            let secureMatches = !cookie.isSecure || isSecureRequest
            return domainMatches
                && pathMatches(requestPath: requestPath, cookiePath: cookie.path)
                && secureMatches
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
        return self.cookies(cookies, matching: url)
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

    private static func normalizedHost(for url: URL) -> String? {
        guard let host = url.host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased(),
            !host.isEmpty
        else {
            return nil
        }
        return host
    }

    private static func normalizedCookieDomain(_ domain: String) -> String? {
        let cookieDomain = domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return cookieDomain.isEmpty ? nil : cookieDomain
    }

    private static func pathMatches(requestPath: String, cookiePath: String) -> Bool {
        let normalizedCookiePath = cookiePath.isEmpty ? "/" : cookiePath
        guard requestPath.hasPrefix(normalizedCookiePath) else { return false }
        guard requestPath != normalizedCookiePath else { return true }
        guard normalizedCookiePath != "/" else { return true }
        guard !normalizedCookiePath.hasSuffix("/") else { return true }

        let boundaryIndex = requestPath.index(requestPath.startIndex, offsetBy: normalizedCookiePath.count)
        return requestPath[boundaryIndex] == "/"
    }

    private static func schemefulSite(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let siteHost = SumiSiteNormalizer().normalizedHost(for: url)
        else {
            return nil
        }
        return "\(scheme)://\(siteHost)"
    }
}
