import Foundation
import WebKit

@available(macOS 15.5, *)
enum SafariExtensionMatchPatternDiagnostics {
    static func make(_ value: String, purpose: String) -> WKWebExtension.MatchPattern? {
        do {
            return try WKWebExtension.MatchPattern(string: value)
        } catch {
            logInvalidPattern(value, purpose: purpose, error: error)
            return nil
        }
    }

    static func normalizedStringOrOriginal(_ value: String, purpose: String) -> String {
        make(value, purpose: purpose)?.string ?? value
    }

    private static func logInvalidPattern(_ value: String, purpose: String, error: Error) {
        RuntimeDiagnostics.debug(category: "SafariExtensionPermissions") {
            let bucket = SafariExtensionPermissionLifecycleDiagnostics.bucket(value) ?? "empty"
            return "Invalid WebExtension match pattern purpose=\(purpose) patternBucket=\(bucket) error=\(error.localizedDescription)"
        }
    }
}
