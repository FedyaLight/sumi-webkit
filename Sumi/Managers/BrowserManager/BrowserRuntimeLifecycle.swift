import Combine
import Foundation

@MainActor
final class BrowserRuntimeLifecycle {
    private enum Phase {
        case idle
        case recoveryPrepared
        case started
        case shutDown
    }

    private let permissionObservation: BrowserRuntimePermissionObservation
    private let startupObservation: BrowserRuntimeStartupObservation
    private let retentionObservation: BrowserRuntimeRetentionObservation
    private let tabRuntime: TabRuntimeLifecycle
    private let attachRuntime: @MainActor () -> AnyCancellable
    private var runtimeSubscription: AnyCancellable?
    private var phase: Phase = .idle

    init(
        permissionObservation: BrowserRuntimePermissionObservation,
        startupObservation: BrowserRuntimeStartupObservation,
        retentionObservation: BrowserRuntimeRetentionObservation,
        tabRuntime: TabRuntimeLifecycle,
        attachRuntime: @escaping @MainActor () -> AnyCancellable
    ) {
        self.permissionObservation = permissionObservation
        self.startupObservation = startupObservation
        self.retentionObservation = retentionObservation
        self.tabRuntime = tabRuntime
        self.attachRuntime = attachRuntime
    }

    isolated deinit {
        shutdown()
    }

    func prepareForStartupRecovery() {
        guard phase == .idle else { return }
        runtimeSubscription = attachRuntime()
        phase = .recoveryPrepared
    }

    func start(after preflight: ProfileRetirementStartupPreflightStatus) {
        guard preflight == .ready,
              phase == .idle || phase == .recoveryPrepared
        else {
            return
        }
        if phase == .idle {
            runtimeSubscription = attachRuntime()
        }
        phase = .started
        permissionObservation.start()
        startupObservation.start()
        retentionObservation.start()
    }

    func shutdown() {
        guard phase != .shutDown else { return }
        phase = .shutDown
        runtimeSubscription?.cancel()
        runtimeSubscription = nil
        permissionObservation.cancel()
        startupObservation.cancel()
        retentionObservation.cancel()
        tabRuntime.shutdown()
    }
}
