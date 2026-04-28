import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

actor SiteSettingsFakePermissionCoordinator: SumiPermissionCoordinating {
    private var recordsByIdentity: [String: SumiPermissionStoreRecord] = [:]
    private(set) var resetKeys: [SumiPermissionKey] = []
    private(set) var setKeys: [SumiPermissionKey] = []

    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .promptRequired,
            state: .ask,
            persistence: nil,
            source: .defaultSetting,
            reason: "fake",
            permissionTypes: context.request.permissionTypes
        )
    }

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision {
        await requestPermission(context)
    }

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery? {
        _ = pageId
        return nil
    }

    func stateSnapshot() async -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in continuation.finish() }
    }

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return recordsByIdentity.values
            .filter {
                $0.key.profilePartitionId == profileId
                    && $0.key.isEphemeralProfile == isEphemeralProfile
            }
            .sorted { $0.key.persistentIdentity < $1.key.persistentIdentity }
    }

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws {
        setKeys.append(key)
        let decision = SumiPermissionDecision(
            state: state,
            persistence: key.isEphemeralProfile ? .session : .persistent,
            source: source,
            reason: reason
        )
        recordsByIdentity[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetSiteDecision(for key: SumiPermissionKey) async throws {
        resetKeys.append(key)
        recordsByIdentity.removeValue(forKey: key.persistentIdentity)
    }

    func resetSiteDecisions(for keys: [SumiPermissionKey]) async throws {
        for key in keys {
            try await resetSiteDecision(for: key)
        }
    }

    func seed(
        key: SumiPermissionKey,
        state: SumiPermissionState,
        updatedAt: Date = Date()
    ) {
        let decision = SumiPermissionDecision(
            state: state,
            persistence: key.isEphemeralProfile ? .session : .persistent,
            source: .user,
            updatedAt: updatedAt
        )
        recordsByIdentity[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func record(for key: SumiPermissionKey) -> SumiPermissionStoreRecord? {
        recordsByIdentity[key.persistentIdentity]
    }

    func cancel(queryId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancel(requestId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancel(pageId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancelNavigation(pageId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    func cancelTab(tabId: String, reason: String) async -> SumiPermissionCoordinatorDecision {
        cancellationDecision(reason: reason)
    }

    private func cancellationDecision(reason: String) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: []
        )
    }
}

struct SiteSettingsFakeSystemPermissionService: SumiSystemPermissionService {
    let states: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState]
    let onOpen: (@Sendable (SumiSystemPermissionKind) async -> Void)?

    init(
        states: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] = [:],
        onOpen: (@Sendable (SumiSystemPermissionKind) async -> Void)? = nil
    ) {
        self.states = states
        self.onOpen = onOpen
    }

    func authorizationState(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState {
        states[kind] ?? .authorized
    }

    func requestAuthorization(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState {
        states[kind] ?? .authorized
    }

    func openSystemSettings(for kind: SumiSystemPermissionKind) async -> Bool {
        await onOpen?(kind)
        return true
    }
}

@MainActor
final class SiteSettingsFakeWebsiteDataService: SumiWebsiteDataCleanupServicing {
    var entries: [SumiSiteDataEntry] = []
    private(set) var exactHostRemovals: [String] = []

    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        _ = dataStore
        return []
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        _ = dataTypes
        _ = dataStore
        return []
    }

    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        _ = domain
        _ = dataTypes
        _ = dataStore
        return entries
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = selection
        _ = dataStore
    }

    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = dataTypes
        _ = date
        _ = dataStore
    }

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = includingCookies
        _ = dataStore
        exactHostRemovals.append(domain)
    }

    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = dataTypes
        _ = includingCookies
        _ = dataStore
        exactHostRemovals.append(host)
    }

    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = dataTypes
        _ = includingCookies
        _ = dataStore
        exactHostRemovals.append(contentsOf: domains.sorted())
    }

    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async {
        _ = dataStore
    }
}

@MainActor
struct SiteSettingsRepositoryHarness {
    let profile: Profile
    let coordinator: SiteSettingsFakePermissionCoordinator
    let recentStore: SumiPermissionRecentActivityStore
    let blockedPopupStore: SumiBlockedPopupStore
    let externalSchemeStore: SumiExternalSchemeSessionStore
    let indicatorStore: SumiPermissionIndicatorEventStore
    let websiteDataService: SiteSettingsFakeWebsiteDataService
    let autoplayStore: SumiAutoplayPolicyStoreAdapter
    let repository: SumiPermissionSettingsRepository
    let modelContainer: ModelContainer
    let userDefaults: UserDefaults

    init(
        profile: Profile? = nil,
        system: SiteSettingsFakeSystemPermissionService = SiteSettingsFakeSystemPermissionService(),
        userDefaults: UserDefaults = UserDefaults(
            suiteName: "SumiSiteSettingsTests-\(UUID().uuidString)"
        )!
    ) throws {
        self.profile = profile ?? Profile(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            name: "Work",
            icon: "person"
        )
        self.coordinator = SiteSettingsFakePermissionCoordinator()
        self.recentStore = SumiPermissionRecentActivityStore()
        self.blockedPopupStore = SumiBlockedPopupStore()
        self.externalSchemeStore = SumiExternalSchemeSessionStore()
        self.indicatorStore = SumiPermissionIndicatorEventStore()
        self.websiteDataService = SiteSettingsFakeWebsiteDataService()
        self.userDefaults = userDefaults
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        self.modelContainer = container
        let store = SwiftDataPermissionStore(container: container)
        self.autoplayStore = SumiAutoplayPolicyStoreAdapter(
            modelContainer: container,
            persistentStore: store
        )
        self.repository = SumiPermissionSettingsRepository(
            coordinator: coordinator,
            systemPermissionService: system,
            autoplayStore: autoplayStore,
            recentActivityStore: recentStore,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeStore,
            indicatorEventStore: indicatorStore,
            websiteDataCleanupService: websiteDataService,
            userDefaults: userDefaults,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    var profileContext: SumiPermissionSettingsProfileContext {
        SumiPermissionSettingsProfileContext(profile: profile)
    }

    func key(
        _ type: SumiPermissionType,
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        profile: Profile? = nil
    ) -> SumiPermissionKey {
        let profile = profile ?? self.profile
        return SumiPermissionKey(
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            permissionType: type,
            profilePartitionId: profile.id.uuidString,
            isEphemeralProfile: profile.isEphemeral
        )
    }
}
