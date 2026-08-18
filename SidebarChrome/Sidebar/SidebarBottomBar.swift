//
//  SidebarBottomBar.swift
//  Sumi
//
//

import SwiftUI

/// Bottom bar of the sidebar containing downloads, spaces list, and new space button.
struct SidebarBottomBar: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext
    let browserContext: SidebarBrowserContext
    let spaceLifecycle: SidebarSpaceLifecycle
    let visualSelectedSpaceId: UUID?
    let onNewSpaceTap: () -> Void
    let onSelectSpace: (Space) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            DownloadsToolbarButton(
                downloadManager: browserContext.downloadManager,
                popoverPresenter: browserContext.downloadsPopoverPresenter,
                action: {
                    browserContext.downloadsPopoverPresenter.toggle(
                        in: windowState,
                        downloadManager: browserContext.downloadManager
                    )
                }
            )
                .environment(windowState)

            // Hide spaces list in incognito windows (only one ephemeral space)
            if !windowState.isIncognito {
                SpacesList(
                    browserContext: browserContext,
                    spaceLifecycle: spaceLifecycle,
                    visualSelectedSpaceId: visualSelectedSpaceId,
                    onSelectSpace: onSelectSpace
                )
                    .frame(maxWidth: .infinity)
                    .environment(windowState)
            }

            // Hide new space button in incognito windows
            if !windowState.isIncognito {
                newSpaceButton
            }
        }.fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, SidebarChromeMetrics.contentHorizontalPadding)
    }

    private var newSpaceButton: some View {
        Group {
            if presentationContext.inputMode == .collapsedOverlay {
                Button(
                    action: { _ = () },
                    label: {
                    newSpaceButtonLabel
                    }
                )
                .buttonStyle(NavButtonStyle(hoverTracking: .sidebarSession))
                .sidebarAppKitContextMenu(
                    surfaceKind: .button,
                    triggers: [.leftClick, .rightClick],
                    entries: newSpaceMenuEntries
                )
            } else {
                Menu {
                    Button("New Space", systemImage: "plus") {
                        onNewSpaceTap()
                    }

                    Button("New Folder", systemImage: "folder.badge.plus") {
                        createFolderInCurrentSpace()
                    }
                } label: {
                    newSpaceButtonLabel
                }
                .menuStyle(.button)
                .buttonStyle(NavButtonStyle(hoverTracking: .sidebarSession))
            }
        }
    }

    private var newSpaceButtonLabel: some View {
        Label("Actions", systemImage: "plus")
            .labelStyle(.iconOnly)
    }

    private func newSpaceMenuEntries() -> [SidebarContextMenuEntry] {
        [
            .action(
                .init(
                    title: "New Space",
                    systemImage: "plus",
                    classification: .structuralMutation,
                    onAction: onNewSpaceTap
                )
            ),
            .action(
                .init(
                    title: "New Folder",
                    systemImage: "folder.badge.plus",
                    classification: .structuralMutation,
                    onAction: createFolderInCurrentSpace
                )
            ),
        ]
    }

    private func createFolderInCurrentSpace() {
        browserContext.folderActions.createFolderInCurrentSpace(
            in: windowState
        )
    }
}
