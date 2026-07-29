import Foundation
import SumiDomain

@MainActor
final class ShortcutDragProxyFactory {
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let tabFactory: TabFactory
    private let runtimePreparation: TabRuntimePreparationOwner

    init(
        resolution: ShortcutPinRuntimeResolutionOwner,
        tabFactory: TabFactory,
        runtimePreparation: TabRuntimePreparationOwner
    ) {
        self.resolution = resolution
        self.tabFactory = tabFactory
        self.runtimePreparation = runtimePreparation
    }

    func make(for pin: ShortcutPin) -> Tab {
        let tab = tabFactory.makeTab(
            id: pin.id,
            url: pin.launchURL,
            name: pin.title,
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: pin.role == .essential ? nil : pin.spaceId,
            index: pin.index
        )
        tab.bindToShortcutPin(pin)
        tab.profileId = resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: pin.spaceId
        )
        tab.folderId = pin.folderId
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        runtimePreparation.prepare(tab)
        return tab
    }
}

@MainActor
final class TabShortcutPresentationOwner {
    private let transientTabs: TabTransientTabRegistryOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let pins: ShortcutPinCollectionStateOwner
    private let dragProxyFactory: ShortcutDragProxyFactory

    init(
        transientTabs: TabTransientTabRegistryOwner,
        runtimeConnection: TabRuntimePortConnection,
        pins: ShortcutPinCollectionStateOwner,
        dragProxyFactory: ShortcutDragProxyFactory
    ) {
        self.transientTabs = transientTabs
        self.runtimeConnection = runtimeConnection
        self.pins = pins
        self.dragProxyFactory = dragProxyFactory
    }

    func shortcutHasDrifted(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let liveTab = shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return false
        }

        return pin.hasDrifted(from: liveTab.url)
    }

    func shortcutRuntimeAffordanceState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> SumiLauncherRuntimeAffordanceState {
        shortcutRuntimeAffordanceState(
            for: pin,
            in: windowState,
            selection: ShortcutSelectionSnapshot(windowState: windowState)
        )
    }

    func shortcutRuntimeAffordanceState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        selection: ShortcutSelectionSnapshot
    ) -> SumiLauncherRuntimeAffordanceState {
        shortcutRuntimeAffordanceState(
            for: pin,
            liveTab: shortcutLiveTab(for: pin.id, in: windowState.id),
            selection: selection
        )
    }

    func shortcutRuntimeAffordanceState(
        for pin: ShortcutPin,
        liveTab: Tab?,
        selection: ShortcutSelectionSnapshot
    ) -> SumiLauncherRuntimeAffordanceState {
        let presentation = shortcutPresentationState(
            for: pin,
            liveTab: liveTab,
            selection: selection
        )
        let drifted = liveTab.map { pin.hasDrifted(from: $0.url) } ?? false

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
        essentialRuntimeState(
            for: pin,
            in: windowState,
            splitQuery: splitQuery,
            selection: ShortcutSelectionSnapshot(windowState: windowState)
        )
    }

    func essentialRuntimeState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        splitQuery: WindowSplitQuery,
        selection: ShortcutSelectionSnapshot
    ) -> SumiEssentialRuntimeState? {
        essentialRuntimeState(
            for: pin,
            liveTab: shortcutLiveTab(for: pin.id, in: windowState.id),
            in: windowState,
            splitQuery: splitQuery,
            selection: selection
        )
    }

    func essentialRuntimeState(
        for pin: ShortcutPin,
        liveTab: Tab?,
        in windowState: BrowserWindowState,
        splitQuery: WindowSplitQuery,
        selection: ShortcutSelectionSnapshot
    ) -> SumiEssentialRuntimeState? {
        guard pin.role == .essential else { return nil }
        guard let liveTab else {
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
                    in: selection
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
            in: ShortcutSelectionSnapshot(windowState: windowState)
        )
        return isSelected ? liveTab : nil
    }

    func dragProxyTab(for pin: ShortcutPin) -> Tab {
        dragProxyFactory.make(for: pin)
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        let liveTabsByWindow = transientTabs.transientShortcutTabsByWindow
        guard let liveTabs = liveTabsByWindow[windowId], !liveTabs.isEmpty else {
            return nil
        }
        let windowState = runtimeConnection.captureLease().windowState(for: windowId)
        if let currentTabId = windowState?.currentTabId,
           let current = liveTabs.values.first(where: { $0.id == currentTabId }) {
            return current
        }
        if windowState?.currentTabId != nil {
            return nil
        }
        if let currentShortcutPinId = windowState?.currentShortcutPinId,
           let current = liveTabs[currentShortcutPinId] {
            return current
        }
        return nil
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        guard let liveTabs = transientTabs.transientShortcutTabsByWindow[windowId] else { return [] }
        return Array(liveTabs.values).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        transientTabs.transientShortcutTabsByWindow[windowId]?[pinId]
    }

    func shortcutPresentationState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPresentationState {
        shortcutPresentationState(
            for: pin,
            in: windowState,
            selection: ShortcutSelectionSnapshot(windowState: windowState)
        )
    }

    func shortcutPresentationState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        selection: ShortcutSelectionSnapshot
    ) -> ShortcutPresentationState {
        shortcutPresentationState(
            for: pin,
            liveTab: shortcutLiveTab(for: pin.id, in: windowState.id),
            selection: selection
        )
    }

    func shortcutPresentationState(
        for pin: ShortcutPin,
        liveTab: Tab?,
        selection: ShortcutSelectionSnapshot
    ) -> ShortcutPresentationState {
        guard let liveTab else {
            return .launcherOnly
        }

        if ShortcutSelectionIdentity.isSelected(
            tabId: liveTab.id,
            pinId: pin.id,
            in: selection
        ) {
            return .visuallySelected
        }

        return .liveBackgrounded
    }

    func activeShortcutTabs(role: ShortcutPinRole? = nil) -> [Tab] {
        transientTabs.transientShortcutTabsByWindow.values
            .flatMap(\.values)
            .filter { role == nil || $0.shortcutPinRole == role }
    }

    func activeEssentialTabs(for profileId: UUID?) -> [Tab] {
        guard let profileId else { return [] }
        return activeShortcutTabs(role: .essential).filter { tab in
            guard let shortcutId = tab.shortcutPinId,
                  let pin = pins.shortcutPin(by: shortcutId) else { return false }
            return pin.profileId == profileId
        }
    }

    func liveSpacePinnedTabs(for spaceId: UUID) -> [Tab] {
        activeShortcutTabs(role: .spacePinned)
            .filter { $0.spaceId == spaceId }
            .sorted { lhs, rhs in
                let lhsIndex = lhs.shortcutPinId.flatMap { pins.shortcutPin(by: $0)?.index } ?? lhs.index
                let rhsIndex = rhs.shortcutPinId.flatMap { pins.shortcutPin(by: $0)?.index } ?? rhs.index
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

}
