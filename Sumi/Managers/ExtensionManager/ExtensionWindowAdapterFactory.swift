import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowAdapterFactory {
    private let windowQuery: any ExtensionWindowQuery
    private let windowActivation: any ExtensionWindowActivation
    private let identity: ExtensionWindowAdapterIdentityProjection
    private let windowPublications: ExtensionWindowPublicationQuery
    private let tabAdapters: any ExtensionTabAdapterResolving
    private let publishedTabs: ExtensionPublishedNormalTabQuery
    private let preparedTabs: ExtensionPreparedNormalTabQuery

    init(
        windowQuery: any ExtensionWindowQuery,
        windowActivation: any ExtensionWindowActivation,
        identity: ExtensionWindowAdapterIdentityProjection,
        windowPublications: ExtensionWindowPublicationQuery,
        tabAdapters: any ExtensionTabAdapterResolving,
        publishedTabs: ExtensionPublishedNormalTabQuery,
        preparedTabs: ExtensionPreparedNormalTabQuery
    ) {
        self.windowQuery = windowQuery
        self.windowActivation = windowActivation
        self.identity = identity
        self.windowPublications = windowPublications
        self.tabAdapters = tabAdapters
        self.publishedTabs = publishedTabs
        self.preparedTabs = preparedTabs
    }

    func make(
        windowID: UUID,
        preparedTabVisibility: ExtensionPreparedTabVisibility
    ) -> ExtensionWindowAdapter? {
        guard let window = windowQuery.extensionWindowState(for: windowID)
        else { return nil }
        return ExtensionWindowAdapter(
            windowState: window,
            windowQuery: windowQuery,
            windowActivation: windowActivation,
            identity: identity,
            preparedTabVisibility: preparedTabVisibility,
            windowPublications: windowPublications,
            tabAdapters: tabAdapters,
            publishedTabs: publishedTabs,
            preparedTabs: preparedTabs
        )
    }

    func publishedAdapter(
        for window: BrowserWindowState,
        extensionContext: WKWebExtensionContext
    ) -> ExtensionWindowAdapter? {
        guard windowQuery.extensionWindowState(for: window.id) === window,
              let profileID = identity.profileID(for: extensionContext),
              identity.profileID(for: window) == profileID,
              let adapter = windowPublications.publishedWindowAdapter(
                  for: window,
                  profileID: profileID
              ),
              adapter.represents(window)
        else { return nil }
        return adapter
    }
}
