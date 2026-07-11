import Foundation

/// Supplies ContentView with only the browser state and persistence operation
/// needed by a window's SwiftUI appear/disappear lifecycle.
@MainActor
final class BrowserWindowLifecycleService: BrowserWindowLifecycleHandling {
    let tabManager: TabManager
    private let persist: @MainActor (BrowserWindowState) -> Void

    init(
        tabManager: TabManager,
        persist: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.tabManager = tabManager
        self.persist = persist
    }

    func persistWindowSession(for windowState: BrowserWindowState) {
        persist(windowState)
    }
}
