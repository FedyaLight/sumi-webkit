import Foundation

@MainActor
extension TabManager {
    private func normalizedShortcutComparisonURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.string?.lowercased() ?? url.absoluteString.lowercased()
    }

    func shortcutHasDrifted(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard pin.role == .spacePinned,
              let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return false
        }

        return normalizedShortcutComparisonURL(liveTab.url)
            != normalizedShortcutComparisonURL(pin.launchURL)
    }

    func shortcutRuntimeAffordanceState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> SumiLauncherRuntimeAffordanceState {
        let presentation = shortcutPresentationState(for: pin, in: windowState)
        let drifted = shortcutHasDrifted(pin, in: windowState)

        switch (presentation, drifted) {
        case (.launcherOnly, _):
            return .launcherOnly
        case (.liveBackgrounded, false):
            return .liveBackgrounded
        case (.visuallySelected, false):
            return .liveSelected
        case (.liveBackgrounded, true):
            return .driftedLiveBackgrounded
        case (.visuallySelected, true):
            return .driftedLiveSelected
        }
    }

    func essentialRuntimeState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        splitManager: SplitViewManager?
    ) -> SumiEssentialRuntimeState? {
        guard pin.role == .essential else { return nil }
        guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return .launcherOnly
        }

        let isInSplit = splitManager?.side(for: liveTab.id, in: windowState.id) != nil
        if isInSplit {
            let isSelected = windowState.currentTabId == liveTab.id || windowState.currentShortcutPinId == pin.id
            return isSelected ? .splitProxySelected : .splitProxyBackgrounded
        }

        return .liveAttached
    }

    func selectedShortcutLiveTab(for pinId: UUID, in windowState: BrowserWindowState) -> Tab? {
        guard let liveTab = shortcutLiveTab(for: pinId, in: windowState.id) else {
            return nil
        }
        let isSelected = windowState.currentTabId == liveTab.id || windowState.currentShortcutPinId == pinId
        return isSelected ? liveTab : nil
    }

    func dragProxyTab(for pin: ShortcutPin) -> Tab {
        let tab = Tab(
            id: pin.id,
            url: pin.launchURL,
            name: pin.title,
            favicon: pin.systemIconName,
            spaceId: pin.role == .essential ? nil : pin.spaceId,
            index: pin.index,
            browserManager: browserManager
        )
        tab.bindToShortcutPin(pin)
        tab.profileId = pin.profileId
        tab.folderId = pin.folderId
        tab.favicon = pin.favicon
        tab.faviconIsTemplateGlobePlaceholder = pin.faviconIsUncachedGlobeTemplate
        return tab
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        guard let liveTabs = transientShortcutTabsByWindow[windowId], !liveTabs.isEmpty else {
            return nil
        }
        if let currentTabId = browserManager?.windowRegistry?.windows[windowId]?.currentTabId,
           let current = liveTabs.values.first(where: { $0.id == currentTabId }) {
            return current
        }
        if browserManager?.windowRegistry?.windows[windowId]?.currentTabId != nil {
            return nil
        }
        if let currentShortcutPinId = browserManager?.windowRegistry?.windows[windowId]?.currentShortcutPinId,
           let current = liveTabs[currentShortcutPinId] {
            return current
        }
        return nil
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        guard let liveTabs = transientShortcutTabsByWindow[windowId] else { return [] }
        return Array(liveTabs.values).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        transientShortcutTabsByWindow[windowId]?[pinId]
    }

    func shortcutPresentationState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPresentationState {
        guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return .launcherOnly
        }

        if windowState.currentShortcutPinId == pin.id || windowState.currentTabId == liveTab.id {
            return .visuallySelected
        }

        return .liveBackgrounded
    }

    func activeShortcutTabs(role: ShortcutPinRole? = nil) -> [Tab] {
        transientShortcutTabsByWindow.values
            .flatMap(\.values)
            .filter { role == nil || $0.shortcutPinRole == role }
    }

    /// After a favicon cache miss (e.g. cleared cache), the live `Tab` may resolve a bitmap while the
    /// `ShortcutPin` still shows the globe. Copies the resolved favicon onto the pin for default (non-custom) icons
    /// and notifies sidebar views that listen for shortcut runtime changes.
    func propagateLauncherFaviconFromLiveTabIfNeeded(_ tab: Tab) {
        guard tab.isShortcutLiveInstance,
              let pinId = tab.shortcutPinId,
              let pin = shortcutPin(by: pinId),
              pin.iconAsset == nil else {
            return
        }
        pin.refreshFromLiveTab(tab)
    }
}
