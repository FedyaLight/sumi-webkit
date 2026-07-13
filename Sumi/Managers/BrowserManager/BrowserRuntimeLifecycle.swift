import Combine
import Foundation

/// Start/cancel surface of permission-event observation as the runtime
/// lifecycle sees it; the live implementation is
/// `BrowserManagerPermissionRuntime`.
@MainActor
protocol BrowserPermissionObservationManaging: AnyObject {
    func startPermissionEventObservation(
        onPermissionEvent: @escaping SumiPermissionEventOwner.EventHandler
    )
    func cancelPermissionEventObservation()
}

/// Begin/cancel surface of the startup protection-level restore task; the
/// live implementation is `BrowserStartupProtectionRuntime`.
@MainActor
protocol BrowserStartupProtectionRestoring: AnyObject {
    func beginProtectionRestoreForStartupIfNeeded()
    func cancelProtectionRestoreTask()
}

/// Models the browser runtime's process lifecycle: one `start()` that begins
/// startup observations, and one idempotent `shutdown()` that cancels those
/// observations plus the runtime-graph subscription it owns and detaches
/// background-media optimization before tab runtime teardown.
///
/// Owns the lifecycle state machine (idle → started → shut down) so
/// initialization and teardown each have a single executor instead of being
/// spread across `BrowserManager.init`, `deinit`, and owner chains.
///
/// Collaborator shape: capabilities the lifecycle starts and cancels are
/// injected as whole collaborators (`permissionObservation`,
/// `protectionRestore`); one-way signals the lifecycle only routes are
/// injected as event-sink closures.
@MainActor
final class BrowserRuntimeLifecycle {
    private enum Phase {
        case idle
        case started
        case shutDown
    }

    private let notificationCenter: NotificationCenter
    private let notificationQueue: OperationQueue?
    private let tabStructureEventBus: TabStructureEventBus
    private let permissionObservation: any BrowserPermissionObservationManaging
    private let onPermissionEvent: SumiPermissionEventOwner.EventHandler
    private let protectionRestore: any BrowserStartupProtectionRestoring
    private let backgroundMediaOptimization: SumiBackgroundMediaOptimizationService
    private var runtimeGraphSubscription: AnyCancellable?
    private let handleTabManagerDataLoaded: @MainActor () -> Void
    private let scheduleBrowsingDataRetentionCleanup: @MainActor () -> Void

    private var phase: Phase = .idle
    private var initialDataLoadedCancellable: AnyCancellable?
    private var browsingDataRetentionObserverToken: NSObjectProtocol?

    init(
        notificationCenter: NotificationCenter = .default,
        notificationQueue: OperationQueue? = .main,
        tabStructureEventBus: TabStructureEventBus,
        permissionObservation: any BrowserPermissionObservationManaging,
        onPermissionEvent: @escaping SumiPermissionEventOwner.EventHandler,
        protectionRestore: any BrowserStartupProtectionRestoring,
        backgroundMediaOptimization: SumiBackgroundMediaOptimizationService,
        runtimeGraphSubscription: AnyCancellable,
        handleTabManagerDataLoaded: @escaping @MainActor () -> Void,
        scheduleBrowsingDataRetentionCleanup: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.notificationQueue = notificationQueue
        self.tabStructureEventBus = tabStructureEventBus
        self.permissionObservation = permissionObservation
        self.onPermissionEvent = onPermissionEvent
        self.protectionRestore = protectionRestore
        self.backgroundMediaOptimization = backgroundMediaOptimization
        self.runtimeGraphSubscription = runtimeGraphSubscription
        self.handleTabManagerDataLoaded = handleTabManagerDataLoaded
        self.scheduleBrowsingDataRetentionCleanup = scheduleBrowsingDataRetentionCleanup
    }

    isolated deinit {
        shutdown()
    }

    func start() {
        guard phase == .idle else { return }
        phase = .started

        permissionObservation.startPermissionEventObservation(
            onPermissionEvent: onPermissionEvent
        )
        initialDataLoadedCancellable = tabStructureEventBus.initialDataLoadedPublisher
            .sink { [weak self] in
                self?.handleTabManagerDataLoaded()
            }

        browsingDataRetentionObserverToken = notificationCenter.addObserver(
            forName: .sumiBrowsingDataRetentionChanged,
            object: nil,
            queue: notificationQueue
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleBrowsingDataRetentionCleanupIfRunning()
            }
        }

        protectionRestore.beginProtectionRestoreForStartupIfNeeded()
    }

    func shutdown() {
        guard phase != .shutDown else { return }
        phase = .shutDown

        runtimeGraphSubscription?.cancel()
        runtimeGraphSubscription = nil
        backgroundMediaOptimization.detach()
        permissionObservation.cancelPermissionEventObservation()
        protectionRestore.cancelProtectionRestoreTask()

        initialDataLoadedCancellable?.cancel()
        initialDataLoadedCancellable = nil

        if let token = browsingDataRetentionObserverToken {
            notificationCenter.removeObserver(token)
            browsingDataRetentionObserverToken = nil
        }
    }

    private func scheduleBrowsingDataRetentionCleanupIfRunning() {
        guard phase == .started else { return }
        scheduleBrowsingDataRetentionCleanup()
    }
}
