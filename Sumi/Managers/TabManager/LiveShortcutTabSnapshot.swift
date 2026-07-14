import Foundation

/// Deterministic read model of the per-window shortcut registry.
@MainActor
struct LiveShortcutTabSnapshot {
    let tabsByWindow: [UUID: [UUID: Tab]]

    var orderedEntries: [LiveShortcutTabEntry] {
        tabsByWindow.flatMap { windowID, tabsByPin in
            tabsByPin.map { pinID, tab in
                LiveShortcutTabEntry(
                    windowId: windowID,
                    pinId: pinID,
                    tab: tab
                )
            }
        }
        .sorted {
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
        orderedEntries.filter { $0.windowId == windowID }
    }

    func entry(containing tab: Tab) -> LiveShortcutTabEntry? {
        orderedEntries.first { $0.tab === tab }
    }

    func entry(tabID: UUID) -> LiveShortcutTabEntry? {
        orderedEntries.first { $0.tab.id == tabID }
    }
}
