import Foundation

/// Foundation-only helpers for recognizing WebExtension-owned URL schemes.
public enum SumiExtensionOwnedURL {
    public static let schemes: Set<String> = [
        "webkit-extension",
        "safari-web-extension",
    ]

    public static func isExtensionOwnedURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return schemes.contains(scheme)
    }
}
