import AppKit
import Foundation

@MainActor
final class SafariContentBlockerSourceMonitor {
    struct Source: Sendable {
        let id: String
        let appexPath: String
    }

    private let shouldObserve: @MainActor () -> Bool
    private let sources: @MainActor () -> [Source]
    private let sourceStampsMatch: @MainActor ([String: String]) -> Bool
    private let onStale: @MainActor () async -> Void
    private var activationObserver: NSObjectProtocol?
    private var probeTask: Task<Void, Never>?

    init(
        shouldObserve: @escaping @MainActor () -> Bool,
        sources: @escaping @MainActor () -> [Source],
        sourceStampsMatch:
            @escaping @MainActor ([String: String]) -> Bool,
        onStale: @escaping @MainActor () async -> Void
    ) {
        self.shouldObserve = shouldObserve
        self.sources = sources
        self.sourceStampsMatch = sourceStampsMatch
        self.onStale = onStale
    }

    isolated deinit {
        stop()
    }

    func reconcileObservation() {
        guard shouldObserve() else {
            stop()
            return
        }
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleProbe()
            }
        }
    }

    func stop() {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        probeTask?.cancel()
        probeTask = nil
    }

    #if DEBUG
        func drainForTests(cancel: Bool) async {
            if cancel {
                probeTask?.cancel()
            }
            await probeTask?.value
        }
    #endif

    private func scheduleProbe() {
        guard probeTask == nil else { return }
        probeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await probe()
            probeTask = nil
        }
    }

    private func probe() async {
        guard shouldObserve() else {
            stop()
            return
        }
        let sources = sources()
        let stamps = await Task.detached(priority: .utility) {
            Dictionary(
                uniqueKeysWithValues: sources.map { source in
                    (
                        source.id,
                        SafariContentBlockerRuleLocator.resourceStamp(
                            appexURL: URL(
                                fileURLWithPath: source.appexPath,
                                isDirectory: true
                            )
                        )
                    )
                }
            )
        }.value
        guard Task.isCancelled == false,
              sourceStampsMatch(stamps) == false
        else { return }
        await onStale()
    }
}
