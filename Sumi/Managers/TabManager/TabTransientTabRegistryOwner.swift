import Foundation

@MainActor
final class TabTransientTabRegistryOwner {
    private(set) var transientShortcutTabsByWindow: [UUID: [UUID: Tab]] = [:]
    private(set) var transientExtensionTabsByID: [UUID: Tab] = [:]
    private(set) var auxiliaryMiniWindowTabsByID: [UUID: Tab] = [:]

    var transientShortcutTabs: [Tab] {
        transientShortcutTabsByWindow.values.flatMap(\.values)
    }

    var allTransientTabs: [Tab] {
        transientShortcutTabs + Array(transientExtensionTabsByID.values)
    }

    func replaceTransientShortcutTabsByWindow(
        _ tabsByWindow: [UUID: [UUID: Tab]]
    ) {
        transientShortcutTabsByWindow = tabsByWindow
    }

    func updateTransientShortcutTabsByWindow(
        _ update: (inout [UUID: [UUID: Tab]]) -> Void
    ) {
        update(&transientShortcutTabsByWindow)
    }

    func removeAll() {
        transientShortcutTabsByWindow.removeAll()
        transientExtensionTabsByID.removeAll()
        auxiliaryMiniWindowTabsByID.removeAll()
    }

    func transientShortcutTabs(inSpace spaceId: UUID) -> [Tab] {
        transientShortcutTabs.filter { $0.spaceId == spaceId }
    }

    func removeTransientShortcutTabs(inSpace spaceId: UUID) {
        transientShortcutTabsByWindow = transientShortcutTabsByWindow
            .compactMapValues { tabsByPin in
                let filtered = tabsByPin.filter { _, tab in tab.spaceId != spaceId }
                return filtered.isEmpty ? nil : filtered
            }
    }

    func removeTransientShortcutTab(tabId: UUID) -> (
        windowId: UUID,
        pinId: UUID,
        tab: Tab
    )? {
        guard
            let match = transientShortcutTabsByWindow.lazy
                .compactMap({ windowId, tabsByPin -> (UUID, UUID, Tab)? in
                    guard let entry = tabsByPin.first(where: { $0.value.id == tabId }) else {
                        return nil
                    }
                    return (windowId, entry.key, entry.value)
                })
                .first
        else {
            return nil
        }

        transientShortcutTabsByWindow[match.0]?.removeValue(forKey: match.1)
        if transientShortcutTabsByWindow[match.0]?.isEmpty == true {
            transientShortcutTabsByWindow.removeValue(forKey: match.0)
        }
        return (windowId: match.0, pinId: match.1, tab: match.2)
    }

    func removeTransientShortcutTab(
        pinId: UUID,
        in windowId: UUID
    ) -> Tab? {
        guard let tab = transientShortcutTabsByWindow[windowId]?
            .removeValue(forKey: pinId) else {
            return nil
        }
        if transientShortcutTabsByWindow[windowId]?.isEmpty == true {
            transientShortcutTabsByWindow.removeValue(forKey: windowId)
        }
        return tab
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        transientExtensionTabsByID[tab.id] != nil
    }

    func registerTransientExtensionTab(_ tab: Tab) {
        transientExtensionTabsByID[tab.id] = tab
    }

    func removeTransientExtensionTab(id: UUID) -> Tab? {
        transientExtensionTabsByID.removeValue(forKey: id)
    }

    @discardableResult
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        transientExtensionTabsByID.removeValue(forKey: tab.id) != nil
    }

    func registerAuxiliaryMiniWindowTab(_ tab: Tab) {
        auxiliaryMiniWindowTabsByID[tab.id] = tab
    }

    func auxiliaryMiniWindowTab(for id: UUID) -> Tab? {
        auxiliaryMiniWindowTabsByID[id]
    }

    func removeAuxiliaryMiniWindowTab(_ tab: Tab) {
        auxiliaryMiniWindowTabsByID.removeValue(forKey: tab.id)
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        auxiliaryMiniWindowTabsByID[tab.id] != nil
    }
}
