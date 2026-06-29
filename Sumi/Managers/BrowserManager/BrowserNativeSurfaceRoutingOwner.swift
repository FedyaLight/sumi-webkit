import AppKit
import Foundation

@MainActor
final class BrowserNativeSurfaceRoutingOwner {
    struct Dependencies {
        let tabManager: @MainActor @Sendable () -> TabManager
        let settings: @MainActor @Sendable () -> SumiSettingsService?
        let openNewTab: @MainActor @Sendable (String, BrowserTabOpenContext) -> Tab
        let selectTab: @MainActor @Sendable (Tab, BrowserWindowState) -> Void
        let focusWindow: @MainActor @Sendable (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID? = nil
    ) {
        let tabManager = dependencies.tabManager()

        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            if let existing = windowState.ephemeralTabs.first(where: { kind.matches($0) }) {
                configureAndSelect(existing, kind: kind, url: url, in: windowState)
            } else {
                let newTab = tabManager.createEphemeralTab(
                    url: url,
                    in: windowState,
                    profile: profile
                )
                configureAndSelect(newTab, kind: kind, url: url, in: windowState)
            }
            dependencies.focusWindow(windowState)
            return
        }

        let targetSpace =
            preferredSpaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }
            ?? windowState.currentSpaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }
            ?? windowState.currentProfileId.flatMap { pid in tabManager.spaces.first(where: { $0.profileId == pid }) }
            ?? tabManager.currentSpace

        let spaceIdForLookup = targetSpace?.id ?? tabManager.currentSpace?.id
        if let sid = spaceIdForLookup,
           let existing = (tabManager.tabsBySpace[sid] ?? []).first(where: { kind.matches($0) }) {
            configureAndSelect(existing, kind: kind, url: url, in: windowState)
            tabManager.scheduleRuntimeStatePersistence(for: existing)
            dependencies.focusWindow(windowState)
            return
        }

        let newTab = dependencies.openNewTab(
            url.absoluteString,
            .foreground(
                windowState: windowState,
                preferredSpaceId: targetSpace?.id,
                loadPolicy: .deferred
            )
        )
        configureSurface(newTab, kind: kind, url: url)
        tabManager.scheduleRuntimeStatePersistence(for: newTab)
        dependencies.focusWindow(windowState)
    }

    private func configureAndSelect(
        _ tab: Tab,
        kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState
    ) {
        configureSurface(tab, kind: kind, url: url)
        dependencies.selectTab(tab, windowState)
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
        dependencies.settings()?.applyNavigationFromSettingsSurfaceURL(url)
    }
}

extension BrowserNativeSurfaceRoutingOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let tabOpeningOwner = browserManager.tabOpeningOwner
        return Self(
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            settings: { [weak browserManager] in browserManager?.sumiSettings },
            openNewTab: { url, context in
                tabOpeningOwner.openNewTab(url: url, context: context)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            focusWindow: { windowState in
                windowState.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        )
    }
}
