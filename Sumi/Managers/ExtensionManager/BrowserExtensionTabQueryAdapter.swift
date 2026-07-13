import Foundation

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionTabQueryAdapter:
    ExtensionTabQuery,
    ExtensionTabInventory {
    private let regularTab: @MainActor (UUID) -> Tab?
    private let allTabs: @MainActor () -> [Tab]
    private let windows: @MainActor () -> [BrowserWindowState]
    private let isTransient: @MainActor (Tab) -> Bool
    private let isAuxiliaryMiniWindow: @MainActor (Tab) -> Bool
    private let isPinned: @MainActor (Tab) -> Bool

    init(
        regularTab: @escaping @MainActor (UUID) -> Tab?,
        allTabs: @escaping @MainActor () -> [Tab],
        windows: @escaping @MainActor () -> [BrowserWindowState],
        isTransient: @escaping @MainActor (Tab) -> Bool,
        isAuxiliaryMiniWindow: @escaping @MainActor (Tab) -> Bool,
        isPinned: @escaping @MainActor (Tab) -> Bool
    ) {
        self.regularTab = regularTab
        self.allTabs = allTabs
        self.windows = windows
        self.isTransient = isTransient
        self.isAuxiliaryMiniWindow = isAuxiliaryMiniWindow
        self.isPinned = isPinned
    }

    var allExtensionTabs: [Tab] {
        var seen = Set<ObjectIdentifier>()
        return allTabs().filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    func extensionTab(for tabId: UUID) -> Tab? {
        if let tab = regularTab(tabId) {
            return tab
        }
        return windows().lazy
            .compactMap { window in
                window.ephemeralTabs.first(where: { $0.id == tabId })
            }
            .first
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        isTransient(tab)
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        isAuxiliaryMiniWindow(tab)
    }

    func isPinnedExtensionTab(_ tab: Tab) -> Bool {
        isPinned(tab)
    }
}
