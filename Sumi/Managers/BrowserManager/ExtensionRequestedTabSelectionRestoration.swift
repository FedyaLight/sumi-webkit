import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabSelectionRestoration {
    struct Witness {
        fileprivate let removedCurrentTab: Bool
    }

    private let selection: TabSelectionStateOwner
    private let membership: TabCollectionMembershipOwner

    init(
        selection: TabSelectionStateOwner,
        membership: TabCollectionMembershipOwner
    ) {
        self.selection = selection
        self.membership = membership
    }

    func capture(for tab: Tab) -> Witness {
        Witness(removedCurrentTab: selection.currentTab === tab)
    }

    func restore(_ witness: Witness, to tabID: UUID?) {
        guard witness.removedCurrentTab else { return }
        selection.replaceCurrentTab(
            tabID.flatMap { membership.tab(for: $0) }
        )
    }
}
