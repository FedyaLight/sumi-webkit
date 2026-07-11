import Foundation

@MainActor
extension WindowSplitPresentationSynchronizer {
    convenience init(liveBrowserManager browserManager: BrowserManager) {
        self.init(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            windows: { [weak browserManager] in
                guard let values = browserManager?.windowRegistry?.windows.values
                else { return [] }
                return Array(values)
            },
            selectTabWithoutPersistence: { [weak browserManager] tab, window in
                browserManager?.applyTabSelection(
                    tab,
                    in: window,
                    updateSpaceFromTab: true,
                    updateTheme: true,
                    rememberSelection: true,
                    persistSelection: false
                )
            },
            refreshCompositor: { [weak browserManager] window in
                browserManager?.shellRuntime.windowVisuals
                    .refreshCompositor(for: window)
            },
            persistWindowSession: { [weak browserManager] window in
                browserManager?.windowSessionBundle.persistence.persist(window)
            }
        )
    }
}
