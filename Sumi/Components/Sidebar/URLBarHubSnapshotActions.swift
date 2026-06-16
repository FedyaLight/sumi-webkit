import SwiftUI

enum URLBarHubScreenshotQuality: Int, CaseIterable, Identifiable {
    case oneX = 1
    case twoX = 2
    case fourX = 4
    case eightX = 8
    case sixteenX = 16

    var id: Int { rawValue }
    var scale: CGFloat { CGFloat(rawValue) }
    var label: String { "\(rawValue)x" }
    var menuTitle: String {
        switch self {
        case .oneX:
            return "1x - Small"
        case .twoX:
            return "2x - Default"
        case .fourX:
            return "4x - High Detail"
        case .eightX:
            return "8x - Ultra"
        case .sixteenX:
            return "16x - Maximum"
        }
    }
}

enum URLBarHubSnapshotActions {
    @MainActor
    static func suggestedFilename(
        for tab: Tab,
        quality: URLBarHubScreenshotQuality = .oneX
    ) -> String {
        let rawTitle = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = rawTitle.isEmpty ? "Sumi Capture" : rawTitle
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let sanitized = base.components(separatedBy: invalidCharacters)
            .joined(separator: "-")
        let scaleSuffix = quality == .oneX ? "" : "@\(quality.rawValue)x"
        return "\(sanitized)\(scaleSuffix).png"
    }
}
