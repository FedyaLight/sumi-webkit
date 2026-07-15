import AppKit
import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionMiniWindowAdapterCatalog {
    private let adapterStore: ExtensionBrowserAdapterStore
    private let auxiliaryWindows: any ExtensionAuxiliaryWindowControl
    private let windowPublications: ExtensionWindowPublicationQuery

    init(
        adapterStore: ExtensionBrowserAdapterStore,
        auxiliaryWindows: any ExtensionAuxiliaryWindowControl,
        windowPublications: ExtensionWindowPublicationQuery
    ) {
        self.adapterStore = adapterStore
        self.auxiliaryWindows = auxiliaryWindows
        self.windowPublications = windowPublications
    }

    func adapter(for tab: Tab) -> ExtensionMiniWindowAdapter? {
        auxiliaryWindows.auxiliaryWindowSession(for: tab)?.miniWindowAdapter
    }

    func adapter(
        for sessionID: UUID,
        tab: Tab,
        window: NSWindow,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) -> ExtensionMiniWindowAdapter? {
        adapterStore.miniWindowAdapter(for: sessionID) {
            [weak auxiliaryWindows] in
            guard let auxiliaryWindows else { return nil }
            return ExtensionMiniWindowAdapter(
                sessionId: sessionID,
                tab: tab,
                window: window,
                auxiliaryWindows: auxiliaryWindows,
                windowPublications: windowPublications,
                isPrivate: isPrivate,
                shouldActivateApp: shouldActivateApp
            )
        }
    }
}
