import Foundation

/// Prepares the native shell/profile side of a WebKit child-window creation.
/// The physical Tab/WebView installer is injected and must settle before the
/// shell can be constructed or published.
@MainActor
final class WebKitChildWindowShellTransaction {
    private weak var commands: BrowserWindowCommands?
    private weak var restoration: WindowSessionRestoreService?
    private weak var profiles: ProfileManager?
    private weak var tabs: TabManager?

    init(
        commands: BrowserWindowCommands,
        restoration: WindowSessionRestoreService,
        profiles: ProfileManager,
        tabs: TabManager
    ) {
        self.commands = commands
        self.restoration = restoration
        self.profiles = profiles
        self.tabs = tabs
    }

    func create(
        source: PhysicalWebViewSourceReceipt,
        activate: Bool,
        installChild: @escaping @MainActor (BrowserWindowState) -> Bool,
        validateChildBeforePublication: @escaping @MainActor (
            BrowserWindowState
        ) -> Bool,
        discardChild: @escaping @MainActor (BrowserWindowState) -> Void
    ) -> BrowserWindowState? {
        guard let commands, let restoration, let profiles, let tabs else {
            return nil
        }
        let isPrivate = source.residence == .privateEphemeral
        if isPrivate {
            guard source.window.isIncognito,
                  source.window.ephemeralProfile
                    === source.executionProfile,
                  source.presentationProfile === source.executionProfile
            else {
                return nil
            }
        } else {
            guard source.window.isIncognito == false,
                  source.window.currentSpaceId
                    == source.presentationSpace.id,
                  source.window.currentProfileId
                    == source.presentationProfile.id,
                  tabs.spaceStateOwner.space(
                      with: source.presentationSpace.id
                  ) === source.presentationSpace,
                  source.presentationSpace.profileId
                    == source.presentationProfile.id else {
                return nil
            }
        }

        var childInstalled = false
        var sharedPrivateProfile: Profile?
        return commands.createPreparedWindow(
            initialize: { target in
                if isPrivate {
                    guard let profile = profiles.shareEphemeralProfile(
                        from: source.window.id,
                        with: target.id
                    ), profile === source.executionProfile else {
                        return
                    }
                    sharedPrivateProfile = profile
                    Self.preparePrivateWindow(
                        target,
                        profile: profile,
                        tabs: tabs
                    )
                } else {
                    guard restoration.prepareContextualWindowWithInitialTab(
                        profileID: source.presentationProfile.id,
                        spaceID: source.presentationSpace.id,
                        initialTabExecutionProfileID:
                            source.executionProfile.id,
                        forRegistration: target
                    ) else {
                        return
                    }
                }
                childInstalled = installChild(target)
            },
            validateBeforeShell: { _ in childInstalled },
            validateBeforePublication: {
                $0.restorationState.isAwaitingInitialResolution == false
                    && $0.currentTabId != nil
                    && validateChildBeforePublication($0)
            },
            discardPreparedState: { target in
                discardChild(target)
                if let sharedPrivateProfile {
                    _ = profiles.cancelEphemeralProfileShare(
                        for: target.id,
                        expected: sharedPrivateProfile
                    )
                } else {
                    restoration.cancelPreparedWindowRegistration(target)
                }
            },
            activate: activate
        )
    }

    private static func preparePrivateWindow(
        _ window: BrowserWindowState,
        profile: Profile,
        tabs: TabManager
    ) {
        window.isIncognito = true
        window.ephemeralProfile = profile
        window.currentProfileId = profile.id
        let space = Space(
            id: UUID(),
            name: "Incognito",
            icon: "🕶️",
            profileId: profile.id
        )
        space.isEphemeral = true
        window.replaceEphemeralSpaces([space])
        window.currentSpaceId = space.id
        window.tabManager = tabs
    }
}
