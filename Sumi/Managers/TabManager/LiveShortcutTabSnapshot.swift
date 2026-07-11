import Foundation

/// Deterministic read model of the per-window shortcut registry.
@MainActor
struct LiveShortcutTabSnapshot {
    let tabsByWindow: [UUID: [UUID: Tab]]

    var orderedEntries: [LiveShortcutTabRegistry.Entry] {
        tabsByWindow.flatMap { windowID, tabsByPin in
            tabsByPin.map { pinID, tab in
                LiveShortcutTabRegistry.Entry(
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

    func entries(for pinID: UUID) -> [LiveShortcutTabRegistry.Entry] {
        orderedEntries.filter { $0.pinId == pinID }
    }

    func entries(in windowID: UUID) -> [LiveShortcutTabRegistry.Entry] {
        orderedEntries.filter { $0.windowId == windowID }
    }

    func entry(containing tab: Tab) -> LiveShortcutTabRegistry.Entry? {
        orderedEntries.first { $0.tab === tab }
    }

    func entry(tabID: UUID) -> LiveShortcutTabRegistry.Entry? {
        orderedEntries.first { $0.tab.id == tabID }
    }
}
