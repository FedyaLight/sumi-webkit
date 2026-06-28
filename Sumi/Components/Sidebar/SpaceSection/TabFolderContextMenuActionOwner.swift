//
//  TabFolderContextMenuActionOwner.swift
//  Sumi
//
//

import AppKit
import SwiftUI

@MainActor
struct TabFolderContextMenuActionOwner {
    let folder: TabFolder
    let space: Space
    let childFoldersByParentId: [UUID: [TabFolder]]
    let folderPinsByFolderId: [UUID: [ShortcutPin]]
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let themeContext: ResolvedThemeContext
    let folderLayoutAnimation: Animation?
    let onUngroup: () -> Void
    let onDelete: () -> Void

    func folderShortcutContextMenuEntries(_ pin: ShortcutPin) -> [SidebarContextMenuEntry] {
        let presentationState = shortcutPresentationState(for: pin)
        let profiles = browserManager.profileManager.profiles
        let folderChoices = makeSidebarContextMenuFolderChoices(
            folders: browserManager.tabManager.folders(for: space.id)
                .filter { !browserManager.liveFolderManager.isLiveFolder($0.id) },
            selectedFolderId: pin.folderId
        )
        let spaceChoices = makeSidebarContextMenuSpaceChoices(
            spaces: browserManager.tabManager.spaces,
            selectedSpaceId: pin.spaceId
        )
        let profileChoices = makeSidebarContextMenuProfileChoices(
            profiles: profiles,
            selectedProfileId: browserManager.tabManager.resolvedExecutionProfileId(
                for: pin,
                currentSpaceId: space.id
            )
        )
        let addToEssentialsAction: (() -> Void)? = browserManager.tabManager.canAddURLToEssentials(
            pin.launchURL,
            using: .init(windowState: windowState, spaceId: space.id)
        )
            ? { pinShortcutGlobally(pin) }
            : nil
        let savedURLDriftActions: SidebarSavedURLDriftActions? =
            browserManager.tabManager.shortcutHasDrifted(pin, in: windowState)
                ? .init(
                    onBackToSavedURL: { resetShortcutPin(pin) },
                    onUseCurrentPageAsSavedURL: { _ = browserManager.tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState) }
                )
                : nil
        let unloadAction: (() -> Void)? = presentationState.isOpenLive
            ? { unloadShortcutPin(pin) }
            : nil

        return makeSidebarTabContextMenuEntries(
            role: .folderPinnedTab,
            actions: .init(
                duplicate: { duplicateShortcutPin(pin) },
                copyLink: { copyLink(pin.launchURL) },
                share: {
                    presentSharePicker(
                        for: pin.launchURL,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                edit: {
                    presentShortcutLinkEditor(
                        for: pin,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                folderTarget: .init(
                    choices: folderChoices,
                    onSelect: { folderId in moveShortcutPin(pin, toFolder: folderId) }
                ),
                moveToSpace: .init(
                    choices: spaceChoices,
                    onSelect: { targetSpaceId in moveShortcutPin(pin, toSpace: targetSpaceId) }
                ),
                profileTarget: .init(
                    choices: profileChoices,
                    onSelect: { profileId in
                        browserManager.tabManager.assign(
                            shortcutPin: pin,
                            toExecutionProfile: profileId
                        )
                    }
                ),
                addToEssentials: addToEssentialsAction,
                savedURLDrift: savedURLDriftActions,
                unload: unloadAction,
                deleteSavedTab: { confirmDeleteShortcutPin(pin) }
            )
        )
    }

    func liveFolderItemContextMenuEntries(_ item: SumiLiveFolderItem) -> [SidebarContextMenuEntry] {
        guard let url = item.url else {
            return []
        }

        return joinSidebarMenuSections(
            [
                [
                    .action(.init(title: "Open", systemImage: "arrow.up.right.square", classification: .presentationOnly) {
                        browserManager.liveFolderManager.open(item: item, in: windowState)
                    }),
                    .action(.init(title: "Copy Link", systemImage: "link", classification: .presentationOnly) {
                        copyLink(url)
                    }),
                    .action(.init(title: "Share…", systemImage: "square.and.arrow.up", classification: .presentationOnly) {
                        presentSharePicker(
                            for: url,
                            source: windowState.resolveSidebarPresentationSource()
                        )
                    }),
                ],
                [
                    .action(.init(title: "Hide Item", systemImage: "xmark", classification: .stateMutationNonStructural) {
                        browserManager.liveFolderManager.dismiss(item: item)
                    }),
                ],
            ]
        )
    }

    func folderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        if currentLiveFolderSource() != nil {
            return liveFolderHeaderContextMenuEntries()
        }

        let unloadActiveTabsAction: (() -> Void)?
        if folderHasLiveSavedTabs {
            unloadActiveTabsAction = unloadActiveFolderTabs
        } else {
            unloadActiveTabsAction = nil
        }

        return makeFolderHeaderContextMenuEntries(
            actions: .init(
                edit: {
                    browserManager.showFolderEditor(
                        for: folder,
                        in: windowState,
                        themeContext: themeContext,
                        source: windowState.resolveSidebarPresentationSource()
                    )
                },
                alphabetize: alphabetizeTabs,
                unloadActiveTabs: unloadActiveTabsAction,
                ungroup: onUngroup,
                delete: onDelete
            )
        )
    }

    func resetShortcutPin(_ pin: ShortcutPin) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? []
        let preserveCurrentPage = modifiers.contains(.command) || modifiers.contains(.control)
        _ = browserManager.tabManager.resetShortcutPinToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }

    func unloadShortcutPin(_ pin: ShortcutPin) {
        if let current = browserManager.tabManager.selectedShortcutLiveTab(for: pin.id, in: windowState) {
            browserManager.closeTab(current, in: windowState)
            return
        }

        browserManager.tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowState.id)
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        mutateFolderContent {
            browserManager.tabManager.removeShortcutPin(pin)
        }
    }

    private func liveFolderHeaderContextMenuEntries() -> [SidebarContextMenuEntry] {
        let source = currentLiveFolderSource()
        let statusTitle: String = {
            if let error = source?.lastErrorKind {
                return error.displayTitle
            }
            if let lastSuccessAt = source?.lastSuccessAt {
                return "Last Updated \(lastSuccessAt.formatted(date: .omitted, time: .shortened))"
            }
            return "Not Updated Yet"
        }()

        let githubLoginSection: [SidebarContextMenuEntry]
        if source?.lastErrorKind == .notAuthenticated,
           source?.kind == .githubPullRequests || source?.kind == .githubIssues {
            githubLoginSection = [
                .action(.init(title: "Sign in to GitHub", systemImage: "person.crop.circle.badge.exclamationmark", classification: .presentationOnly) {
                    browserManager.openNewTab(
                        url: "https://github.com/login",
                        context: .foreground(windowState: windowState, preferredSpaceId: space.id)
                    )
                }),
            ]
        } else {
            githubLoginSection = []
        }

        return joinSidebarMenuSections(
            [
                [
                    .action(.init(title: statusTitle, systemImage: "clock", isEnabled: false, classification: .presentationOnly) {}),
                    .action(.init(title: "Refresh Now", systemImage: "arrow.clockwise", classification: .stateMutationNonStructural) {
                        browserManager.liveFolderManager.refresh(folderId: folder.id)
                    }),
                    refreshIntervalSubmenu(for: source),
                ],
                githubLoginSection,
                [
                    .action(
                        .init(
                            title: "Delete Live Folder",
                            systemImage: "trash",
                            role: .destructive,
                            classification: .structuralMutation,
                            onAction: onDelete
                        )
                    ),
                ],
            ]
        )
    }

    private func refreshIntervalSubmenu(for source: SumiLiveFolderSource?) -> SidebarContextMenuEntry {
        let options: [(title: String, seconds: TimeInterval)] = [
            ("15 Minutes", 15 * 60),
            ("30 Minutes", 30 * 60),
            ("1 Hour", 60 * 60),
            ("6 Hours", 6 * 60 * 60),
        ]
        let currentInterval = source?.refreshIntervalSeconds

        return .submenu(
            title: "Refresh Every",
            systemImage: "timer",
            children: options.map { option in
                .action(
                    .init(
                        title: option.title,
                        systemImage: nil,
                        isEnabled: currentInterval != option.seconds,
                        state: currentInterval == option.seconds ? .on : .off,
                        classification: .stateMutationNonStructural
                    ) {
                        browserManager.liveFolderManager.setRefreshInterval(folderId: folder.id, seconds: option.seconds)
                    }
                )
            }
        )
    }

    private func presentShortcutLinkEditor(
        for pin: ShortcutPin,
        source: SidebarTransientPresentationSource? = nil
    ) {
        browserManager.showShortcutEditor(
            for: pin,
            in: windowState,
            themeContext: themeContext,
            source: source ?? windowState.resolveSidebarPresentationSource()
        )
    }

    private func currentLiveFolderSource() -> SumiLiveFolderSource? {
        browserManager.liveFolderManager.source(for: folder.id)
    }

    private func alphabetizeTabs() {
        withAnimation(folderLayoutAnimation) {
            browserManager.tabManager.alphabetizeFolderPins(folder.id, in: space.id)
        }
    }

    private func shortcutPresentationState(for pin: ShortcutPin) -> ShortcutPresentationState {
        browserManager.tabManager.shortcutPresentationState(for: pin, in: windowState)
    }

    private func activeShortcutTab(for pin: ShortcutPin) -> Tab? {
        browserManager.tabManager.shortcutLiveTab(for: pin.id, in: windowState.id)
    }

    private func confirmDeleteShortcutPin(_ pin: ShortcutPin) {
        SidebarSavedItemDeletionConfirmationPresenter.confirmDeleteSavedTab(
            kind: .pinnedTab,
            title: pin.preferredDisplayTitle,
            url: pin.launchURL,
            window: windowState.window,
            onDelete: { removeShortcutPin(pin) }
        )
    }

    private func mutateFolderContent(_ update: () -> Void) {
        if let animation = folderLayoutAnimation {
            withAnimation(animation, update)
        } else {
            update()
        }
    }

    private func duplicateShortcutPin(_ pin: ShortcutPin) {
        _ = browserManager.openNewTab(
            url: pin.launchURL.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: space.id
            )
        )
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toFolder folderId: UUID) {
        guard let targetFolder = browserManager.tabManager.folder(by: folderId) else { return }
        let targetIndex = browserManager.tabManager.folderPinnedPins(
            for: folderId,
            in: targetFolder.spaceId
        ).count

        mutateFolderContent {
            _ = browserManager.tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetFolder.spaceId,
                folderId: folderId,
                index: targetIndex
            )
        }
    }

    private func moveShortcutPin(_ pin: ShortcutPin, toSpace targetSpaceId: UUID) {
        let targetIndex = browserManager.tabManager.topLevelSpacePinnedItems(for: targetSpaceId).count

        mutateFolderContent {
            _ = browserManager.tabManager.moveShortcutPin(
                pin,
                to: .spacePinned,
                profileId: nil,
                spaceId: targetSpaceId,
                folderId: nil,
                index: targetIndex
            )
        }
    }

    private func pinShortcutGlobally(_ pin: ShortcutPin) {
        let syntheticTab = Tab(
            url: pin.launchURL,
            name: pin.resolvedDisplayTitle(liveTab: activeShortcutTab(for: pin)),
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: space.id,
            index: 0,
            browserManager: browserManager
        )
        browserManager.tabManager.pinTab(
            syntheticTab,
            context: .init(windowState: windowState, spaceId: space.id)
        )
    }

    private var folderHasLiveSavedTabs: Bool {
        folderHasLiveSavedTabsHelper(folderId: folder.id)
    }

    private func folderHasLiveSavedTabsHelper(folderId: UUID) -> Bool {
        if let directPins = folderPinsByFolderId[folderId],
           directPins.contains(where: { browserManager.tabManager.shortcutLiveTab(for: $0.id, in: windowState.id) != nil }) {
            return true
        }
        if let children = childFoldersByParentId[folderId] {
            for child in children {
                if folderHasLiveSavedTabsHelper(folderId: child.id) {
                    return true
                }
            }
        }
        return false
    }

    private var descendantShortcutPins: [ShortcutPin] {
        descendantShortcutPins(in: folder.id, visited: [])
    }

    private func descendantShortcutPins(in folderId: UUID, visited: Set<UUID>) -> [ShortcutPin] {
        guard !visited.contains(folderId) else { return [] }
        var nextVisited = visited
        nextVisited.insert(folderId)

        let directPins = folderPinsByFolderId[folderId] ?? []
        let nestedPins = (childFoldersByParentId[folderId] ?? []).flatMap { childFolder in
            descendantShortcutPins(in: childFolder.id, visited: nextVisited)
        }
        return directPins + nestedPins
    }

    private func unloadActiveFolderTabs() {
        for pin in descendantShortcutPins {
            unloadShortcutPin(pin)
        }
    }

    private func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func presentSharePicker(
        for url: URL,
        source: SidebarTransientPresentationSource? = nil
    ) {
        if let source {
            browserManager.presentSharingServicePicker([url], source: source)
            return
        }

        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }
}
