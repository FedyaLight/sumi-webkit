import Foundation

@MainActor
enum BrowserHoverSidebarRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> HoverSidebarRuntime {
        HoverSidebarRuntime(
            browserRuntimeAvailable: { [weak browserManager] in
                browserManager != nil
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }
}

extension HoverSidebarRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        BrowserHoverSidebarRuntimeFactory.runtime(for: browserManager)
    }
}
