import AppKit
import SwiftUI

@MainActor
protocol BrowserProfileSwitchTransitionHost: AnyObject {
    var currentProfile: Profile? { get set }
    var isTransitioningProfile: Bool { get set }
    var windowRegistry: WindowRegistry? { get }
}

@MainActor
final class BrowserProfileSwitchTransitionOwner {
    actor ProfileOps {
        func run(_ body: @MainActor () -> Bool) async -> Bool {
            await body()
        }
    }

    private unowned let host: BrowserProfileSwitchTransitionHost
    private let auxiliaryWindowManager: AuxiliaryWindowManager
    private let bookmarkManager: SumiBookmarkManager
    private let extensionsModule: SumiExtensionsModule
    private let faviconService: any BrowserFaviconServicing
    private let historyManager: HistoryManager
    private let tabManager: TabManager
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?
    private let runAutomaticPermissionCleanupIfNeeded: @MainActor (Profile?) async -> Void
    private let scheduleAutomaticBrowsingDataCleanup: @MainActor (String) -> Void
    private let profileOps = ProfileOps()

    init(
        host: BrowserProfileSwitchTransitionHost,
        auxiliaryWindowManager: AuxiliaryWindowManager,
        bookmarkManager: SumiBookmarkManager,
        extensionsModule: SumiExtensionsModule,
        faviconService: any BrowserFaviconServicing,
        historyManager: HistoryManager,
        tabManager: TabManager,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?,
        runAutomaticPermissionCleanupIfNeeded: @escaping @MainActor (Profile?) async -> Void,
        scheduleAutomaticBrowsingDataCleanup: @escaping @MainActor (String) -> Void
    ) {
        self.host = host
        self.auxiliaryWindowManager = auxiliaryWindowManager
        self.bookmarkManager = bookmarkManager
        self.extensionsModule = extensionsModule
        self.faviconService = faviconService
        self.historyManager = historyManager
        self.tabManager = tabManager
        self.notifications = notifications
        self.runAutomaticPermissionCleanupIfNeeded = runAutomaticPermissionCleanupIfNeeded
        self.scheduleAutomaticBrowsingDataCleanup = scheduleAutomaticBrowsingDataCleanup
    }

    func switchToProfile(
        _ profile: Profile,
        context: BrowserManager.ProfileSwitchContext,
        in windowState: BrowserWindowState?
    ) async {
        let targetWindowState = windowState ?? host.windowRegistry?.activeWindow
        let shouldRunCleanup = await profileOps.run { [weak self] in
            guard let self else { return false }
            let host = self.host
            guard self.canApplyProfileSwitch(
                context: context,
                targetWindowState: targetWindowState
            ) else { return false }

            let previousProfile = host.currentProfile
            RuntimeDiagnostics.emit {
                "🔀 [BrowserManager] Switching to profile: \(profile.name) (\(profile.id.uuidString)) from: \(previousProfile?.name ?? "none")"
            }

            let animateTransition = context.shouldAnimateTransition
            let performUpdates = {
                self.applyProfileSwitchUpdates(
                    profile,
                    in: targetWindowState,
                    animateTransition: animateTransition
                )
            }

            if animateTransition {
                withAnimation(.easeInOut(duration: 0.35)) {
                    performUpdates()
                }
            } else {
                performUpdates()
            }

            if context.shouldProvideFeedback {
                notifications()?.presentProfileSwitchNotification(
                    to: profile,
                    in: targetWindowState
                )
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .generic,
                    performanceTime: .drawCompleted
                )
            }

            if animateTransition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak host] in
                    host?.isTransitioningProfile = false
                }
            }

            return true
        }

        guard shouldRunCleanup else { return }
        await runAutomaticPermissionCleanupIfNeeded(profile)
        scheduleAutomaticBrowsingDataCleanup("profile-switch")
    }

    private func canApplyProfileSwitch(
        context: BrowserManager.ProfileSwitchContext,
        targetWindowState: BrowserWindowState?
    ) -> Bool {
        switch context {
        case .userInitiated, .recovery:
            return true
        case .windowActivation, .spaceChange:
            guard let targetWindowState,
                  let windowRegistry = host.windowRegistry,
                  let registeredWindow = windowRegistry.windows[targetWindowState.id],
                  registeredWindow === targetWindowState,
                  windowRegistry.activeWindow === targetWindowState
            else {
                RuntimeDiagnostics.emit {
                    let targetId = targetWindowState?.id.uuidString ?? "nil"
                    return "⏳ [BrowserManager] Ignoring stale profile switch for \(context): targetWindow=\(targetId)"
                }
                return false
            }
            return true
        }
    }

    private func applyProfileSwitchUpdates(
        _ profile: Profile,
        in windowState: BrowserWindowState?,
        animateTransition: Bool
    ) {
        let host = self.host
        auxiliaryWindowManager.closeAll(reason: .profileSwitch)
        host.isTransitioningProfile = animateTransition
        host.currentProfile = profile
        windowState?.currentProfileId = profile.id
        bookmarkManager.setFaviconPrefetchPartition(
            faviconService.partition(profile: profile)
        )
        extensionsModule.switchProfileIfLoaded(profile)
        historyManager.switchProfile(profile.id)
        tabManager.profileAssignmentOwner.handleProfileSwitch(contextWindowId: windowState?.id)
    }
}

extension BrowserManager: BrowserProfileSwitchTransitionHost {}
