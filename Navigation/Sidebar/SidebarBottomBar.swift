//
//  SidebarBottomBar.swift
//  Sumi
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI

/// Bottom bar of the sidebar containing downloads, spaces list, and new space button.
struct SidebarBottomBar: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarPresentationContext) private var presentationContext
    let visualSelectedSpaceId: UUID?
    let onNewSpaceTap: () -> Void
    let onSelectSpace: (Space) -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            DownloadsToolbarButton()
                .environmentObject(browserManager)
                .environment(windowState)
            
            // Hide spaces list in incognito windows (only one ephemeral space)
            if !windowState.isIncognito {
                SpacesList(
                    visualSelectedSpaceId: visualSelectedSpaceId,
                    onSelectSpace: onSelectSpace
                )
                    .frame(maxWidth: .infinity)
                    .environmentObject(browserManager)
                    .environment(windowState)
            }
            
            // Hide new space button in incognito windows
            if !windowState.isIncognito {
                newSpaceButton
            }
        }.fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
    }

    private var newSpaceButton: some View {
        Group {
            if presentationContext.inputMode == .collapsedOverlay {
                Button(action: {}) {
                    newSpaceButtonLabel
                }
                .buttonStyle(NavButtonStyle())
                .sidebarAppKitContextMenu(
                    surfaceKind: .button,
                    triggers: [.leftClick, .rightClick],
                    entries: newSpaceMenuEntries
                )
            } else {
                Menu {
                    Button("New Space", systemImage: "square.grid.2x2") {
                        onNewSpaceTap()
                    }

                    Button("New Folder", systemImage: "folder.badge.plus") {
                        createFolderInCurrentSpace()
                    }
                } label: {
                    newSpaceButtonLabel
                }
                .menuStyle(.button)
                .buttonStyle(NavButtonStyle())
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
                    systemImage: "square.grid.2x2",
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
        if let currentSpace = windowState.currentSpaceId
            .flatMap({ id in browserManager.tabManager.spaces.first(where: { $0.id == id }) })
            ?? browserManager.tabManager.currentSpace {
            _ = browserManager.tabManager.createFolder(for: currentSpace.id)
        }
    }
}
