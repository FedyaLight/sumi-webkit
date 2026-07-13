import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionPreparedTabQuery: AnyObject {
    func containsPreparedTab(_ tab: Tab) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionPublishedTabQuery: AnyObject {
    func containsPublishedTab(_ tab: Tab) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabProfileResolving: AnyObject {
    func profileID(for tab: Tab) -> UUID?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWindowProfileQuery: AnyObject {
    func profileIDForWindowContainingExactTab(_ tab: Tab) -> UUID?
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabProfileResolution: ExtensionTabProfileResolving {
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var windowProfiles: (any ExtensionTabWindowProfileQuery)?

    init(
        profileRuntime: ExtensionProfileRuntime,
        windowProfiles: (any ExtensionTabWindowProfileQuery)?
    ) {
        self.profileRuntime = profileRuntime
        self.windowProfiles = windowProfiles
    }

    func profileID(for tab: Tab) -> UUID? {
        tab.profileId
            ?? tab.resolveProfile()?.id
            ?? windowProfiles?.profileIDForWindowContainingExactTab(tab)
            ?? profileRuntime?.currentProfileId
    }
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabControllerQuery: AnyObject {
    func existingController(for tab: Tab) -> WKWebExtensionController?
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionExistingExactTabControllerQuery:
    ExtensionTabControllerQuery {
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var profiles: (any ExtensionTabProfileResolving)?

    init(
        tabs: any ExtensionTabQuery,
        profileRuntime: ExtensionProfileRuntime,
        profiles: any ExtensionTabProfileResolving
    ) {
        self.tabs = tabs
        self.profileRuntime = profileRuntime
        self.profiles = profiles
    }

    func existingController(for tab: Tab) -> WKWebExtensionController? {
        guard tabs?.extensionTab(for: tab.id) === tab,
              let profileID = profiles?.profileID(for: tab)
        else { return nil }
        return profileRuntime?.controller(for: profileID)
    }
}

/// Separates the weaker window-first preparation authority from a settled
/// WebKit Tab publication. Callers must choose the phase they actually need.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPreparedNormalTabQuery: ExtensionPreparedTabQuery {
    private weak var tabPublicationRevisions:
        ExtensionTabPublicationRevisionAuthority?
    private weak var tabs: (any ExtensionTabQuery)?

    init(
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        tabs: any ExtensionTabQuery
    ) {
        self.tabPublicationRevisions = tabPublicationRevisions
        self.tabs = tabs
    }

    func containsPreparedTab(_ tab: Tab) -> Bool {
        guard let generation = tabPublicationRevisions?.issue()
        else { return false }
        return tab.isEphemeral == false
            && tabs?.extensionTab(for: tab.id) === tab
            && tab.extensionPageRuntimeOwner.canPublishFutureOpenNotification()
            && tab.extensionPageRuntimeOwner.isEligible(for: generation)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionPublishedNormalTabQuery: ExtensionPublishedTabQuery {
    private weak var prepared: (any ExtensionPreparedTabQuery)?
    private weak var tabPublicationRevisions:
        ExtensionTabPublicationRevisionAuthority?
    private weak var publicationGate: ExtensionRuntimePublicationGate?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var adapters: ExtensionBrowserAdapterStore?
    private weak var windows: (any ExtensionTabPublicationEvidenceQuery)?

    init(
        prepared: any ExtensionPreparedTabQuery,
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        publicationGate: ExtensionRuntimePublicationGate,
        profiles: any ExtensionTabProfileResolving,
        adapters: ExtensionBrowserAdapterStore,
        windows: any ExtensionTabPublicationEvidenceQuery
    ) {
        self.prepared = prepared
        self.tabPublicationRevisions = tabPublicationRevisions
        self.publicationGate = publicationGate
        self.profiles = profiles
        self.adapters = adapters
        self.windows = windows
    }

    func containsPublishedTab(_ tab: Tab) -> Bool {
        guard prepared?.containsPreparedTab(tab) == true,
              publicationGate?.acceptsBrowserEvents == true,
              let generation = tabPublicationRevisions?.issue(),
              tab.extensionPageRuntimeOwner
              .hasSettledDidOpenTabNotification(for: generation),
              let profileID = profiles?.profileID(for: tab),
              windows?.tabPublicationIsCurrent(
                  tab,
                  profileID: profileID
              ) == true,
              let adapter = adapters?.existingTabAdapter(for: tab.id),
              adapter.represents(tab)
        else {
            return false
        }
        return true
    }
}
