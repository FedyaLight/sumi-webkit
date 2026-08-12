//
//  SpaceSidebarChromeBindings.swift
//  Sumi
//
//

import Foundation
import SumiDomain
import SwiftUI

/// Pure chrome binding helpers extracted from `SpacesSideBarView` so the
/// sidebar shell can shrink without changing observation topology.
@MainActor
enum SpaceSidebarChromeBindings {
    static func shouldShowSidebarExtensionGrid(slotCount: Int) -> Bool {
        ExtensionActionPlacement.resolve(totalActions: slotCount) == .sidebarGrid
    }

    static func shouldAnimateFavoriteLayout(
        isActiveWindow: Bool,
        isTransitioningProfile: Bool,
        pageRenderMode: SidebarPageRenderMode,
        allowsInteractiveWork: Bool
    ) -> Bool {
        SpaceSidebarChromePreviewPolicy.shouldAnimateFavoriteLayout(
            isActiveWindow: isActiveWindow,
            isTransitioningProfile: isTransitioningProfile,
            pageRenderMode: pageRenderMode
        ) && allowsInteractiveWork
    }
}

/// Updater strip shown above the mini-player / bottom bar in the sidebar shell.
struct SpaceSidebarUpdateNoticeStrip: View {
    let notice: SumiUpdateSidebarNotice
    let onUpdate: () -> Void
    let onDismiss: () -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        SumiUpdateSidebarNoticeView(
            notice: notice,
            onUpdate: onUpdate,
            onDismiss: onDismiss,
            onOpenURL: onOpenURL
        )
        .padding(.horizontal, 8)
    }
}

struct SpaceSidebarUpdateNoticeReader: View {
    @ObservedObject var updaterService: SumiUpdaterService
    let browserContext: SidebarBrowserContext

    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        if let notice = updaterService.sidebarNotice {
            SpaceSidebarUpdateNoticeStrip(
                notice: notice,
                onUpdate: { updaterService.startUpdateFromSidebarNotice() },
                onDismiss: { updaterService.dismissSidebarNotice(notice) },
                onOpenURL: openURLInNewTab
            )
        }
    }

    private func openURLInNewTab(_ url: URL) {
        _ = browserContext.tabOpening.openNewTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: windowState.currentSpaceId,
                loadPolicy: .immediate
            )
        )
    }
}

struct SpaceSidebarMiniPlayer: View {
    @ObservedObject var nowPlayingController: SumiNativeNowPlayingController
    let faviconImageReader: any BrowserFaviconImageReading

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var settings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let states = settings.sidebarMiniPlayerEnabled
            ? SumiBackgroundMediaCardProjection.visibleStates(
                    nowPlayingController.cardStates,
                    in: windowState
                )
            : []

        MediaControlsView(
            cardStates: states,
            controller: nowPlayingController,
            faviconImageReader: faviconImageReader
        )
        .zIndex(100)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                nowPlayingController.scheduleRefresh(delayNanoseconds: 0)
            }
        }
        .onChange(of: windowState.currentTabId) { _, _ in
            nowPlayingController.scheduleRefresh(delayNanoseconds: 0)
        }
        .onChange(of: windowState.currentSpaceId) { _, _ in
            nowPlayingController.scheduleRefresh(delayNanoseconds: 0)
        }
    }
}

struct SidebarSpaceCreationProfilesView: View {
    let session: SpaceCreationSession
    let currentProfiles: @MainActor () -> [Profile]
    let profileUpdates: SidebarProfileUpdates
    let isActive: Bool
    let currentProfileID: @MainActor () -> UUID?
    let onThemePreview: @MainActor (WorkspaceTheme) -> Void
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        SidebarScopedSnapshotReader(
            current: currentProfiles,
            changes: profileUpdates.profiles,
            areEquivalent: ==,
            isActive: isActive
        ) { profiles in
            SidebarSpaceCreationView(
                session: session,
                profileContext: SpaceCreationProfileContext(
                    profiles: profiles,
                    currentProfileID: currentProfileID()
                ),
                onThemePreview: onThemePreview,
                onCreate: onCreate,
                onCancel: onCancel
            )
        }
    }
}
