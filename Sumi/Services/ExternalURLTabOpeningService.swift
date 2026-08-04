import AppKit
import Foundation

@MainActor
final class ExternalURLTabOpeningService: ExternalURLHandling {
    private weak var windowRegistry: WindowRegistry?
    private weak var tabOpening: (any URLTabOpening)?
    private let focusWindow: @MainActor (BrowserWindowState) -> Void

    init(
        windowRegistry: WindowRegistry,
        tabOpening: any URLTabOpening,
        focusWindow: (@MainActor (BrowserWindowState) -> Void)? = nil
    ) {
        self.windowRegistry = windowRegistry
        self.tabOpening = tabOpening
        self.focusWindow = focusWindow ?? { [weak windowRegistry] windowState in
            NSApp.activate(ignoringOtherApps: true)
            windowRegistry?.appKitWindow(for: windowState)?.makeKeyAndOrderFront(nil)
        }
    }

    func presentExternalURL(_ url: URL) {
        guard let windowState = windowRegistry?.activeWindow,
              let tabOpening
        else { return }
        _ = tabOpening.openNewTab(
            url: url.absoluteString,
            context: .foreground(windowState: windowState)
        )
        focusWindow(windowState)
    }
}
