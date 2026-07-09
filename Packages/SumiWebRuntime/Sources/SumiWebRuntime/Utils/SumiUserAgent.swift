import Foundation
import WebKit

enum SumiUserAgent {
    private static let fallbackSafariVersion = "26.5"
    private static let fallbackWebKitVersion = "605.1.15"

    /// Dynamically constructs a Safari-compatible application name suffix to avoid Google blocks and bot-detection.
    @MainActor
    static let safariCompatibleApplicationNameForUserAgent: String = {
        let safariVersion = getSafariVersion() ?? fallbackSafariVersion
        let webKitVersion = getWebKitVersion() ?? fallbackWebKitVersion
        return "Version/\(safariVersion) Safari/\(webKitVersion)"
    }()

    @MainActor
    static func apply(to webView: WKWebView) {
        webView.customUserAgent = nil
    }

    /// Reads the actual system's Safari version from Safari's Info.plist
    private static func getSafariVersion() -> String? {
        let plistPath = "/Applications/Safari.app/Contents/Info.plist"
        guard let plist = NSDictionary(contentsOfFile: plistPath),
              let version = plist["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return version
    }

    /// Parses the dynamic WebKit version from a temporary WKWebView User-Agent to match the runtime perfectly
    @MainActor
    private static func getWebKitVersion() -> String? {
        let webView = WKWebView(frame: .zero)
        guard let userAgent = webView.value(forKey: "userAgent") as? String else {
            return nil
        }

        let pattern = #"AppleWebKit\s*\/\s*([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: userAgent, options: [], range: NSRange(userAgent.startIndex..., in: userAgent)) else {
            return nil
        }

        if let range = Range(match.range(at: 1), in: userAgent) {
            return String(userAgent[range])
        }
        return nil
    }
}
