import Foundation

/// Owns the one-shot startup restore gate and initial-data readiness event.
/// Store loading remains in `TabStoreRestoreService`; this lifecycle decides
/// whether and when that load is admitted.
@MainActor
final class TabStartupRestoreLifecycle {
    private let eventBus: TabStructureEventBus
    private let shouldLoadPersistedState: Bool
    private let automaticallyStartAfterRuntimeAttachment: Bool
    private let requestedStructuralRevision: UInt64?

    private(set) var hasLoadedInitialData = false
    private(set) var didStartPersistedStateLoad = false

    init(
        shouldLoadPersistedState: Bool,
        automaticallyStartAfterRuntimeAttachment: Bool,
        requestedStructuralRevision: UInt64 = 0,
        eventBus: TabStructureEventBus
    ) {
        self.shouldLoadPersistedState = shouldLoadPersistedState
        self.automaticallyStartAfterRuntimeAttachment =
            automaticallyStartAfterRuntimeAttachment
        self.requestedStructuralRevision = shouldLoadPersistedState
            ? requestedStructuralRevision
            : nil
        self.eventBus = eventBus
    }

    func markLoadStarted() {
        hasLoadedInitialData = false
        eventBus.resetInitialDataLoaded()
    }

    func markLoadFinished() {
        hasLoadedInitialData = true
        eventBus.publishInitialDataLoaded()
    }

    func startIfNeeded(
        runtimeIsAttached: Bool,
        restore: @escaping @MainActor (UInt64) -> Void
    ) {
        guard shouldLoadPersistedState,
              !didStartPersistedStateLoad,
              let requestedStructuralRevision
        else { return }
        precondition(
            runtimeIsAttached,
            "Persisted tab restore requires runtime ports to be attached first"
        )
        didStartPersistedStateLoad = true
        Task { @MainActor in
            restore(requestedStructuralRevision)
        }
    }

    func startAfterRuntimeAttachmentIfConfigured(
        runtimeIsAttached: Bool,
        restore: @escaping @MainActor (UInt64) -> Void
    ) {
        guard automaticallyStartAfterRuntimeAttachment else { return }
        startIfNeeded(runtimeIsAttached: runtimeIsAttached, restore: restore)
    }
}
