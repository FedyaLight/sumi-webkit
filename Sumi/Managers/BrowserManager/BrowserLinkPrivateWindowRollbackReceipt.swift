import Foundation

/// Complete unpublished private-window aggregate captured before WebView
/// materialization. Rollback is admitted only while every physical object and
/// selection field still describes that same transaction.
@MainActor
struct BrowserLinkPrivateWindowRollbackReceipt {
    let window: BrowserWindowState
    let windowID: UUID
    let profile: Profile
    let space: Space
    let tab: Tab
    let residences: BrowserTabResidenceAuthority
    let childWindowIdentity: WebKitChildWindowIdentity?

    init(
        window: BrowserWindowState,
        profile: Profile,
        space: Space,
        tab: Tab,
        residences: BrowserTabResidenceAuthority
    ) {
        self.window = window
        windowID = window.id
        self.profile = profile
        self.space = space
        self.tab = tab
        self.residences = residences
        childWindowIdentity = window.webKitChildWindowIdentity
    }

    func admits(
        _ candidateWindow: BrowserWindowState,
        profiles: ProfileManager
    ) -> Bool {
        candidateWindow === window
            && candidateWindow.id == windowID
            && candidateWindow.isIncognito
            && residences.owns(candidateWindow)
            && profiles.hasEphemeralProfileLease(
                profile,
                forWindowID: windowID
            )
            && candidateWindow.ephemeralProfile === profile
            && candidateWindow.currentProfileId == profile.id
            && candidateWindow.currentSpaceId == space.id
            && candidateWindow.currentTabId == tab.id
            && candidateWindow.webKitChildWindowIdentity
            == childWindowIdentity
            && candidateWindow.ephemeralSpaces.count == 1
            && candidateWindow.ephemeralSpaces.first === space
            && candidateWindow.ephemeralTabs.count == 1
            && candidateWindow.ephemeralTabs.first === tab
            && space.isEphemeral
            && space.profileId == profile.id
            && tab.spaceId == nil
            && tab.profileId == profile.id
    }

    @discardableResult
    func commitRollbackAggregate(
        in candidateWindow: BrowserWindowState,
        profiles: ProfileManager
    ) -> Bool {
        guard admits(candidateWindow, profiles: profiles) else {
            return false
        }
        return residences.rollbackUnpublishedPrivateAggregate(
            in: candidateWindow,
            expectedProfile: profile,
            expectedSpace: space,
            expectedTab: tab,
            expectedChildWindowIdentity: childWindowIdentity
        )
    }
}
