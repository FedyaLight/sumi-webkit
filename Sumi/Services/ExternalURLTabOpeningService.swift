import Foundation

@MainActor
final class ExternalURLTabOpeningService: ExternalURLHandling {
    private weak var windowRegistry: WindowRegistry?
    private weak var tabOpening: (any URLTabOpening)?

    init(
        windowRegistry: WindowRegistry,
        tabOpening: any URLTabOpening
    ) {
        self.windowRegistry = windowRegistry
        self.tabOpening = tabOpening
    }

    func presentExternalURL(_ url: URL) {
        guard let windowState = windowRegistry?.activeWindow,
              let tabOpening
        else { return }
        _ = tabOpening.openNewTab(
            url: url.absoluteString,
            context: .foreground(windowState: windowState)
        )
    }
}
