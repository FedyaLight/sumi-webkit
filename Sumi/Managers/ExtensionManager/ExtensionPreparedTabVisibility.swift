import Foundation
import WebKit

/// Grants prepared-Tab reads only while WebKit is synchronously crossing the
/// exact window or Tab open callback that needs window-first visibility.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPreparedTabVisibility {
    private struct WindowScope {
        let token: UUID
        let window: BrowserWindowState
        let adapter: ExtensionWindowAdapter
        let controller: WKWebExtensionController
    }

    private struct TabScope {
        let token: UUID
        let tab: Tab
    }

    private weak var gate: ExtensionRuntimePublicationGate?
    private var windowScopes: [WindowScope] = []
    private var tabScopes: [TabScope] = []

    init(gate: ExtensionRuntimePublicationGate) {
        self.gate = gate
    }

    func withWindowOpenCallback(
        window: BrowserWindowState,
        adapter: ExtensionWindowAdapter,
        controller: WKWebExtensionController,
        _ callback: () -> Void
    ) {
        let token = UUID()
        windowScopes.append(
            WindowScope(
                token: token,
                window: window,
                adapter: adapter,
                controller: controller
            )
        )
        defer { windowScopes.removeAll { $0.token == token } }
        callback()
    }

    func withTabOpenCallback(
        tab: Tab,
        _ callback: () -> Void
    ) {
        let token = UUID()
        tabScopes.append(TabScope(token: token, tab: tab))
        defer { tabScopes.removeAll { $0.token == token } }
        callback()
    }

    func allowsPreparedTabRead(
        _ tab: Tab,
        in window: BrowserWindowState,
        through adapter: ExtensionWindowAdapter
    ) -> Bool {
        if windowScopes.contains(where: {
            $0.window === window && $0.adapter === adapter
        }) {
            return true
        }
        guard tabScopes.isEmpty == false else { return false }
        if gate?.isBrowserEventHandoffActive == true {
            return true
        }
        return tabScopes.contains { $0.tab === tab }
    }

    /// Returns authority only while the exact `didOpenWindow` callback that
    /// exposed this prepared adapter is still on the stack. The controller's
    /// own open-Tab catalog proves WebKit actually adopted the adapter.
    func controllerExposingPreparedAdapter(
        _ adapter: ExtensionTabAdapter
    ) -> WKWebExtensionController? {
        windowScopes.reversed().first(where: { scope in
            scope.controller.extensionContexts.contains { context in
                context.openTabs.contains { ($0 as AnyObject) === adapter }
            }
        })?.controller
    }
}
