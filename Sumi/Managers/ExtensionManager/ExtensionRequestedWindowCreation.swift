import Foundation
import WebKit

/// Immutable input for creating a normal browser window requested by WebKit.
/// The Space is the presentation partition; its profile must match `profileID`.
@available(macOS 15.5, *)
struct ExtensionRequestedWindowSeed {
    let profileID: UUID
    let space: Space
    let url: URL?
    let webExtensionContext: WKWebExtensionContext?
}

/// Exact hidden browser window whose model, initial Tab, physical WebView, and
/// extension projection have already crossed their ordered publication boundary.
/// Presentation remains deferred until the caller validates the public adapter
/// against the requesting controller/context. A failed validation can therefore
/// still roll the complete transaction back without flashing an empty window.
@available(macOS 15.5, *)
@MainActor
protocol PreparedExtensionRequestedWindow: AnyObject {
    var window: BrowserWindowState { get }

    /// Emits focus/activation only after the exact published adapter is known.
    func present() -> Bool

    /// Finalizes persistence after post-focus controller/context validation.
    func accept() -> Bool

    /// Balances publication and removes the exact Tab/WebView/window state.
    func cancel()
}

/// Browser-side transaction boundary for an extension-requested normal window.
/// Preparation is atomic but deliberately does not present the native shell.
@available(macOS 15.5, *)
@MainActor
protocol ExtensionRequestedWindowCreating: AnyObject {
    func prepareExtensionRequestedWindow(
        _ seed: ExtensionRequestedWindowSeed
    ) -> (any PreparedExtensionRequestedWindow)?
}
