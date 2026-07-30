import Foundation
import OSLog

@MainActor
final class SafariContentBlockerMetadataStore {
    private static let log = Logger.sumi(category: "SafariContentBlocker")
    private let database: SumiDatabase?

    var isAvailable: Bool { database != nil }

    init(database: SumiDatabase?) {
        self.database = database
    }

    func installedRecords() -> [InstalledSafariContentBlockerRecord] {
        guard let database else { return [] }
        do {
            return try database.read { try $0.safariContentBlockers.all() }
                .map(InstalledSafariContentBlockerRecord.init)
                .sorted {
                    if $0.containingAppName == $1.containingAppName {
                        return $0.displayName.localizedCaseInsensitiveCompare(
                            $1.displayName
                        ) == .orderedAscending
                    }
                    return $0.containingAppName
                        .localizedCaseInsensitiveCompare($1.containingAppName)
                        == .orderedAscending
                }
        } catch {
            Self.log.error(
                "Failed to fetch Safari content blocker records: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func siteOverrides()
        -> [String: SumiSafariContentBlockerSiteOverride] {
        (try? database?.read {
            try $0.safariContentBlockers.siteOverrides()
        }) ?? [:]
    }

    func replaceSiteOverrides(
        _ overrides: [String: SumiSafariContentBlockerSiteOverride]
    ) throws {
        try database?.transaction {
            try $0.safariContentBlockers.replaceSiteOverrides(overrides)
        }
    }

    func entity(
        forBundleIdentifier bundleIdentifier: String
    ) throws -> SafariContentBlockerMetadata? {
        guard let database else { return nil }
        return try database.read {
            try $0.safariContentBlockers.find(bundleID: bundleIdentifier)
        }
    }

    func setEnabled(
        _ enabled: Bool,
        entity: SafariContentBlockerMetadata
    ) throws {
        guard let database else { return }
        entity.isEnabled = enabled
        entity.lastUpdateDate = Date()
        try database.transaction {
            try $0.safariContentBlockers.save(entity)
        }
    }

    func upsert(
        candidate: DiscoveredSafariExtensionCandidate,
        resourceFingerprint: String,
        isEnabled: Bool,
        compileStatus: SafariContentBlockerCompileStatus,
        lastError: String?,
        ruleListCount: Int,
        ignoredEmptyRuleListCount: Int
    ) throws -> SafariContentBlockerMetadata {
        guard let database else {
            throw ExtensionError.unsupportedOS
        }

        if let existing = try entity(
            forBundleIdentifier: candidate.extensionBundleIdentifier
        ) {
            existing.displayName = candidate.displayName
            existing.version = candidate.version
            existing.containingAppName = candidate.containingAppName
            existing.containingAppBundleIdentifier =
                candidate.containingAppBundleIdentifier
            existing.appexPath = candidate.appexURL.path
            existing.containingAppPath = candidate.containingAppURL.path
            existing.resourceFingerprint = resourceFingerprint
            existing.isEnabled = isEnabled
            existing.lastUpdateDate = Date()
            existing.compileStatus = compileStatus
            existing.lastError = lastError
            existing.ruleListCount = ruleListCount
            existing.ignoredEmptyRuleListCount =
                ignoredEmptyRuleListCount
            try database.transaction {
                try $0.safariContentBlockers.save(existing)
            }
            return existing
        }

        let entity = SafariContentBlockerMetadata(
            id: candidate.extensionBundleIdentifier,
            extensionBundleIdentifier: candidate.extensionBundleIdentifier,
            displayName: candidate.displayName,
            version: candidate.version,
            containingAppName: candidate.containingAppName,
            containingAppBundleIdentifier:
                candidate.containingAppBundleIdentifier,
            appexPath: candidate.appexURL.path,
            containingAppPath: candidate.containingAppURL.path,
            resourceFingerprint: resourceFingerprint,
            isEnabled: isEnabled,
            compileStatus: compileStatus,
            lastError: lastError,
            ruleListCount: ruleListCount,
            ignoredEmptyRuleListCount: ignoredEmptyRuleListCount
        )
        try database.transaction {
            try $0.safariContentBlockers.save(entity)
        }
        return entity
    }

    func repair(
        record: InstalledSafariContentBlockerRecord,
        locatedRules: SafariContentBlockerLocatedRules
    ) -> Bool {
        guard locatedRules.resourceFingerprint != record.resourceFingerprint
                || locatedRules.definitions.count != record.ruleListCount
                || locatedRules.ignoredEmptyRuleListCount
                    != record.ignoredEmptyRuleListCount
        else { return false }

        let storedEntity: SafariContentBlockerMetadata?
        do {
            storedEntity = try entity(
                forBundleIdentifier: record.extensionBundleIdentifier
            )
        } catch {
            Self.log.error(
                "Failed to fetch Safari content blocker metadata for \(record.extensionBundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        guard let entity = storedEntity else { return false }

        entity.resourceFingerprint = locatedRules.resourceFingerprint
        entity.ruleListCount = locatedRules.definitions.count
        entity.ignoredEmptyRuleListCount =
            locatedRules.ignoredEmptyRuleListCount
        entity.compileStatus = .available
        entity.lastError = nil
        entity.lastUpdateDate = Date()
        return persistRepair(entity)
    }

    func markUnavailable(
        _ record: InstalledSafariContentBlockerRecord,
        error: Error
    ) -> Bool {
        let storedEntity: SafariContentBlockerMetadata?
        do {
            storedEntity = try entity(
                forBundleIdentifier: record.extensionBundleIdentifier
            )
        } catch {
            Self.log.error(
                "Failed to fetch unavailable Safari content blocker record \(record.extensionBundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        guard let entity = storedEntity else { return false }

        let compileStatus = (error as? SafariContentBlockerRuleLocatorError)?
            .persistedCompileStatus
            ?? SafariContentBlockerCompileStatus.rulesUnavailable
        var didMutate = false
        func update<T: Equatable>(
            _ keyPath:
                ReferenceWritableKeyPath<SafariContentBlockerMetadata, T>,
            _ value: T
        ) {
            guard entity[keyPath: keyPath] != value else { return }
            entity[keyPath: keyPath] = value
            didMutate = true
        }

        update(\.isEnabled, false)
        update(\.compileStatus, compileStatus)
        update(\.lastError, error.localizedDescription)
        update(\.ruleListCount, 0)
        update(\.ignoredEmptyRuleListCount, 0)
        if didMutate {
            entity.lastUpdateDate = Date()
        }
        return didMutate && persistRepair(entity)
    }

    private func persistRepair(
        _ metadata: SafariContentBlockerMetadata
    ) -> Bool {
        guard let database else { return false }
        do {
            try database.transaction {
                try $0.safariContentBlockers.save(metadata)
            }
            return true
        } catch {
            Self.log.error(
                "Failed to persist Safari content blocker metadata repair: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}

extension SafariContentBlockerRuleLocatorError {
    var persistedCompileStatus: SafariContentBlockerCompileStatus {
        switch self {
        case .resourcesDirectoryMissing, .staticRulesUnavailable:
            return .rulesUnavailable
        case .invalidJSON, .invalidRuleListShape:
            return .compileFailed
        }
    }
}
