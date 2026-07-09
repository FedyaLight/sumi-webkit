//
//  SpaceSidebarChromeBindings.swift
//  Sumi
//
//

import SwiftUI

/// Pure chrome binding helpers extracted from `SpacesSideBarView` so the
/// sidebar shell can shrink without changing observation topology.
@MainActor
enum SpaceSidebarChromeBindings {
    static func shouldMountMiniPlayer(
        sidebarMiniPlayerEnabled: Bool,
        nowPlayingController: SumiNativeNowPlayingController,
        windowState: BrowserWindowState
    ) -> Bool {
        guard sidebarMiniPlayerEnabled else { return false }
        return SumiBackgroundMediaCardStore.shouldMountMiniPlayer(
            globalState: nowPlayingController.cardState,
            in: windowState
        )
    }

    static func shouldShowSidebarExtensionGrid(slotCount: Int) -> Bool {
        ExtensionActionPlacement.resolve(totalActions: slotCount) == .sidebarGrid
    }

    static func shouldAnimateEssentialsLayout(
        isActiveWindow: Bool,
        isTransitioningProfile: Bool,
        pageRenderMode: SidebarPageRenderMode,
        allowsInteractiveWork: Bool
    ) -> Bool {
        SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
            isActiveWindow: isActiveWindow,
            isTransitioningProfile: isTransitioningProfile,
            pageRenderMode: pageRenderMode
        ) && allowsInteractiveWork
    }
}

/// Updater strip shown above the mini-player / bottom bar in the sidebar shell.
struct SpaceSidebarUpdateNoticeStrip: View {
    @Environment(\.sidebarPresentationContext) private var sidebarPresentationContext

    let notice: SumiUpdateSidebarNotice
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Group {
            if sidebarPresentationContext.inputMode == .collapsedOverlay {
                HStack {
                    Spacer(minLength: 0)
                    SumiUpdateSidebarCompactIndicator(
                        notice: notice,
                        onUpdate: onUpdate
                    )
                    .disabled(notice.primaryActionTitle == nil)
                }
                .padding(.horizontal, 8)
            } else {
                SumiUpdateSidebarNoticeView(
                    notice: notice,
                    onUpdate: onUpdate,
                    onDismiss: onDismiss
                )
                .padding(.horizontal, 8)
            }
        }
    }
}
