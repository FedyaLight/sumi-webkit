import Foundation

/// Closes a shell that is still dedicated to its initial WebKit top-level
/// child. Dedicated state is window-local and survives WebView suspension; it
/// is not inferred from the current number of materialized WebViews.
@MainActor
final class WebKitChildWindowCloseTransaction: WebKitChildWindowClosing {
    private weak var lifecycle: WebViewLifecycleService?
    private weak var ownership: WebViewOwnershipQuery?
    private let tabClosure: TabClosureService
    private weak var windowTabs: BrowserWindowTabContext?
    private weak var windowCommands: BrowserWindowCommands?
    private let registry: @MainActor () -> WindowRegistry?

    init(
        lifecycle: WebViewLifecycleService,
        ownership: WebViewOwnershipQuery,
        tabClosure: TabClosureService,
        windowTabs: BrowserWindowTabContext,
        windowCommands: BrowserWindowCommands,
        registry: @escaping @MainActor () -> WindowRegistry?
    ) {
        self.lifecycle = lifecycle
        self.ownership = ownership
        self.tabClosure = tabClosure
        self.windowTabs = windowTabs
        self.windowCommands = windowCommands
        self.registry = registry
    }

    func closeIfDedicatedChild(_ target: TrackedWebKitCloseTarget) -> Bool {
        guard target.window.webKitChildWindowIdentity?.initialTabID
                == target.tab.id
        else {
            return false
        }

        guard windowTabs?.windowLocalTabResidenceIDs(in: target.window)
            == [target.tab.id]
        else {
            target.window.webKitChildWindowIdentity = nil
            return false
        }

        // Consume provenance before cleanup so a repeated callback is
        // idempotent and cannot close a subsequently adopted shell.
        target.window.webKitChildWindowIdentity = nil

        if target.window.isIncognito == false {
            target.window.currentTabId = nil
            target.window.selectionHistory.removeFromRegularTabHistory(
                target.tab.id
            )
            if hasOtherPhysicalResidence(
                for: target.tab,
                excluding: target.window.id
            ) {
                lifecycle?.cleanupTrackedWebViewAfterWebKitClose(
                    target.webView,
                    owner: target.owner
                )
            } else {
                tabClosure.removeTab(target.tab.id)
            }
        }

        windowCommands?.closeWindow(target.window)
        return true
    }

    private func hasOtherPhysicalResidence(
        for tab: Tab,
        excluding windowID: UUID
    ) -> Bool {
        if let windowTabs,
           registry()?.allWindows.contains(where: { window in
               window.id != windowID
                   && windowTabs.windowLocalTabResidenceIDs(in: window)
                       .contains(tab.id)
           }) == true {
            return true
        }
        return ownership?.windowIDs(for: tab.id).contains {
            $0 != windowID
        } == true
    }
}
