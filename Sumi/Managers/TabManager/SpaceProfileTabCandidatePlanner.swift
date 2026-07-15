import Foundation

@MainActor
struct SpaceProfileTabCandidate {
    let tab: Tab
    let desiredProfileID: UUID?
}

/// Selects Tabs whose physical execution profile inherits from one Space.
/// Account-fork shortcut Tabs keep their explicit execution profile.
@MainActor
final class SpaceProfileTabCandidatePlanner {
    private let membership: TabCollectionMembershipOwner
    private let registry: LiveShortcutTabRegistry
    private let pins: ShortcutPinCollectionStateOwner

    init(
        membership: TabCollectionMembershipOwner,
        registry: LiveShortcutTabRegistry,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.membership = membership
        self.registry = registry
        self.pins = pins
    }

    func candidates(
        in spaceID: UUID,
        sourceProfileID: UUID?,
        targetProfileID: UUID
    ) -> [SpaceProfileTabCandidate]? {
        guard let tabs = tabs(in: spaceID) else { return nil }
        var candidates: [SpaceProfileTabCandidate] = []
        for tab in tabs {
            guard tab.isShortcutLiveInstance else {
                if tab.profileId == nil {
                    candidates.append(.init(tab: tab, desiredProfileID: nil))
                }
                continue
            }
            guard let entry = registry.entry(containing: tab),
                  entry.presentationPage.page.spaceID == spaceID,
                  let pinID = tab.shortcutPinId,
                  entry.pinId == pinID,
                  let pin = pins.shortcutPin(by: pinID),
                  pin.role == .spacePinned,
                  pin.spaceId == spaceID else { return nil }
            if let executionProfileID = pin.executionProfileId {
                guard tab.profileId == executionProfileID else { return nil }
                continue
            }
            guard tab.profileId == sourceProfileID else { return nil }
            candidates.append(.init(
                tab: tab,
                desiredProfileID: targetProfileID
            ))
        }
        return candidates
    }

    private func tabs(in spaceID: UUID) -> [Tab]? {
        var seen: Set<UUID> = []
        for tab in membership.allIdentityWitnesses() {
            guard seen.insert(tab.id).inserted else { return nil }
        }
        seen.removeAll(keepingCapacity: true)
        var result: [Tab] = []
        for tab in membership.allTabs() {
            guard seen.insert(tab.id).inserted else { return nil }
            if tab.spaceId == spaceID {
                result.append(tab)
            }
        }
        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
