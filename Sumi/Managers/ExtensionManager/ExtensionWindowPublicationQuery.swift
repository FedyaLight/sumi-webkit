import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
enum ExtensionAuxiliaryTabPublicationState {
    case notAuxiliarySession
    case committed
    case unavailable
}

/// Read-only evidence from the two window-publication ledgers. Callers cannot
/// materialize adapters or mutate either lifecycle through this surface.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowPublicationQuery {
    private let normalWindows: ExtensionNormalWindowLifecycle
    private let auxiliaryWindows: ExtensionAuxiliaryWindowPublicationQuery
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let control:
        @MainActor () -> (any ExtensionAuxiliaryWindowControl)?

    init(
        normalWindows: ExtensionNormalWindowLifecycle,
        auxiliaryWindows: ExtensionAuxiliaryWindowPublicationQuery,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        control: @escaping @MainActor () -> (
            any ExtensionAuxiliaryWindowControl
        )?
    ) {
        self.normalWindows = normalWindows
        self.auxiliaryWindows = auxiliaryWindows
        self.runtime = runtime
        self.control = control
    }

    func publishedWindowAdapter(
        for windowState: BrowserWindowState,
        profileID: UUID
    ) -> ExtensionWindowAdapter? {
        normalWindows.publishedAdapter(
            for: windowState,
            profileID: profileID
        )
    }

    func publishedAuxiliaryWindowAdapters(
        ownerExtensionID: String,
        profileID: UUID
    ) -> [ExtensionMiniWindowAdapter] {
        var adapters = auxiliaryWindows.publishedAdapters(
            ownerExtensionID: ownerExtensionID,
            profileID: profileID,
            runtime: runtime(),
            control: control()
        )
        adapters.sort {
            $0.sessionId.uuidString < $1.sessionId.uuidString
        }
        guard let focused = control()?
            .focusedExtensionMiniWindowAdapter(
                forOwnerExtensionID: ownerExtensionID
            ), let index = adapters.firstIndex(where: { $0 === focused }) else {
            return adapters
        }
        adapters.remove(at: index)
        adapters.insert(focused, at: 0)
        return adapters
    }

    func auxiliaryTabPublicationState(
        for tab: Tab
    ) -> ExtensionAuxiliaryTabPublicationState {
        let currentControl = control()
        if tab.isAuxiliaryMiniWindow {
            guard let currentControl,
                  let session = currentControl.auxiliaryWindowSession(for: tab),
                  session.tab === tab else {
                return .unavailable
            }
            return auxiliaryWindows.canUseCommittedTabPublication(
                for: tab,
                runtime: runtime(),
                control: currentControl
            ) ? .committed : .unavailable
        }
        guard currentControl?.auxiliaryWindowSession(for: tab) == nil else {
            return .unavailable
        }
        return .notAuxiliarySession
    }

    func isCommittedAuxiliaryTabAdapter(
        _ adapter: ExtensionTabAdapter,
        for tab: Tab,
        visibleTo context: WKWebExtensionContext
    ) -> Bool {
        guard tab.isAuxiliaryMiniWindow else { return false }
        return auxiliaryWindows.isCommittedTabAdapter(
            adapter,
            for: tab,
            visibleTo: context,
            runtime: runtime(),
            control: control()
        )
    }

    func isCurrentAuxiliaryWindowAdapter(
        _ adapter: ExtensionMiniWindowAdapter,
        visibleTo context: WKWebExtensionContext
    ) -> Bool {
        auxiliaryWindows.isCurrentWindowAdapter(
            adapter,
            visibleTo: context,
            runtime: runtime(),
            control: control()
        )
    }

    func publishedAuxiliaryTabAdapter(
        for adapter: ExtensionMiniWindowAdapter,
        visibleTo context: WKWebExtensionContext
    ) -> ExtensionTabAdapter? {
        auxiliaryWindows.tabAdapter(
            for: adapter,
            visibleTo: context,
            runtime: runtime(),
            control: control()
        )
    }

    func isAuxiliarySessionTab(_ tab: Tab) -> Bool {
        if tab.isAuxiliaryMiniWindow { return true }
        guard let control = control() else { return false }
        return control.auxiliaryWindowSession(for: tab)?.tab === tab
    }

    func tabPublicationIsCurrent(_ tab: Tab, profileID: UUID) -> Bool {
        if tab.isAuxiliaryMiniWindow {
            guard let control = control(),
                  let session = control.auxiliaryWindowSession(for: tab),
                  session.tab === tab else {
                return false
            }
            return auxiliaryWindows.canUseCommittedTabPublication(
                for: tab,
                profileID: profileID,
                runtime: runtime(),
                control: control
            )
        }
        if let control = control(),
           control.auxiliaryWindowSession(for: tab) != nil {
            return false
        }
        return normalWindows.tabPublicationIsCurrent(
            tab,
            profileID: profileID
        )
    }

    func windowPublicationIsCurrent(
        _ window: BrowserWindowState,
        selectedTab: Tab,
        profileID: UUID
    ) -> Bool {
        guard selectedTab.isAuxiliaryMiniWindow == false else { return false }
        return normalWindows.windowPublicationIsCurrent(
            window,
            selectedTab: selectedTab,
            profileID: profileID
        )
    }
}
