import AppKit
import Foundation

/// Pure reversible state for one synchronous structural collection batch.
/// It stores exact source values and typed effects, never executable work.
@MainActor
final class TabStructuralMutationTransaction {
    struct FolderReceipt {
        let folder: TabFolder
        let name: String
        let placement: TabFolderPlacement
        let isOpen: Bool
        let icon: String
        let color: NSColor

        @MainActor
        init(_ folder: TabFolder) {
            self.folder = folder
            name = folder.name
            placement = folder.placementSnapshot
            isOpen = folder.isOpen
            icon = folder.icon
            color = folder.color
        }

        @MainActor
        @discardableResult
        func restore() -> Bool {
            let didRestoreExpansion = folder.isOpen != isOpen
            if folder.name != name { folder.name = name }
            if folder.placementSnapshot != placement {
                folder.installPlacement(placement)
            }
            if folder.isOpen != isOpen { folder.isOpen = isOpen }
            if folder.icon != icon { folder.icon = icon }
            if folder.color != color { folder.color = color }
            return didRestoreExpansion
        }

        @MainActor
        func acceptsCurrent() -> Bool {
            folder.name == name
                && folder.placementSnapshot == placement
                && folder.isOpen == isOpen
                && folder.icon == icon
                && folder.color == color
        }
    }

    struct Snapshot {
        let tabs: [UUID: [Tab]]
        let folders: [UUID: [TabFolder]]
        let pinned: [UUID: [ShortcutPin]]
        let spacePinned: [UUID: [ShortcutPin]]
        let pendingPinnedWithoutProfile: [ShortcutPin]
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

    static func applyFolderPlacements(
        _ placements: [UUID: TabFolderPlacement],
        to folders: [TabFolder]
    ) -> Bool {
        var didChange = false
        for folder in folders {
            guard let placement = placements[folder.id],
                  folder.placementSnapshot != placement else { continue }
            folder.installPlacement(placement)
            didChange = true
        }
        return didChange
    }

    private let snapshot: Snapshot
    private var effects: [Effect] = []
    private var didMutate = false
    private var didReplaceTabs = false
    private var isFinished = false

    var hasRecordedMutations: Bool { didMutate || didReplaceTabs }

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

    func discardUnmodified() {
        precondition(isFinished == false && hasRecordedMutations == false)
        isFinished = true
    }

    func discardInvalidated() -> Snapshot {
        precondition(isFinished == false)
        isFinished = true
        return snapshot
    }

    func discardCoveredByTerminalDrain() {
        precondition(isFinished == false)
        isFinished = true
    }
}
