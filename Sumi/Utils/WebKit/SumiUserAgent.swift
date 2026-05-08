import Foundation
import WebKit

enum SumiUserAgent {
    private static let fallbackSafariVersion = "14.1.2"
    private static let fallbackWebKitVersion = "605.1.15"

    static let duckDuckGoApplicationNameForUserAgent: String = {
        let safariVersion = SafariVersionReader.getVersion() ?? fallbackSafariVersion
        let webKitVersion = WebKitVersionProvider.getVersion() ?? fallbackWebKitVersion
        return "Version/\(safariVersion) Safari/\(webKitVersion)"
    }()

    @MainActor
    static func apply(to webView: WKWebView) {
        // DuckDuckGo relies on the default WKWebView user agent and appends only
        // the Safari/WebKit suffix through WKWebViewConfiguration.
        webView.customUserAgent = nil
    }
}

private enum SafariVersionReader {
    private static let safariPath = "/Applications/Safari.app"

    static func getVersion() -> String? {
        Bundle(path: safariPath)?
            .infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

private struct WebKitVersionProvider {
    static func getVersion() -> String? {
        guard let userAgent = WKWebView().value(forKey: "userAgent") as? String else {
            return nil
        }

        let pattern = #"AppleWebKit\s*/\s*([\d.]+)"#
        guard
            let regularExpression = try? NSRegularExpression(pattern: pattern),
            let match = regularExpression.firstMatch(
                in: userAgent,
                range: NSRange(userAgent.startIndex..., in: userAgent)
            ),
            let matchRange = Range(match.range(at: 1), in: userAgent)
        else {
            return nil
        }

        return String(userAgent[matchRange])
    }
}
