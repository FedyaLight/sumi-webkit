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

    private enum Const {
        static let defaultsKey =
            "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastSessionWindows"
    }

    private struct Archive: Codable {
        var snapshots: [LastSessionWindowSnapshot]
        var tabSnapshot: TabPersistenceSnapshot?
    }

    @Published private(set) var snapshots: [LastSessionWindowSnapshot]
    private(set) var tabSnapshot: TabPersistenceSnapshot?
    private(set) var archiveLoadState: ArchiveLoadState

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        switch Self.loadArchive(from: userDefaults) {
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
           normalized == self.snapshots,
           tabSnapshot == nil,
           self.tabSnapshot == nil {
            return false
        }
        guard save(archive) else { return false }
        self.snapshots = normalized
        self.tabSnapshot = tabSnapshot
        self.archiveLoadState = .loaded
        return true
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

    private let userDefaults: UserDefaults

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
        userDefaults.set(data, forKey: Const.defaultsKey)
        return true
    }

    private enum ArchiveLoadResult {
        case missing
        case loaded(Archive)
        case failed
    }

    private static func loadArchive(
        from userDefaults: UserDefaults
    ) -> ArchiveLoadResult {
        guard let data = userDefaults.data(forKey: Const.defaultsKey) else {
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
