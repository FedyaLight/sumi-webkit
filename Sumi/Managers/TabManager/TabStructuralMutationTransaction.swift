import AppKit
import Foundation

/// Pure reversible state for one synchronous structural collection batch.
/// It stores exact source values and typed effects, never executable work.
@MainActor
final class TabStructuralMutationTransaction {
    struct FolderReceipt {
        let folder: TabFolder
        let name: String
        let spaceID: UUID
        let parentFolderID: UUID?
        let isOpen: Bool
        let icon: String
        let index: Int
        let color: NSColor

        @MainActor
        init(_ folder: TabFolder) {
            self.folder = folder
            name = folder.name
            spaceID = folder.spaceId
            parentFolderID = folder.parentFolderId
            isOpen = folder.isOpen
            icon = folder.icon
            index = folder.index
            color = folder.color
        }

        @MainActor
        func restore() {
            folder.name = name
            folder.spaceId = spaceID
            folder.parentFolderId = parentFolderID
            folder.isOpen = isOpen
            folder.icon = icon
            folder.index = index
            folder.color = color
        }
    }

    struct Snapshot {
        let tabs: [UUID: [Tab]]
        let folders: [UUID: [TabFolder]]
        let pinned: [UUID: [ShortcutPin]]
        let spacePinned: [UUID: [ShortcutPin]]
        let folderReceipts: [FolderReceipt]
    }

    enum Effect {
        case regularTabs(UUID, previous: [Tab], current: [Tab])
        case folders(UUID, previous: [TabFolder], current: [TabFolder])
        case profilePins(
            UUID,
            previous: [ShortcutPin],
            current: [ShortcutPin],
            allPins: [ShortcutPin]
        )
        case spacePins(
            UUID,
            previous: [ShortcutPin],
            current: [ShortcutPin],
            allPins: [ShortcutPin]
        )
    }

    enum Settlement {
        case committed(
            effects: [Effect],
            announce: Bool,
            publishTabs: Bool
        )
        case rolledBack(Snapshot)
    }

    private let snapshot: Snapshot
    private var effects: [Effect] = []
    private var didMutate = false
    private var didReplaceTabs = false
    private var isFinished = false

    init(snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    func record(_ effect: Effect) {
        precondition(isFinished == false)
        didMutate = true
        effects.append(effect)
    }

    func recordTabsReplacement() {
        precondition(isFinished == false)
        didReplaceTabs = true
    }

    func finish(committed: Bool) -> Settlement {
        precondition(isFinished == false)
        isFinished = true
        if committed {
            return .committed(
                effects: effects,
                announce: didMutate,
                publishTabs: didReplaceTabs
            )
        }
        return .rolledBack(snapshot)
    }
}
