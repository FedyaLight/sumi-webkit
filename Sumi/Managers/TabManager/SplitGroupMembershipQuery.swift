import Foundation
import SumiDomain

/// Resolves runtime tab or pin identifiers to canonical split membership.
/// Durable lookup remains typed in `SplitGroupStore`; this boundary is the
/// only place where a window-local shortcut tab is translated to its pin.
@MainActor
struct SplitGroupMembershipQuery {
    private let store: SplitGroupStore
    private let tabs: TabCollectionMembershipOwner
    private let pins: ShortcutPinCollectionStateOwner

    init(
        store: SplitGroupStore,
        tabs: TabCollectionMembershipOwner,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.store = store
        self.tabs = tabs
        self.pins = pins
    }

    func memberID(for tab: Tab) -> SplitMemberID {
        tab.shortcutPinId.map(SplitMemberID.shortcutPin)
            ?? .regularTab(tab.id)
    }

    func memberID(forLookupID id: UUID) -> SplitMemberID? {
        if pins.shortcutPin(by: id) != nil {
            return .shortcutPin(id)
        }
        guard let tab = tabs.tab(for: id) else { return nil }
        return memberID(for: tab)
    }

    func group(containing memberID: SplitMemberID) -> SplitGroup? {
        store.group(containing: memberID)
    }

    func group(containing tab: Tab) -> SplitGroup? {
        store.group(containing: memberID(for: tab))
    }

    func group(forLookupID id: UUID) -> SplitGroup? {
        memberID(forLookupID: id).flatMap {
            store.group(containing: $0)
        }
    }
}
