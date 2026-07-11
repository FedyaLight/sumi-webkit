import Foundation
import SumiDomain

@MainActor
final class TabShortcutPresentationOwner {
    private let transientShortcutTabsByWindow: @MainActor () -> [UUID: [UUID: Tab]]
    private let windowState: @MainActor (UUID) -> BrowserWindowState?
    private let shortcutPin: @MainActor (UUID) -> ShortcutPin?
    private let resolvedExecutionProfileId: @MainActor (ShortcutPin, UUID?) -> UUID?
    private let tabFactory: TabFactory
    private let prepareTabForRuntime: @MainActor (Tab) -> Void

    init(
        transientShortcutTabsByWindow: @escaping @MainActor () -> [UUID: [UUID: Tab]],
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState?,
        shortcutPin: @escaping @MainActor (UUID) -> ShortcutPin?,
        resolvedExecutionProfileId: @escaping @MainActor (ShortcutPin, UUID?) -> UUID?,
        tabFactory: TabFactory,
        prepareTabForRuntime: @escaping @MainActor (Tab) -> Void
    ) {
        self.transientShortcutTabsByWindow = transientShortcutTabsByWindow
        self.windowState = windowState
        self.shortcutPin = shortcutPin
        self.resolvedExecutionProfileId = resolvedExecutionProfileId
        self.tabFactory = tabFactory
        self.prepareTabForRuntime = prepareTabForRuntime
    }

    convenience init(tabManager: TabManager) {
        self.init(
            transientShortcutTabsByWindow: { [weak tabManager] in
                tabManager?.transientTabRegistryOwner.transientShortcutTabsByWindow ?? [:]
            },
            windowState: { [weak tabManager] windowId in
                tabManager?.runtimePorts?.windowState(for: windowId)
            },
            shortcutPin: { [weak tabManager] pinId in
                tabManager?.shortcutPinCollectionStateOwner.shortcutPin(by: pinId)
            },
            resolvedExecutionProfileId: { [weak tabManager] pin, currentSpaceId in
                tabManager?.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
            },
            tabFactory: tabManager.tabFactory,
            prepareTabForRuntime: { [weak tabManager] tab in
                tabManager?.runtimePreparationOwner.prepare(tab)
            }
        )
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
        splitQuery: WindowSplitQuery
    ) -> SumiEssentialRuntimeState? {
        guard pin.role == .essential else { return nil }
        guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return .launcherOnly
        }

        let isInSplit = splitQuery.contains(
            tabID: liveTab.id,
            in: windowState.id
        )
        if isInSplit {
            let isSelected = splitQuery.isActive(
                tabID: liveTab.id,
                in: windowState.id
            )
                || ShortcutSelectionIdentity.isSelected(
                    tabId: liveTab.id,
                    pinId: pin.id,
                    in: windowState
                )
            return isSelected ? .splitProxySelected : .splitProxyBackgrounded
        }

        return .liveAttached
    }

    func selectedShortcutLiveTab(for pinId: UUID, in windowState: BrowserWindowState) -> Tab? {
        guard let liveTab = shortcutLiveTab(for: pinId, in: windowState.id) else {
            return nil
        }
        let isSelected = ShortcutSelectionIdentity.isSelected(
            tabId: liveTab.id,
            pinId: pinId,
            in: windowState
        )
        return isSelected ? liveTab : nil
    }

    func dragProxyTab(for pin: ShortcutPin) -> Tab {
        let tab = tabFactory.makeTab(
            id: pin.id,
            url: pin.launchURL,
            name: pin.title,
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: pin.role == .essential ? nil : pin.spaceId,
            index: pin.index
        )
        tab.bindToShortcutPin(pin)
        tab.profileId = resolvedExecutionProfileId(pin, pin.spaceId)
        tab.folderId = pin.folderId
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        prepareTabForRuntime(tab)
        return tab
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        let liveTabsByWindow = transientShortcutTabsByWindow()
        guard let liveTabs = liveTabsByWindow[windowId], !liveTabs.isEmpty else {
            return nil
        }
        if let currentTabId = windowState(windowId)?.currentTabId,
           let current = liveTabs.values.first(where: { $0.id == currentTabId }) {
            return current
        }
        if windowState(windowId)?.currentTabId != nil {
            return nil
        }
        if let currentShortcutPinId = windowState(windowId)?.currentShortcutPinId,
           let current = liveTabs[currentShortcutPinId] {
            return current
        }
        return nil
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        guard let liveTabs = transientShortcutTabsByWindow()[windowId] else { return [] }
        return Array(liveTabs.values).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        transientShortcutTabsByWindow()[windowId]?[pinId]
    }

    func shortcutPresentationState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPresentationState {
        guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return .launcherOnly
        }

        if ShortcutSelectionIdentity.isSelected(
            tabId: liveTab.id,
            pinId: pin.id,
            in: windowState
        ) {
            return .visuallySelected
        }

        return .liveBackgrounded
    }

    func activeShortcutTabs(role: ShortcutPinRole? = nil) -> [Tab] {
        transientShortcutTabsByWindow().values
            .flatMap(\.values)
            .filter { role == nil || $0.shortcutPinRole == role }
    }

    func activeEssentialTabs(for profileId: UUID?) -> [Tab] {
        guard let profileId else { return [] }
        return activeShortcutTabs(role: .essential).filter { tab in
            guard let shortcutId = tab.shortcutPinId,
                  let pin = shortcutPin(shortcutId) else { return false }
            return pin.profileId == profileId
        }
    }

    func liveSpacePinnedTabs(for spaceId: UUID) -> [Tab] {
        activeShortcutTabs(role: .spacePinned)
            .filter { $0.spaceId == spaceId }
            .sorted { lhs, rhs in
                let lhsIndex = lhs.shortcutPinId.flatMap { shortcutPin($0)?.index } ?? lhs.index
                let rhsIndex = rhs.shortcutPinId.flatMap { shortcutPin($0)?.index } ?? rhs.index
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func normalizedShortcutComparisonURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }
        components.fragment = nil
        return components.string?.lowercased() ?? url.absoluteString.lowercased()
    }
}
