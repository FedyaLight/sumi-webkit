import Combine
import Foundation

@MainActor
final class BrowserRuntimeLifecycle {
    private enum Phase {
        case idle
        case started
        case shutDown
    }

    private let permissionObservation: BrowserRuntimePermissionObservation
    private let startupObservation: BrowserRuntimeStartupObservation
    private let retentionObservation: BrowserRuntimeRetentionObservation
    private let backgroundMedia: SumiBackgroundMediaOptimizationService
    private let tabRuntime: TabRuntimeLifecycle
    private var runtimeSubscription: AnyCancellable?
    private var phase: Phase = .idle

    init(
        permissionObservation: BrowserRuntimePermissionObservation,
        startupObservation: BrowserRuntimeStartupObservation,
        retentionObservation: BrowserRuntimeRetentionObservation,
        backgroundMedia: SumiBackgroundMediaOptimizationService,
        tabRuntime: TabRuntimeLifecycle,
        runtimeSubscription: AnyCancellable
    ) {
        self.permissionObservation = permissionObservation
        self.startupObservation = startupObservation
        self.retentionObservation = retentionObservation
        self.backgroundMedia = backgroundMedia
        self.tabRuntime = tabRuntime
        self.runtimeSubscription = runtimeSubscription
    }

    isolated deinit {
        shutdown()
    }

    func start(after preflight: ProfileRetirementStartupPreflightStatus) {
        guard preflight == .ready, phase == .idle else { return }
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
        backgroundMedia.detach()
        permissionObservation.cancel()
        startupObservation.cancel()
        retentionObservation.cancel()
        tabRuntime.shutdown()
    }
}
