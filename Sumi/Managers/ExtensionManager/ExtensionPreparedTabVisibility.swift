import Foundation

/// Grants prepared-Tab reads only while WebKit is synchronously crossing the
/// exact window or Tab open callback that needs window-first visibility.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPreparedTabVisibility {
    private struct WindowScope {
        let token: UUID
        let window: BrowserWindowState
        let adapter: ExtensionWindowAdapter
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
        _ callback: () -> Void
    ) {
        let token = UUID()
        windowScopes.append(
            WindowScope(token: token, window: window, adapter: adapter)
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
}
