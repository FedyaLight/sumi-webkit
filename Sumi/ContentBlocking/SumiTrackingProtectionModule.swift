import Combine
import Foundation

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

    private var cachedSettings: SumiTrackingProtectionSettings?
    private var cachedDataStore: SumiTrackingProtectionDataStore?
    private var cachedContentBlockingService: SumiContentBlockingService?

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
        }
    ) {
        self.moduleRegistry = moduleRegistry
        self.settingsFactory = settingsFactory
        self.dataStoreFactory = dataStoreFactory
        self.contentBlockingServiceFactory = contentBlockingServiceFactory
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
        if let cachedContentBlockingService {
            return cachedContentBlockingService
        }
        let settings = settingsIfEnabled()
        let dataStore = dataStoreIfEnabled()
        guard let settings, let dataStore else { return nil }
        let service = contentBlockingServiceFactory(settings, dataStore)
        cachedContentBlockingService = service
        return service
    }

    func effectivePolicyIfEnabled(for url: URL?) -> SumiTrackingProtectionEffectivePolicy? {
        settingsIfEnabled()?.resolve(for: url)
    }

    func settingsChangesPublisherIfEnabled() -> AnyPublisher<Void, Never> {
        settingsIfEnabled()?.changesPublisher ?? Empty().eraseToAnyPublisher()
    }
}
