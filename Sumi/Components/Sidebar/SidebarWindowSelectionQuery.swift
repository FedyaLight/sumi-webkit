import AppKit
import Foundation
import SumiDomain

/// Validates that a sidebar action or query still belongs to the exact
/// registered window object, not merely a retained object with the same UUID.
@MainActor
final class SidebarWindowIdentityQuery {
    private weak var registry: WindowRegistry?

    init(registry: WindowRegistry?) {
        self.registry = registry
    }

    func contains(_ windowState: BrowserWindowState) -> Bool {
        registry?.windows[windowState.id] === windowState
    }

    func window(id: UUID) -> BrowserWindowState? {
        registry?.windows[id]
    }

    func shellWindow(for windowState: BrowserWindowState) -> NSWindow? {
        windowState.shellWindow(in: registry)
    }

    func presentationSource(
        for windowState: BrowserWindowState,
        ownerView: NSView? = nil
    ) -> SidebarTransientPresentationSource {
        windowState.resolveSidebarPresentationSource(
            ownerView: ownerView,
            in: registry
        )
    }
}

/// Window-local shortcut and split selection boundary for sidebar consumers.
/// Structural inventory is deliberately resolved elsewhere.
@MainActor
final class SidebarWindowSelectionQuery {
    private let runtimeIsAlive: @MainActor () -> Bool
    private let windows: SidebarWindowIdentityQuery
    private let windowTabs: BrowserWindowTabContext
    private let shortcutPresentation: TabShortcutPresentationOwner
    private let splitQuery: WindowSplitQuery

    init(
        runtimeIsAlive: @escaping @MainActor () -> Bool,
        windows: SidebarWindowIdentityQuery,
        windowTabs: BrowserWindowTabContext,
        shortcutPresentation: TabShortcutPresentationOwner,
        splitQuery: WindowSplitQuery
    ) {
        self.runtimeIsAlive = runtimeIsAlive
        self.windows = windows
        self.windowTabs = windowTabs
        self.shortcutPresentation = shortcutPresentation
        self.splitQuery = splitQuery
    }

    func isCurrent(_ windowState: BrowserWindowState) -> Bool {
        runtimeIsAlive() && windows.contains(windowState)
    }

    func currentTab(in windowState: BrowserWindowState) -> Tab? {
        guard isCurrent(windowState),
              let tab = windowTabs.currentTab(for: windowState) else {
            return nil
        }

        guard let pinID = tab.shortcutPinId else {
            return tab
        }
        return shortcutPresentation.shortcutLiveTab(
            for: pinID,
            in: windowState.id
        ) === tab ? tab : nil
    }

    func selectedTabID(in windowState: BrowserWindowState) -> UUID? {
        guard isCurrent(windowState) else { return nil }
        return windowState.currentTabId
    }

    func liveTab(
        for pinID: UUID,
        in windowState: BrowserWindowState
    ) -> Tab? {
        guard isCurrent(windowState) else { return nil }
        return shortcutPresentation.shortcutLiveTab(
            for: pinID,
            in: windowState.id
        )
    }

    func presentationState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPresentationState {
        guard isCurrent(windowState) else { return .launcherOnly }
        return shortcutPresentation.shortcutPresentationState(
            for: pin,
            in: windowState
        )
    }

    func runtimeAffordance(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> SumiLauncherRuntimeAffordanceState {
        guard isCurrent(windowState) else { return .launcherOnly }
        return shortcutPresentation.shortcutRuntimeAffordanceState(
            for: pin,
            in: windowState
        )
    }

    func essentialRuntimeState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> SumiEssentialRuntimeState? {
        guard isCurrent(windowState) else {
            return pin.role == .essential ? .launcherOnly : nil
        }
        return shortcutPresentation.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitQuery: splitQuery
        )
    }

    func hasSavedURLDrift(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard isCurrent(windowState) else { return false }
        return shortcutPresentation.shortcutHasDrifted(pin, in: windowState)
    }

    func selectedSplitGroup(in windowState: BrowserWindowState) -> SplitGroup? {
        guard isCurrent(windowState) else { return nil }
        return splitQuery.group(in: windowState.id)
    }

    func isRegularTabSelected(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) -> Bool {
        selectedTabID(in: windowState) == tab.id
    }

    func isSplitGroupSelected(
        _ group: SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        selectedSplitGroup(in: windowState)?.id == group.id
    }

    func isShortcutSelected(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        runtimeAffordance(for: pin, in: windowState).isSelected
    }

    func isSplitMemberSelected(
        groupID: UUID,
        memberID: SplitMemberID,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let group = selectedSplitGroup(in: windowState),
              group.id == groupID else {
            return false
        }
        return windowState.splitSelection?.activeMemberID == memberID
    }
}
