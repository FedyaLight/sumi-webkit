import Foundation
import OSLog
import SumiDomain

struct SumiPermissionPersistenceDiagnostics: Equatable, Sendable {
    enum LoadOutcome: Equatable, Sendable {
        case notLoaded
        case missing
        case loadedFile
        case loadedLegacySnapshots
        case loadedLegacyUserDefaults
        case failedFileRead(String)
        case failedFileDecode(String)
        case failedLegacyUserDefaultsDecode(String)
        case unsupportedFileVersion(Int)
    }

    var loadOutcome: LoadOutcome = .notLoaded
    var lastWriteFailure: String?
    var successfulWriteCount = 0
}

struct SumiPermissionPersistenceEnvelope: Codable, Sendable {
    var version: Int
    var generation: UInt64
    var antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
    var siteActivityRecords: [SumiPermissionSiteActivityRecord]
}

private final class SumiPermissionLoadedStateBox: @unchecked Sendable {
    var value: SumiPermissionPersistenceLoadedState?
}

private struct SumiPermissionUserDefaultsReference: @unchecked Sendable {
    let value: UserDefaults?
}

/// The single state and generation authority for permission persistence.
///
/// Feature stores mutate their domain collections through this type. A
/// mutation advances the logical generation immediately, while one delayed
/// utility-QoS publication writes the newest complete generation atomically.
final class SumiPermissionPersistenceAuthority: @unchecked Sendable {
    static let canonicalFileName = "permission-state.v1.json"
    static let legacyAntiAbuseFileName = "permission-anti-abuse-events.v1.json"
    static let legacySiteActivityFileName = "permission-site-activity.v1.json"
    static let defaultLegacyAntiAbuseStorageKey = "permissions.anti-abuse.events.v1"
    static let legacySiteActivityStorageKey = "permissions.siteActivity.v1"

    static let storageVersion = 1

    private static let log = Logger.sumi(category: "PermissionPersistence")
    private static let coalescingDelay: DispatchTimeInterval = .milliseconds(200)
    private static let bootstrapLoadingQueue = DispatchQueue(
        label: "com.sumi.permissions.persistence.bootstrap-load",
        qos: .userInitiated
    )

    private struct WriteCandidate {
        var envelope: SumiPermissionPersistenceEnvelope
        var shouldRetireLegacyPersistence: Bool
    }

    private let ioQueue = DispatchQueue(
        label: "com.sumi.permissions.persistence",
        qos: .utility
    )
    private let stateLock = NSLock()
    private let publisher: SumiPermissionCanonicalSnapshotPublisher?
    private let legacyDirectoryURL: URL?
    private let userDefaults: UserDefaults?
    private let legacyAntiAbuseStorageKey: String

    private var generation: UInt64
    private var antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
    private var siteActivityRecordsById: [String: SumiPermissionSiteActivityRecord]
    private var diagnostics: SumiPermissionPersistenceDiagnostics
    private var isDirty: Bool
    private var shouldRetireLegacyPersistence: Bool
    private var pendingWrite: DispatchWorkItem?
    private var pendingWriteToken: UInt64?
    private var nextWriteToken: UInt64

    init(
        userDefaults: UserDefaults?,
        legacyAntiAbuseStorageKey: String = defaultLegacyAntiAbuseStorageKey,
        storageDirectory: URL? = nil,
        bootstrapLoadObserver: (@Sendable () -> Void)? = nil,
        publishingFaultInjector: SumiPermissionCanonicalSnapshotPublisher.FaultInjector? = nil
    ) {
        let fileURL = storageDirectory?.appendingPathComponent(
            Self.canonicalFileName,
            isDirectory: false
        )
        publisher = fileURL.map {
            SumiPermissionCanonicalSnapshotPublisher(
                fileURL: $0,
                faultInjector: publishingFaultInjector
            )
        }
        legacyDirectoryURL = storageDirectory
        self.userDefaults = userDefaults
        self.legacyAntiAbuseStorageKey = legacyAntiAbuseStorageKey

        let loaded = if fileURL == nil, userDefaults == nil {
            SumiPermissionPersistenceLoadedState(
                generation: 0,
                antiAbuseEvents: [],
                siteActivityRecordsById: [:],
                outcome: .missing,
                needsCanonicalWrite: false,
                shouldRetireLegacyPersistence: false
            )
        } else {
            Self.loadBootstrapState(
                fileURL: fileURL,
                legacyDirectoryURL: storageDirectory,
                userDefaults: userDefaults,
                legacyAntiAbuseStorageKey: legacyAntiAbuseStorageKey,
                observer: bootstrapLoadObserver
            )
        }
        generation = loaded.generation
        antiAbuseEvents = loaded.antiAbuseEvents
        siteActivityRecordsById = loaded.siteActivityRecordsById
        diagnostics = SumiPermissionPersistenceDiagnostics(loadOutcome: loaded.outcome)
        isDirty = loaded.needsCanonicalWrite && publisher != nil
        shouldRetireLegacyPersistence = loaded.shouldRetireLegacyPersistence
        pendingWrite = nil
        pendingWriteToken = nil
        nextWriteToken = 0

        if isDirty {
            withStateLock {
                scheduleWriteLocked()
            }
        }
    }

    /// The stores expose synchronous initial snapshots, so startup waits for
    /// this directly submitted work item. Unlike a semaphore, waiting on the
    /// item lets libdispatch donate priority while all load I/O stays off main.
    private static func loadBootstrapState(
        fileURL: URL?,
        legacyDirectoryURL: URL?,
        userDefaults: UserDefaults?,
        legacyAntiAbuseStorageKey: String,
        observer: (@Sendable () -> Void)?
    ) -> SumiPermissionPersistenceLoadedState {
        let loadedStateBox = SumiPermissionLoadedStateBox()
        let userDefaultsReference = SumiPermissionUserDefaultsReference(value: userDefaults)
        let work = DispatchWorkItem(qos: .userInitiated, flags: .enforceQoS) {
            observer?()
            loadedStateBox.value = SumiPermissionSnapshotLoader.load(
                fileURL: fileURL,
                legacyDirectoryURL: legacyDirectoryURL,
                userDefaults: userDefaultsReference.value,
                legacyAntiAbuseStorageKey: legacyAntiAbuseStorageKey
            )
        }
        bootstrapLoadingQueue.async(execute: work)
        work.wait()
        guard let loaded = loadedStateBox.value else {
            preconditionFailure("Permission persistence loading did not produce a snapshot")
        }
        return loaded
    }

    var persistenceDiagnostics: SumiPermissionPersistenceDiagnostics {
        withStateLock { diagnostics }
    }

    func mutateAntiAbuseEvents<Result>(
        _ mutation: (inout [SumiPermissionAntiAbuseEvent]) -> Result
    ) -> Result {
        withStateLock {
            let before = persistentAntiAbuseEvents()
            let result = mutation(&antiAbuseEvents)
            if persistentAntiAbuseEvents() != before {
                markDirtyLocked()
            }
            return result
        }
    }

    func siteActivityRecords() -> [String: SumiPermissionSiteActivityRecord] {
        withStateLock { siteActivityRecordsById }
    }

    func replaceSiteActivityRecords(
        _ records: [String: SumiPermissionSiteActivityRecord]
    ) {
        withStateLock {
            let before = persistentSiteActivityRecords()
            siteActivityRecordsById = records
            if persistentSiteActivityRecords() != before {
                markDirtyLocked()
            }
        }
    }

    /// Awaits publication of the generation captured when this flush reaches
    /// the serial utility queue. Failed writes remain dirty for a later retry.
    @discardableResult
    func flushPendingWrites() async -> Bool {
        // Cancel before enqueueing so an eligible delayed block cannot publish
        // ahead of this flush. A mutation racing after this boundary may install
        // a newer delayed block; the immediate writer must not clear that block.
        withStateLock {
            pendingWrite?.cancel()
            pendingWrite = nil
            pendingWriteToken = nil
        }
        return await withCheckedContinuation { continuation in
            ioQueue.async { [self] in
                continuation.resume(returning: writeDirtyGeneration(scheduledToken: nil))
            }
        }
    }

    private func markDirtyLocked() {
        precondition(generation < UInt64.max, "Permission persistence generation exhausted")
        generation += 1
        isDirty = publisher != nil
        scheduleWriteLocked()
    }

    private func scheduleWriteLocked() {
        guard isDirty, pendingWrite == nil else { return }
        precondition(nextWriteToken < UInt64.max, "Permission persistence write token exhausted")
        nextWriteToken += 1
        let token = nextWriteToken
        let work = DispatchWorkItem { [weak self] in
            _ = self?.writeDirtyGeneration(scheduledToken: token)
        }
        pendingWrite = work
        pendingWriteToken = token
        ioQueue.asyncAfter(deadline: .now() + Self.coalescingDelay, execute: work)
    }

    private func writeDirtyGeneration(scheduledToken: UInt64?) -> Bool {
        var ignoredCancelledScheduledWrite = false
        let candidate: WriteCandidate? = withStateLock {
            if let scheduledToken {
                guard pendingWriteToken == scheduledToken else {
                    ignoredCancelledScheduledWrite = true
                    return nil
                }
                pendingWrite = nil
                pendingWriteToken = nil
            }
            guard isDirty else { return nil }
            return WriteCandidate(
                envelope: SumiPermissionPersistenceEnvelope(
                    version: Self.storageVersion,
                    generation: generation,
                    antiAbuseEvents: persistentAntiAbuseEvents(),
                    siteActivityRecords: persistentSiteActivityRecords().values.sorted { $0.id < $1.id }
                ),
                shouldRetireLegacyPersistence: shouldRetireLegacyPersistence
            )
        }
        if ignoredCancelledScheduledWrite { return true }

        guard let candidate, let publisher else {
            return retireLegacyPersistenceIfNeededAfterCanonicalPublication()
        }

        do {
            try publisher.publish(candidate.envelope)
            let didRetireLegacyPersistence = !candidate.shouldRetireLegacyPersistence
                || SumiPermissionSnapshotLoader.retireLegacyPersistence(
                    legacyDirectoryURL: legacyDirectoryURL,
                    userDefaults: userDefaults,
                    legacyAntiAbuseStorageKey: legacyAntiAbuseStorageKey
                )
            withStateLock {
                if generation == candidate.envelope.generation {
                    isDirty = false
                }
                if didRetireLegacyPersistence {
                    shouldRetireLegacyPersistence = false
                }
                diagnostics.lastWriteFailure = nil
                diagnostics.successfulWriteCount += 1
            }
            return true
        } catch {
            withStateLock {
                diagnostics.lastWriteFailure = error.localizedDescription
            }
            Self.log.error(
                "Failed to publish permission snapshot generation \(candidate.envelope.generation, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func retireLegacyPersistenceIfNeededAfterCanonicalPublication() -> Bool {
        let needsCleanup = withStateLock { shouldRetireLegacyPersistence }
        guard needsCleanup, publisher?.canonicalFileExists == true else { return true }
        let didRetire = SumiPermissionSnapshotLoader.retireLegacyPersistence(
            legacyDirectoryURL: legacyDirectoryURL,
            userDefaults: userDefaults,
            legacyAntiAbuseStorageKey: legacyAntiAbuseStorageKey
        )
        if didRetire {
            withStateLock {
                shouldRetireLegacyPersistence = false
            }
        }
        return didRetire
    }

    private func persistentAntiAbuseEvents() -> [SumiPermissionAntiAbuseEvent] {
        antiAbuseEvents.filter { !$0.key.isEphemeralProfile }
    }

    private func persistentSiteActivityRecords() -> [String: SumiPermissionSiteActivityRecord] {
        siteActivityRecordsById.filter { !$0.value.isEphemeralProfile }
    }

    private func withStateLock<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
