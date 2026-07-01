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
    struct Dependencies {
        let auxiliaryWindowManager: AuxiliaryWindowManager
        let bookmarkManager: SumiBookmarkManager
        let extensionsModule: SumiExtensionsModule
        let faviconService: any BrowserFaviconServicing
        let historyManager: HistoryManager
        let tabManager: TabManager
        let showProfileSwitchToast: @MainActor (Profile, BrowserWindowState?) -> Void
        let runAutomaticPermissionCleanupIfNeeded: @MainActor (Profile?) async -> Void
        let scheduleAutomaticBrowsingDataCleanup: @MainActor (String) -> Void
    }

    actor ProfileOps {
        func run(_ body: @MainActor () -> Bool) async -> Bool {
            await body()
        }
    }

    private unowned let host: BrowserProfileSwitchTransitionHost
    private let dependencies: Dependencies
    private let profileOps = ProfileOps()

    init(
        host: BrowserProfileSwitchTransitionHost,
        dependencies: Dependencies
    ) {
        self.host = host
        self.dependencies = dependencies
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
                dependencies.showProfileSwitchToast(
                    profile,
                    targetWindowState
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
        await dependencies.runAutomaticPermissionCleanupIfNeeded(profile)
        dependencies.scheduleAutomaticBrowsingDataCleanup("profile-switch")
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
        dependencies.auxiliaryWindowManager.closeAll(reason: .profileSwitch)
        host.isTransitioningProfile = animateTransition
        host.currentProfile = profile
        windowState?.currentProfileId = profile.id
        dependencies.bookmarkManager.setFaviconPrefetchPartition(
            dependencies.faviconService.partition(profile: profile)
        )
        dependencies.extensionsModule.switchProfileIfLoaded(profile)
        dependencies.historyManager.switchProfile(profile.id)
        dependencies.tabManager.handleProfileSwitch(contextWindowId: windowState?.id)
    }
}

extension BrowserManager: BrowserProfileSwitchTransitionHost {}

extension BrowserProfileSwitchTransitionOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            auxiliaryWindowManager: browserManager.auxiliaryWindowManager,
            bookmarkManager: browserManager.bookmarkManager,
            extensionsModule: browserManager.extensionsModule,
            faviconService: browserManager.dataServices.faviconService,
            historyManager: browserManager.historyManager,
            tabManager: browserManager.tabManager,
            showProfileSwitchToast: { [weak browserManager] profile, windowState in
                browserManager?.toastPresenter.showProfileSwitchToast(
                    to: profile,
                    in: windowState
                )
            },
            runAutomaticPermissionCleanupIfNeeded: { [weak browserManager] profile in
                _ = await browserManager?.automaticDataCleanupOwner
                    .runAutomaticPermissionCleanupIfNeeded(for: profile)
            },
            scheduleAutomaticBrowsingDataCleanup: { [weak browserManager] reason in
                browserManager?.automaticDataCleanupOwner.scheduleAutomaticBrowsingDataCleanup(
                    reason: reason
                )
            }
        )
    }
}
