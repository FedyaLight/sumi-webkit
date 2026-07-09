import Foundation

@MainActor
protocol BrowserAppLifecycleHandling: AnyObject {
    func handleApplicationWillResignActive()
    func handleApplicationDidBecomeActive()
}

@MainActor
final class BrowserApplicationLifecycleController: BrowserAppLifecycleHandling {
    private let scheduleBackgroundMediaReconcile: @MainActor (String) -> Void
    private let pauseGeolocationOnAppBackgroundIfNeeded: @MainActor () -> Void
    private let resumeGeolocationOnAppForegroundIfNeeded: @MainActor () -> Void

    init(
        scheduleBackgroundMediaReconcile: @escaping @MainActor (String) -> Void,
        pauseGeolocationOnAppBackgroundIfNeeded: @escaping @MainActor () -> Void,
        resumeGeolocationOnAppForegroundIfNeeded: @escaping @MainActor () -> Void
    ) {
        self.scheduleBackgroundMediaReconcile = scheduleBackgroundMediaReconcile
        self.pauseGeolocationOnAppBackgroundIfNeeded = pauseGeolocationOnAppBackgroundIfNeeded
        self.resumeGeolocationOnAppForegroundIfNeeded = resumeGeolocationOnAppForegroundIfNeeded
    }

    func handleApplicationWillResignActive() {
        scheduleBackgroundMediaReconcile("app-will-resign-active")
        pauseGeolocationOnAppBackgroundIfNeeded()
    }

    func handleApplicationDidBecomeActive() {
        scheduleBackgroundMediaReconcile("app-did-become-active")
        resumeGeolocationOnAppForegroundIfNeeded()
    }
}
