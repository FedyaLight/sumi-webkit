import Foundation

@MainActor
final class BrowserRuntimeRetentionObservation {
    private let notificationCenter: NotificationCenter
    private let automaticCleanup: BrowserAutomaticBrowsingDataCleanup
    private var observerToken: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        automaticCleanup: BrowserAutomaticBrowsingDataCleanup
    ) {
        self.notificationCenter = notificationCenter
        self.automaticCleanup = automaticCleanup
    }

    func start() {
        guard observerToken == nil else { return }
        observerToken = notificationCenter.addObserver(
            forName: .sumiBrowsingDataRetentionChanged,
            object: nil,
            queue: .main
        ) { [weak automaticCleanup] _ in
            Task { @MainActor [weak automaticCleanup] in
                automaticCleanup?.schedule(
                    reason: "retention-setting-changed",
                    force: true,
                    delayNanoseconds: 0
                )
            }
        }
    }

    func cancel() {
        guard let observerToken else { return }
        notificationCenter.removeObserver(observerToken)
        self.observerToken = nil
    }
}
