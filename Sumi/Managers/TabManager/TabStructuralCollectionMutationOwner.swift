import Foundation

@MainActor
final class TabStructuralCollectionMutationOwner {
    struct Dependencies {
        let tabsBySpace: @MainActor () -> [UUID: [Tab]]
        let setTabsBySpace: @MainActor ([UUID: [Tab]]) -> Void
        let foldersBySpace: @MainActor () -> [UUID: [TabFolder]]
        let setFoldersBySpace: @MainActor ([UUID: [TabFolder]]) -> Void
        let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
        let setPinnedByProfile: @MainActor ([UUID: [ShortcutPin]]) -> Void
        let spacePinnedShortcuts: @MainActor () -> [UUID: [ShortcutPin]]
        let setSpacePinnedShortcuts: @MainActor ([UUID: [ShortcutPin]]) -> Void
        let syncShortcutPins: @MainActor ([ShortcutPin]) -> Void
        let markRegularTabsSnapshotDirty: @MainActor (UUID) -> Void
        let markFoldersSnapshotDirty: @MainActor (UUID) -> Void
        let markPinnedSnapshotDirty: @MainActor (UUID) -> Void
        let markSpacePinnedSnapshotDirty: @MainActor (UUID) -> Void
        let recordRegularTabsStructuralChange: @MainActor ([Tab], [Tab]) -> Void
        let recordFoldersStructuralChange: @MainActor ([TabFolder], [TabFolder]) -> Void
        let recordShortcutPinsStructuralChange: @MainActor ([ShortcutPin], [ShortcutPin]) -> Void
        let queueTabLookupEntries: @MainActor ([Tab], [Tab]) -> Void
        let requestStructuralPublish: @MainActor (TabStructureChangeScope) -> Void
        let announceStateChange: @MainActor () -> Void
        let publishTabsBySpaceSnapshot: @MainActor () -> Void
    }

    private let dependencies: Dependencies
    private var transaction: TabStructuralMutationTransaction?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func withReversibleSideEffects(_ operation: () -> Bool) -> Bool {
        precondition(transaction == nil, "Nested structural mutation transaction")
        let folders = dependencies.foldersBySpace()
        transaction = TabStructuralMutationTransaction(
            snapshot: TabStructuralMutationTransaction.Snapshot(
                tabs: dependencies.tabsBySpace(),
                folders: folders,
                pinned: dependencies.pinnedByProfile(),
                spacePinned: dependencies.spacePinnedShortcuts(),
                folderReceipts: folders.values.flatMap { $0 }.map(
                    TabStructuralMutationTransaction.FolderReceipt.init
                )
            )
        )
        let committed = operation()
        guard let transaction else {
            preconditionFailure("Structural mutation transaction disappeared")
        }
        let settlement = transaction.finish(committed: committed)
        self.transaction = nil
        apply(settlement)
        return committed
    }

    func setTabs(_ items: [Tab], for spaceId: UUID) {
        var tabsBySpace = dependencies.tabsBySpace()
        let previousTabs = tabsBySpace[spaceId] ?? []
        let sortedItems = Self.sortedTabs(items)

        willMutate()
        tabsBySpace[spaceId] = sortedItems
        dependencies.setTabsBySpace(tabsBySpace)
        tabsDidChange()
        record(.regularTabs(
            spaceId,
            previous: previousTabs,
            current: sortedItems
        ))
    }

    func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        var foldersBySpace = dependencies.foldersBySpace()
        let previousFolders = foldersBySpace[spaceId] ?? []

        willMutate()
        foldersBySpace[spaceId] = items
        dependencies.setFoldersBySpace(foldersBySpace)
        record(.folders(
            spaceId,
            previous: previousFolders,
            current: items
        ))
    }

    func setPinnedTabs(_ items: [ShortcutPin], for profileId: UUID) {
        var pinnedByProfile = dependencies.pinnedByProfile()
        let previousPins = pinnedByProfile[profileId] ?? []

        willMutate()
        pinnedByProfile[profileId] = items
        dependencies.setPinnedByProfile(pinnedByProfile)
        let spacePinnedShortcuts = dependencies.spacePinnedShortcuts()
        record(.profilePins(
            profileId,
            previous: previousPins,
            current: items,
            allPins:
                Array(pinnedByProfile.values.joined())
                    + Array(spacePinnedShortcuts.values.joined())
        ))
    }

    func setSpacePinnedShortcuts(_ items: [ShortcutPin], for spaceId: UUID) {
        var spacePinnedShortcuts = dependencies.spacePinnedShortcuts()
        let previousPins = spacePinnedShortcuts[spaceId] ?? []

        willMutate()
        spacePinnedShortcuts[spaceId] = items
        dependencies.setSpacePinnedShortcuts(spacePinnedShortcuts)
        let pinnedByProfile = dependencies.pinnedByProfile()
        record(.spacePins(
            spaceId,
            previous: previousPins,
            current: items,
            allPins:
                Array(pinnedByProfile.values.joined())
                    + Array(spacePinnedShortcuts.values.joined())
        ))
    }

    private func willMutate() {
        if transaction == nil { dependencies.announceStateChange() }
    }

    private func tabsDidChange() {
        if let transaction {
            transaction.recordTabsReplacement()
        } else {
            dependencies.publishTabsBySpaceSnapshot()
        }
    }

    private func record(_ effect: TabStructuralMutationTransaction.Effect) {
        if let transaction {
            transaction.record(effect)
        } else {
            apply(effect)
        }
    }

    private func apply(_ settlement: TabStructuralMutationTransaction.Settlement) {
        switch settlement {
        case .committed(let effects, let announce, let publishTabs):
            effects.forEach(apply)
            if announce { dependencies.announceStateChange() }
            if publishTabs { dependencies.publishTabsBySpaceSnapshot() }
        case .rolledBack(let snapshot):
            snapshot.folderReceipts.forEach { $0.restore() }
            dependencies.setTabsBySpace(snapshot.tabs)
            dependencies.setFoldersBySpace(snapshot.folders)
            dependencies.setPinnedByProfile(snapshot.pinned)
            dependencies.setSpacePinnedShortcuts(snapshot.spacePinned)
        }
    }

    private func apply(_ effect: TabStructuralMutationTransaction.Effect) {
        switch effect {
        case .regularTabs(let spaceID, let previous, let current):
            dependencies.markRegularTabsSnapshotDirty(spaceID)
            dependencies.recordRegularTabsStructuralChange(previous, current)
            dependencies.queueTabLookupEntries(previous, current)
            dependencies.requestStructuralPublish(.space(spaceID))
        case .folders(let spaceID, let previous, let current):
            dependencies.markFoldersSnapshotDirty(spaceID)
            dependencies.recordFoldersStructuralChange(previous, current)
            dependencies.requestStructuralPublish(.space(spaceID))
        case .profilePins(let profileID, let previous, let current, let allPins):
            dependencies.syncShortcutPins(allPins)
            dependencies.markPinnedSnapshotDirty(profileID)
            dependencies.recordShortcutPinsStructuralChange(previous, current)
            dependencies.requestStructuralPublish(.profile(profileID))
        case .spacePins(let spaceID, let previous, let current, let allPins):
            dependencies.syncShortcutPins(allPins)
            dependencies.markSpacePinnedSnapshotDirty(spaceID)
            dependencies.recordShortcutPinsStructuralChange(previous, current)
            dependencies.requestStructuralPublish(.space(spaceID))
        }
    }

    private static func sortedTabs(_ tabs: [Tab]) -> [Tab] {
        tabs.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

extension TabStructuralCollectionMutationOwner.Dependencies {
    static func live(tabManager: TabManager) -> Self {
        Self(
            tabsBySpace: { [weak tabManager] in
                tabManager?.regularTabCollectionStateOwner.tabsBySpace ?? [:]
            },
            setTabsBySpace: { [weak tabManager] tabsBySpace in
                tabManager?.regularTabCollectionStateOwner.replaceTabsBySpace(
                    tabsBySpace,
                    publish: false
                )
            },
            foldersBySpace: { [weak tabManager] in
                tabManager?.folderCollectionStateOwner.foldersBySpaceSnapshot() ?? [:]
            },
            setFoldersBySpace: { [weak tabManager] foldersBySpace in
                tabManager?.folderCollectionStateOwner.replaceFoldersBySpace(foldersBySpace)
            },
            pinnedByProfile: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot() ?? [:]
            },
            setPinnedByProfile: { [weak tabManager] pinnedByProfile in
                tabManager?.shortcutPinCollectionStateOwner.replacePinnedByProfile(pinnedByProfile)
            },
            spacePinnedShortcuts: { [weak tabManager] in
                tabManager?.shortcutPinCollectionStateOwner.spacePinnedShortcutsSnapshot() ?? [:]
            },
            setSpacePinnedShortcuts: { [weak tabManager] spacePinnedShortcuts in
                tabManager?.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts(spacePinnedShortcuts)
            },
            syncShortcutPins: { [weak tabManager] shortcutPins in
                tabManager?.faviconService.syncShortcutPins(shortcutPins)
            },
            markRegularTabsSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markRegularTabsSnapshotDirty(for: spaceId)
            },
            markFoldersSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markFoldersSnapshotDirty(for: spaceId)
            },
            markPinnedSnapshotDirty: { [weak tabManager] profileId in
                tabManager?.structuralPersistence.markPinnedSnapshotDirty(for: profileId)
            },
            markSpacePinnedSnapshotDirty: { [weak tabManager] spaceId in
                tabManager?.structuralPersistence.markSpacePinnedSnapshotDirty(for: spaceId)
            },
            recordRegularTabsStructuralChange: { [weak tabManager] previous, current in
                tabManager?.structuralPersistence.recordRegularTabsStructuralChange(previous: previous, current: current)
            },
            recordFoldersStructuralChange: { [weak tabManager] previous, current in
                tabManager?.structuralPersistence.recordFoldersStructuralChange(previous: previous, current: current)
            },
            recordShortcutPinsStructuralChange: { [weak tabManager] previous, current in
                tabManager?.structuralPersistence.recordShortcutPinsStructuralChange(previous: previous, current: current)
            },
            queueTabLookupEntries: { [weak tabManager] previous, current in
                tabManager?.structuralLookupCoordinator.queueEntries(removing: previous, with: current)
            },
            requestStructuralPublish: { [weak tabManager] scope in
                tabManager?.structuralLookupCoordinator.requestPublish(scope: scope)
            },
            announceStateChange: { [weak tabManager] in
                tabManager?.objectWillChange.send()
            },
            publishTabsBySpaceSnapshot: { [weak tabManager] in
                tabManager?.regularTabCollectionStateOwner
                    .publishTabsBySpaceSnapshot()
            }
        )
    }
}
