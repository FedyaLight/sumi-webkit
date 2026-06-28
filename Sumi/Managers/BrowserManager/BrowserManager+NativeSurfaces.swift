import AppKit
import SwiftUI

@MainActor
enum SumiNativeBrowserSurfaceKind {
    case settings
    case history
    case bookmarks

    func matches(_ tab: Tab) -> Bool {
        switch self {
        case .settings:
            return tab.representsSumiSettingsSurface
        case .history:
            return tab.representsSumiHistorySurface
        case .bookmarks:
            return tab.representsSumiBookmarksSurface
        }
    }

    func configure(_ tab: Tab, url: URL) {
        tab.url = url
        switch self {
        case .settings:
            tab.name = "Settings"
            tab.favicon = Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
        case .history:
            tab.name = "History"
            tab.favicon = Image(systemName: SumiSurface.historyTabFaviconSystemImageName)
        case .bookmarks:
            tab.name = "Bookmarks"
            tab.favicon = Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
        }
        tab.faviconIsTemplateGlobePlaceholder = false
    }
}

@MainActor
extension BrowserManager {
    func openNativeBrowserSurface(
        _ kind: SumiNativeBrowserSurfaceKind,
        url: URL,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID? = nil
    ) {
        if windowState.isIncognito, let profile = windowState.ephemeralProfile {
            if let existing = windowState.ephemeralTabs.first(where: { kind.matches($0) }) {
                kind.configure(existing, url: url)
                applySettingsSurfaceNavigationIfNeeded(kind, url: url)
                selectTab(existing, in: windowState)
            } else {
                let newTab = tabManager.createEphemeralTab(
                    url: url,
                    in: windowState,
                    profile: profile
                )
                kind.configure(newTab, url: url)
                applySettingsSurfaceNavigationIfNeeded(kind, url: url)
                selectTab(newTab, in: windowState)
            }
            focusWindow(windowState)
            return
        }

        let targetSpace =
            preferredSpaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }
            ?? windowState.currentSpaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }
            ?? windowState.currentProfileId.flatMap { pid in tabManager.spaces.first(where: { $0.profileId == pid }) }
            ?? tabManager.currentSpace

        let spaceIdForLookup = targetSpace?.id ?? tabManager.currentSpace?.id
        if let sid = spaceIdForLookup,
           let existing = (tabManager.tabsBySpace[sid] ?? []).first(where: { kind.matches($0) })
        {
            kind.configure(existing, url: url)
            applySettingsSurfaceNavigationIfNeeded(kind, url: url)
            selectTab(existing, in: windowState)
            tabManager.scheduleRuntimeStatePersistence(for: existing)
            focusWindow(windowState)
            return
        }

        let newTab = openNewTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: targetSpace?.id,
                loadPolicy: .deferred
            )
        )
        kind.configure(newTab, url: url)
        applySettingsSurfaceNavigationIfNeeded(kind, url: url)
        tabManager.scheduleRuntimeStatePersistence(for: newTab)
        focusWindow(windowState)
    }

    private func applySettingsSurfaceNavigationIfNeeded(_ kind: SumiNativeBrowserSurfaceKind, url: URL) {
        guard case .settings = kind else { return }
        sumiSettings?.applyNavigationFromSettingsSurfaceURL(url)
    }

    private func focusWindow(_ windowState: BrowserWindowState) {
        windowState.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
