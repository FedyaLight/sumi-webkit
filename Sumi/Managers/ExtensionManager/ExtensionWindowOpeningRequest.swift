import Foundation
import WebKit

/// Immutable projection of WebKit's window-opening callback payload.
///
/// WebKit owns `WKWebExtension.WindowConfiguration`. Snapshotting the fields
/// Sumi consumes at the delegate boundary keeps the asynchronous transaction
/// independent of SDK object lifetime and makes policy admission a value-only
/// operation.
@available(macOS 15.5, *)
struct ExtensionWindowOpeningRequest {
    let windowType: WKWebExtension.WindowType
    let frame: CGRect
    let tabURLs: [URL]
    let shouldBeFocused: Bool
    let shouldBePrivate: Bool

    init(
        windowType: WKWebExtension.WindowType,
        frame: CGRect,
        tabURLs: [URL],
        shouldBeFocused: Bool,
        shouldBePrivate: Bool
    ) {
        self.windowType = windowType
        self.frame = frame
        self.tabURLs = tabURLs
        self.shouldBeFocused = shouldBeFocused
        self.shouldBePrivate = shouldBePrivate
    }

    @MainActor
    init(configuration: WKWebExtension.WindowConfiguration) {
        self.init(
            windowType: configuration.windowType,
            frame: configuration.frame,
            tabURLs: configuration.tabURLs,
            shouldBeFocused: configuration.shouldBeFocused,
            shouldBePrivate: configuration.shouldBePrivate
        )
    }
}
