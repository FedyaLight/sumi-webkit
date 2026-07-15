import Foundation

@MainActor
final class TabTransientTabRegistryOwner {
    let liveShortcutResidences = LiveShortcutTabResidenceStore()
    private(set) var transientExtensionTabsByID: [UUID: Tab] = [:]
    private(set) var auxiliaryMiniWindowTabsByID: [UUID: Tab] = [:]

    var transientShortcutTabsByWindow: [UUID: [UUID: Tab]] {
        liveShortcutResidences.tabsByWindow
    }

    var transientShortcutTabs: [Tab] {
        liveShortcutResidences.tabs
    }

    var allTransientTabs: [Tab] {
        transientShortcutTabs + Array(transientExtensionTabsByID.values)
    }

    func removeAll() {
        liveShortcutResidences.removeAll()
        transientExtensionTabsByID.removeAll()
        auxiliaryMiniWindowTabsByID.removeAll()
    }

    func liveShortcutEntries(presentedInSpace spaceId: UUID) -> [LiveShortcutTabEntry] {
        liveShortcutResidences.snapshot.orderedEntries.filter {
            $0.presentationPage.page.spaceID == spaceId
        }
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
