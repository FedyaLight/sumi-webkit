import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabAdapterPublicationQuery: AnyObject {
    func existingTabAdapter(for tabID: UUID) -> ExtensionTabAdapter?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabPublicationEvidenceQuery: AnyObject {
    func isCommittedAuxiliaryTabAdapter(
        _ adapter: ExtensionTabAdapter,
        for tab: Tab,
        visibleTo context: WKWebExtensionContext
    ) -> Bool
    func tabPublicationIsCurrent(_ tab: Tab, profileID: UUID) -> Bool
    func isAuxiliarySessionTab(_ tab: Tab) -> Bool
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionTabCurrentPublication {
    let tab: Tab
    let contextIdentity: (extensionID: String, profileID: UUID)
    let isAuxiliary: Bool
}

/// Exact physical Tab identity plus the current WebExtension publication
/// evidence required before any projection or command may use it.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabCurrentPublicationEvidence {
    let tabID: UUID

    private weak var exactTab: Tab?
    private weak var adapter: ExtensionTabAdapter?
    private weak var tabQuery: (any ExtensionTabQuery)?
    private weak var runtimeSession: ExtensionRuntimeSession?
    private let profileID: @MainActor (Tab) -> UUID?
    private weak var adapterPublications:
        (any ExtensionTabAdapterPublicationQuery)?
    private weak var windowPublications:
        (any ExtensionTabPublicationEvidenceQuery)?
    private weak var contextPublications: ExtensionContextPublicationQuery?
    private let requiresAuxiliaryPublication: Bool

    init(
        tab: Tab,
        tabQuery: any ExtensionTabQuery,
        runtimeSession: ExtensionRuntimeSession,
        profileID: @escaping @MainActor (Tab) -> UUID?,
        adapterPublications: any ExtensionTabAdapterPublicationQuery,
        windowPublications: any ExtensionTabPublicationEvidenceQuery,
        contextPublications: ExtensionContextPublicationQuery
    ) {
        tabID = tab.id
        exactTab = tab
        self.tabQuery = tabQuery
        self.runtimeSession = runtimeSession
        self.profileID = profileID
        self.adapterPublications = adapterPublications
        self.windowPublications = windowPublications
        self.contextPublications = contextPublications
        requiresAuxiliaryPublication = tab.isAuxiliaryMiniWindow
            || tabQuery.isAuxiliaryMiniWindowTab(tab)
    }

    func bind(adapter: ExtensionTabAdapter) {
        precondition(self.adapter == nil)
        self.adapter = adapter
    }

    var currentTab: Tab? {
        guard let exactTab,
              tabQuery?.extensionTab(for: tabID) === exactTab else {
            return nil
        }
        return exactTab
    }

    func represents(_ tab: Tab) -> Bool {
        exactTab === tab && tabQuery?.extensionTab(for: tabID) === tab
    }

    func hasExactIdentity(_ tab: Tab) -> Bool {
        exactTab === tab
    }

    func canBeReplaced(by tab: Tab) -> Bool {
        exactTab !== tab && tabQuery?.extensionTab(for: tabID) === tab
    }

    func currentPublication(
        visibleTo context: WKWebExtensionContext
    ) -> ExtensionTabCurrentPublication? {
        guard let identity = contextPublications?.currentIdentity(for: context),
              let tab = currentTab,
              let adapter,
              adapterPublications?.existingTabAdapter(for: tabID) === adapter,
              tabIsEligible(tab)
        else {
            return nil
        }

        let auxiliary = isAuxiliary(tab)
        if auxiliary {
            guard windowPublications?.isCommittedAuxiliaryTabAdapter(
                    adapter,
                    for: tab,
                    visibleTo: context
                  ) == true
            else {
                return nil
            }
        } else {
            guard profileID(tab) == identity.profileID,
                  windowPublications?.tabPublicationIsCurrent(
                    tab,
                    profileID: identity.profileID
                  ) == true
            else {
                return nil
            }
        }

        return ExtensionTabCurrentPublication(
            tab: tab,
            contextIdentity: identity,
            isAuxiliary: auxiliary
        )
    }

    func isCurrent(
        _ publication: ExtensionTabCurrentPublication,
        visibleTo context: WKWebExtensionContext
    ) -> Bool {
        guard let current = currentPublication(visibleTo: context) else {
            return false
        }
        return current.tab === publication.tab
            && current.contextIdentity.extensionID
                == publication.contextIdentity.extensionID
            && current.contextIdentity.profileID
                == publication.contextIdentity.profileID
            && current.isAuxiliary == publication.isAuxiliary
    }

    func isAuxiliary(_ tab: Tab) -> Bool {
        requiresAuxiliaryPublication
            || tab.isAuxiliaryMiniWindow
            || tabQuery?.isAuxiliaryMiniWindowTab(tab) == true
            || windowPublications?.isAuxiliarySessionTab(tab) == true
    }

    private func tabIsEligible(_ tab: Tab) -> Bool {
        guard tab.isEphemeral == false,
              let generation = runtimeSession?.tabOpenNotificationGeneration
        else {
            return false
        }
        return tab.extensionPageRuntimeOwner.isEligible(for: generation)
    }
}

@available(macOS 15.5, *)
extension ExtensionBrowserAdapterStore: ExtensionTabAdapterPublicationQuery {}
