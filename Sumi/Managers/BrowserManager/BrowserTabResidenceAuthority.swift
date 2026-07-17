import Foundation

/// Runtime-generation identity installed into every window owned by one
/// browser kernel. Windows retain no service locator; this token only fences
/// stale prepublication and rollback receipts from a replacement kernel.
@MainActor
final class BrowserTabResidenceSessionIdentity {}

/// Exact browser-tab residence and rollback authority shared by native window,
/// WebKit child-window, link-window, and extension publication transactions.
@MainActor
final class BrowserTabResidenceAuthority {
    struct RegularRemovalAdmission {
        fileprivate let authorityID: ObjectIdentifier
        fileprivate let window: BrowserWindowState
        let tab: Tab
        let spaceID: UUID
    }

    struct RemovalAdmission {
        fileprivate enum Residence {
            case regular(spaceID: UUID)
            case ephemeral(window: BrowserWindowState)
        }

        fileprivate let authorityID: ObjectIdentifier
        fileprivate let tab: Tab
        fileprivate let residence: Residence
    }

    private let sessionIdentity: BrowserTabResidenceSessionIdentity
    private let regularTabs: RegularTabCollectionOwner
    private let liveShortcuts: LiveShortcutTabRegistry
    private let structuralLookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService

    init(
        sessionIdentity: BrowserTabResidenceSessionIdentity,
        regularTabs: RegularTabCollectionOwner,
        liveShortcuts: LiveShortcutTabRegistry,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService
    ) {
        self.sessionIdentity = sessionIdentity
        self.regularTabs = regularTabs
        self.liveShortcuts = liveShortcuts
        self.structuralLookup = structuralLookup
        self.persistence = persistence
    }

    func owns(_ window: BrowserWindowState) -> Bool {
        window.tabResidenceSessionIdentity === sessionIdentity
    }

    func establishResidenceSession(on window: BrowserWindowState) {
        window.tabResidenceSessionIdentity = sessionIdentity
    }

    func rollbackUnpublishedPrivateAggregate(
        in window: BrowserWindowState,
        expectedProfile: Profile,
        expectedSpace: Space,
        expectedTab: Tab,
        expectedChildWindowIdentity: WebKitChildWindowIdentity?
    ) -> Bool {
        guard owns(window) else { return false }
        return window.rollbackUnpublishedPrivateAggregate(
            expectedProfile: expectedProfile,
            expectedSpace: expectedSpace,
            expectedTab: expectedTab,
            expectedResidenceSessionID: ObjectIdentifier(sessionIdentity),
            expectedChildWindowIdentity: expectedChildWindowIdentity
        )
    }

    func containsExact(
        _ tab: Tab,
        in window: BrowserWindowState
    ) -> Bool {
        guard owns(window) else { return false }
        if window.isIncognito {
            return tab.spaceId == nil
                && window.containsEphemeralTab(ifIdentical: tab)
        }
        if let entry = liveShortcuts.entry(containing: tab) {
            return entry.windowId == window.id
                && structuralLookup.lookupOwner.containsExact(tab)
        }
        guard let spaceID = tab.spaceId,
              window.currentSpaceId == spaceID,
              regularTabs.containsIdentical(tab, in: spaceID)
        else {
            return false
        }
        return structuralLookup.lookupOwner.containsExact(tab)
    }

    func admitRemoval(
        of tab: Tab,
        from window: BrowserWindowState
    ) -> RemovalAdmission? {
        guard owns(window) else { return nil }
        if window.isIncognito {
            guard tab.spaceId == nil,
                  window.containsEphemeralTab(ifIdentical: tab)
            else { return nil }
            return RemovalAdmission(
                authorityID: ObjectIdentifier(self),
                tab: tab,
                residence: .ephemeral(window: window)
            )
        }
        guard liveShortcuts.entry(containing: tab) == nil,
              let spaceID = tab.spaceId,
              window.currentSpaceId == spaceID,
              regularTabs.containsIdentical(tab, in: spaceID),
              structuralLookup.lookupOwner.containsExact(tab)
        else {
            return nil
        }
        return RemovalAdmission(
            authorityID: ObjectIdentifier(self),
            tab: tab,
            residence: .regular(spaceID: spaceID)
        )
    }

    func admitRegularRemoval(
        of tab: Tab,
        from window: BrowserWindowState
    ) -> RegularRemovalAdmission? {
        guard owns(window),
              liveShortcuts.entry(containing: tab) == nil,
              let spaceID = tab.spaceId,
              window.currentSpaceId == spaceID,
              regularTabs.containsIdentical(tab, in: spaceID),
              structuralLookup.lookupOwner.containsExact(tab)
        else {
            return nil
        }
        return RegularRemovalAdmission(
            authorityID: ObjectIdentifier(self),
            window: window,
            tab: tab,
            spaceID: spaceID
        )
    }

    func validates(_ admission: RegularRemovalAdmission) -> Bool {
        admission.authorityID == ObjectIdentifier(self)
            && owns(admission.window)
            && admission.window.currentSpaceId == admission.spaceID
            && admission.tab.spaceId == admission.spaceID
            && regularTabs.containsIdentical(
                admission.tab,
                in: admission.spaceID
            )
            && structuralLookup.lookupOwner.containsExact(admission.tab)
    }

    @discardableResult
    func commitRemoval(
        _ admission: RemovalAdmission,
        currentSpaceID: UUID?
    ) -> Bool {
        guard admission.authorityID == ObjectIdentifier(self) else {
            return false
        }
        switch admission.residence {
        case .regular(let spaceID):
            return structuralLookup.withTransaction {
                guard admission.tab.spaceId == spaceID,
                      regularTabs.containsIdentical(
                          admission.tab,
                          in: spaceID
                      ),
                      structuralLookup.lookupOwner.containsExact(
                          admission.tab
                      )
                else {
                    return false
                }
                persistence.cancelRuntimeStatePersistence(
                    for: admission.tab.id
                )
                guard regularTabs.remove(
                    ifIdentical: admission.tab,
                    from: spaceID,
                    currentSpaceId: currentSpaceID
                ) != nil else {
                    return false
                }
                precondition(
                    structuralLookup.lookupOwner.detachExact(admission.tab),
                    "Exact regular residence diverged during rollback"
                )
                persistence.scheduleStructuralPersistence()
                return true
            }
        case .ephemeral(let window):
            guard owns(window),
                  admission.tab.spaceId == nil,
                  window.containsEphemeralTab(ifIdentical: admission.tab)
            else {
                return false
            }
            persistence.cancelRuntimeStatePersistence(for: admission.tab.id)
            return window.removeEphemeralTab(ifIdentical: admission.tab)
        }
    }

    func prepareEphemeralAggregateRemoval(
        _ admission: RemovalAdmission
    ) -> Bool {
        guard admission.authorityID == ObjectIdentifier(self),
              case .ephemeral(let window) = admission.residence,
              owns(window),
              admission.tab.spaceId == nil,
              window.containsEphemeralTab(ifIdentical: admission.tab)
        else { return false }
        persistence.cancelRuntimeStatePersistence(for: admission.tab.id)
        return true
    }
}
