import AppKit
import SwiftUI

@MainActor
protocol BrowserProfileSwitchTransitionHost: AnyObject {
    var currentProfile: Profile? { get set }
    var isSwitchingProfile: Bool { get set }
    var isTransitioningProfile: Bool { get set }
    var windowRegistry: WindowRegistry? { get }

    func showProfileSwitchToast(to profile: Profile, in windowState: BrowserWindowState?)
    func runAutomaticPermissionCleanupIfNeeded(
        for profile: Profile?
    ) async -> SumiPermissionCleanupResult?
    func scheduleAutomaticBrowsingDataCleanup(
        reason: String,
        force: Bool,
        delayNanoseconds: UInt64?
    )
}

@MainActor
final class BrowserProfileSwitchTransitionOwner {
    struct Dependencies {
        let auxiliaryWindowManager: AuxiliaryWindowManager
        let bookmarkManager: SumiBookmarkManager
        let extensionsModule: SumiExtensionsModule
        let historyManager: HistoryManager
        let tabManager: TabManager
    }

    actor ProfileOps {
        func run(_ body: @MainActor () async -> Void) async {
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
        await profileOps.run { [weak self] in
            guard let self else { return }
            let host = self.host
            if host.isSwitchingProfile {
                RuntimeDiagnostics.emit {
                    "⏳ [BrowserManager] Ignoring concurrent profile switch request"
                }
                return
            }
            host.isSwitchingProfile = true
            defer { host.isSwitchingProfile = false }

            let previousProfile = host.currentProfile
            RuntimeDiagnostics.emit {
                "🔀 [BrowserManager] Switching to profile: \(profile.name) (\(profile.id.uuidString)) from: \(previousProfile?.name ?? "none")"
            }

            let animateTransition = context.shouldAnimateTransition
            let performUpdates = {
                self.applyProfileSwitchUpdates(
                    profile,
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
                host.showProfileSwitchToast(
                    to: profile,
                    in: windowState ?? host.windowRegistry?.activeWindow
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

            await host.runAutomaticPermissionCleanupIfNeeded(for: profile)
            host.scheduleAutomaticBrowsingDataCleanup(
                reason: "profile-switch",
                force: false,
                delayNanoseconds: nil
            )
        }
    }

    private func applyProfileSwitchUpdates(
        _ profile: Profile,
        animateTransition: Bool
    ) {
        let host = self.host
        dependencies.auxiliaryWindowManager.closeAll(reason: .profileSwitch)
        host.isTransitioningProfile = animateTransition
        host.currentProfile = profile
        host.windowRegistry?.activeWindow?.currentProfileId = profile.id
        dependencies.bookmarkManager.setFaviconPrefetchPartition(
            SumiFaviconSystem.shared.partition(profile: profile)
        )
        dependencies.extensionsModule.switchProfileIfLoaded(profile)
        dependencies.historyManager.switchProfile(profile.id)
        dependencies.tabManager.handleProfileSwitch()
    }
}

extension BrowserManager: BrowserProfileSwitchTransitionHost {}
