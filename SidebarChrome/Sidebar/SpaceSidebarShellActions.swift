//
//  SpaceSidebarShellActions.swift
//  Sumi
//
//

import SwiftUI

extension SpacesSideBarView {
    // MARK: - Context Menu

    func sidebarContextMenuEntries() -> [SidebarContextMenuEntry] {
        let newFolderAction: (() -> Void)? = browserContext.folderActions
            .canCreateFolderInCurrentSpace(in: windowState) == false
            ? nil
            : {
                browserContext.folderActions.createFolderInCurrentSpace(
                    in: windowState
                )
            }
        let changeThemeAction: (() -> Void)? = spaceLifecycle.currentSpace() == nil
            ? nil
            : {
                browserContext.workspaceThemeEditor.showGradientEditor(
                    source: windowState.resolveSidebarPresentationSource(
                        in: windowRegistry
                    )
                )
            }

        return makeSidebarShellContextMenuEntries(
            isCompactModeEnabled: !windowState.isSidebarVisible,
            actions: .init(
                newTab: {
                    browserContext.floatingBarCommit.openNewTabSurface(
                        in: windowState
                    )
                },
                newFolder: newFolderAction,
                newRSSLiveFolder: newFolderAction.map { _ in
                    {
                        browserContext.folderActions
                            .createRSSLiveFolderInCurrentSpace(in: windowState)
                    }
                },
                newGitHubPullRequestsLiveFolder: newFolderAction.map { _ in
                    {
                        browserContext.folderActions
                            .createGitHubPRFolderInCurrentSpace(in: windowState)
                    }
                },
                newGitHubIssuesLiveFolder: newFolderAction.map { _ in
                    {
                        browserContext.folderActions
                            .createGitHubIssuesFolderInCurrentSpace(in: windowState)
                    }
                },
                changeTheme: changeThemeAction,
                toggleCompactMode: {
                    browserContext.sidebarPresentation.toggleSidebar(for: windowState)
                },
                openSettings: {
                    browserContext.settingsNavigation.openSettings(
                        selecting: .appearance,
                        in: windowState
                    )
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
            ?? browserContext.profileAuthority.currentProfile?.id
            ?? browserContext.profileManager.profiles.first?.id

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
            do {
                let createdProfile = try browserContext.profileManager.createProfile(
                    name: session.trimmedNewProfileName,
                    icon: session.resolvedNewProfileIcon
                )
                profileId = createdProfile.id
            } catch {
                RuntimeDiagnostics.emit(
                    "[ProfileManager] Space profile creation failed: \(error)"
                )
                return
            }
        } else {
            profileId = session.profileID
        }

        let newSpace = spaceLifecycle.createSpace(
            name: session.trimmedName,
            icon: session.resolvedIcon,
            profileID: profileId
        )
        if let newSpace,
           let resolvedSpace = spaceLifecycle.space(id: newSpace.id) {
            browserContext.spaceTransitions.setActiveSpace(
                resolvedSpace,
                in: windowState
            )
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
        return !browserContext.profileManager.profiles.contains {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}
