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

    @Published private(set) var snapshots: [LastSessionWindowSnapshot]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.snapshots = Self.loadSnapshots(from: userDefaults)
    }

    var canRestoreLastSession: Bool {
        !snapshots.isEmpty
    }

    func updateSnapshots(_ snapshots: [LastSessionWindowSnapshot]) {
        let normalized = snapshots.uniqued(by: \.session)
        self.snapshots = normalized
        save()
    }

    private let userDefaults: UserDefaults

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }
        userDefaults.set(data, forKey: Const.defaultsKey)
    }

    private static func loadSnapshots(from userDefaults: UserDefaults) -> [LastSessionWindowSnapshot] {
        guard let data = userDefaults.data(forKey: Const.defaultsKey),
              let snapshots = try? JSONDecoder().decode([LastSessionWindowSnapshot].self, from: data)
        else {
            return []
        }
        return snapshots
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
