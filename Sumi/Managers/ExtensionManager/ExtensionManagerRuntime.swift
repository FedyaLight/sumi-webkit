import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerRuntime {
    typealias CurrentProfileProvider = @MainActor () -> Profile?
    typealias ProfileProvider = @MainActor (_ profileId: UUID) -> Profile?
    typealias EphemeralProfileProvider = @MainActor (_ profileId: UUID) -> Profile?
    typealias WindowStateProvider = @MainActor (_ windowId: UUID) -> BrowserWindowState?
    typealias ActiveWindowStateProvider = @MainActor () -> BrowserWindowState?
    typealias AllTabsProvider = @MainActor () -> [Tab]
    typealias AllWindowStatesProvider = @MainActor () -> [BrowserWindowState]
    typealias WindowStateContainingTabProvider = @MainActor (_ tab: Tab) -> BrowserWindowState?
    typealias WindowOwnedWebViewProvider = @MainActor (_ tab: Tab, _ windowId: UUID) -> WKWebView?
    typealias PrimaryTrackedWindowIdProvider = @MainActor (_ tabId: UUID) -> UUID?
    typealias UntrackedOwnedWebViewProvider = @MainActor (_ tab: Tab) -> WKWebView?
    typealias TrackedWebViewsProvider = @MainActor (_ tabId: UUID) -> [WKWebView]
    typealias RebuildLiveWebViews = @MainActor (_ tab: Tab) -> Void
    typealias BrowserRuntimeAvailabilityProvider = @MainActor () -> Bool
    typealias ModuleEnabledProvider = @MainActor () -> ModuleEnabledState

    enum ModuleEnabledState: Equatable {
        case unavailable
        case enabled(Bool)
    }

    let currentProfile: CurrentProfileProvider
    let profile: ProfileProvider
    let ephemeralProfile: EphemeralProfileProvider
    let windowState: WindowStateProvider
    let activeWindowState: ActiveWindowStateProvider
    let allTabs: AllTabsProvider
    let allWindowStates: AllWindowStatesProvider
    let windowStateContainingTab: WindowStateContainingTabProvider
    let windowOwnedWebView: WindowOwnedWebViewProvider
    let primaryTrackedWindowId: PrimaryTrackedWindowIdProvider
    let untrackedOwnedWebView: UntrackedOwnedWebViewProvider
    let trackedWebViews: TrackedWebViewsProvider
    let rebuildLiveWebViews: RebuildLiveWebViews
    let browserRuntimeAvailable: BrowserRuntimeAvailabilityProvider
    let extensionsModuleEnabled: ModuleEnabledProvider

    static let inactive = ExtensionManagerRuntime(
        currentProfile: { nil },
        profile: { _ in nil },
        ephemeralProfile: { _ in nil },
        windowState: { _ in nil },
        activeWindowState: { nil },
        allTabs: { [] },
        allWindowStates: { [] },
        windowStateContainingTab: { _ in nil },
        windowOwnedWebView: { _, _ in nil },
        primaryTrackedWindowId: { _ in nil },
        untrackedOwnedWebView: { _ in nil },
        trackedWebViews: { _ in [] },
        rebuildLiveWebViews: { _ in /* No-op. */ },
        browserRuntimeAvailable: { false },
        extensionsModuleEnabled: { .unavailable }
    )
}
