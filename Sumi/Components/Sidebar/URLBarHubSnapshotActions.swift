import SwiftUI

enum URLBarHubSnapshotActions {
    @MainActor
    static func suggestedFilename(for tab: Tab) -> String {
        let rawTitle = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = rawTitle.isEmpty ? "Sumi Capture" : rawTitle
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = base.components(separatedBy: invalidCharacters)
            .joined(separator: "-")
        return "\(sanitized).png"
    }
}
