import AppKit
import Foundation
import SumiDomain

/// Applies a last-session merge plan as one structural transaction. Mutable
/// browser state is deliberately confined here; planning stays value-only.
@MainActor
final class TabLastSessionMergeMaterializer {
    private struct RegularTabKey: Hashable {
        let spaceId: UUID
        let tabId: UUID
    }

    private struct FolderKey: Hashable {
        let spaceId: UUID
        let folderId: UUID
    }

    private let planner: TabLastSessionMergePlanner
    private let state: TabStateStore
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let membership: TabCollectionMembershipOwner
    private let normalizeSpacePinnedShortcuts: ([ShortcutPin]) -> [ShortcutPin]
    private let tabFactory: TabFactory
    private let lazyRestore: TabLazyRestoreCoordinator
    private let structuralLookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService
    private let announceStateChange: () -> Void

    init(
        planner: TabLastSessionMergePlanner = TabLastSessionMergePlanner(),
        state: TabStateStore,
        structuralMutations: TabStructuralCollectionMutationOwner,
        membership: TabCollectionMembershipOwner,
        normalizeSpacePinnedShortcuts: @escaping ([ShortcutPin]) -> [ShortcutPin],
        tabFactory: TabFactory,
        lazyRestore: TabLazyRestoreCoordinator,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService,
        announceStateChange: @escaping () -> Void
    ) {
        self.planner = planner
        self.state = state
        self.structuralMutations = structuralMutations
        self.membership = membership
        self.normalizeSpacePinnedShortcuts = normalizeSpacePinnedShortcuts
        self.tabFactory = tabFactory
        self.lazyRestore = lazyRestore
        self.structuralLookup = structuralLookup
        self.persistence = persistence
        self.announceStateChange = announceStateChange
    }

    func merge(_ snapshot: TabPersistenceSnapshot) {
        let plan = planner.makePlan(snapshot: snapshot, live: liveState())
        let existingSpaces = Dictionary(
            uniqueKeysWithValues: state.spaces.spaces.map { ($0.id, $0) }
        )
        let existingFolders = existingFolders()
        let existingTabs = existingRegularTabs()

        structuralLookup.withTransaction {
            let spacesById = materializeSpaces(plan, existing: existingSpaces)
            materializeFolders(plan, existing: existingFolders)
            materializeShortcuts(plan)
            let regularTabsById = materializeRegularTabs(plan, existing: existingTabs)
            materializeSelection(
                plan,
                spacesById: spacesById,
                regularTabsById: regularTabsById
            )
            lazyRestore.reset(restoredTabIDs: plan.lazyRestoredTabIds)
            persistence.scheduleStructuralPersistenceFromMain()
        }
    }
}

private extension TabLastSessionMergeMaterializer {
    func liveState() -> TabLastSessionLiveState {
        let orderedSpaces = state.spaces.spaces
        let foldersBySpace = state.folders.foldersBySpaceSnapshot().mapValues { folders in
            folders.map {
                TabLastSessionLiveState.FolderReference(
                    id: $0.id,
                    spaceId: $0.spaceId,
                    parentFolderId: $0.parentFolderId,
                    index: $0.index
                )
            }
        }
        let essentialPins = state.shortcutPins.pinnedByProfileSnapshot().mapValues { pins in
            pins.map(shortcutDescriptor)
        }
        let spacePins = state.shortcutPins.spacePinnedShortcutsSnapshot().mapValues { pins in
            pins.map(shortcutDescriptor)
        }
        let regularTabs = state.regularTabs.tabsBySpaceSnapshot().mapValues { tabs in
            tabs.map {
                TabLastSessionLiveState.RegularTabReference(id: $0.id, index: $0.index)
            }
        }
        return TabLastSessionLiveState(
            spaces: orderedSpaces.map { .init(id: $0.id, profileId: $0.profileId) },
            currentSpaceId: state.spaces.currentSpaceId,
            foldersBySpace: foldersBySpace,
            essentialPinsByProfile: essentialPins,
            spacePinnedShortcuts: spacePins,
            regularTabsBySpace: regularTabs
        )
    }

    func shortcutDescriptor(_ pin: ShortcutPin) -> TabLastSessionShortcutDescriptor {
        TabLastSessionShortcutDescriptor(
            id: pin.id,
            kind: pin.role == .essential ? .essential : .spacePinned,
            profileId: pin.profileId,
            executionProfileId: pin.executionProfileId,
            spaceId: pin.spaceId,
            index: pin.index,
            folderId: pin.folderId,
            launchURL: pin.launchURL,
            title: pin.title,
            iconAsset: pin.iconAsset
        )
    }

    private func existingRegularTabs() -> [RegularTabKey: Tab] {
        var tabsByKey: [RegularTabKey: Tab] = [:]
        for (spaceId, tabs) in state.regularTabs.tabsBySpaceSnapshot() {
            for tab in tabs {
                tabsByKey[RegularTabKey(spaceId: spaceId, tabId: tab.id)] = tab
            }
        }
        return tabsByKey
    }

    private func existingFolders() -> [FolderKey: TabFolder] {
        var foldersByKey: [FolderKey: TabFolder] = [:]
        for (spaceId, folders) in state.folders.foldersBySpaceSnapshot() {
            for folder in folders {
                foldersByKey[FolderKey(spaceId: spaceId, folderId: folder.id)] = folder
            }
        }
        return foldersByKey
    }

    func materializeSpaces(
        _ plan: TabLastSessionMergePlan,
        existing: [UUID: Space]
    ) -> [UUID: Space] {
        var spacesById = existing
        let orderedSpaces = plan.orderedSpaceIds.compactMap { spaceId -> Space? in
            guard let restored = plan.restoredSpacesById[spaceId] else {
                return existing[spaceId]
            }
            let theme = restored.workspaceThemeData.flatMap(WorkspaceTheme.decode) ?? .default
            if let space = existing[spaceId] {
                space.name = restored.name
                space.icon = SumiPersistentGlyph.normalizedSpaceIconValue(restored.icon)
                space.workspaceTheme = theme
                space.profileId = restored.profileId
                return space
            }
            let space = Space(
                id: restored.id,
                name: restored.name,
                icon: restored.icon,
                workspaceTheme: theme,
                profileId: restored.profileId
            )
            spacesById[space.id] = space
            return space
        }
        announceStateChange()
        state.spaces.replaceSpaces(orderedSpaces)
        persistence.markAllSpacesStructurallyDirty()
        return spacesById
    }

    private func materializeFolders(
        _ plan: TabLastSessionMergePlan,
        existing: [FolderKey: TabFolder]
    ) {
        for spaceId in plan.orderedSpaceIds {
            let folders = (plan.foldersBySpace[spaceId] ?? []).map { placement -> TabFolder in
                if let folder = existing[
                    FolderKey(spaceId: placement.spaceId, folderId: placement.id)
                ] {
                    if let restored = placement.restoredValues {
                        apply(restored, to: folder)
                    }
                    return folder
                }
                guard let restored = placement.restoredValues else {
                    preconditionFailure("Last-session plan referenced a missing live folder")
                }
                let folder = TabFolder(
                    id: restored.id,
                    name: restored.name,
                    spaceId: restored.spaceId,
                    parentFolderId: restored.parentFolderId,
                    icon: restored.icon,
                    color: NSColor(hex: restored.color) ?? .controlAccentColor,
                    index: restored.index
                )
                folder.isOpen = restored.isOpen
                return folder
            }
            structuralMutations.setFolders(folders, for: spaceId)
        }
    }

    func apply(_ restored: TabPersistenceFolder, to folder: TabFolder) {
        folder.name = restored.name
        folder.icon = SumiZenFolderIconCatalog.normalizedFolderIconValue(restored.icon)
        folder.color = NSColor(hex: restored.color) ?? .controlAccentColor
        folder.spaceId = restored.spaceId
        folder.parentFolderId = restored.parentFolderId
        folder.isOpen = restored.isOpen
        folder.index = restored.index
    }

    func materializeShortcuts(_ plan: TabLastSessionMergePlan) {
        for profileId in plan.essentialPinsByProfile.keys.sorted(by: uuidOrder) {
            let pins = (plan.essentialPinsByProfile[profileId] ?? []).enumerated().map {
                makeShortcut(from: $0.element, index: $0.offset)
            }
            structuralMutations.setPinnedTabs(pins, for: profileId)
        }
        for spaceId in plan.orderedSpaceIds {
            let pins = (plan.spacePinnedShortcuts[spaceId] ?? []).map {
                makeShortcut(from: $0, index: $0.index)
            }
            structuralMutations.setSpacePinnedShortcuts(
                normalizeSpacePinnedShortcuts(pins),
                for: spaceId
            )
        }
    }

    func makeShortcut(
        from descriptor: TabLastSessionShortcutDescriptor,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: descriptor.id,
            role: descriptor.kind == .essential ? .essential : .spacePinned,
            profileId: descriptor.profileId,
            executionProfileId: descriptor.executionProfileId,
            spaceId: descriptor.spaceId,
            index: index,
            folderId: descriptor.folderId,
            launchURL: descriptor.launchURL,
            title: descriptor.title,
            iconAsset: descriptor.iconAsset
        )
    }

    private func materializeRegularTabs(
        _ plan: TabLastSessionMergePlan,
        existing: [RegularTabKey: Tab]
    ) -> [UUID: Tab] {
        var tabsById: [UUID: Tab] = [:]
        for spaceId in plan.orderedSpaceIds {
            let tabs = (plan.regularTabsBySpace[spaceId] ?? []).enumerated().map {
                offset, placement -> Tab in
                let tab: Tab
                switch placement {
                case .existing(let id, let sourceSpaceId, _):
                    guard let liveTab = existing[
                        RegularTabKey(spaceId: sourceSpaceId, tabId: id)
                    ] else {
                        preconditionFailure("Last-session plan referenced a missing live tab")
                    }
                    tab = liveTab
                case .restored(let restored):
                    let restoredTab = tabFactory.makeTab(
                        id: restored.id,
                        url: restored.url,
                        name: restored.name,
                        favicon: "globe",
                        spaceId: restored.spaceId,
                        index: offset,
                        loadsCachedFaviconOnInit: false
                    )
                    restoredTab.profileId = restored.profileId
                    restoredTab.canGoBack = restored.canGoBack
                    restoredTab.canGoForward = restored.canGoForward
                    membership.attach(restoredTab)
                    tab = restoredTab
                }
                tab.spaceId = spaceId
                tab.index = offset
                tabsById[tab.id] = tab
                return tab
            }
            structuralMutations.setTabs(tabs, for: spaceId)
        }
        return tabsById
    }

    func materializeSelection(
        _ plan: TabLastSessionMergePlan,
        spacesById: [UUID: Space],
        regularTabsById: [UUID: Tab]
    ) {
        switch plan.spaceSelection {
        case .keepCurrent:
            break
        case .select(let spaceId):
            state.spaces.replaceCurrentSpace(spaceId.flatMap { spacesById[$0] })
        }
        if let tabId = plan.requestedCurrentTabId,
           let tab = regularTabsById[tabId] {
            state.selection.replaceCurrentTab(tab)
        }
    }

    func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
