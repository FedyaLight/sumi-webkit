import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapterEvidenceFactory {
    private let tabQuery: any ExtensionTabQuery
    private let tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority
    private let profileIDForTab: @MainActor (Tab) -> UUID?
    private let adapterStore: ExtensionBrowserAdapterStore
    private let windowPublications: ExtensionWindowPublicationQuery
    private let contextPublications: ExtensionContextPublicationQuery

    init(
        tabQuery: any ExtensionTabQuery,
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        profileIDForTab: @escaping @MainActor (Tab) -> UUID?,
        adapterStore: ExtensionBrowserAdapterStore,
        windowPublications: ExtensionWindowPublicationQuery,
        contextPublications: ExtensionContextPublicationQuery
    ) {
        self.tabQuery = tabQuery
        self.tabPublicationRevisions = tabPublicationRevisions
        self.profileIDForTab = profileIDForTab
        self.adapterStore = adapterStore
        self.windowPublications = windowPublications
        self.contextPublications = contextPublications
    }

    func make(for tab: Tab) -> ExtensionTabCurrentPublicationEvidence? {
        guard tabQuery.extensionTab(for: tab.id) === tab else { return nil }
        return ExtensionTabCurrentPublicationEvidence(
            tab: tab,
            tabQuery: tabQuery,
            tabPublicationRevisions: tabPublicationRevisions,
            profileID: profileIDForTab,
            adapterPublications: adapterStore,
            windowPublications: windowPublications,
            contextPublications: contextPublications
        )
    }
}
