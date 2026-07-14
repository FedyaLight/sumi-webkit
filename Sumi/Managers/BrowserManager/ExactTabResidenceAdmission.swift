import Foundation

/// Exact physical residence receipt for rollback-only effects. Admission and
/// removal both use object identity, so a stale transaction cannot clean up or
/// remove a newer Tab that reused the same durable UUID.
@MainActor
struct ExactTabResidenceAdmission {
    private enum Residence {
        case regular(spaceID: UUID)
        case ephemeral(window: BrowserWindowState)
    }

    private let tab: Tab
    private let residence: Residence

    static func regular(
        _ tab: Tab,
        in spaceID: UUID,
        tabs: TabManager
    ) -> Self? {
        guard tabs.regularTabCollectionOwner.containsIdentical(
            tab,
            in: spaceID
        ) else { return nil }
        return Self(tab: tab, residence: .regular(spaceID: spaceID))
    }

    static func ephemeral(
        _ tab: Tab,
        in window: BrowserWindowState
    ) -> Self? {
        guard window.containsEphemeralTab(ifIdentical: tab) else { return nil }
        return Self(tab: tab, residence: .ephemeral(window: window))
    }

    @discardableResult
    func remove(
        tabs: TabManager,
        currentSpaceID: UUID?
    ) -> Bool {
        switch residence {
        case .regular(let spaceID):
            tabs.regularTabCollectionOwner.remove(
                ifIdentical: tab,
                from: spaceID,
                currentSpaceId: currentSpaceID
            ) != nil
        case .ephemeral(let window):
            window.removeEphemeralTab(ifIdentical: tab)
        }
    }
}
