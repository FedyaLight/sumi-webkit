import Foundation

@MainActor
final class SidebarRegularTabDragService {
    struct Dependencies {
        private let convertTabToShortcutPinBody: (
            Tab,
            ShortcutPinRole,
            UUID?,
            UUID?,
            UUID?,
            Int,
            Bool,
            UUID?
        ) -> ShortcutPin?

        let resolvedEssentialsProfileId: (DragOperation) -> UUID?
        let folderSpaceId: (UUID) -> UUID?
        let shortcutPin: (UUID) -> ShortcutPin?
        let reorderSpacePinned: (ShortcutPin, UUID, Int) -> Bool
        let withStructuralUpdateTransaction: (@MainActor () -> Bool) -> Bool
        let reorderRegularTab: (Tab, UUID, Int) -> Bool
        let scheduleStructuralPersistence: () -> Void
        let reorderEssential: (ShortcutPin, Int) -> Bool
        let removeFromCurrentContainer: (Tab) -> Void
        let insertRegularTab: (Tab, UUID, Int) -> Void
        let runtimeContext: () -> TabManagerRuntimeContext?

        init(
            convertTabToShortcutPin: @escaping (
                Tab,
                ShortcutPinRole,
                UUID?,
                UUID?,
                UUID?,
                Int,
                Bool,
                UUID?
            ) -> ShortcutPin?,
            resolvedEssentialsProfileId: @escaping (DragOperation) -> UUID?,
            folderSpaceId: @escaping (UUID) -> UUID?,
            shortcutPin: @escaping (UUID) -> ShortcutPin?,
            reorderSpacePinned: @escaping (ShortcutPin, UUID, Int) -> Bool,
            withStructuralUpdateTransaction: @escaping (@MainActor () -> Bool) -> Bool,
            reorderRegularTab: @escaping (Tab, UUID, Int) -> Bool,
            scheduleStructuralPersistence: @escaping () -> Void,
            reorderEssential: @escaping (ShortcutPin, Int) -> Bool,
            removeFromCurrentContainer: @escaping (Tab) -> Void,
            insertRegularTab: @escaping (Tab, UUID, Int) -> Void,
            runtimeContext: @escaping () -> TabManagerRuntimeContext?
        ) {
            self.convertTabToShortcutPinBody = convertTabToShortcutPin
            self.resolvedEssentialsProfileId = resolvedEssentialsProfileId
            self.folderSpaceId = folderSpaceId
            self.shortcutPin = shortcutPin
            self.reorderSpacePinned = reorderSpacePinned
            self.withStructuralUpdateTransaction = withStructuralUpdateTransaction
            self.reorderRegularTab = reorderRegularTab
            self.scheduleStructuralPersistence = scheduleStructuralPersistence
            self.reorderEssential = reorderEssential
            self.removeFromCurrentContainer = removeFromCurrentContainer
            self.insertRegularTab = insertRegularTab
            self.runtimeContext = runtimeContext
        }

        func convertTabToShortcutPin(
            _ tab: Tab,
            role: ShortcutPinRole,
            profileId: UUID?,
            spaceId: UUID?,
            folderId: UUID?,
            at index: Int,
            openTargetFolder: Bool = true,
            preferredWindowId: UUID? = nil
        ) -> ShortcutPin? {
            convertTabToShortcutPinBody(
                tab,
                role,
                profileId,
                spaceId,
                folderId,
                index,
                openTargetFolder,
                preferredWindowId
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func execute(
        _ tab: Tab,
        regularOperation: SidebarRegularTabDragOperationKind,
        dragOperation operation: DragOperation
    ) -> Bool {
        var didMutate = false
        switch regularOperation {
        case .reorder where operation.toContainer == .essentials:
            didMutate = reorderGlobalPinnedTabs(tab, to: operation.toIndex)

        case .reorder(let spaceId) where operation.toContainer == .spacePinned(spaceId):
            didMutate = reorderSpacePinnedTabs(tab, in: spaceId, to: operation.toIndex)

        case .reorder(let spaceId) where operation.toContainer == .spaceRegular(spaceId):
            didMutate = reorderRegularTabs(tab, in: spaceId, to: operation.toIndex)

        case .moveToPinned(let targetSpaceId) where operation.fromContainer == .spaceRegular(operation.scope.spaceId):
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .moveToRegular(let targetSpaceId) where operation.fromContainer == .spacePinned(operation.scope.spaceId):
            didMutate = moveTabIntoRegularSection(tab, spaceId: targetSpaceId, index: operation.toIndex)

        case .moveToEssentials
            where operation.fromContainer == .spaceRegular(operation.scope.spaceId)
                || operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard let profileId = dependencies.resolvedEssentialsProfileId(operation) else { return false }
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .moveToRegular(let spaceId) where operation.fromContainer == .essentials:
            didMutate = moveTabIntoRegularSection(tab, spaceId: spaceId, index: operation.toIndex)

        case .moveToPinned(let spaceId) where operation.fromContainer == .essentials:
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .moveToFolder(let toFolderId) where isFolderContainer(operation.fromContainer):
            guard let spaceId = tab.spaceId else { return false }
            guard case .folder(let fromFolderId) = operation.fromContainer else { return false }
            let targetFolderId = fromFolderId == toFolderId ? fromFolderId : toFolderId
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: targetFolderId,
                at: operation.toIndex,
                openTargetFolder: false,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .moveToEssentials where isFolderContainer(operation.fromContainer):
            guard let profileId = dependencies.resolvedEssentialsProfileId(operation) else { return false }
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .moveToPinned(let spaceId) where isFolderContainer(operation.fromContainer):
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: operation.toIndex,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .moveToRegular(let spaceId) where isFolderContainer(operation.fromContainer):
            didMutate = moveTabIntoRegularSection(tab, spaceId: spaceId, index: operation.toIndex)

        case .moveToFolder(let toFolderId) where operation.fromContainer == .spaceRegular(operation.scope.spaceId):
            guard case .spaceRegular(let spaceId) = operation.fromContainer else { return false }
            guard let targetSpaceId = dependencies.folderSpaceId(toFolderId), targetSpaceId == spaceId else {
                return false
            }
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .moveToFolder(let toFolderId) where operation.fromContainer == .spacePinned(operation.scope.spaceId):
            guard case .spacePinned(let spaceId) = operation.fromContainer else { return false }
            guard let targetSpaceId = dependencies.folderSpaceId(toFolderId), targetSpaceId == spaceId else {
                return false
            }
            didMutate = dependencies.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: toFolderId,
                at: operation.toIndex,
                openTargetFolder: false,
                preferredWindowId: operation.scope.windowId
            ) != nil

        case .unsupported,
             .reorder,
             .moveToPinned,
             .moveToFolder,
             .moveToEssentials,
             .moveToRegular:
            RuntimeDiagnostics.emit("⚠️ Invalid drag operation: \(operation)")
            return false
        }

        if didMutate {
            dissolveActiveSplitIfNeeded(for: tab)
        }
        return didMutate
    }

    @discardableResult
    func reorderSpacePinnedTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        if let shortcutId = tab.shortcutPinId,
           let pin = dependencies.shortcutPin(shortcutId) {
            return dependencies.reorderSpacePinned(pin, spaceId, index)
        }

        return dependencies.convertTabToShortcutPin(
            tab,
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceId,
            folderId: nil,
            at: index
        ) != nil
    }

    @discardableResult
    func reorderRegularTabs(_ tab: Tab, in spaceId: UUID, to index: Int) -> Bool {
        dependencies.withStructuralUpdateTransaction {
            guard dependencies.reorderRegularTab(tab, spaceId, index) else {
                return false
            }
            dependencies.scheduleStructuralPersistence()
            return true
        }
    }

    @discardableResult
    private func reorderGlobalPinnedTabs(_ tab: Tab, to index: Int) -> Bool {
        dependencies.withStructuralUpdateTransaction {
            guard let shortcutId = tab.shortcutPinId,
                  let pin = dependencies.shortcutPin(shortcutId),
                  pin.profileId != nil else {
                return false
            }
            return dependencies.reorderEssential(pin, index)
        }
    }

    private func moveTabIntoRegularSection(_ tab: Tab, spaceId: UUID, index: Int) -> Bool {
        dependencies.removeFromCurrentContainer(tab)
        dependencies.insertRegularTab(tab, spaceId, index)
        dependencies.scheduleStructuralPersistence()
        return true
    }

    private func isFolderContainer(_ container: TabDragManager.DragContainer) -> Bool {
        if case .folder = container {
            return true
        }
        return false
    }

    private func dissolveActiveSplitIfNeeded(for tab: Tab) {
        guard !tab.isShortcutLiveInstance else { return }
        guard let runtimeContext = dependencies.runtimeContext() else { return }

        runtimeContext.forEachWindow { windowId, _ in
            if runtimeContext.visibleSplitTabIds(for: windowId).contains(tab.id) {
                runtimeContext.handleTabClosure(tab.id)
            }
        }
    }
}

extension SidebarRegularTabDragService.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            convertTabToShortcutPin: { [weak tabManager] tab, role, profileId, spaceId, folderId, index, openTargetFolder, preferredWindowId in
                tabManager?.shortcutPinCommandOwner.convertTabToShortcutPin(
                    tab,
                    role: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    at: index,
                    openTargetFolder: openTargetFolder,
                    preferredWindowId: preferredWindowId
                )
            },
            resolvedEssentialsProfileId: { [weak tabManager] operation in
                tabManager?.essentialsShortcutPlacementOwner.resolvedProfileId(for: operation)
            },
            folderSpaceId: { [weak tabManager] folderId in
                tabManager?.folderCollectionStateOwner.spaceId(for: folderId)
            },
            shortcutPin: { [weak tabManager] shortcutId in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutId)
            },
            reorderSpacePinned: { [weak tabManager] pin, spaceId, index in
                tabManager?.shortcutPinCommandOwner.reorderSpacePinned(pin, in: spaceId, to: index) ?? false
            },
            withStructuralUpdateTransaction: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.withStructuralUpdateTransaction(operation)
            },
            reorderRegularTab: { [weak tabManager] tab, spaceId, index in
                tabManager?.regularTabCollectionOwner.reorder(tab, in: spaceId, to: index) ?? false
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
            },
            reorderEssential: { [weak tabManager] pin, index in
                tabManager?.shortcutPinCommandOwner.reorderEssential(pin, to: index) ?? false
            },
            removeFromCurrentContainer: { [weak tabManager] tab in
                tabManager?.shortcutLiveTabOwner.removeFromCurrentContainer(tab)
            },
            insertRegularTab: { [weak tabManager] tab, spaceId, index in
                tabManager?.regularTabCollectionOwner.insert(tab, in: spaceId, at: index)
            },
            runtimeContext: { [weak tabManager] in
                tabManager?.runtimeContext
            }
        )
    }
}
