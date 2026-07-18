import AppKit
import Foundation
import SumiDomain
import SwiftUI

struct SidebarWindowSelectionSnapshot: Equatable {
    static let none = Self()

    let shortcut: ShortcutSelectionSnapshot
    let splitSelection: WindowSplitSelection?

    var currentTabID: UUID? { shortcut.currentTabID }
    var currentShortcutPinID: UUID? { shortcut.currentShortcutPinID }

    init(
        shortcut: ShortcutSelectionSnapshot = ShortcutSelectionSnapshot(),
        splitSelection: WindowSplitSelection? = nil
    ) {
        self.shortcut = shortcut
        self.splitSelection = splitSelection
    }

    @MainActor
    init(windowState: BrowserWindowState) {
        self.init(
            shortcut: ShortcutSelectionSnapshot(windowState: windowState),
            splitSelection: windowState.splitSelection
        )
    }
}

private struct SidebarWindowSelectionSnapshotKey: EnvironmentKey {
    static let defaultValue = SidebarWindowSelectionSnapshot.none
}

extension EnvironmentValues {
    var sidebarWindowSelectionSnapshot: SidebarWindowSelectionSnapshot {
        get { self[SidebarWindowSelectionSnapshotKey.self] }
        set { self[SidebarWindowSelectionSnapshotKey.self] = newValue }
    }
}

struct SidebarWindowSelectionSnapshotScope<Content: View>: View {
    @Environment(BrowserWindowState.self) private var windowState

    @ViewBuilder let content: () -> Content

    var body: some View {
        let snapshot = SidebarWindowSelectionSnapshot(
            shortcut: ShortcutSelectionSnapshot(
                currentTabID: windowState.currentTabId,
                currentShortcutPinID: windowState.currentShortcutPinId
            ),
            splitSelection: windowState.splitSelection
        )
        content()
            .environment(\.sidebarWindowSelectionSnapshot, snapshot)
    }
}

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
        presentationState(
            for: pin,
            in: windowState,
            selection: SidebarWindowSelectionSnapshot(windowState: windowState)
        )
    }

    func presentationState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        selection: SidebarWindowSelectionSnapshot
    ) -> ShortcutPresentationState {
        guard isCurrent(windowState) else { return .launcherOnly }
        return shortcutPresentation.shortcutPresentationState(
            for: pin,
            in: windowState,
            selection: selection.shortcut
        )
    }

    func runtimeAffordance(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> SumiLauncherRuntimeAffordanceState {
        runtimeAffordance(
            for: pin,
            in: windowState,
            selection: SidebarWindowSelectionSnapshot(windowState: windowState)
        )
    }

    func runtimeAffordance(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        selection: SidebarWindowSelectionSnapshot
    ) -> SumiLauncherRuntimeAffordanceState {
        guard isCurrent(windowState) else { return .launcherOnly }
        return shortcutPresentation.shortcutRuntimeAffordanceState(
            for: pin,
            in: windowState,
            selection: selection.shortcut
        )
    }

    func essentialRuntimeState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> SumiEssentialRuntimeState? {
        essentialRuntimeState(
            for: pin,
            in: windowState,
            selection: SidebarWindowSelectionSnapshot(windowState: windowState)
        )
    }

    func essentialRuntimeState(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState,
        selection: SidebarWindowSelectionSnapshot
    ) -> SumiEssentialRuntimeState? {
        guard isCurrent(windowState) else {
            return pin.role == .essential ? .launcherOnly : nil
        }
        return shortcutPresentation.essentialRuntimeState(
            for: pin,
            in: windowState,
            splitQuery: splitQuery,
            selection: selection.shortcut
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
        isSplitGroupSelected(
            group,
            in: windowState,
            selection: SidebarWindowSelectionSnapshot(windowState: windowState)
        )
    }

    func isSplitGroupSelected(
        _ group: SplitGroup,
        in windowState: BrowserWindowState,
        selection: SidebarWindowSelectionSnapshot
    ) -> Bool {
        guard selectedSplitGroup(in: windowState)?.id == group.id else {
            return false
        }
        return selection.splitSelection?.groupID == group.id
    }

    func isShortcutSelected(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        runtimeAffordance(for: pin, in: windowState).isSelected
    }

    func isShortcutSelected(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        selection: SidebarWindowSelectionSnapshot
    ) -> Bool {
        runtimeAffordance(
            for: pin,
            in: windowState,
            selection: selection
        ).isSelected
    }

    func isSplitMemberSelected(
        groupID: UUID,
        memberID: SplitMemberID,
        in windowState: BrowserWindowState
    ) -> Bool {
        isSplitMemberSelected(
            groupID: groupID,
            memberID: memberID,
            in: windowState,
            selection: SidebarWindowSelectionSnapshot(windowState: windowState)
        )
    }

    func isSplitMemberSelected(
        groupID: UUID,
        memberID: SplitMemberID,
        in windowState: BrowserWindowState,
        selection: SidebarWindowSelectionSnapshot
    ) -> Bool {
        guard selectedSplitGroup(in: windowState)?.id == groupID,
              selection.splitSelection?.groupID == groupID else {
            return false
        }
        return selection.splitSelection?.activeMemberID == memberID
    }
}
