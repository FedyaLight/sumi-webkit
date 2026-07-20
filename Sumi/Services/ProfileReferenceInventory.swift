import Foundation
import SumiDomain

/// Exact profile UUIDs referenced by one structural browser state.
@MainActor
struct ProfileReferenceInventory {
    let profileIDs: Set<UUID>

    func contains(_ profileID: UUID) -> Bool {
        profileIDs.contains(profileID)
    }

    init(runtimeState: SumiImportRuntimeState) {
        self.init(
            spaces: runtimeState.spaces,
            tabsBySpace: runtimeState.tabsBySpace,
            pinnedByProfile: runtimeState.pinnedByProfile,
            spacePinnedShortcuts: runtimeState.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: runtimeState.pendingPinnedWithoutProfile,
            splitGroups: runtimeState.splitGroups,
            currentSpace: runtimeState.currentSpace,
            currentTab: runtimeState.currentTab,
            additionalProfileID: runtimeState.currentProfile?.id
        )
    }

    init(
        spaces: [Space],
        tabsBySpace: [UUID: [Tab]],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        pendingPinnedWithoutProfile: [ShortcutPin],
        splitGroups: [SplitGroup],
        currentSpace: Space?,
        currentTab: Tab?,
        additionalProfileID: UUID? = nil
    ) {
        var profileIDs = Set(spaces.compactMap(\.profileId))
        profileIDs.formUnion(tabsBySpace.values.joined().compactMap(\.profileId))
        Self.insertShortcutReferences(from: pinnedByProfile, into: &profileIDs)
        Self.insertShortcutReferences(
            from: spacePinnedShortcuts.values.joined(),
            into: &profileIDs
        )
        Self.insertShortcutReferences(from: pendingPinnedWithoutProfile, into: &profileIDs)
        Self.insertSplitReferences(from: splitGroups, into: &profileIDs)

        profileIDs.insertIfPresent(additionalProfileID)
        profileIDs.insertIfPresent(currentSpace?.profileId)
        profileIDs.insertIfPresent(currentTab?.profileId)
        self.profileIDs = profileIDs
    }

    init(tabSnapshot: TabPersistenceSnapshot) {
        var profileIDs = Set<UUID>()
        profileIDs.formUnion(tabSnapshot.spaces.compactMap(\.profileId))
        for tab in tabSnapshot.tabs {
            profileIDs.insertIfPresent(tab.profileId)
            profileIDs.insertIfPresent(tab.executionProfileId)
        }
        Self.insertSplitReferences(
            from: tabSnapshot.splitGroups,
            into: &profileIDs
        )
        self.profileIDs = profileIDs
    }

    init(
        shortcutPins: ShortcutPinCollectionStateOwner,
        splitGroups: [SplitGroup]
    ) {
        var profileIDs = Set<UUID>()
        Self.insertShortcutReferences(
            from: shortcutPins.pinnedByProfileSnapshot(),
            into: &profileIDs
        )
        Self.insertShortcutReferences(
            from: shortcutPins.spacePinnedShortcutsSnapshot().values.joined(),
            into: &profileIDs
        )
        Self.insertShortcutReferences(
            from: shortcutPins.pendingPinnedWithoutProfileSnapshot(),
            into: &profileIDs
        )
        Self.insertSplitReferences(from: splitGroups, into: &profileIDs)
        self.profileIDs = profileIDs
    }

    init(windowSnapshot: WindowSessionSnapshot) {
        profileIDs = Set(optional: windowSnapshot.currentProfileId)
    }

    init(lastSessionWindowSnapshot: LastSessionWindowSnapshot) {
        self.init(windowSnapshot: lastSessionWindowSnapshot.session)
    }

    init(windowState: BrowserWindowState) {
        profileIDs = Set(optional: windowState.currentProfileId)
    }

    init(glanceSession: GlanceSession) {
        profileIDs = Set(optional: glanceSession.previewTab.profileId)
    }

    init(shortcutPin: ShortcutPin) {
        var profileIDs = Set<UUID>()
        profileIDs.insertIfPresent(shortcutPin.profileId)
        profileIDs.insertIfPresent(shortcutPin.executionProfileId)
        self.profileIDs = profileIDs
    }

    init(recentlyClosedItem: RecentlyClosedItem) {
        var profileIDs = Set<UUID>()
        switch recentlyClosedItem {
        case .tab(let tab):
            profileIDs.insertIfPresent(tab.profileId)
        case .shortcutLiveInstance(let shortcut):
            profileIDs.insertIfPresent(shortcut.pin.profileId)
            profileIDs.insertIfPresent(shortcut.pin.executionProfileId)
        case .shortcutLauncher(let shortcut):
            profileIDs.insertIfPresent(shortcut.pin.profileId)
            profileIDs.insertIfPresent(shortcut.pin.executionProfileId)
        case .window(let window):
            profileIDs.formUnion(
                ProfileReferenceInventory(windowSnapshot: window.session)
                    .profileIDs
            )
        }
        self.profileIDs = profileIDs
    }

    private static func insertShortcutReferences(
        from pinsByProfile: [UUID: [ShortcutPin]],
        into profileIDs: inout Set<UUID>
    ) {
        profileIDs.formUnion(pinsByProfile.keys)
        insertShortcutReferences(
            from: pinsByProfile.values.joined(),
            into: &profileIDs
        )
    }

    private static func insertShortcutReferences<S: Sequence>(
        from pins: S,
        into profileIDs: inout Set<UUID>
    ) where S.Element == ShortcutPin {
        for pin in pins {
            profileIDs.insertIfPresent(pin.profileId)
            profileIDs.insertIfPresent(pin.executionProfileId)
        }
    }

    private static func insertSplitReferences(
        from groups: [SplitGroup],
        into profileIDs: inout Set<UUID>
    ) {
        for group in groups {
            switch group.container {
            case .regularTabs:
                break
            case .essentialSidebar(let profileID, _),
                 .shortcutSidebar(_, let profileID, _, _):
                profileIDs.insertIfPresent(profileID)
            }
        }
    }
}

private extension Set where Element == UUID {
    init(optional element: UUID?) {
        self = element.map { [$0] } ?? []
    }

    mutating func insertIfPresent(_ element: UUID?) {
        guard let element else { return }
        insert(element)
    }
}
