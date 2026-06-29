import Foundation
import SwiftData

@MainActor
final class SafariContentBlockerRuntimeOwner {
    private let context: ModelContext?
    private let defaults: UserDefaults
    private let isModuleEnabled: @MainActor () -> Bool

    private var service: SumiContentBlockingService?
    private var serviceCacheKey: String?
    private var siteOverrides: [String: SumiSafariContentBlockerSiteOverride]

    init(
        context: ModelContext?,
        defaults: UserDefaults,
        isModuleEnabled: @escaping @MainActor () -> Bool
    ) {
        self.context = context
        self.defaults = defaults
        self.isModuleEnabled = isModuleEnabled
        self.siteOverrides = Self.loadSiteOverrides(from: defaults)
    }

    func installedContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        guard let context else { return [] }
        do {
            return try context.fetch(FetchDescriptor<SafariContentBlockerEntity>())
                .map(InstalledSafariContentBlockerRecord.init)
                .sorted {
                    if $0.containingAppName == $1.containingAppName {
                        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                    return $0.containingAppName.localizedCaseInsensitiveCompare($1.containingAppName) == .orderedAscending
                }
        } catch {
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
        guard isModuleEnabled(), let context else {
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
            try context.save()
            clearRuntime()
            throw ExtensionError.installationFailed(error.localizedDescription)
        }

        let validationService = SumiContentBlockingService(policy: .disabled)
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
            try context.save()
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
        try context.save()
        clearRuntime()
        return InstalledSafariContentBlockerRecord(entity: entity)
    }

    func setContentBlockerEnabled(
        _ enabled: Bool,
        bundleIdentifier: String
    ) async throws -> InstalledSafariContentBlockerRecord? {
        guard let context else { return nil }
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
        try context.save()
        clearRuntime()
        return InstalledSafariContentBlockerRecord(entity: entity)
    }

    func enabledContentBlockingServices(
        for url: URL?,
        profileId: UUID?
    ) -> [SumiContentBlockingService] {
        _ = profileId
        guard isModuleEnabled(),
              attachmentState(for: url).isEnabled,
              let context
        else { return [] }

        let enabledRecords = installedContentBlockers()
            .filter { $0.isEnabled && $0.compileStatus == .available }
        guard enabledRecords.isEmpty == false else { return [] }

        var definitions: [SumiContentRuleListDefinition] = []
        var cacheParts: [String] = []
        for record in enabledRecords {
            let appexURL = URL(fileURLWithPath: record.appexPath, isDirectory: true)
            do {
                let located = try SafariContentBlockerRuleLocator.locateRules(
                    appexURL: appexURL,
                    extensionBundleIdentifier: record.extensionBundleIdentifier,
                    displayName: record.displayName
                )
                definitions.append(contentsOf: located.definitions)
                cacheParts.append("\(record.id):\(located.resourceFingerprint):\(located.definitions.count)")
                if located.resourceFingerprint != record.resourceFingerprint,
                   let entity = try? entity(
                       forBundleIdentifier: record.extensionBundleIdentifier
                   ) {
                    entity.resourceFingerprint = located.resourceFingerprint
                    entity.ruleListCount = located.definitions.count
                    entity.ignoredEmptyRuleListCount = located.ignoredEmptyRuleListCount
                    entity.lastUpdateDate = Date()
                    try? context.save()
                }
            } catch {
                continue
            }
        }

        guard definitions.isEmpty == false else { return [] }
        let cacheKey = cacheParts.sorted().joined(separator: "|")
        if let service,
           serviceCacheKey == cacheKey {
            return [service]
        }

        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: definitions)
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

        let enabledRecords = installedContentBlockers()
            .filter { $0.isEnabled && $0.compileStatus == .available }
        guard enabledRecords.isEmpty == false,
              let siteHost
        else {
            return .disabled(siteHost: siteHost)
        }
        let siteOverride = siteOverrides[siteHost] ?? .inherit
        return SumiSafariContentBlockerAttachmentState(
            siteHost: siteHost,
            isEnabledForSite: siteOverride != .disabled,
            enabledContentBlockerIds: enabledRecords.map(\.id).sorted(),
            enabledContentBlockerRuleIdentities: enabledRecords
                .map { "\($0.id):\($0.resourceFingerprint)" }
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

        let enabledRecords = installedContentBlockers()
            .filter { $0.isEnabled && $0.compileStatus == .available }
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
        Self.persistSiteOverrides(updated, to: defaults)
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
    ) throws -> SafariContentBlockerEntity? {
        guard let context else { return nil }
        return try context.fetch(FetchDescriptor<SafariContentBlockerEntity>())
            .first { $0.extensionBundleIdentifier == bundleIdentifier }
    }

    private func upsertEntity(
        from candidate: DiscoveredSafariExtensionCandidate,
        resourceFingerprint: String,
        isEnabled: Bool,
        compileStatus: SafariContentBlockerCompileStatus,
        lastError: String?,
        ruleListCount: Int,
        ignoredEmptyRuleListCount: Int
    ) throws -> SafariContentBlockerEntity {
        guard let context else {
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
            return existing
        }

        let entity = SafariContentBlockerEntity(
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
        context.insert(entity)
        return entity
    }

    private static let siteOverridesDefaultsKey =
        "\(SumiAppIdentity.bundleIdentifier).extensions.safariContentBlocker.siteOverrides.v1"

    private static func normalizedSiteHost(for url: URL?) -> String? {
        SumiSiteNormalizer().normalizedHost(for: url)
    }

    private static func loadSiteOverrides(
        from defaults: UserDefaults
    ) -> [String: SumiSafariContentBlockerSiteOverride] {
        guard let data = defaults.data(forKey: siteOverridesDefaultsKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return raw.reduce(into: [:]) { result, entry in
            guard let override = SumiSafariContentBlockerSiteOverride(rawValue: entry.value),
                  override != .inherit
            else { return }
            result[entry.key] = override
        }
    }

    private static func persistSiteOverrides(
        _ overrides: [String: SumiSafariContentBlockerSiteOverride],
        to defaults: UserDefaults
    ) {
        let raw = overrides.mapValues(\.rawValue)
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: siteOverridesDefaultsKey)
        }
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
