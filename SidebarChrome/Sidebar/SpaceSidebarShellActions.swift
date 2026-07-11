//
//  SpaceSidebarShellActions.swift
//  Sumi
//
//

import SwiftUI

extension SpacesSideBarView {
    // MARK: - Context Menu

    func sidebarContextMenuEntries() -> [SidebarContextMenuEntry] {
        let newFolderAction: (() -> Void)? = browserContext.commands.canCreateFolderInCurrentSpace(windowState) == false
            ? nil
            : {
                browserContext.commands.createFolderInCurrentSpace(windowState)
            }
        let changeThemeAction: (() -> Void)? = pageModel.tabManager.spaceStateOwner.currentSpace == nil
            ? nil
            : {
                browserContext.commands.showGradientEditor(windowState.resolveSidebarPresentationSource(in: windowRegistry))
            }

        return makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: !windowState.isSidebarVisible,
            actions: .init(
                newTab: {
                    browserContext.commands.openNewTabOrFloatingBar(windowState)
                },
                newFolder: newFolderAction,
                newRSSLiveFolder: newFolderAction.map { _ in
                    { browserContext.commands.createRSSLiveFolderInCurrentSpace(windowState) }
                },
                newGitHubPullRequestsLiveFolder: newFolderAction.map { _ in
                    { browserContext.commands.createGitHubPRFolderInCurrentSpace(windowState) }
                },
                newGitHubIssuesLiveFolder: newFolderAction.map { _ in
                    { browserContext.commands.createGitHubIssuesFolderInCurrentSpace(windowState) }
                },
                changeTheme: changeThemeAction,
                toggleCompactMode: {
                    browserContext.commands.toggleSidebar(windowState)
                },
                openSettings: {
                    browserContext.commands.openAppearanceSettings(windowState)
                }
            )
        )
    }
    // MARK: - Space Creation

    var spaceCreationTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        )
    }

    func beginSpaceCreationMode() {
        let source = windowState.resolveSidebarPresentationSource(in: windowRegistry)
        let defaultProfileID = windowState.currentProfileId
            ?? browserContext.currentProfile()?.id
            ?? pageModel.profileManager.profiles.first?.id

        windowState.spaceCreationSession.begin(
            source: source,
            previousSpaceID: windowState.currentSpaceId,
            defaultProfileID: defaultProfileID
        )
    }

    func commitSpaceCreationSession(_ session: SpaceCreationSession) {
        guard session.canCommit else { return }

        let profileId: UUID?
        if session.createsNewProfile {
            guard isNewProfileNameAvailable(for: session) else { return }
            let createdProfile = pageModel.profileManager.createProfile(
                name: session.trimmedNewProfileName,
                icon: session.resolvedNewProfileIcon
            )
            profileId = createdProfile.id
        } else {
            profileId = session.profileID
        }

        let newSpace = pageModel.tabManager.spaceServices.catalog.createSpace(
            name: session.trimmedName,
            icon: session.resolvedIcon,
            profileId: profileId
        )
        if let resolvedSpace = pageModel.tabManager.spaceStateOwner.space(with: newSpace.id) {
            browserContext.spaceTransitions.setActiveSpace(resolvedSpace, windowState)
        }

        windowState.spaceCreationSession.finish(
            session,
            reason: "SpacesSideBarView.commitSpaceCreationSession"
        )
    }

    func cancelSpaceCreationSession(_ session: SpaceCreationSession) {
        session.cancelsOnDismiss = true
        windowState.spaceCreationSession.finish(
            session,
            reason: "SpacesSideBarView.cancelSpaceCreationSession"
        )
    }

    func isNewProfileNameAvailable(for session: SpaceCreationSession) -> Bool {
        let trimmed = session.trimmedNewProfileName
        guard !trimmed.isEmpty else { return false }
        return !pageModel.profileManager.profiles.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

}
