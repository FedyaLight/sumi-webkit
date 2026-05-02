import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

let sumiPermissionIntegrationNow = Date(timeIntervalSince1970: 1_800_100_000)

func sumiPermissionIntegrationDate() -> Date {
    sumiPermissionIntegrationNow
}

func sumiPermissionIntegrationAuthorizedSystemStates() -> [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] {
    Dictionary(uniqueKeysWithValues: SumiSystemPermissionKind.allCases.map { ($0, .authorized) })
}

func sumiPermissionIntegrationOrigin(_ value: String = "https://example.com") -> SumiPermissionOrigin {
    SumiPermissionOrigin(string: value)
}

func sumiPermissionIntegrationContext(
    _ permissionTypes: [SumiPermissionType],
    id: String = "permission-request-a",
    tabId: String = "tab-a",
    pageId: String = "tab-a:1",
    requestingOrigin: SumiPermissionOrigin = sumiPermissionIntegrationOrigin(),
    topOrigin: SumiPermissionOrigin = sumiPermissionIntegrationOrigin(),
    committedURL: URL? = URL(string: "https://example.com/page"),
    visibleURL: URL? = URL(string: "https://example.com/page"),
    mainFrameURL: URL? = URL(string: "https://example.com/page"),
    isEphemeralProfile: Bool = false,
    profilePartitionId: String = "profile-a",
    navigationOrPageGeneration: String? = "1"
) -> SumiPermissionSecurityContext {
    let request = SumiPermissionRequest(
        id: id,
        tabId: tabId,
        pageId: pageId,
        requestingOrigin: requestingOrigin,
        topOrigin: topOrigin,
        displayDomain: requestingOrigin.displayDomain,
        permissionTypes: permissionTypes,
        requestedAt: sumiPermissionIntegrationNow,
        isEphemeralProfile: isEphemeralProfile,
        profilePartitionId: profilePartitionId
    )
    return SumiPermissionSecurityContext(
        request: request,
        requestingOrigin: requestingOrigin,
        topOrigin: topOrigin,
        committedURL: committedURL,
        visibleURL: visibleURL,
        mainFrameURL: mainFrameURL,
        isMainFrame: true,
        isActiveTab: true,
        isVisibleTab: true,
        isEphemeralProfile: isEphemeralProfile,
        profilePartitionId: profilePartitionId,
        transientPageId: pageId,
        surface: .normalTab,
        navigationOrPageGeneration: navigationOrPageGeneration,
        now: sumiPermissionIntegrationNow
    )
}

func sumiPermissionIntegrationKey(
    _ permissionType: SumiPermissionType,
    requestingOrigin: SumiPermissionOrigin = sumiPermissionIntegrationOrigin(),
    topOrigin: SumiPermissionOrigin = sumiPermissionIntegrationOrigin(),
    profilePartitionId: String = "profile-a",
    pageId: String? = "tab-a:1",
    isEphemeralProfile: Bool = false
) -> SumiPermissionKey {
    SumiPermissionKey(
        requestingOrigin: requestingOrigin,
        topOrigin: topOrigin,
        permissionType: permissionType,
        profilePartitionId: profilePartitionId,
        transientPageId: pageId,
        isEphemeralProfile: isEphemeralProfile
    )
}

func sumiPermissionIntegrationDecision(
    _ state: SumiPermissionState,
    persistence: SumiPermissionPersistence = .persistent,
    source: SumiPermissionDecisionSource = .user,
    reason: String = "test"
) -> SumiPermissionDecision {
    SumiPermissionDecision(
        state: state,
        persistence: persistence,
        source: source,
        reason: reason,
        createdAt: sumiPermissionIntegrationNow,
        updatedAt: sumiPermissionIntegrationNow
    )
}

func sumiPermissionIntegrationWaitForActiveQuery(
    _ coordinator: any SumiPermissionCoordinating,
    pageId: String = "tab-a:1",
    file: StaticString = #filePath,
    line: UInt = #line
) async -> SumiPermissionAuthorizationQuery {
    for _ in 0..<200 {
        if let query = await coordinator.activeQuery(forPageId: pageId) {
            return query
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("Timed out waiting for active permission query", file: file, line: line)
    await coordinator.cancel(pageId: pageId, reason: "test-timeout-waiting-for-active-query")
    return SumiPermissionAuthorizationQuery(
        id: "missing-query",
        pageId: pageId,
        profilePartitionId: "profile-a",
        displayDomain: "missing",
        requestingOrigin: .invalid(),
        topOrigin: .invalid(),
        permissionTypes: [],
        presentationPermissionType: nil,
        availablePersistences: [],
        systemAuthorizationSnapshots: [],
        policyReasons: [],
        createdAt: sumiPermissionIntegrationNow,
        isEphemeralProfile: false,
        shouldOfferSystemSettings: false,
        disablesPersistentAllow: false,
    )
}

actor SumiPermissionIntegrationStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private var getCount = 0
    private var setCount = 0
    private var resetCount = 0
    private var lastUsedCount = 0

    func seed(_ key: SumiPermissionKey, decision: SumiPermissionDecision) {
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        getCount += 1
        return records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        setCount += 1
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        resetCount += 1
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records.values
            .filter { $0.key.profilePartitionId == profileId }
            .sorted { $0.key.persistentIdentity < $1.key.persistentIdentity }
    }

    func listDecisions(
        forDisplayDomain displayDomain: String,
        profilePartitionId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        let domain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
        return try await listDecisions(profilePartitionId: profilePartitionId)
            .filter { $0.displayDomain == domain }
    }

    func clearAll(profilePartitionId: String) async throws {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        records = records.filter { _, record in record.key.profilePartitionId != profileId }
    }

    func clearForDisplayDomains(
        _ displayDomains: Set<String>,
        profilePartitionId: String
    ) async throws {
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        records = records.filter { _, record in
            record.key.profilePartitionId != profileId || !domains.contains(record.displayDomain)
        }
    }

    func clearForOrigins(
        _ origins: Set<SumiPermissionOrigin>,
        profilePartitionId: String
    ) async throws {
        let originIds = Set(origins.map(\.identity))
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        records = records.filter { _, record in
            record.key.profilePartitionId != profileId
                || (!originIds.contains(record.key.requestingOrigin.identity)
                    && !originIds.contains(record.key.topOrigin.identity))
        }
    }

    @discardableResult
    func expireDecisions(now: Date) async throws -> Int {
        let expired = records.filter { _, record in
            record.decision.expiresAt.map { $0 <= now } == true
        }
        for key in expired.keys {
            records.removeValue(forKey: key)
        }
        return expired.count
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {
        lastUsedCount += 1
        guard let record = records[key.persistentIdentity] else { return }
        let decision = SumiPermissionDecision(
            state: record.decision.state,
            persistence: record.decision.persistence,
            source: record.decision.source,
            reason: record.decision.reason,
            createdAt: record.decision.createdAt,
            updatedAt: record.decision.updatedAt,
            expiresAt: record.decision.expiresAt,
            lastUsedAt: date,
            systemAuthorizationSnapshot: record.decision.systemAuthorizationSnapshot
        )
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func record(for key: SumiPermissionKey) -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func allRecords() -> [SumiPermissionStoreRecord] {
        records.values.sorted { $0.key.persistentIdentity < $1.key.persistentIdentity }
    }

    func state(for key: SumiPermissionKey) -> SumiPermissionState? {
        records[key.persistentIdentity]?.decision.state
    }

    func setDecisionCallCount() -> Int {
        setCount
    }

    func getDecisionCallCount() -> Int {
        getCount
    }

    func resetDecisionCallCount() -> Int {
        resetCount
    }

    func recordLastUsedCallCount() -> Int {
        lastUsedCount
    }
}

@MainActor
final class SumiPermissionIntegrationExternalAppResolver: SumiExternalAppResolving {
    var handlerSchemes: Set<String>
    var appDisplayName: String?
    var openResult = true
    private(set) var openedURLs: [URL] = []

    init(handlerSchemes: Set<String> = ["mailto"], appDisplayName: String? = "Mail") {
        self.handlerSchemes = handlerSchemes
        self.appDisplayName = appDisplayName
    }

    func appInfo(for url: URL) -> SumiExternalAppInfo? {
        let scheme = SumiExternalSchemePermissionRequest.normalizedScheme(for: url)
        guard handlerSchemes.contains(scheme) else { return nil }
        return SumiExternalAppInfo(
            appDisplayName: appDisplayName
        )
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }
}

@MainActor
final class SumiPermissionIntegrationAutoplayStore: SumiCurrentSiteAutoplayPolicyManaging {
    private var policiesByIdentity: [String: SumiAutoplayPolicy] = [:]

    func effectivePolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy {
        explicitPolicy(for: url, profile: profile) ?? .default
    }

    func explicitPolicy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy? {
        guard let key = key(for: url, profile: profile) else { return nil }
        return explicitPolicy(for: key)
    }

    func explicitPolicy(for key: SumiPermissionKey) -> SumiAutoplayPolicy? {
        policiesByIdentity[key.persistentIdentity]
    }

    func setPolicy(
        _ policy: SumiAutoplayPolicy,
        for url: URL?,
        profile: Profile?,
        source: SumiPermissionDecisionSource,
        now: Date
    ) async throws {
        guard let key = key(for: url, profile: profile) else { return }
        if policy == .default {
            policiesByIdentity.removeValue(forKey: key.persistentIdentity)
        } else {
            policiesByIdentity[key.persistentIdentity] = policy
        }
        _ = source
        _ = now
    }

    func resetPolicy(for url: URL?, profile: Profile?) async throws {
        guard let key = key(for: url, profile: profile) else { return }
        policiesByIdentity.removeValue(forKey: key.persistentIdentity)
    }

    private func key(for url: URL?, profile: Profile?) -> SumiPermissionKey? {
        guard let profile else { return nil }
        let origin = SumiPermissionOrigin(url: url)
        guard origin.isWebOrigin else { return nil }
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .autoplay,
            profilePartitionId: profile.id.uuidString,
            isEphemeralProfile: profile.isEphemeral
        )
    }
}

@MainActor
func sumiPermissionIntegrationModelContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Schema([PermissionDecisionEntity.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
}

@MainActor
func sumiPermissionIntegrationProfile(
    id: String = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    isEphemeral: Bool = false
) -> Profile {
    let profile = Profile(
        id: UUID(uuidString: id)!,
        name: isEphemeral ? "Ephemeral" : "Work",
        icon: "person"
    )
    profile.isEphemeral = isEphemeral
    return profile
}
