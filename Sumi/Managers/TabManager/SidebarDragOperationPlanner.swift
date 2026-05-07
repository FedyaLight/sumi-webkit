import Foundation

@MainActor
struct SidebarDragOperationPlan {
    let kind: SidebarDragOperationKind
}

@MainActor
enum SidebarDragOperationKind {
    case folderHeaderReorder(folder: TabFolder, spaceId: UUID)
    case folderHeaderUnsupported(folder: TabFolder)
    case launcher(pin: ShortcutPin, operation: SidebarLauncherDragOperationKind)
    case regularTab(tab: Tab, operation: SidebarRegularTabDragOperationKind)
    case unsupported
}

enum SidebarLauncherDragOperationKind {
    case reorder
    case moveToPinned
    case moveToFolder
    case moveToEssentials
    case moveToRegular
    case unsupported
}

enum SidebarRegularTabDragOperationKind {
    case reorder(spaceId: UUID)
    case moveToPinned(spaceId: UUID)
    case moveToFolder(folderId: UUID)
    case moveToEssentials
    case moveToRegular(spaceId: UUID)
    case unsupported
}

@MainActor
enum SidebarDragOperationPlanner {
    typealias ShortcutPinResolver = (UUID) -> ShortcutPin?

    static func plan(
        operation: DragOperation,
        shortcutPin: ShortcutPinResolver
    ) -> SidebarDragOperationPlan {
        if let folder = operation.folder {
            return SidebarDragOperationPlan(
                kind: folderOperation(folder, operation: operation)
            )
        }

        if let pin = operation.pin {
            return SidebarDragOperationPlan(
                kind: .launcher(
                    pin: pin,
                    operation: launcherOperation(for: operation)
                )
            )
        }

        guard let tab = operation.tab else {
            return SidebarDragOperationPlan(kind: .unsupported)
        }

        if let shortcutId = tab.shortcutPinId,
           let pin = shortcutPin(shortcutId) {
            return SidebarDragOperationPlan(
                kind: .launcher(
                    pin: pin,
                    operation: launcherOperation(for: operation)
                )
            )
        }

        return SidebarDragOperationPlan(
            kind: .regularTab(
                tab: tab,
                operation: regularTabOperation(for: operation)
            )
        )
    }

    private static func folderOperation(
        _ folder: TabFolder,
        operation: DragOperation
    ) -> SidebarDragOperationKind {
        switch (operation.fromContainer, operation.toContainer) {
        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)) where fromSpaceId == toSpaceId:
            return .folderHeaderReorder(folder: folder, spaceId: toSpaceId)
        default:
            return .folderHeaderUnsupported(folder: folder)
        }
    }

    private static func launcherOperation(
        for operation: DragOperation
    ) -> SidebarLauncherDragOperationKind {
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials),
             (.spacePinned, .spacePinned):
            return .reorder

        case (.folder(let fromFolderId), .folder(let toFolderId)) where fromFolderId == toFolderId:
            return .reorder

        case (.essentials, .spacePinned),
             (.folder, .spacePinned):
            return .moveToPinned

        case (.essentials, .folder),
             (.spacePinned, .folder),
             (.folder, .folder):
            return .moveToFolder

        case (.spacePinned, .essentials),
             (.folder, .essentials):
            return .moveToEssentials

        case (.essentials, .spaceRegular),
             (.spacePinned, .spaceRegular),
             (.folder, .spaceRegular):
            return .moveToRegular

        case (.spaceRegular, _),
             (.none, _),
             (_, .none):
            return .unsupported
        }
    }

    private static func regularTabOperation(
        for operation: DragOperation
    ) -> SidebarRegularTabDragOperationKind {
        switch (operation.fromContainer, operation.toContainer) {
        case (.essentials, .essentials):
            return .reorder(spaceId: operation.scope.spaceId)

        case (.spacePinned(let fromSpaceId), .spacePinned(let toSpaceId)) where fromSpaceId == toSpaceId:
            return .reorder(spaceId: toSpaceId)

        case (.spaceRegular(let fromSpaceId), .spaceRegular(let toSpaceId)) where fromSpaceId == toSpaceId:
            return .reorder(spaceId: toSpaceId)

        case (.spaceRegular, .spacePinned(let targetSpaceId)),
             (.essentials, .spacePinned(let targetSpaceId)),
             (.folder, .spacePinned(let targetSpaceId)):
            return .moveToPinned(spaceId: targetSpaceId)

        case (.spaceRegular, .folder(let folderId)),
             (.spacePinned, .folder(let folderId)),
             (.folder, .folder(let folderId)):
            return .moveToFolder(folderId: folderId)

        case (.spaceRegular, .essentials),
             (.spacePinned, .essentials),
             (.folder, .essentials):
            return .moveToEssentials

        case (.spacePinned, .spaceRegular(let targetSpaceId)),
             (.essentials, .spaceRegular(let targetSpaceId)),
             (.folder, .spaceRegular(let targetSpaceId)):
            return .moveToRegular(spaceId: targetSpaceId)

        case (.essentials, .folder),
             (.spacePinned, .spacePinned),
             (.spaceRegular, .spaceRegular),
             (.none, _),
             (_, .none):
            return .unsupported
        }
    }
}
