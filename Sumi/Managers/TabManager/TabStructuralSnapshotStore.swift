import Foundation
import OSLog

protocol TabStructuralSnapshotPersisting: Sendable {
    func persistFullReconcile(
        snapshot: TabPersistenceSnapshot,
        generation: Int
    ) async -> Bool

    func persistIncremental(
        delta: TabStructuralPersistenceDelta,
        generation: Int
    ) async -> Bool
}

/// Orders structural generations and owns recovery for full snapshot writes.
/// Selection and runtime-state writes deliberately live on separate capabilities.
actor TabStructuralSnapshotStore: TabStructuralSnapshotPersisting {
    private static let log = Logger.sumi(category: "TabPersistence")

    private let writes: TabStoreWriteExecutor
    private let codec: TabPersistenceCodec
    private var latestGeneration = 0
    private var lastBackup: Data?

    init(
        writes: TabStoreWriteExecutor,
        codec: TabPersistenceCodec = TabPersistenceCodec()
    ) {
        self.writes = writes
        self.codec = codec
    }

    func persistFullReconcile(
        snapshot: TabPersistenceSnapshot,
        generation: Int
    ) async -> Bool {
        let signpostState = PerformanceTrace.beginInterval(
            "TabStructuralSnapshotStore.fullReconcile"
        )
        defer {
            PerformanceTrace.endInterval(
                "TabStructuralSnapshotStore.fullReconcile",
                signpostState
            )
        }

        guard accept(generation: generation, operation: "full reconcile") else {
            return false
        }

        do {
            lastBackup = try codec.encodeSnapshot(snapshot)
            try await writes.execute(.reconcile(snapshot, validating: true))
            return true
        } catch {
            let classified = TabPersistenceErrorClassifier.classify(error)
            Self.log.error(
                "Full tab reconcile failed (\(String(describing: classified), privacy: .public)): \(String(describing: error), privacy: .public)"
            )

            guard generation == latestGeneration else {
                Self.log.notice(
                    "Skipped recovery for stale tab generation \(generation, privacy: .public); latest is \(self.latestGeneration, privacy: .public)"
                )
                return false
            }

            do {
                try await writes.execute(.reconcile(snapshot, validating: false))
                Self.log.notice("Tab persistence recovery fallback succeeded")
                return false
            } catch {
                Self.log.fault(
                    "Tab persistence recovery fallback failed: \(String(describing: error), privacy: .public). Attempting backup recovery."
                )
                guard generation == latestGeneration else {
                    Self.log.notice(
                        "Skipped backup recovery for stale tab generation \(generation, privacy: .public)"
                    )
                    return false
                }
                return await recoverBackup(generation: generation)
            }
        }
    }

    func persistIncremental(
        delta: TabStructuralPersistenceDelta,
        generation: Int
    ) async -> Bool {
        let signpostState = PerformanceTrace.beginInterval(
            "TabStructuralSnapshotStore.incremental"
        )
        defer {
            PerformanceTrace.endInterval(
                "TabStructuralSnapshotStore.incremental",
                signpostState
            )
        }

        guard accept(generation: generation, operation: "incremental write") else {
            return false
        }

        do {
            try await writes.execute(.incremental(delta))
            return true
        } catch {
            let classified = TabPersistenceErrorClassifier.classify(error)
            Self.log.error(
                "Incremental tab persistence failed (\(String(describing: classified), privacy: .public)): \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    private func accept(generation: Int, operation: String) -> Bool {
        guard generation >= latestGeneration else {
            RuntimeDiagnostics.debug(
                "Skipping stale tab \(operation), generation=\(generation) < latest=\(latestGeneration)",
                category: "TabPersistence"
            )
            return false
        }
        latestGeneration = generation
        return true
    }

    private func recoverBackup(generation: Int) async -> Bool {
        guard generation == latestGeneration else { return false }
        guard let lastBackup else {
            Self.log.fault("Tab persistence backup recovery had no backup payload")
            return false
        }
        do {
            let snapshot = try codec.decodeSnapshot(from: lastBackup)
            try await writes.execute(.reconcile(snapshot, validating: false))
            Self.log.notice("Recovered tab persistence from the in-memory backup payload")
        } catch {
            Self.log.fault(
                "Tab persistence backup recovery failed: \(String(describing: error), privacy: .public)"
            )
        }
        return false
    }
}
