import Foundation
import OSLog
import SumiDomain

struct SumiPermissionPersistenceDiagnostics: Equatable, Sendable {
    enum LoadOutcome: Equatable, Sendable {
        case notLoaded
        case loadedDatabase
        case failedDatabaseRead(String)
    }

    var loadOutcome: LoadOutcome = .notLoaded
    var lastWriteFailure: String?
    var successfulWriteCount = 0
}

enum SumiPermissionProfileDataCleanupError: Error, Equatable {
    case persistenceStateUnreadable
    case publicationFailed
}

/// Owns the document-shaped permission activity state stored inside the
/// browser database. Mutations advance a logical generation immediately and
/// coalesce durable writes away from the main thread.
final class SumiPermissionPersistenceAuthority: @unchecked Sendable {
    private static let log = Logger.sumi(category: "PermissionPersistence")
    private static let coalescingDelay: DispatchTimeInterval = .milliseconds(200)

    private let database: SumiDatabase
    private let ioQueue = DispatchQueue(
        label: "com.sumi.permissions.persistence",
        qos: .utility
    )
    private let stateLock = NSLock()
    private var generation: UInt64
    private var antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
    private var siteActivityRecordsById: [String: SumiPermissionSiteActivityRecord]
    private var retiredProfileIDs: Set<String> = []
    private var diagnostics: SumiPermissionPersistenceDiagnostics
    private var isDirty = false
    private var pendingWrite: DispatchWorkItem?
    private var pendingWriteToken: UInt64?
    private var nextWriteToken: UInt64 = 0

    init(database: SumiDatabase) {
        self.database = database
        do {
            let loaded = try database.read {
                try $0.permissionAuxiliary.load()
            }
            generation = loaded.generation
            antiAbuseEvents = loaded.antiAbuseEvents
            siteActivityRecordsById = Dictionary(
                loaded.siteActivityRecords.map { ($0.id, $0) },
                uniquingKeysWith: { _, newest in newest }
            )
            diagnostics = .init(loadOutcome: .loadedDatabase)
        } catch {
            generation = 0
            antiAbuseEvents = []
            siteActivityRecordsById = [:]
            diagnostics = .init(
                loadOutcome: .failedDatabaseRead(error.localizedDescription)
            )
        }
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
            antiAbuseEvents.removeAll {
                retiredProfileIDs.contains($0.key.profilePartitionId)
            }
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
            siteActivityRecordsById = records.filter {
                !retiredProfileIDs.contains($0.value.profilePartitionId)
            }
            if persistentSiteActivityRecords() != before {
                markDirtyLocked()
            }
        }
    }

    func sealProfile(_ profilePartitionId: String) {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        _ = withStateLock { retiredProfileIDs.insert(profileID) }
    }

    func deleteProfileData(profilePartitionId: String) async throws {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        let readable = withStateLock {
            retiredProfileIDs.insert(profileID)
            guard case .loadedDatabase = diagnostics.loadOutcome else {
                return false
            }
            let oldEvents = persistentAntiAbuseEvents()
            let oldActivity = persistentSiteActivityRecords()
            antiAbuseEvents.removeAll {
                $0.key.profilePartitionId == profileID
            }
            siteActivityRecordsById = siteActivityRecordsById.filter {
                $0.value.profilePartitionId != profileID
            }
            if oldEvents != persistentAntiAbuseEvents()
                || oldActivity != persistentSiteActivityRecords() {
                markDirtyLocked()
            }
            return true
        }
        guard readable else {
            throw SumiPermissionProfileDataCleanupError
                .persistenceStateUnreadable
        }
        guard await flushPendingWrites() else {
            throw SumiPermissionProfileDataCleanupError.publicationFailed
        }
    }

    @discardableResult
    func flushPendingWrites() async -> Bool {
        withStateLock {
            pendingWrite?.cancel()
            pendingWrite = nil
            pendingWriteToken = nil
        }
        return await withCheckedContinuation { continuation in
            ioQueue.async { [self] in
                continuation.resume(
                    returning: writeDirtyGeneration(scheduledToken: nil)
                )
            }
        }
    }

    private func markDirtyLocked() {
        precondition(generation < UInt64.max)
        generation += 1
        isDirty = true
        scheduleWriteLocked()
    }

    private func scheduleWriteLocked() {
        guard isDirty, pendingWrite == nil else { return }
        nextWriteToken += 1
        let token = nextWriteToken
        let work = DispatchWorkItem { [weak self] in
            _ = self?.writeDirtyGeneration(scheduledToken: token)
        }
        pendingWrite = work
        pendingWriteToken = token
        ioQueue.asyncAfter(
            deadline: .now() + Self.coalescingDelay,
            execute: work
        )
    }

    private func writeDirtyGeneration(scheduledToken: UInt64?) -> Bool {
        var cancelled = false
        let state: PermissionAuxiliaryState? = withStateLock {
            if let scheduledToken {
                guard pendingWriteToken == scheduledToken else {
                    cancelled = true
                    return nil
                }
                pendingWrite = nil
                pendingWriteToken = nil
            }
            guard isDirty else { return nil }
            return .init(
                generation: generation,
                antiAbuseEvents: persistentAntiAbuseEvents(),
                siteActivityRecords: persistentSiteActivityRecords()
                    .values.sorted { $0.id < $1.id }
            )
        }
        if cancelled || state == nil { return true }
        guard let state else { return true }
        do {
            try database.transaction {
                try $0.permissionAuxiliary.save(state)
            }
            withStateLock {
                if generation == state.generation {
                    isDirty = false
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
                "Failed to persist permission generation \(state.generation, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func persistentAntiAbuseEvents()
        -> [SumiPermissionAntiAbuseEvent] {
        antiAbuseEvents.filter { !$0.key.isEphemeralProfile }
    }

    private func persistentSiteActivityRecords()
        -> [String: SumiPermissionSiteActivityRecord] {
        siteActivityRecordsById.filter { !$0.value.isEphemeralProfile }
    }

    private func withStateLock<Result>(_ body: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
