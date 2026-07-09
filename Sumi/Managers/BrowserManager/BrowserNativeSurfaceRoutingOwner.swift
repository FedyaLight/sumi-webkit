import AppKit
import Foundation

@MainActor
final class BrowserNativeSurfaceRoutingOwner {
    private let tabManagerAction: @MainActor @Sendable () -> TabManager
    private let settingsAction: @MainActor @Sendable () -> SumiSettingsService?
    private let openNewTabAction: @MainActor @Sendable (String, BrowserTabOpenContext) -> Tab
    private let selectTabAction: @MainActor @Sendable (Tab, BrowserWindowState) -> Void
    private let focusWindowAction: @MainActor @Sendable (BrowserWindowState) -> Void

    init(
        tabManager: @escaping @MainActor @Sendable () -> TabManager,
        settings: @escaping @MainActor @Sendable () -> SumiSettingsService?,
        openNewTab: @escaping @MainActor @Sendable (String, BrowserTabOpenContext) -> Tab,
        selectTab: @escaping @MainActor @Sendable (Tab, BrowserWindowState) -> Void,
        focusWindow: @escaping @MainActor @Sendable (BrowserWindowState) -> Void
    ) {
        self.tabManagerAction = tabManager
        self.settingsAction = settings
        self.openNewTabAction = openNewTab
        self.selectTabAction = selectTab
        self.focusWindowAction = focusWindow
    }

    convenience init(browserManager: BrowserManager) {
        let tabLifecycleService = browserManager.tabLifecycleService
        self.init(
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            settings: { [weak browserManager] in browserManager?.sumiSettings },
            openNewTab: { url, context in
                tabLifecycleService.opening.openNewTab(url: url, context: context)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            focusWindow: { [weak browserManager] windowState in
                windowState.shellWindow(in: browserManager?.windowRegistry)?
                    .makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        )
    }

    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID? = nil
    ) {
        let tabManager = tabManagerAction()

        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            if let existing = windowState.ephemeralTabs.first(where: { kind.matches($0) }) {
                configureAndSelect(existing, kind: kind, url: url, in: windowState)
            } else {
                let newTab = tabManager.ephemeralLifecycleOwner.createEphemeralTab(
                    url: url,
                    in: windowState,
                    profile: profile
                )
                configureAndSelect(newTab, kind: kind, url: url, in: windowState)
            }
            focusWindowAction(windowState)
            return
        }

        let targetSpace = resolvedTargetSpace(
            tabManager: tabManager,
            windowState: windowState,
            preferredSpaceId: preferredSpaceId
        )

        if let sid = targetSpace?.id,
           let existing = tabManager.regularTabCollectionOwner.tabs(in: sid).first(where: { kind.matches($0) }) {
            configureAndSelect(existing, kind: kind, url: url, in: windowState)
            tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: existing)
            focusWindowAction(windowState)
            return
        }

        let newTab = openNewTabAction(
            url.absoluteString,
            .foreground(
                windowState: windowState,
                preferredSpaceId: targetSpace?.id,
                loadPolicy: .deferred
            )
        )
        configureSurface(newTab, kind: kind, url: url)
        tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: newTab)
        focusWindowAction(windowState)
    }

    private func resolvedTargetSpace(
        tabManager: TabManager,
        windowState: BrowserWindowState,
        preferredSpaceId: UUID?
    ) -> Space? {
        if let preferredSpaceId,
           let preferredSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.id == preferredSpaceId }) {
            return preferredSpace
        }

        if let windowSpaceId = windowState.currentSpaceId,
           let windowSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        if let profileId = windowState.currentProfileId,
           let profileSpace = tabManager.spaceStateOwner.spaces.first(where: { $0.profileId == profileId }) {
            return profileSpace
        }

        return tabManager.spaceStateOwner.spaces.first
    }

    private func configureAndSelect(
        _ tab: Tab,
        kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState
    ) {
        configureSurface(tab, kind: kind, url: url)
        selectTabAction(tab, windowState)
    }

    private func configureSurface(
        _ tab: Tab,
        kind: SumiNativeBrowserSurfaceKind,
        url: URL
    ) {
        kind.configure(tab, url: url)
        applySettingsSurfaceNavigationIfNeeded(kind, url: url)
    }

    private func applySettingsSurfaceNavigationIfNeeded(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL
    ) {
        guard case .settings = kind else { return }
        settingsAction()?.applyNavigationFromSettingsSurfaceURL(url)
    }
}
