//
//  LastSessionWindowsStore.swift
//  Sumi
//

import Foundation
import OSLog

@MainActor
final class LastSessionWindowsStore: ObservableObject {
    enum ArchiveLoadState: Equatable {
        case missing
        case loaded
        case failed
    }

    private static let log = Logger.sumi(category: "LastSessionWindowsStore")

    private static let documentKey = "session.last-windows"

    private struct Archive: Codable {
        var snapshots: [LastSessionWindowSnapshot]
        var tabSnapshot: TabPersistenceSnapshot?
    }

    private struct DeferredArchive: @unchecked Sendable {
        let value: Archive
    }

    @Published private(set) var snapshots: [LastSessionWindowSnapshot]
    private(set) var tabSnapshot: TabPersistenceSnapshot?
    private(set) var archiveLoadState: ArchiveLoadState
    private var needsPersistenceRetry = false
    private var persistenceRevision: UInt64 = 0

    init(database: SumiDatabase) {
        self.database = database
        switch Self.loadArchive(from: database) {
        case .missing:
            self.snapshots = []
            self.tabSnapshot = nil
            self.archiveLoadState = .missing
        case .loaded(let archive):
            self.snapshots = archive.snapshots
            self.tabSnapshot = archive.tabSnapshot
            self.archiveLoadState = .loaded
        case .failed:
            self.snapshots = []
            self.tabSnapshot = nil
            self.archiveLoadState = .failed
        }
    }

    var canRestoreLastSession: Bool {
        !snapshots.isEmpty
    }

    @discardableResult
    func updateSnapshots(
        _ snapshots: [LastSessionWindowSnapshot],
        tabSnapshot: TabPersistenceSnapshot? = nil
    ) -> Bool {
        let normalized = snapshots.uniqued(by: \.id)
        let archive = Archive(
            snapshots: normalized,
            tabSnapshot: tabSnapshot
        )
        if archiveLoadState == .loaded,
           needsPersistenceRetry == false,
           normalized == self.snapshots,
           tabSnapshot == nil,
           self.tabSnapshot == nil {
            return false
        }
        database.flushEnqueuedTransactions()
        guard save(archive) else { return false }
        persistenceRevision &+= 1
        self.snapshots = normalized
        self.tabSnapshot = tabSnapshot
        self.archiveLoadState = .loaded
        needsPersistenceRetry = false
        return true
    }

    @discardableResult
    func enqueueUpdateSnapshots(
        _ snapshots: [LastSessionWindowSnapshot],
        tabSnapshot: TabPersistenceSnapshot? = nil
    ) -> Bool {
        let normalized = snapshots.uniqued(by: \.id)
        if archiveLoadState == .loaded,
           needsPersistenceRetry == false,
           normalized == self.snapshots,
           tabSnapshot == nil,
           self.tabSnapshot == nil {
            return false
        }

        let payload = DeferredArchive(
            value: Archive(
                snapshots: normalized,
                tabSnapshot: tabSnapshot
            )
        )
        self.snapshots = normalized
        self.tabSnapshot = tabSnapshot
        archiveLoadState = .loaded
        let documentKey = Self.documentKey
        let log = Self.log
        persistenceRevision &+= 1
        let revision = persistenceRevision

        database.enqueueTransaction(
            { connection in
                let data = try JSONEncoder().encode(payload.value)
                try connection.documents.save(data, forKey: documentKey)
            },
            completion: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.persistenceRevision == revision else {
                        return
                    }
                    switch result {
                    case .success:
                        self.needsPersistenceRetry = false
                    case .failure(let error):
                        self.needsPersistenceRetry = true
                        log.error(
                            "Failed to persist last-session windows: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        )
        return true
    }

    func flushPendingPersistence() {
        database.flushEnqueuedTransactions()
    }

    @discardableResult
    func migrateProfileReferences(
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> Bool {
        guard archiveLoadState != .failed else { return false }
        let migrated = snapshots.map {
            $0.replacingCurrentProfileReference(
                from: deletedProfileID,
                to: fallbackProfileID
            )
        }
        let migratedTabSnapshot: TabPersistenceSnapshot?
        if let tabSnapshot {
            guard let migrated = TabPersistenceSnapshotProfileMigration.migrate(
                tabSnapshot,
                from: deletedProfileID,
                to: fallbackProfileID
            ) else {
                return false
            }
            migratedTabSnapshot = migrated
        } else {
            migratedTabSnapshot = nil
        }
        return updateSnapshots(
            migrated,
            tabSnapshot: migratedTabSnapshot
        )
    }

    func containsProfileReference(to profileID: UUID) -> Bool {
        archiveLoadState == .failed
            || snapshots.contains {
            ProfileReferenceInventory(lastSessionWindowSnapshot: $0)
                .contains(profileID)
        }
            || tabSnapshot.map {
                ProfileReferenceInventory(tabSnapshot: $0).contains(profileID)
            } == true
    }

    private let database: SumiDatabase

    private func save(_ archive: Archive) -> Bool {
        let data: Data
        do {
            data = try JSONEncoder().encode(archive)
        } catch {
            Self.log.error(
                "Failed to encode last-session windows: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        do {
            try database.transaction {
                try $0.documents.save(data, forKey: Self.documentKey)
            }
            return true
        } catch {
            Self.log.error(
                "Failed to persist last-session windows: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private enum ArchiveLoadResult {
        case missing
        case loaded(Archive)
        case failed
    }

    private static func loadArchive(
        from database: SumiDatabase
    ) -> ArchiveLoadResult {
        let data: Data?
        do {
            data = try database.read {
                try $0.documents.data(forKey: documentKey)
            }
        } catch {
            log.error(
                "Failed to read last-session archive: \(error.localizedDescription, privacy: .public)"
            )
            return .failed
        }
        guard let data else {
            return .missing
        }
        do {
            var archive = try JSONDecoder().decode(Archive.self, from: data)
            archive.snapshots = archive.snapshots.uniqued(by: \.id)
            return .loaded(archive)
        } catch {
            log.error(
                "Failed to decode last-session archive: \(error.localizedDescription, privacy: .public)"
            )
        }
        return .failed
    }
}

private extension LastSessionWindowSnapshot {
    func replacingCurrentProfileReference(
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> LastSessionWindowSnapshot {
        var migratedSession = session
        if migratedSession.currentProfileId == deletedProfileID {
            migratedSession.currentProfileId = fallbackProfileID
        }
        return LastSessionWindowSnapshot(id: id, session: migratedSession)
    }
}

private extension Array {
    func uniqued<Value: Hashable>(by keyPath: KeyPath<Element, Value>) -> [Element] {
        var seen = Set<Value>()
        return filter { element in
            let value = element[keyPath: keyPath]
            return seen.insert(value).inserted
        }
    }
}
