//
//  SafariExtensionImportStore.swift
//  Sumi
//
//  Tracks discovered Safari Web Extension candidates and user imports.
//  Does not auto-enable or load WebKit runtime state.
//

import Foundation

struct SafariExtensionImportCandidateRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { extensionBundleIdentifier }

    let extensionBundleIdentifier: String
    let appexPath: String
    let displayName: String
    let containingAppName: String
    let lastDiscoveredAt: Date
}

struct SafariExtensionImportedRecord: Codable, Equatable, Sendable {
    let extensionBundleIdentifier: String
    let appexPath: String
    let installedExtensionId: String
    let importedAt: Date
}

/// Minimal registry for scanner output vs explicit user imports.
final class SafariExtensionImportStore: @unchecked Sendable {
    static let shared = SafariExtensionImportStore()

    private let defaults: UserDefaults
    private let discoveredKey = "Sumi.SafariExtensionImportStore.discovered"
    private let importedKey = "Sumi.SafariExtensionImportStore.imported"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func refreshDiscoveredCandidates(_ candidates: [DiscoveredSafariExtensionCandidate]) {
        let now = Date()
        let records = candidates.map {
            SafariExtensionImportCandidateRecord(
                extensionBundleIdentifier: $0.extensionBundleIdentifier,
                appexPath: $0.appexURL.path,
                displayName: $0.displayName,
                containingAppName: $0.containingAppName,
                lastDiscoveredAt: now
            )
        }
        persistDiscovered(records)
    }

    func discoveredCandidates() -> [SafariExtensionImportCandidateRecord] {
        loadDiscovered().sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func importedRecords() -> [SafariExtensionImportedRecord] {
        loadImported().sorted {
            $0.importedAt > $1.importedAt
        }
    }

    func isImported(extensionBundleIdentifier: String) -> Bool {
        loadImported().contains { $0.extensionBundleIdentifier == extensionBundleIdentifier }
    }

    func importedExtensionId(forExtensionBundleIdentifier identifier: String) -> String? {
        loadImported().first { $0.extensionBundleIdentifier == identifier }?.installedExtensionId
    }

    func importableCandidates(
        excludingInstalledBundlePaths installedBundlePaths: Set<String> = []
    ) -> [SafariExtensionImportCandidateRecord] {
        discoveredCandidates().filter { candidate in
            installedBundlePaths.contains(candidate.appexPath) == false
        }
    }

    func removeImportedRecord(forInstalledExtensionId installedExtensionId: String) {
        var imported = loadImported()
        imported.removeAll { $0.installedExtensionId == installedExtensionId }
        persistImported(imported)
    }

    func removeImportedRecord(extensionBundleIdentifier: String) {
        var imported = loadImported()
        imported.removeAll { $0.extensionBundleIdentifier == extensionBundleIdentifier }
        persistImported(imported)
    }

    func markImported(
        candidate: DiscoveredSafariExtensionCandidate,
        installedExtensionId: String
    ) {
        var imported = loadImported()
        imported.removeAll { $0.extensionBundleIdentifier == candidate.extensionBundleIdentifier }
        imported.append(
            SafariExtensionImportedRecord(
                extensionBundleIdentifier: candidate.extensionBundleIdentifier,
                appexPath: candidate.appexURL.path,
                installedExtensionId: installedExtensionId,
                importedAt: Date()
            )
        )
        persistImported(imported)
    }

    func markImported(
        extensionBundleIdentifier: String,
        appexPath: String,
        installedExtensionId: String
    ) {
        var imported = loadImported()
        imported.removeAll { $0.extensionBundleIdentifier == extensionBundleIdentifier }
        imported.append(
            SafariExtensionImportedRecord(
                extensionBundleIdentifier: extensionBundleIdentifier,
                appexPath: appexPath,
                installedExtensionId: installedExtensionId,
                importedAt: Date()
            )
        )
        persistImported(imported)
    }

    // MARK: - Persistence

    private func loadDiscovered() -> [SafariExtensionImportCandidateRecord] {
        decode([SafariExtensionImportCandidateRecord].self, forKey: discoveredKey) ?? []
    }

    private func persistDiscovered(_ records: [SafariExtensionImportCandidateRecord]) {
        encode(records, forKey: discoveredKey)
    }

    private func loadImported() -> [SafariExtensionImportedRecord] {
        decode([SafariExtensionImportedRecord].self, forKey: importedKey) ?? []
    }

    private func persistImported(_ records: [SafariExtensionImportedRecord]) {
        encode(records, forKey: importedKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
