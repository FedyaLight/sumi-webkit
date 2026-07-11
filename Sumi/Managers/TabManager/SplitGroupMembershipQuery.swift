import Foundation
import SumiDomain

/// Resolves runtime tab or pin identifiers to canonical split membership.
/// Durable lookup remains typed in `SplitGroupStore`; this boundary is the
/// only place where a window-local shortcut tab is translated to its pin.
@MainActor
struct SplitGroupMembershipQuery {
    private let store: SplitGroupStore
    private let tab: (UUID) -> Tab?
    private let shortcutPinExists: (UUID) -> Bool

    init(
        store: SplitGroupStore,
        tab: @escaping (UUID) -> Tab?,
        shortcutPinExists: @escaping (UUID) -> Bool
    ) {
        self.store = store
        self.tab = tab
        self.shortcutPinExists = shortcutPinExists
    }

    func memberID(for tab: Tab) -> SplitMemberID {
        tab.shortcutPinId.map(SplitMemberID.shortcutPin)
            ?? .regularTab(tab.id)
    }

    func memberID(forLookupID id: UUID) -> SplitMemberID? {
        if shortcutPinExists(id) {
            return .shortcutPin(id)
        }
        guard let tab = tab(id) else { return nil }
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

extension SplitGroupMembershipQuery {
    init(tabManager: TabManager) {
        self.init(
            store: tabManager.splitGroupStore,
            tab: { [weak tabManager] in
                tabManager?.tabCollectionMembershipOwner.tab(for: $0)
            },
            shortcutPinExists: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner
                    .shortcutPin(by: $0) != nil
            }
        )
    }
}
