import Combine
import Foundation

enum SumiTrackingProtectionManualUpdateResult: Equatable, Sendable {
    case disabled
    case alreadyInProgress
    case downloaded(date: Date, etag: String)
    case notModified(date: Date)
    case resetToBundled
    case failed(message: String)
}

struct SumiTrackingProtectionNormalTabContentBlockingDecision {
    let effectivePolicy: SumiTrackingProtectionEffectivePolicy
    let contentBlockingService: SumiContentBlockingService?

    var attachmentState: SumiTrackingProtectionAttachmentState {
        effectivePolicy.attachmentState
    }
}

@MainActor
final class SumiTrackingProtectionModule {
    static let shared = SumiTrackingProtectionModule()

    private let moduleRegistry: SumiModuleRegistry
    private let settingsFactory: @MainActor () -> SumiTrackingProtectionSettings
    private let dataStoreFactory: @MainActor () -> SumiTrackingProtectionDataStore
    private let contentBlockingServiceFactory: @MainActor (
        SumiTrackingProtectionSettings,
        SumiTrackingProtectionDataStore
    ) -> SumiContentBlockingService
    private let siteNormalizer: SumiTrackingProtectionSiteNormalizer

    private var cachedSettings: SumiTrackingProtectionSettings?
    private var cachedDataStore: SumiTrackingProtectionDataStore?
    private var cachedContentBlockingService: SumiContentBlockingService?
    private var cachedContentBlockingServicePolicy: SumiTrackingProtectionPolicy?

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        settingsFactory: @escaping @MainActor () -> SumiTrackingProtectionSettings = { .shared },
        dataStoreFactory: @escaping @MainActor () -> SumiTrackingProtectionDataStore = { .shared },
        contentBlockingServiceFactory: @escaping @MainActor (
            SumiTrackingProtectionSettings,
            SumiTrackingProtectionDataStore
        ) -> SumiContentBlockingService = { settings, dataStore in
            SumiContentBlockingService(
                policy: .defaultPolicy,
                trackingProtectionSettings: settings,
                trackingRuleSource: SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore),
                trackingDataStore: dataStore,
                siteDataPolicyStore: .shared,
                siteDataRuleSource: SumiSiteDataCookieBlockingRuleSource()
            )
        },
        siteNormalizer: SumiTrackingProtectionSiteNormalizer = SumiTrackingProtectionSiteNormalizer()
    ) {
        self.moduleRegistry = moduleRegistry
        self.settingsFactory = settingsFactory
        self.dataStoreFactory = dataStoreFactory
        self.contentBlockingServiceFactory = contentBlockingServiceFactory
        self.siteNormalizer = siteNormalizer
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.trackingProtection)
    }

    func settingsIfEnabled() -> SumiTrackingProtectionSettings? {
        guard isEnabled else { return nil }
        if let cachedSettings {
            return cachedSettings
        }
        let settings = settingsFactory()
        cachedSettings = settings
        return settings
    }

    func dataStoreIfEnabled() -> SumiTrackingProtectionDataStore? {
        guard isEnabled else { return nil }
        if let cachedDataStore {
            return cachedDataStore
        }
        let dataStore = dataStoreFactory()
        cachedDataStore = dataStore
        return dataStore
    }

    func contentBlockingServiceIfEnabled() -> SumiContentBlockingService? {
        guard isEnabled else { return nil }
        let settings = settingsIfEnabled()
        let dataStore = dataStoreIfEnabled()
        guard let settings, let dataStore else { return nil }

        let currentPolicy = settings.policy
        if let cachedContentBlockingService,
           cachedContentBlockingServicePolicy == currentPolicy {
            return cachedContentBlockingService
        }

        let service = contentBlockingServiceFactory(settings, dataStore)
        cachedContentBlockingService = service
        cachedContentBlockingServicePolicy = currentPolicy
        return service
    }

    func normalizedSiteHost(for url: URL?) -> String? {
        siteNormalizer.normalizedHost(for: url)
    }

    func effectivePolicy(for url: URL?) -> SumiTrackingProtectionEffectivePolicy {
        guard isEnabled else {
            return SumiTrackingProtectionEffectivePolicy(
                host: normalizedSiteHost(for: url),
                isEnabled: false,
                source: .moduleDisabled
            )
        }
        return settingsIfEnabled()?.resolve(for: url)
            ?? SumiTrackingProtectionEffectivePolicy(
                host: normalizedSiteHost(for: url),
                isEnabled: false,
                source: .moduleDisabled
            )
    }

    func effectivePolicyIfEnabled(for url: URL?) -> SumiTrackingProtectionEffectivePolicy? {
        settingsIfEnabled()?.resolve(for: url)
    }

    func siteOverrideIfEnabled(for url: URL?) -> SumiTrackingProtectionSiteOverride? {
        settingsIfEnabled()?.override(for: url)
    }

    func normalTabContentBlockingDecision(
        for url: URL?
    ) -> SumiTrackingProtectionNormalTabContentBlockingDecision {
        let policy = effectivePolicy(for: url)
        guard policy.isEnabled else {
            return SumiTrackingProtectionNormalTabContentBlockingDecision(
                effectivePolicy: policy,
                contentBlockingService: nil
            )
        }

        return SumiTrackingProtectionNormalTabContentBlockingDecision(
            effectivePolicy: policy,
            contentBlockingService: contentBlockingServiceIfEnabled()
        )
    }

    func settingsChangesPublisherIfEnabled() -> AnyPublisher<Void, Never> {
        settingsIfEnabled()?.changesPublisher ?? Empty().eraseToAnyPublisher()
    }

    func updateTrackerDataManually(
        updaterFactory: () -> SumiTrackerDataUpdater = { SumiTrackerDataUpdater() }
    ) async -> SumiTrackingProtectionManualUpdateResult {
        guard isEnabled else { return .disabled }
        guard let settings = settingsIfEnabled(),
              let dataStore = dataStoreIfEnabled(),
              let service = contentBlockingServiceIfEnabled()
        else { return .disabled }

        guard dataStore.beginManualUpdate() else {
            return .alreadyInProgress
        }
        defer { dataStore.endManualUpdate() }

        do {
            let updater = updaterFactory()
            let updateResult = try await updater.updateTrackerData(
                currentETag: dataStore.activeETag
            )

            switch updateResult {
            case .downloaded(let data, let etag, let date):
                let stagedDataSet = try dataStore.downloadedDataSet(
                    from: data,
                    etag: etag
                )
                let preparedUpdate = try await prepareManualTrackingDataUpdate(
                    dataSet: stagedDataSet,
                    settings: settings,
                    service: service
                )
                try dataStore.storeDownloadedData(
                    data,
                    etag: etag,
                    date: date,
                    notifyChanges: false
                )
                service.commitPreparedManualTrackingDataUpdate(preparedUpdate)
                return .downloaded(date: date, etag: etag)

            case .notModified(let date):
                dataStore.noteSuccessfulNotModifiedUpdate(date: date)
                return .notModified(date: date)
            }
        } catch {
            dataStore.recordUpdateError(error)
            return .failed(message: Self.errorMessage(error))
        }
    }

    func resetTrackerDataToBundledManually() async -> SumiTrackingProtectionManualUpdateResult {
        guard isEnabled else { return .disabled }
        guard let settings = settingsIfEnabled(),
              let dataStore = dataStoreIfEnabled(),
              let service = contentBlockingServiceIfEnabled()
        else { return .disabled }

        guard dataStore.beginManualUpdate() else {
            return .alreadyInProgress
        }
        defer { dataStore.endManualUpdate() }

        do {
            let bundledDataSet = try dataStore.loadBundledDataSet()
            let preparedUpdate = try await prepareManualTrackingDataUpdate(
                dataSet: bundledDataSet,
                settings: settings,
                service: service
            )
            dataStore.resetToBundled(notifyChanges: false)
            service.commitPreparedManualTrackingDataUpdate(preparedUpdate)
            return .resetToBundled
        } catch {
            dataStore.recordUpdateError(error)
            return .failed(message: Self.errorMessage(error))
        }
    }

    private func prepareManualTrackingDataUpdate(
        dataSet: SumiTrackerDataSet,
        settings: SumiTrackingProtectionSettings,
        service: SumiContentBlockingService
    ) async throws -> SumiPreparedContentBlockingUpdate {
        let validationRuleLists = try SumiEmbeddedDDGTrackerDataRuleSource.ruleLists(
            for: validationPolicy(for: settings.policy),
            trackerData: dataSet.trackerData
        )
        try await service.validateManualTrackingRuleLists(validationRuleLists)

        let activeTrackingRuleLists = try SumiEmbeddedDDGTrackerDataRuleSource.ruleLists(
            for: settings.policy,
            trackerData: dataSet.trackerData
        )
        return try await service.prepareManualTrackingDataUpdate(
            trackingRuleLists: activeTrackingRuleLists
        )
    }

    private func validationPolicy(
        for policy: SumiTrackingProtectionPolicy
    ) -> SumiTrackingProtectionPolicy {
        guard policy.requiresRuleList else {
            return SumiTrackingProtectionPolicy(
                globalMode: .enabled,
                enabledSiteHosts: [],
                disabledSiteHosts: []
            )
        }
        return policy
    }

    private static func errorMessage(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
