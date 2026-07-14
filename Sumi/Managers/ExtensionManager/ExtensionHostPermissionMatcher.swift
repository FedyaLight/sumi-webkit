import Foundation
import WebKit

@available(macOS 15.5, *)
enum ExtensionHostPermissionMatcher {
    @MainActor
    static func matches(_ pattern: String, url: URL) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        do {
            return try WKWebExtension.MatchPattern(string: trimmed).matches(url)
        } catch {
            RuntimeDiagnostics.debug(category: "Extensions") {
                "Invalid extension host pattern ignored: bytes=\(trimmed.utf8.count) error=\(error.localizedDescription)"
            }
            return false
        }
    }
}
