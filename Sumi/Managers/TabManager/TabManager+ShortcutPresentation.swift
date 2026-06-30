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
        guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
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

        let isInSplit = splitManager?.isTabVisibleInSplit(liveTab.id, in: windowState.id) == true
        if isInSplit {
            let isSelected = splitManager?.isTabActiveInSplit(liveTab.id, in: windowState.id) == true
                || windowState.currentShortcutPinId == pin.id
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
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: pin.role == .essential ? nil : pin.spaceId,
            index: pin.index,
            faviconService: faviconService,
            faviconImageService: faviconImageService,
            visitedLinkStore: visitedLinkStore
        )
        tab.bindToShortcutPin(pin)
        tab.profileId = resolvedExecutionProfileId(for: pin, currentSpaceId: pin.spaceId)
        tab.folderId = pin.folderId
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        prepareTabForRuntime(tab)
        return tab
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        guard let liveTabs = transientShortcutTabsByWindow[windowId], !liveTabs.isEmpty else {
            return nil
        }
        if let currentTabId = runtimeContext?.windowState(for: windowId)?.currentTabId,
           let current = liveTabs.values.first(where: { $0.id == currentTabId }) {
            return current
        }
        if runtimeContext?.windowState(for: windowId)?.currentTabId != nil {
            return nil
        }
        if let currentShortcutPinId = runtimeContext?.windowState(for: windowId)?.currentShortcutPinId,
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
}
