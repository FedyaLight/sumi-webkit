import Foundation
import WebKit

/// Creates a link window as one model/shell publication transaction. The
/// initial Tab and its profile partition exist before WindowRegistry observers
/// can see the window; every pre-publication mutation has a matching rollback.
@MainActor
final class BrowserLinkWindowTransaction {
    private enum Residence {
        case regular(
            spaceID: UUID,
            presentationProfileID: UUID,
            executionProfileID: UUID,
            tabProfileID: UUID?
        )
        case ephemeral(receipt: BrowserLinkPrivateWindowRollbackReceipt)
    }

    private weak var commands: BrowserWindowCommands?
    private weak var restoration: WindowSessionRestoreService?
    private weak var extensionPublication:
        WindowExtensionPublicationTransaction?
    private weak var profiles: ProfileManager?
    private weak var tabs: TabManager?
    private let persistWindow: @MainActor (BrowserWindowState) -> Void
    private let materialize: @MainActor (
        Tab,
        BrowserWindowState
    ) -> FocusableWKWebView?

    init(
        commands: BrowserWindowCommands,
        restoration: WindowSessionRestoreService,
        extensionPublication: WindowExtensionPublicationTransaction,
        profiles: ProfileManager,
        tabs: TabManager,
        persistWindow: @escaping @MainActor (BrowserWindowState) -> Void,
        materialize: @escaping @MainActor (
            Tab,
            BrowserWindowState
        ) -> FocusableWKWebView?
    ) {
        self.commands = commands
        self.restoration = restoration
        self.extensionPublication = extensionPublication
        self.profiles = profiles
        self.tabs = tabs
        self.persistWindow = persistWindow
        self.materialize = materialize
    }

    func open(
        _ url: URL,
        from source: PhysicalWebViewSourceReceipt,
        activate: Bool
    ) -> BrowserWindowState? {
        guard let commands, let restoration, let profiles, let tabs else {
            return nil
        }

        let regularSource: PhysicalWebViewSourceReceipt?
        if source.residence == .privateEphemeral {
            guard source.window.isIncognito,
                  source.window.ephemeralProfile === source.executionProfile,
                  source.presentationProfile === source.executionProfile,
                  source.dataStore === source.executionProfile.dataStore
            else { return nil }
            regularSource = nil
        } else {
            guard source.window.isIncognito == false,
                  source.presentationSpace.profileId
                  == source.presentationProfile.id,
                  source.window.currentSpaceId == source.presentationSpace.id,
                  source.window.currentProfileId
                  == source.presentationProfile.id,
                  source.dataStore === source.executionProfile.dataStore
            else { return nil }
            regularSource = source
        }

        if source.webView.owningTab !== source.tab {
            return nil
        }

        if source.residence == .privateEphemeral {
            guard source.tab.profileId == source.executionProfile.id else {
                return nil
            }
        }

        var initialTab: Tab?
        var residence: Residence?
        var initialWebView: FocusableWKWebView?
        var didStageExtensionPublication = false
        var didPrepareContextualWindow = false
        let targetWindow = commands.createPreparedWindow(
            initialize: { target in
                if let regularSource {
                    guard let space = tabs.spaceStateOwner.space(
                        with: regularSource.presentationSpace.id
                    ), space === regularSource.presentationSpace,
                    space.profileId
                    == regularSource.presentationProfile.id else {
                        return
                    }
                    let tab = tabs.regularTabLifecycleOwner.createNewTab(
                        url: url.absoluteString,
                        in: space,
                        activate: false,
                        executionProfileID:
                        regularSource.descendantProfileID
                    )
                    let effectiveExecutionProfileID = tab.profileId
                        ?? regularSource.presentationProfile.id
                    initialTab = tab
                    residence = .regular(
                        spaceID: space.id,
                        presentationProfileID:
                        regularSource.presentationProfile.id,
                        executionProfileID: effectiveExecutionProfileID,
                        tabProfileID: tab.profileId
                    )
                    guard restoration.prepareContextualWindowWithInitialTab(
                        profileID: regularSource.presentationProfile.id,
                        spaceID: regularSource.presentationSpace.id,
                        initialTabExecutionProfileID:
                        effectiveExecutionProfileID,
                        forRegistration: target
                    ) else {
                        return
                    }
                    didPrepareContextualWindow = true
                    _ = WindowTabSelectionStateApplicator.apply(
                        tab,
                        to: target,
                        updateSpaceFromTab: true,
                        rememberSelection: true
                    )
                } else {
                    let profile = profiles.createEphemeralProfile(for: target.id)
                    let space = Self.preparePrivateWindow(
                        target,
                        profile: profile,
                        tabs: tabs
                    )
                    let tab = tabs.ephemeralLifecycleOwner.createEphemeralTab(
                        url: url,
                        in: target,
                        profile: profile
                    )
                    initialTab = tab
                    residence = .ephemeral(
                        receipt: BrowserLinkPrivateWindowRollbackReceipt(
                            window: target,
                            profile: profile,
                            space: space,
                            tab: tab,
                            tabs: tabs
                        )
                    )
                }
            },
            validateBeforeShell: { target in
                guard let initialTab, let residence else { return false }
                return Self.validate(
                    initialTab,
                    residence: residence,
                    in: target,
                    tabs: tabs,
                    profiles: profiles
                )
            },
            validateBeforePublication: { target in
                guard target.restorationState.isAwaitingInitialResolution == false,
                      let initialTab,
                      let residence
                else {
                    return false
                }
                guard Self.validate(
                    initialTab,
                    residence: residence,
                    in: target,
                    tabs: tabs,
                    profiles: profiles
                ) else {
                    return false
                }

                if initialWebView == nil {
                    initialWebView = self.materialize(initialTab, target)
                }
                guard let initialWebView else { return false }
                guard case .regular = residence else { return true }
                guard let extensionPublication = self.extensionPublication else {
                    return false
                }
                if didStageExtensionPublication == false {
                    switch extensionPublication.stageInitialTab(
                        initialTab,
                        webView: initialWebView,
                        in: target,
                        reason: "BrowserLinkWindowTransaction.open"
                    ) {
                    case .extensionPrepared, .nativeOnly, .suppressed:
                        didStageExtensionPublication = true
                    case .rejected:
                        return false
                    }
                }
                return extensionPublication
                    .validateStagedInitialTab(
                        initialTab,
                        webView: initialWebView,
                        in: target
                    )
            },
            discardPreparedState: { [weak self] target in
                if let initialTab, let residence {
                    self?.discard(
                        initialTab,
                        residence: residence,
                        from: target
                    )
                } else if didPrepareContextualWindow {
                    restoration.cancelPreparedWindowRegistration(target)
                }
            },
            activate: activate
        )

        guard let targetWindow, initialTab != nil else { return nil }
        persistWindow(targetWindow)
        precondition(initialWebView != nil)
        targetWindow.compositorInvalidation.refresh()
        return targetWindow
    }

    private static func preparePrivateWindow(
        _ window: BrowserWindowState,
        profile: Profile,
        tabs: TabManager
    ) -> Space {
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
        return space
    }

    private static func validate(
        _ tab: Tab,
        residence: Residence,
        in window: BrowserWindowState,
        tabs: TabManager,
        profiles: ProfileManager
    ) -> Bool {
        guard window.currentTabId == tab.id else { return false }
        switch residence {
        case .regular(
            let spaceID,
            let presentationProfileID,
            let executionProfileID,
            let tabProfileID
        ):
            guard window.isIncognito == false,
                  tab.spaceId == spaceID,
                  window.currentSpaceId == spaceID,
                  let profileID = tabs.spaceStateOwner.profileId(for: spaceID),
                  profileID == presentationProfileID,
                  window.currentProfileId == presentationProfileID,
                  (tab.profileId ?? presentationProfileID)
                  == executionProfileID,
                  tab.profileId == tabProfileID
            else {
                return false
            }
            return tabs.regularTabCollectionOwner
                .tabs(in: spaceID)
                .contains(where: { $0 === tab })
        case .ephemeral(let receipt):
            return receipt.tab === tab
                && receipt.admits(
                    window,
                    tabs: tabs,
                    profiles: profiles
                )
        }
    }

    private func discard(
        _ tab: Tab,
        residence: Residence,
        from window: BrowserWindowState
    ) {
        guard let tabs, let profiles else { return }
        switch residence {
        case .regular(let spaceID, _, _, _):
            guard let admission = ExactTabResidenceAdmission.regular(
                tab,
                in: spaceID,
                tabs: tabs
            ) else { return }
            tabs.structuralPersistence.cancelRuntimeStatePersistence(for: tab.id)
            tab.performComprehensiveWebViewCleanup()
            guard admission.remove(
                tabs: tabs,
                currentSpaceID: window.currentSpaceId
            ) else { return }
            if window.currentTabId == tab.id {
                window.currentTabId = nil
            }
            tabs.tabCollectionMembershipOwner.detach(tab)
            tabs.structuralPersistence.scheduleStructuralPersistence()
            restoration?.cancelPreparedWindowRegistration(window)
        case .ephemeral(let receipt):
            guard receipt.tab === tab,
                  receipt.admits(window, tabs: tabs, profiles: profiles)
            else { return }
            tabs.structuralPersistence.cancelRuntimeStatePersistence(for: tab.id)
            tab.performComprehensiveWebViewCleanup()
            guard receipt.commitRollbackAggregate(
                in: window,
                tabs: tabs,
                profiles: profiles
            ) else {
                return
            }
            // This exact-CAS lease cancellation is the only effect after
            // deferred inventory publication. A subscriber may already have
            // installed a replacement aggregate; its different profile object
            // cannot be cancelled by this stale receipt.
            _ = profiles.cancelEphemeralProfileCreation(
                for: window.id,
                expected: receipt.profile
            )
        }
    }
}
