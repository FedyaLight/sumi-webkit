//
//  LastSessionWindowsStore.swift
//  Sumi
//

import Foundation
import OSLog

@MainActor
final class LastSessionWindowsStore: ObservableObject {
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

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let archive = Self.loadArchive(from: userDefaults)
        self.snapshots = archive.snapshots
        self.tabSnapshot = archive.tabSnapshot
    }

    var canRestoreLastSession: Bool {
        !snapshots.isEmpty
    }

    func updateSnapshots(
        _ snapshots: [LastSessionWindowSnapshot],
        tabSnapshot: TabPersistenceSnapshot? = nil
    ) {
        let normalized = snapshots.uniqued(by: \.id)
        self.snapshots = normalized
        self.tabSnapshot = tabSnapshot
        save()
    }

    private let userDefaults: UserDefaults

    private func save() {
        let archive = Archive(snapshots: snapshots, tabSnapshot: tabSnapshot)
        let data: Data
        do {
            data = try JSONEncoder().encode(archive)
        } catch {
            Self.log.error(
                "Failed to encode last-session windows: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        userDefaults.set(data, forKey: Const.defaultsKey)
    }

    private static func loadArchive(from userDefaults: UserDefaults) -> Archive {
        guard let data = userDefaults.data(forKey: Const.defaultsKey) else {
            return Archive(snapshots: [], tabSnapshot: nil)
        }
        do {
            var archive = try JSONDecoder().decode(Archive.self, from: data)
            archive.snapshots = archive.snapshots.uniqued(by: \.id)
            return archive
        } catch {
            log.error(
                "Failed to decode last-session archive, trying legacy snapshot format: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            let snapshots = try JSONDecoder()
                .decode([LastSessionWindowSnapshot].self, from: data)
                .uniqued(by: \.id)
            return Archive(snapshots: snapshots, tabSnapshot: nil)
        } catch {
            log.error(
                "Failed to decode legacy last-session windows: \(error.localizedDescription, privacy: .public)"
            )
        }
        return Archive(snapshots: [], tabSnapshot: nil)
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
