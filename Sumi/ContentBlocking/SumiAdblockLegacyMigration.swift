import Foundation

@MainActor
final class SumiAdblockLegacyMigration {
    private enum Key {
        static let storageVersion = "settings.adblock.localGenerationMigrationVersion"
        static let compiledRulesVersion = "settings.adblock.compiledRulesMigrationVersion"
        static let level = "settings.protection.level"
        static let appliedLevel = "settings.protection.appliedLevel"
        static let appliedSelection = "settings.protection.appliedFilterListSelection"
    }

    private static let currentVersion = 2
    private static let obsoleteDefaults = [
        "settings.protection.browserRestartRequired",
        "settings.protection.bundleUpdate.lastAttemptDate",
        "settings.protection.bundleUpdate.lastSuccessDate",
        "settings.protection.bundleUpdate.lastReleaseVersion",
        "settings.protection.bundleUpdate.lastBundleId",
        "settings.protection.bundleUpdate.lastSummary",
        "settings.protection.bundleUpdate.lastFailureReason",
        "settings.protection.bundleUpdate.lastSignatureVerified",
        "settings.protection.bundleUpdate.lastSigningKeyId",
        "settings.protection.bundleUpdate.lastSigningKeyVersion",
        "settings.protection.bundleUpdate.lastSignatureError",
        "settings.protection.bundleUpdate.lastDowngradeRejected",
    ]

    private let userDefaults: UserDefaults
    private let database: SumiDatabase
    private let fileManager: FileManager
    private let storageURLs: [URL]
    private let compiler: any SumiContentRuleListCompiling

    init(
        userDefaults: UserDefaults,
        database: SumiDatabase,
        fileManager: FileManager = .default,
        storageURLs: [URL]? = nil,
        compiler: any SumiContentRuleListCompiling = SumiWKContentRuleListCompiler()
    ) {
        self.userDefaults = userDefaults
        self.database = database
        self.fileManager = fileManager
        self.compiler = compiler
        self.storageURLs = storageURLs
            ?? Self.defaultStorageURLs(fileManager: fileManager)
    }

    func prepareOwnedStateIfNeeded() throws {
        guard userDefaults.integer(forKey: Key.storageVersion)
            < Self.currentVersion else { return }

        for url in storageURLs where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try database.transaction {
            try $0.documents.delete(
                key: SumiCompiledContentRuleListCatalog.documentKey
            )
        }

        let selected = [Key.level, Key.appliedLevel]
            .compactMap { userDefaults.string(forKey: $0) }
            .contains { $0 == "adblock" || $0 == "protection" }
            ? "adblock"
            : "off"
        userDefaults.set(selected, forKey: Key.level)
        userDefaults.set("off", forKey: Key.appliedLevel)
        userDefaults.removeObject(forKey: Key.appliedSelection)
        for key in Self.obsoleteDefaults {
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.set(Self.currentVersion, forKey: Key.storageVersion)
    }

    func removeLegacyCompiledRulesIfNeeded() async throws {
        guard userDefaults.integer(forKey: Key.compiledRulesVersion)
            < Self.currentVersion else { return }

        let identifiers = await compiler.availableContentRuleListIdentifiers()
        for identifier in identifiers where Self.isOwned(identifier) {
            try await compiler.removeContentRuleList(forIdentifier: identifier)
        }
        userDefaults.set(Self.currentVersion, forKey: Key.compiledRulesVersion)
    }

    private static func defaultStorageURLs(fileManager: FileManager) -> [URL] {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let caches = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        return [
            applicationSupport.appendingPathComponent(
                "Sumi/Adblock",
                isDirectory: true
            ),
            applicationSupport.appendingPathComponent(
                "Sumi/AdblockRemoteBundles",
                isDirectory: true
            ),
            caches.appendingPathComponent(
                "Sumi/ContentBlocking/SelectedFilterBundles",
                isDirectory: true
            ),
        ]
    }

    private static func isOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.")
            || identifier.hasPrefix("sumi.tracking.")
    }
}
