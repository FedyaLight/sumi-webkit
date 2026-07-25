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
                    browserContext.commandPaletteCommit.openNewTabSurface(
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
        let defaultTheme = SumiWorkspaceThemePresets.rotatingTheme(
            at: spaceLifecycle.availableSpaces(
                isIncognito: windowState.isIncognito,
                ephemeralSpaces: windowState.ephemeralSpaces
            ).count
        )

        let session = windowState.spaceCreationSession.begin(
            source: source,
            previousSpaceID: windowState.currentSpaceId,
            reservedSpaceID: UUID(),
            defaultProfileID: defaultProfileID,
            workspaceTheme: defaultTheme,
            originalWorkspaceTheme: windowState.workspaceTheme
        )
        browserContext.spaceTransitions.previewWorkspaceTheme(
            session.workspaceTheme,
            in: windowState
        )
    }

    func commitSpaceCreationSession(_ session: SpaceCreationSession) {
        guard session.canCommit else { return }

        let profileId: UUID?
        if session.createsNewProfile {
            guard isNewProfileNameAvailable(for: session) else { return }
            do {
                let createdProfile = try browserContext.profileManager.createProfile(
                    name: session.trimmedNewProfileName
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

        guard let newSpace = spaceLifecycle.createSpace(
            id: session.reservedSpaceID,
            name: session.trimmedName,
            icon: session.resolvedIcon,
            workspaceTheme: session.workspaceTheme,
            profileID: profileId
        ), let resolvedSpace = spaceLifecycle.space(id: newSpace.id)
        else { return }
        browserContext.spaceTransitions.setActiveSpace(
            resolvedSpace,
            in: windowState
        )

        windowState.spaceCreationSession.finish(
            session,
            reason: "SpacesSideBarView.commitSpaceCreationSession"
        )
    }

    func cancelSpaceCreationSession(_ session: SpaceCreationSession) {
        session.cancelsOnDismiss = true
        let restoredTheme = session.previousSpaceID
            .flatMap { spaceLifecycle.space(id: $0)?.workspaceTheme }
            ?? session.originalWorkspaceTheme
        browserContext.spaceTransitions.previewWorkspaceTheme(
            restoredTheme,
            in: windowState
        )
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
