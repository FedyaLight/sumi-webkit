import Foundation

/// Immutable capture of atomic live-shortcut slots. A slot always carries its
/// Tab and presentation-page authority together; snapshots never join parallel
/// maps or manufacture an entry from independently mutable state.
@MainActor
struct LiveShortcutTabSnapshot {
    let entriesByWindow: [UUID: [UUID: LiveShortcutTabEntry]]

    var orderedEntries: [LiveShortcutTabEntry] {
        entriesByWindow.values.flatMap(\.values).sorted {
            if $0.windowId != $1.windowId {
                return $0.windowId.uuidString < $1.windowId.uuidString
            }
            return $0.pinId.uuidString < $1.pinId.uuidString
        }
    }

    func entries(for pinID: UUID) -> [LiveShortcutTabEntry] {
        orderedEntries.filter { $0.pinId == pinID }
    }

    func entries(in windowID: UUID) -> [LiveShortcutTabEntry] {
        entriesByWindow[windowID]?.values.sorted {
            $0.pinId.uuidString < $1.pinId.uuidString
        } ?? []
    }

    func entry(containing tab: Tab) -> LiveShortcutTabEntry? {
        orderedEntries.first { $0.tab === tab }
    }

    func entry(tabID: UUID) -> LiveShortcutTabEntry? {
        orderedEntries.first { $0.tab.id == tabID }
    }

    func isIdentical(to other: LiveShortcutTabSnapshot) -> Bool {
        let lhs = orderedEntries
        let rhs = other.orderedEntries
        return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.isIdentical(to: $1)
        }
    }
}
