//
//  LastSessionWindowsStore.swift
//  Sumi
//

import Foundation

@MainActor
final class LastSessionWindowsStore: ObservableObject {
    private enum Const {
        static let defaultsKey =
            "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastSessionWindows"
    }

    private struct Archive: Codable {
        var snapshots: [LastSessionWindowSnapshot]
        var tabSnapshot: TabSnapshotRepository.Snapshot?
    }

    @Published private(set) var snapshots: [LastSessionWindowSnapshot]
    private(set) var tabSnapshot: TabSnapshotRepository.Snapshot?

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
        tabSnapshot: TabSnapshotRepository.Snapshot? = nil
    ) {
        let normalized = snapshots.uniqued(by: \.session)
        self.snapshots = normalized
        self.tabSnapshot = tabSnapshot
        save()
    }

    private let userDefaults: UserDefaults

    private func save() {
        let archive = Archive(snapshots: snapshots, tabSnapshot: tabSnapshot)
        guard let data = try? JSONEncoder().encode(archive) else {
            return
        }
        userDefaults.set(data, forKey: Const.defaultsKey)
    }

    private static func loadArchive(from userDefaults: UserDefaults) -> Archive {
        guard let data = userDefaults.data(forKey: Const.defaultsKey) else {
            return Archive(snapshots: [], tabSnapshot: nil)
        }
        if let archive = try? JSONDecoder().decode(Archive.self, from: data) {
            return archive
        }
        if let snapshots = try? JSONDecoder().decode([LastSessionWindowSnapshot].self, from: data) {
            return Archive(snapshots: snapshots, tabSnapshot: nil)
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
