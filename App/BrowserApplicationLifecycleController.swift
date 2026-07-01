import Foundation

@MainActor
protocol BrowserAppLifecycleHandling: AnyObject {
    func handleApplicationWillResignActive()
    func handleApplicationDidBecomeActive()
}

@MainActor
final class BrowserApplicationLifecycleController: BrowserAppLifecycleHandling {
    struct Dependencies {
        let scheduleBackgroundMediaReconcile: @MainActor (String) -> Void
        let pauseGeolocationOnAppBackgroundIfNeeded: @MainActor () -> Void
        let resumeGeolocationOnAppForegroundIfNeeded: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func handleApplicationWillResignActive() {
        dependencies.scheduleBackgroundMediaReconcile("app-will-resign-active")
        dependencies.pauseGeolocationOnAppBackgroundIfNeeded()
    }

    func handleApplicationDidBecomeActive() {
        dependencies.scheduleBackgroundMediaReconcile("app-did-become-active")
        dependencies.resumeGeolocationOnAppForegroundIfNeeded()
    }
}

extension BrowserApplicationLifecycleController.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let backgroundMediaOptimizationService = browserManager.backgroundMediaOptimizationService
        let permissionRuntime = browserManager.permissionRuntime

        return Self(
            scheduleBackgroundMediaReconcile: { reason in
                backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            pauseGeolocationOnAppBackgroundIfNeeded: {
                permissionRuntime.pauseGeolocationOnAppBackgroundIfNeeded()
            },
            resumeGeolocationOnAppForegroundIfNeeded: {
                permissionRuntime.resumeGeolocationOnAppForegroundIfNeeded()
            }
        )
    }
}
