import Foundation
import OSLog
import SumiDomain

@MainActor
final class SafariContentBlockerRuntimeOwner {
    private static let log = Logger.sumi(category: "SafariContentBlocker")

    private let database: SumiDatabase?
    private let isModuleEnabled: @MainActor () -> Bool
    private let compiledRuleListCatalog: SumiCompiledContentRuleListCataloging

    private var service: SumiContentBlockingService?
    private var serviceCacheKey: String?
    private var siteOverrides: [String: SumiSafariContentBlockerSiteOverride]

    private struct MaterializedContentBlockerRules {
        let record: InstalledSafariContentBlockerRecord
        let locatedRules: SafariContentBlockerLocatedRules
    }

    init(
        database: SumiDatabase?,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        isModuleEnabled: @escaping @MainActor () -> Bool
    ) {
        self.database = database
        self.compiledRuleListCatalog = compiledRuleListCatalog
        self.isModuleEnabled = isModuleEnabled
        self.siteOverrides = (try? database?.read {
            try $0.safariContentBlockers.siteOverrides()
        }) ?? [:]
    }

    func installedContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        guard let database else { return [] }
        do {
            return try database.read { try $0.safariContentBlockers.all() }
                .map(InstalledSafariContentBlockerRecord.init)
                .sorted {
                    if $0.containingAppName == $1.containingAppName {
                        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                    return $0.containingAppName.localizedCaseInsensitiveCompare($1.containingAppName) == .orderedAscending
                }
        } catch {
            Self.log.error("Failed to fetch Safari content blocker records: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func contentBlockerRecord(
        forBundleIdentifier bundleIdentifier: String
    ) -> InstalledSafariContentBlockerRecord? {
        installedContentBlockers().first {
            $0.extensionBundleIdentifier == bundleIdentifier
        }
    }

    func enableContentBlocker(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord {
        guard candidate.bundleKind == .contentBlocker else {
            throw ExtensionError.installationFailed(
                "Only Safari Content Blocker bundles can be enabled as content blockers."
            )
        }
        guard isModuleEnabled(), database != nil else {
            throw ExtensionError.unsupportedOS
        }

        let locatedRules: SafariContentBlockerLocatedRules
        do {
            locatedRules = try SafariContentBlockerRuleLocator.locateRules(in: candidate)
        } catch let error as SafariContentBlockerRuleLocatorError {
            _ = try upsertEntity(
                from: candidate,
                resourceFingerprint: SafariContentBlockerRuleLocator.resourceFingerprint(
                    appexURL: candidate.appexURL
                ),
                isEnabled: false,
                compileStatus: error.persistedCompileStatus,
                lastError: error.localizedDescription,
                ruleListCount: 0,
                ignoredEmptyRuleListCount: 0
            )
            clearRuntime()
            throw ExtensionError.installationFailed(error.localizedDescription)
        }

        let validationService = SumiContentBlockingService(
            policy: .disabled,
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        do {
            let preparedUpdate = try await validationService.prepareRuleListUpdate(
                ruleLists: locatedRules.definitions,
                retainEncodedRuleListsInPreparedPolicy: false
            )
            validationService.commitPreparedContentBlockingUpdate(preparedUpdate)
        } catch {
            _ = try upsertEntity(
                from: candidate,
                resourceFingerprint: locatedRules.resourceFingerprint,
                isEnabled: false,
                compileStatus: .compileFailed,
                lastError: error.localizedDescription,
                ruleListCount: locatedRules.definitions.count,
                ignoredEmptyRuleListCount: locatedRules.ignoredEmptyRuleListCount
            )
            clearRuntime()
            throw ExtensionError.installationFailed(error.localizedDescription)
        }

        let entity = try upsertEntity(
            from: candidate,
            resourceFingerprint: locatedRules.resourceFingerprint,
            isEnabled: true,
            compileStatus: .available,
            lastError: nil,
            ruleListCount: locatedRules.definitions.count,
            ignoredEmptyRuleListCount: locatedRules.ignoredEmptyRuleListCount
        )
        clearRuntime()
        return InstalledSafariContentBlockerRecord(entity: entity)
    }

    func setContentBlockerEnabled(
        _ enabled: Bool,
        bundleIdentifier: String
    ) async throws -> InstalledSafariContentBlockerRecord? {
        guard let database else { return nil }
        guard let entity = try entity(forBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        if enabled {
            let candidate = DiscoveredSafariExtensionCandidate(
                extensionBundleIdentifier: entity.extensionBundleIdentifier,
                displayName: entity.displayName,
                version: entity.version,
                extensionPointIdentifier: SafariExtensionScanner.safariContentBlockerExtensionPointIdentifier,
                bundleKind: .contentBlocker,
                runtimeStatus: .contentBlockerImportable,
                containingAppName: entity.containingAppName,
                containingAppBundleIdentifier: entity.containingAppBundleIdentifier,
                containingAppURL: URL(fileURLWithPath: entity.containingAppPath, isDirectory: true),
                appexURL: URL(fileURLWithPath: entity.appexPath, isDirectory: true),
                manifestURL: nil,
                isReadable: true
            )
            return try await enableContentBlocker(from: candidate)
        }

        entity.isEnabled = false
        entity.lastUpdateDate = Date()
        try database.transaction {
            try $0.safariContentBlockers.save(entity)
        }
        clearRuntime()
        return InstalledSafariContentBlockerRecord(entity: entity)
    }

    func enabledContentBlockingServices(
        for url: URL?,
        profileId: UUID?
    ) -> [SumiContentBlockingService] {
        _ = profileId
        let siteHost = Self.normalizedSiteHost(for: url)
        guard isModuleEnabled(),
              let siteHost,
              siteOverrides[siteHost] != .disabled
        else { return [] }

        let materializedRecords = materializedEnabledContentBlockerRules()
        guard materializedRecords.isEmpty == false else { return [] }

        var definitions: [SumiContentRuleListDefinition] = []
        var cacheParts: [String] = []
        for materialized in materializedRecords {
            let record = materialized.record
            let located = materialized.locatedRules
            definitions.append(contentsOf: located.definitions)
            cacheParts.append("\(record.id):\(located.resourceFingerprint):\(located.definitions.count)")
        }

        guard definitions.isEmpty == false else { return [] }
        let cacheKey = cacheParts.sorted().joined(separator: "|")
        if let service,
           serviceCacheKey == cacheKey {
            return [service]
        }

        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: definitions),
            compiledRuleListCatalog: compiledRuleListCatalog
        )
        self.service = service
        serviceCacheKey = cacheKey
        return [service]
    }

    func attachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        let siteHost = Self.normalizedSiteHost(for: url)
        guard isModuleEnabled() else {
            return .disabled(siteHost: siteHost)
        }

        let materializedRecords = materializedEnabledContentBlockerRules()
        guard materializedRecords.isEmpty == false,
              let siteHost
        else {
            return .disabled(siteHost: siteHost)
        }
        let siteOverride = siteOverrides[siteHost] ?? .inherit
        return SumiSafariContentBlockerAttachmentState(
            siteHost: siteHost,
            isEnabledForSite: siteOverride != .disabled,
            enabledContentBlockerIds: materializedRecords.map(\.record.id).sorted(),
            enabledContentBlockerRuleIdentities: materializedRecords
                .map { "\($0.record.id):\($0.locatedRules.resourceFingerprint)" }
                .sorted()
        )
    }

    func siteState(
        for url: URL?
    ) -> SumiSafariContentBlockerSiteState {
        let siteHost = Self.normalizedSiteHost(for: url)
        let siteOverride = siteHost.flatMap { siteOverrides[$0] } ?? .inherit
        guard isModuleEnabled() else {
            return SumiSafariContentBlockerSiteState(
                siteHost: siteHost,
                isGloballyAvailable: false,
                isEnabledForSite: siteOverride != .disabled,
                enabledContentBlockerCount: 0
            )
        }

        let enabledRecords = materializedEnabledContentBlockerRules()
        return SumiSafariContentBlockerSiteState(
            siteHost: siteHost,
            isGloballyAvailable: !enabledRecords.isEmpty,
            isEnabledForSite: siteOverride != .disabled,
            enabledContentBlockerCount: enabledRecords.count
        )
    }

    func attachedRuleListIdentifiers() -> [String] {
        service?.latestRuleListIdentifiers ?? []
    }

    func setSiteOverride(
        _ override: SumiSafariContentBlockerSiteOverride,
        for url: URL?
    ) {
        guard let host = Self.normalizedSiteHost(for: url) else { return }
        var updated = siteOverrides
        if override == .inherit {
            updated.removeValue(forKey: host)
        } else {
            updated[host] = override
        }
        guard updated != siteOverrides else { return }
        siteOverrides = updated
        do {
            try database?.transaction {
                try $0.safariContentBlockers.replaceSiteOverrides(updated)
            }
        } catch {
            Self.log.error(
                "Failed to persist Safari content blocker site overrides: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func clearRuntime() {
        service = nil
        serviceCacheKey = nil
    }

    #if DEBUG
        func drainRuntimeForTests(cancel: Bool = false) async {
            await service?.drainScheduledTasksForTests(cancel: cancel)
        }
    #endif

    private func entity(
        forBundleIdentifier bundleIdentifier: String
    ) throws -> SafariContentBlockerMetadata? {
        guard let database else { return nil }
        return try database.read {
            try $0.safariContentBlockers.find(bundleID: bundleIdentifier)
        }
    }

    private func materializedEnabledContentBlockerRules() -> [MaterializedContentBlockerRules] {
        guard database != nil else { return [] }
        let enabledRecords = installedContentBlockers()
            .filter { $0.isEnabled && $0.compileStatus == .available }
        guard enabledRecords.isEmpty == false else { return [] }

        var materializedRecords: [MaterializedContentBlockerRules] = []
        var didMutateStoredRecords = false

        for record in enabledRecords {
            let appexURL = URL(fileURLWithPath: record.appexPath, isDirectory: true)
            do {
                let locatedRules = try SafariContentBlockerRuleLocator.locateRules(
                    appexURL: appexURL,
                    extensionBundleIdentifier: record.extensionBundleIdentifier,
                    displayName: record.displayName
                )
                materializedRecords.append(
                    MaterializedContentBlockerRules(
                        record: record,
                        locatedRules: locatedRules
                    )
                )
                didMutateStoredRecords = updateStoredMetadataIfNeeded(
                    for: record,
                    locatedRules: locatedRules
                ) || didMutateStoredRecords
            } catch {
                didMutateStoredRecords = markStoredRecordUnavailable(
                    record,
                    error: error
                ) || didMutateStoredRecords
            }
        }

        if didMutateStoredRecords {
            clearRuntime()
        }

        return materializedRecords
    }

    private func updateStoredMetadataIfNeeded(
        for record: InstalledSafariContentBlockerRecord,
        locatedRules: SafariContentBlockerLocatedRules
    ) -> Bool {
        guard locatedRules.resourceFingerprint != record.resourceFingerprint
                || locatedRules.definitions.count != record.ruleListCount
                || locatedRules.ignoredEmptyRuleListCount != record.ignoredEmptyRuleListCount
        else { return false }

        let storedEntity: SafariContentBlockerMetadata?
        do {
            storedEntity = try entity(forBundleIdentifier: record.extensionBundleIdentifier)
        } catch {
            Self.log.error("Failed to fetch Safari content blocker metadata for \(record.extensionBundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard let entity = storedEntity else {
            return false
        }

        entity.resourceFingerprint = locatedRules.resourceFingerprint
        entity.ruleListCount = locatedRules.definitions.count
        entity.ignoredEmptyRuleListCount = locatedRules.ignoredEmptyRuleListCount
        entity.compileStatus = .available
        entity.lastError = nil
        entity.lastUpdateDate = Date()
        return persistMetadataRepair(entity)
    }

    private func markStoredRecordUnavailable(
        _ record: InstalledSafariContentBlockerRecord,
        error: Error
    ) -> Bool {
        let storedEntity: SafariContentBlockerMetadata?
        do {
            storedEntity = try entity(forBundleIdentifier: record.extensionBundleIdentifier)
        } catch {
            Self.log.error("Failed to fetch unavailable Safari content blocker record \(record.extensionBundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard let entity = storedEntity else {
            return false
        }

        let compileStatus = (error as? SafariContentBlockerRuleLocatorError)?
            .persistedCompileStatus ?? SafariContentBlockerCompileStatus.rulesUnavailable
        var didMutate = false

        func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<SafariContentBlockerMetadata, T>, _ value: T) {
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
        return didMutate && persistMetadataRepair(entity)
    }

    private func upsertEntity(
        from candidate: DiscoveredSafariExtensionCandidate,
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
            existing.containingAppBundleIdentifier = candidate.containingAppBundleIdentifier
            existing.appexPath = candidate.appexURL.path
            existing.containingAppPath = candidate.containingAppURL.path
            existing.resourceFingerprint = resourceFingerprint
            existing.isEnabled = isEnabled
            existing.lastUpdateDate = Date()
            existing.compileStatus = compileStatus
            existing.lastError = lastError
            existing.ruleListCount = ruleListCount
            existing.ignoredEmptyRuleListCount = ignoredEmptyRuleListCount
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
            containingAppBundleIdentifier: candidate.containingAppBundleIdentifier,
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

    private func persistMetadataRepair(
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

    private static func normalizedSiteHost(for url: URL?) -> String? {
        SumiSiteNormalizer().normalizedHost(for: url)
    }
}

private extension SafariContentBlockerRuleLocatorError {
    var persistedCompileStatus: SafariContentBlockerCompileStatus {
        switch self {
        case .resourcesDirectoryMissing, .staticRulesUnavailable:
            return .rulesUnavailable
        case .invalidJSON, .invalidRuleListShape:
            return .compileFailed
        }
    }
}
