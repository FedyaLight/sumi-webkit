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
    let windowState: WKWebExtension.WindowState
    let frame: CGRect
    let tabURLs: [URL]
    let tabs: [any WKWebExtensionTab]
    let shouldBeFocused: Bool
    let shouldBePrivate: Bool

    init(
        windowType: WKWebExtension.WindowType,
        windowState: WKWebExtension.WindowState = .normal,
        frame: CGRect,
        tabURLs: [URL],
        tabs: [any WKWebExtensionTab] = [],
        shouldBeFocused: Bool,
        shouldBePrivate: Bool
    ) {
        self.windowType = windowType
        self.windowState = windowState
        self.frame = frame
        self.tabURLs = tabURLs
        self.tabs = tabs
        self.shouldBeFocused = shouldBeFocused
        self.shouldBePrivate = shouldBePrivate
    }

    @MainActor
    init(configuration: WKWebExtension.WindowConfiguration) {
        self.init(
            windowType: configuration.windowType,
            windowState: configuration.windowState,
            frame: configuration.frame,
            tabURLs: configuration.tabURLs,
            tabs: configuration.tabs,
            shouldBeFocused: configuration.shouldBeFocused,
            shouldBePrivate: configuration.shouldBePrivate
        )
    }
}
