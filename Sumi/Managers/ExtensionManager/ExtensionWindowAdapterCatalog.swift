import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowAdapterCatalog {
    private let adapterStore: ExtensionBrowserAdapterStore
    private let factory: ExtensionWindowAdapterFactory

    init(
        adapterStore: ExtensionBrowserAdapterStore,
        factory: ExtensionWindowAdapterFactory
    ) {
        self.adapterStore = adapterStore
        self.factory = factory
    }

    func adapter(
        for windowID: UUID,
        preparedTabVisibility: ExtensionPreparedTabVisibility
    ) -> ExtensionWindowAdapter? {
        adapterStore.windowAdapter(for: windowID) {
            factory.make(
                windowID: windowID,
                preparedTabVisibility: preparedTabVisibility
            )
        }
    }

    func publishedAdapter(
        for window: BrowserWindowState,
        extensionContext: WKWebExtensionContext
    ) -> ExtensionWindowAdapter? {
        factory.publishedAdapter(for: window, extensionContext: extensionContext)
    }
}
