import Foundation
import SumiDomain

@MainActor
final class SidebarSplitGroupDuplicationService {
    private let regular: RegularSplitGroupDuplicationService
    private let saved: SavedSplitGroupDuplicationService

    init(
        regular: RegularSplitGroupDuplicationService,
        saved: SavedSplitGroupDuplicationService
    ) {
        self.regular = regular
        self.saved = saved
    }

    func duplicate(_ group: SplitGroup, in windowState: BrowserWindowState) {
        if group.container.isShortcutSidebar {
            _ = saved.duplicate(group)
        } else {
            _ = regular.duplicate(group, in: windowState)
        }
    }
}

@MainActor
final class RegularSplitGroupDuplicationService {
    private let groups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let regularTabs: RegularTabCollectionOwner
    private let duplication: SplitTabDuplicationService

    init(
        groups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        regularTabs: RegularTabCollectionOwner,
        duplication: SplitTabDuplicationService
    ) {
        self.groups = groups
        self.mutations = mutations
        self.regularTabs = regularTabs
        self.duplication = duplication
    }

    func duplicate(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard groups.group(id: group.id) == group,
              case .regularTabs(let spaceID?) = group.container else {
            return false
        }
        let sourceTabs = group.memberIDs.compactMap { memberID -> Tab? in
            guard case .regularTab(let tabID) = memberID else { return nil }
            return regularTabs.tab(for: tabID)
        }
        guard sourceTabs.count == group.memberIDs.count else { return false }
        let insertionIndex = sourceTabs.compactMap { source in
            regularTabs.tabs(in: spaceID).firstIndex { $0 === source }
        }.max().map { $0 + 1 } ?? regularTabs.tabs(in: spaceID).count

        let copies = sourceTabs.map {
            duplication.duplicate($0, into: spaceID, in: windowState)
        }
        guard let duplicate = SplitGroup(
            layoutKind: group.layoutKind,
            layoutTree: replacingTree(group.layoutTree, sourceTabs, copies),
            container: group.container,
            title: SplitGroupDuplicateTitleResolver.title(
                copiedFrom: group,
                existingGroups: groups.groups
            ),
            iconAsset: group.iconAsset
        ), mutations.insert(duplicate, persist: false) else {
            copies.forEach(duplication.discard)
            return false
        }
        let copiedIDs = Set(copies.map(\.id))
        let currentIDs = regularTabs.tabs(in: spaceID).map(\.id)
        let expectedIDs = copies.map(\.id)
        let isAlreadyAdjacent = insertionIndex + expectedIDs.count
            <= currentIDs.count
            && Array(
                currentIDs[
                    insertionIndex..<(insertionIndex + expectedIDs.count)
                ]
            ) == expectedIDs
        guard isAlreadyAdjacent || regularTabs.reorderSplitGroup(
            memberIDs: copiedIDs,
            in: spaceID,
            toRawIndex: insertionIndex
        ) else {
            _ = mutations.remove(duplicate, persist: false)
            copies.forEach(duplication.discard)
            return false
        }
        return true
    }

    private func replacingTree(
        _ source: SplitLayoutTree,
        _ sourceTabs: [Tab],
        _ copies: [Tab]
    ) -> SplitLayoutTree {
        zip(sourceTabs, copies).reduce(source) { tree, pair in
            tree.replacingMember(
                .regularTab(pair.0.id),
                with: .regularTab(pair.1.id)
            ) ?? tree
        }
    }
}

@MainActor
final class SavedSplitGroupDuplicationService {
    private let groups: SplitGroupStore
    private let mutations: SplitGroupMutationService
    private let pins: ShortcutPinCollectionStateOwner
    private let pinStore: ShortcutPinStoreOwner

    init(
        groups: SplitGroupStore,
        mutations: SplitGroupMutationService,
        pins: ShortcutPinCollectionStateOwner,
        pinStore: ShortcutPinStoreOwner
    ) {
        self.groups = groups
        self.mutations = mutations
        self.pins = pins
        self.pinStore = pinStore
    }

    func duplicate(_ group: SplitGroup) -> Bool {
        guard groups.group(id: group.id) == group,
              group.container.isShortcutSidebar else { return false }
        let sourcePins = group.memberIDs.compactMap { memberID -> ShortcutPin? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pins.shortcutPin(by: pinID)
        }
        guard sourcePins.count == group.memberIDs.count else { return false }
        let copies = sourcePins.map { pin in
            ShortcutPin(
                id: UUID(),
                role: pin.role,
                profileId: pin.profileId,
                executionProfileId: pin.executionProfileId,
                spaceId: pin.spaceId,
                index: .max,
                folderId: pin.folderId,
                launchURL: pin.launchURL,
                title: pin.title,
                iconAsset: pin.iconAsset,
                titleIsCustom: pin.titleIsCustom
            )
        }
        var tree = group.layoutTree
        for (source, copy) in zip(sourcePins, copies) {
            guard let replacement = tree.replacingMember(
                .shortcutPin(source.id),
                with: .shortcutPin(copy.id)
            ) else { return false }
            tree = replacement
        }
        guard let duplicate = SplitGroup(
            layoutKind: group.layoutKind,
            layoutTree: tree,
            container: duplicatedContainer(group.container),
            title: SplitGroupDuplicateTitleResolver.title(
                copiedFrom: group,
                existingGroups: groups.groups
            ),
            iconAsset: group.iconAsset
        ) else { return false }
        let expected = groups.groups
        return mutations.replaceAllAtomically(
            expected: expected,
            with: expected + [duplicate],
            applying: { [pinStore] in
                for copy in copies {
                    guard pinStore.insert(
                        copy,
                        at: copy.index,
                        openTargetFolder: false,
                        sidebarVisualMembership: .splitMember
                    ) != nil else { return false }
                }
                return true
            }
        )
    }

    private func duplicatedContainer(
        _ container: SplitGroupContainer
    ) -> SplitGroupContainer {
        switch container {
        case .regularTabs:
            return container
        case .essentialSidebar(let profileID, let index):
            return .essentialSidebar(
                profileId: profileID,
                index: (index ?? 0) + 1
            )
        case .shortcutSidebar(
            let spaceID,
            let profileID,
            let folderID,
            let index
        ):
            return .shortcutSidebar(
                spaceId: spaceID,
                profileId: profileID,
                folderId: folderID,
                index: (index ?? 0) + 1
            )
        }
    }
}

enum SplitGroupDuplicateTitleResolver {
    static func title(
        copiedFrom group: SplitGroup,
        existingGroups: [SplitGroup]
    ) -> String? {
        guard let source = group.title?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !source.isEmpty else { return nil }
        let existing = Set(existingGroups.compactMap {
            $0.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        })
        var suffix = 2
        while existing.contains("\(source) (\(suffix))") { suffix += 1 }
        return "\(source) (\(suffix))"
    }
}
