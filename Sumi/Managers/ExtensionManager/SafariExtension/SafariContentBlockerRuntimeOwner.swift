import Foundation
import OSLog
import SumiDomain

@MainActor
final class SafariContentBlockerRuntimeOwner {
    private static let log = Logger.sumi(category: "SafariContentBlocker")

    private let metadataStore: SafariContentBlockerMetadataStore
    private let inventoryStore: SafariContentBlockerPreparedInventoryStore
    private let isModuleEnabled: @MainActor () -> Bool
    private let onPreparedInventoryRefresh: @MainActor () -> Void
    private let compiledRuleListCatalog: SumiCompiledContentRuleListCataloging

    private var installedRecords: [InstalledSafariContentBlockerRecord]
    private var recordsByBundleIdentifier:
        [String: InstalledSafariContentBlockerRecord]
    private var service: SumiContentBlockingService?
    private var serviceCacheKey: String?
    private var preparationTask: Task<Void, Never>?
    private var runtimeGeneration: UInt64 = 0
    private var siteOverrides: [String: SumiSafariContentBlockerSiteOverride]
    private var sourceMonitor: SafariContentBlockerSourceMonitor?

    init(
        database: SumiDatabase?,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        isModuleEnabled: @escaping @MainActor () -> Bool,
        onPreparedInventoryRefresh: @escaping @MainActor () -> Void = {}
    ) {
        let metadataStore = SafariContentBlockerMetadataStore(
            database: database
        )
        self.metadataStore = metadataStore
        self.inventoryStore = SafariContentBlockerPreparedInventoryStore(
            database: database
        )
        self.compiledRuleListCatalog = compiledRuleListCatalog
        self.isModuleEnabled = isModuleEnabled
        self.onPreparedInventoryRefresh = onPreparedInventoryRefresh
        let installedRecords = metadataStore.installedRecords()
        self.installedRecords = installedRecords
        self.recordsByBundleIdentifier = Dictionary(
            installedRecords.map { ($0.extensionBundleIdentifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        self.siteOverrides = metadataStore.siteOverrides()
        sourceMonitor = makeSourceMonitor()

        if isModuleEnabled(),
           installedRecords.contains(where: Self.isRuntimeEnabledRecord) {
            prepareRuntimeIfNeeded()
        }
        sourceMonitor?.reconcileObservation()
    }

    isolated deinit {
        preparationTask?.cancel()
        sourceMonitor?.stop()
    }

    func installedContentBlockers() -> [InstalledSafariContentBlockerRecord] {
        installedRecords
    }

    func contentBlockerRecord(
        forBundleIdentifier bundleIdentifier: String
    ) -> InstalledSafariContentBlockerRecord? {
        recordsByBundleIdentifier[bundleIdentifier]
    }

    func enableContentBlocker(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledSafariContentBlockerRecord {
        guard candidate.bundleKind == .contentBlocker else {
            throw ExtensionError.installationFailed(
                "Only Safari Content Blocker bundles can be enabled as content blockers."
            )
        }
        guard isModuleEnabled(), metadataStore.isAvailable else {
            throw ExtensionError.unsupportedOS
        }

        let locatedRules: SafariContentBlockerLocatedRules
        do {
            locatedRules = try await Self.locateRules(in: candidate)
        } catch let error as SafariContentBlockerRuleLocatorError {
            let fingerprint = await Self.resourceFingerprint(
                appexURL: candidate.appexURL
            )
            _ = try metadataStore.upsert(
                candidate: candidate,
                resourceFingerprint: fingerprint,
                isEnabled: false,
                compileStatus: error.persistedCompileStatus,
                lastError: error.localizedDescription,
                ruleListCount: 0,
                ignoredEmptyRuleListCount: 0
            )
            reloadInstalledRecords()
            inventoryStore.remove(
                blockerID: candidate.extensionBundleIdentifier
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
            _ = try metadataStore.upsert(
                candidate: candidate,
                resourceFingerprint: locatedRules.resourceFingerprint,
                isEnabled: false,
                compileStatus: .compileFailed,
                lastError: error.localizedDescription,
                ruleListCount: locatedRules.definitions.count,
                ignoredEmptyRuleListCount: locatedRules.ignoredEmptyRuleListCount
            )
            reloadInstalledRecords()
            inventoryStore.remove(
                blockerID: candidate.extensionBundleIdentifier
            )
            clearRuntime()
            throw ExtensionError.installationFailed(error.localizedDescription)
        }

        let entity = try metadataStore.upsert(
            candidate: candidate,
            resourceFingerprint: locatedRules.resourceFingerprint,
            isEnabled: true,
            compileStatus: .available,
            lastError: nil,
            ruleListCount: locatedRules.definitions.count,
            ignoredEmptyRuleListCount: locatedRules.ignoredEmptyRuleListCount
        )
        let record = InstalledSafariContentBlockerRecord(entity: entity)
        reloadInstalledRecords()
        inventoryStore.upsert(record: record, locatedRules: locatedRules)
        replaceRuntimeService(
            validationService,
            cacheKey: runtimeCacheKey(for: enabledRuntimeRecords())
        )
        return record
    }

    func setContentBlockerEnabled(
        _ enabled: Bool,
        bundleIdentifier: String
    ) async throws -> InstalledSafariContentBlockerRecord? {
        guard metadataStore.isAvailable else { return nil }
        guard let entity = try metadataStore.entity(
            forBundleIdentifier: bundleIdentifier
        ) else {
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

        try metadataStore.setEnabled(false, entity: entity)
        reloadInstalledRecords()
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

        guard enabledRuntimeRecords().isEmpty == false else { return [] }
        let service = preparedService()
        prepareRuntimeIfNeeded()
        return [service]
    }

    func attachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        let siteHost = Self.normalizedSiteHost(for: url)
        guard isModuleEnabled() else {
            return .disabled(siteHost: siteHost)
        }

        let enabledRecords = enabledRuntimeRecords()
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

        let enabledRecords = enabledRuntimeRecords()
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
            try metadataStore.replaceSiteOverrides(updated)
        } catch {
            Self.log.error(
                "Failed to persist Safari content blocker site overrides: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func clearRuntime() {
        runtimeGeneration &+= 1
        preparationTask?.cancel()
        preparationTask = nil
        service?.stopRuntime()
        service = nil
        serviceCacheKey = nil
        sourceMonitor?.reconcileObservation()
    }

    #if DEBUG
        func drainRuntimeForTests(cancel: Bool = false) async {
            if cancel {
                preparationTask?.cancel()
            }
            await sourceMonitor?.drainForTests(cancel: cancel)
            await preparationTask?.value
            await service?.drainScheduledTasksForTests(cancel: cancel)
        }
    #endif

    private func preparedService() -> SumiContentBlockingService {
        if let service {
            return service
        }
        let service = SumiContentBlockingService(
            pendingCompiledRuleListCatalog: compiledRuleListCatalog
        )
        self.service = service
        return service
    }

    private func refreshPreparedInventory() async {
        clearRuntime()
        prepareRuntimeIfNeeded(forceSourceRefresh: true)
        await preparationTask?.value
    }

    private func prepareRuntimeIfNeeded(
        forceSourceRefresh: Bool = false
    ) {
        guard isModuleEnabled() else { return }
        let records = enabledRuntimeRecords()
        guard records.isEmpty == false else { return }
        let cacheKey = runtimeCacheKey(for: records)
        guard serviceCacheKey != cacheKey, preparationTask == nil else {
            return
        }

        let service = preparedService()
        runtimeGeneration &+= 1
        let generation = runtimeGeneration
        preparationTask = Task { [weak self, service] in
            await self?.prepareRuntime(
                generation: generation,
                records: records,
                cacheKey: cacheKey,
                forceSourceRefresh: forceSourceRefresh,
                service: service
            )
        }
    }

    private func prepareRuntime(
        generation: UInt64,
        records: [InstalledSafariContentBlockerRecord],
        cacheKey: String,
        forceSourceRefresh: Bool,
        service: SumiContentBlockingService
    ) async {
        defer {
            if runtimeGeneration == generation {
                preparationTask = nil
            }
        }

        if forceSourceRefresh == false,
           let blockers = inventoryStore.preparedBlockers(
            matching: records
        ) {
            let definitions = blockers.flatMap {
                $0.ruleLists.map(\.definition)
            }
            do {
                let prepared = try await service
                    .prepareExistingRuleListUpdate(ruleLists: definitions)
                guard canCommit(
                    generation: generation,
                    service: service
                ) else { return }
                service.commitPreparedContentBlockingUpdate(prepared)
                serviceCacheKey = cacheKey
                return
            } catch {
                Self.log.notice(
                    "Compiled Safari content blocker inventory missed WebKit storage; refreshing source rules: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        var located: [(
            record: InstalledSafariContentBlockerRecord,
            rules: SafariContentBlockerLocatedRules
        )] = []
        var unavailableBlockerIDs = Set<String>()
        var didMutateStoredRecords = false
        for record in records {
            guard Task.isCancelled == false else { return }
            do {
                let rules = try await Self.locateRules(for: record)
                located.append((record, rules))
                didMutateStoredRecords =
                    metadataStore.repair(
                        record: record,
                        locatedRules: rules
                    ) || didMutateStoredRecords
            } catch {
                unavailableBlockerIDs.insert(record.id)
                didMutateStoredRecords =
                    metadataStore.markUnavailable(record, error: error)
                    || didMutateStoredRecords
            }
        }

        guard canCommit(generation: generation, service: service) else {
            return
        }
        if didMutateStoredRecords {
            reloadInstalledRecords()
        }
        inventoryStore.replace(
            with: located.map {
                SafariContentBlockerPreparedInventory.Blocker(
                    record: $0.record,
                    locatedRules: $0.rules
                )
            },
            removing: unavailableBlockerIDs
        )

        let definitions = located.flatMap(\.rules.definitions)
        guard definitions.isEmpty == false else {
            service.setPolicy(.disabled)
            serviceCacheKey = nil
            return
        }

        do {
            let prepared = try await service.prepareRuleListUpdate(
                ruleLists: definitions,
                retainEncodedRuleListsInPreparedPolicy: false
            )
            guard canCommit(generation: generation, service: service) else {
                return
            }
            service.commitPreparedContentBlockingUpdate(prepared)
            serviceCacheKey = runtimeCacheKey(
                for: enabledRuntimeRecords()
            )
        } catch {
            Self.log.error(
                "Failed to prepare Safari content blocker runtime: \(error.localizedDescription, privacy: .public)"
            )
            service.setPolicy(.disabled)
            serviceCacheKey = nil
        }
    }

    private func canCommit(
        generation: UInt64,
        service: SumiContentBlockingService
    ) -> Bool {
        Task.isCancelled == false
            && runtimeGeneration == generation
            && self.service === service
            && isModuleEnabled()
    }

    private func enabledRuntimeRecords()
        -> [InstalledSafariContentBlockerRecord] {
        installedRecords.filter(Self.isRuntimeEnabledRecord)
    }

    private static func isRuntimeEnabledRecord(
        _ record: InstalledSafariContentBlockerRecord
    ) -> Bool {
        record.isEnabled && record.compileStatus == .available
    }

    private func runtimeCacheKey(
        for records: [InstalledSafariContentBlockerRecord]
    ) -> String {
        records
            .map {
                "\($0.id):\($0.resourceFingerprint):\($0.ruleListCount)"
            }
            .sorted()
            .joined(separator: "|")
    }

    private func replaceRuntimeService(
        _ replacement: SumiContentBlockingService,
        cacheKey: String
    ) {
        runtimeGeneration &+= 1
        preparationTask?.cancel()
        preparationTask = nil
        if let service, service !== replacement {
            service.stopRuntime()
        }
        service = replacement
        serviceCacheKey = cacheKey
    }

    private func reloadInstalledRecords() {
        let records = metadataStore.installedRecords()
        installedRecords = records
        recordsByBundleIdentifier = Dictionary(
            records.map { ($0.extensionBundleIdentifier, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        sourceMonitor?.reconcileObservation()
    }

    private func makeSourceMonitor() -> SafariContentBlockerSourceMonitor {
        SafariContentBlockerSourceMonitor(
            shouldObserve: { [weak self] in
                guard let self else { return false }
                return isModuleEnabled()
                    && enabledRuntimeRecords().isEmpty == false
            },
            sources: { [weak self] in
                self?.enabledRuntimeRecords().map {
                    SafariContentBlockerSourceMonitor.Source(
                        id: $0.id,
                        appexPath: $0.appexPath
                    )
                } ?? []
            },
            sourceStampsMatch: { [weak self] stamps in
                guard let self else { return true }
                return inventoryStore.sourceStampsMatch(
                    stamps,
                    records: enabledRuntimeRecords()
                )
            },
            onStale: { [weak self] in
                guard let self else { return }
                await refreshPreparedInventory()
                onPreparedInventoryRefresh()
            }
        )
    }

    private static func locateRules(
        in candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> SafariContentBlockerLocatedRules {
        let appexURL = candidate.appexURL
        let extensionBundleIdentifier = candidate.extensionBundleIdentifier
        let displayName = candidate.displayName
        return try await Task.detached(priority: .utility) {
            try SafariContentBlockerRuleLocator.locateRules(
                appexURL: appexURL,
                extensionBundleIdentifier: extensionBundleIdentifier,
                displayName: displayName
            )
        }.value
    }

    private static func locateRules(
        for record: InstalledSafariContentBlockerRecord
    ) async throws -> SafariContentBlockerLocatedRules {
        let appexURL = URL(
            fileURLWithPath: record.appexPath,
            isDirectory: true
        )
        let extensionBundleIdentifier = record.extensionBundleIdentifier
        let displayName = record.displayName
        return try await Task.detached(priority: .utility) {
            try SafariContentBlockerRuleLocator.locateRules(
                appexURL: appexURL,
                extensionBundleIdentifier: extensionBundleIdentifier,
                displayName: displayName
            )
        }.value
    }

    private static func resourceFingerprint(appexURL: URL) async -> String {
        await Task.detached(priority: .utility) {
            SafariContentBlockerRuleLocator.resourceFingerprint(
                appexURL: appexURL
            )
        }.value
    }

    private static func normalizedSiteHost(for url: URL?) -> String? {
        SumiSiteNormalizer().normalizedHost(for: url)
    }
}
