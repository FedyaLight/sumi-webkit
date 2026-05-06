import Combine
import ContentBlocking
import CryptoKit
import Foundation
import TrackerRadarKit
@preconcurrency import WebKit

struct SumiContentRuleListDefinition: Equatable, Sendable {
    let name: String
    let encodedContentRuleList: String

    init(name: String, encodedContentRuleList: String) {
        self.name = name
        self.encodedContentRuleList = encodedContentRuleList
    }

    var contentHash: String {
        let digest = SHA256.hash(data: Data(encodedContentRuleList.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

enum SumiContentBlockingPolicy: Equatable, Sendable {
    case disabled
    case enabled(ruleLists: [SumiContentRuleListDefinition])

    static let defaultPolicy: SumiContentBlockingPolicy = .disabled

    var ruleLists: [SumiContentRuleListDefinition] {
        switch self {
        case .disabled:
            return []
        case .enabled(let ruleLists):
            return ruleLists
        }
    }

    var shouldEnableContentBlockingFeature: Bool {
        !ruleLists.isEmpty
    }
}

protocol SumiContentRuleListCompiling: AnyObject {
    @MainActor
    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList?

    @MainActor
    func compileContentRuleList(forIdentifier identifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList
}

final class SumiWKContentRuleListCompiler: SumiContentRuleListCompiling {
    @MainActor
    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
                continuation.resume(returning: ruleList)
            }
        }
    }

    @MainActor
    func compileContentRuleList(forIdentifier identifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedContentRuleList
            ) { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let ruleList {
                    continuation.resume(returning: ruleList)
                } else {
                    continuation.resume(throwing: SumiContentBlockingCompilationError.missingCompiledRuleList(identifier))
                }
            }
        }
    }
}

enum SumiContentBlockingCompilationError: Error {
    case missingCompiledRuleList(String)
}

struct SumiPreparedContentBlockingUpdate {
    let policy: SumiContentBlockingPolicy
    let updateEvent: ContentBlockerRulesManager.UpdateEvent
}

@MainActor
final class SumiContentBlockingService {
    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager

    private let compiler: SumiContentRuleListCompiling
    private let updatesSubject: CurrentValueSubject<ContentBlockerRulesManager.UpdateEvent?, Never>
    private let ruleListProvider: SumiContentRuleListSetProviding?
    private let trackingProtectionSettings: SumiTrackingProtectionSettings?
    private let trackingRuleSource: SumiTrackingProtectionRuleProviding?
    private let trackingDataStore: SumiTrackingProtectionDataStore?
    private let siteDataPolicyStore: SumiSiteDataPolicyStore?
    private let siteDataRuleSource: SumiSiteDataContentRuleProviding?
    private var currentPolicy: SumiContentBlockingPolicy
    private var compiledRulesByIdentifier: [String: ContentBlockerRulesManager.Rules] = [:]
    private var compilationGeneration = 0
    private var trackingRefreshGeneration = 0
    private var profileRefreshGenerations: [String: Int] = [:]
    private var profileUpdateSubjects: [String: CurrentValueSubject<ContentBlockerRulesManager.UpdateEvent?, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private(set) var latestUpdate: ContentBlockerRulesManager.UpdateEvent?
    init(
        policy: SumiContentBlockingPolicy = .defaultPolicy,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        ruleListProvider: SumiContentRuleListSetProviding? = nil,
        trackingProtectionSettings: SumiTrackingProtectionSettings? = nil,
        trackingRuleSource: SumiTrackingProtectionRuleProviding? = nil,
        trackingDataStore: SumiTrackingProtectionDataStore? = nil,
        siteDataPolicyStore: SumiSiteDataPolicyStore? = nil,
        siteDataRuleSource: SumiSiteDataContentRuleProviding? = nil
    ) {
        currentPolicy = policy
        self.compiler = compiler
        self.ruleListProvider = ruleListProvider
        self.trackingProtectionSettings = trackingProtectionSettings
        self.trackingRuleSource = trackingRuleSource
        self.trackingDataStore = trackingDataStore
        self.siteDataPolicyStore = siteDataPolicyStore
        self.siteDataRuleSource = siteDataRuleSource
        privacyConfigurationManager = SumiContentBlockingPrivacyConfigurationManager(
            isContentBlockingEnabled: policy.shouldEnableContentBlockingFeature
        )

        let initialUpdate: ContentBlockerRulesManager.UpdateEvent?
        if policy.ruleLists.isEmpty {
            initialUpdate = Self.emptyUpdate()
        } else {
            initialUpdate = nil
        }
        latestUpdate = initialUpdate
        updatesSubject = CurrentValueSubject(initialUpdate)

        if let ruleListProvider {
            bindRuleListProvider(ruleListProvider)
            scheduleTrackingPolicyRefresh()
        } else if trackingProtectionSettings != nil || siteDataPolicyStore != nil {
            bindTrackingProtection()
            scheduleTrackingPolicyRefresh()
        } else if !policy.ruleLists.isEmpty {
            scheduleCompilation(for: policy)
        }
    }

    var updatesPublisher: AnyPublisher<ContentBlockerRulesManager.UpdateEvent, Never> {
        updatesSubject.compactMap { $0 }.eraseToAnyPublisher()
    }

    func userContentPublisher(for scriptsProvider: SumiNormalTabUserScripts) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        updatesPublisher
            .map { update in
                SumiNormalTabUserContent(
                    rulesUpdate: update,
                    sourceProvider: scriptsProvider
                )
            }
            .eraseToAnyPublisher()
    }

    func userContentPublisher(
        for scriptsProvider: SumiNormalTabUserScripts,
        profileId: UUID?
    ) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        guard let profileId else {
            return userContentPublisher(for: scriptsProvider)
        }
        guard ruleListProvider?.hasProfileSpecificRuleLists == true
            || trackingProtectionSettings != nil
            || siteDataRuleSource != nil
        else {
            return userContentPublisher(for: scriptsProvider)
        }

        let subject = profileSubject(for: profileId)
        scheduleProfilePolicyRefresh(profileId: profileId, delayNanoseconds: 0)
        return subject
            .compactMap { $0 }
            .map { update in
                SumiNormalTabUserContent(
                    rulesUpdate: update,
                    sourceProvider: scriptsProvider
                )
            }
            .eraseToAnyPublisher()
    }

    func setPolicy(_ policy: SumiContentBlockingPolicy) {
        guard policy != currentPolicy else { return }

        let previousPolicy = currentPolicy
        currentPolicy = policy
        privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)

        if policy.ruleLists.isEmpty {
            publish(Self.emptyUpdate())
        } else {
            scheduleCompilation(for: policy, previousPolicy: previousPolicy)
        }
    }

    func validateRuleLists(
        _ definitions: [SumiContentRuleListDefinition]
    ) async throws {
        _ = try await updateEvent(for: definitions)
    }

    func prepareRuleListUpdate(
        ruleLists definitions: [SumiContentRuleListDefinition]
    ) async throws -> SumiPreparedContentBlockingUpdate {
        let policy: SumiContentBlockingPolicy = definitions.isEmpty
            ? .disabled
            : .enabled(ruleLists: definitions)
        let update = try await updateEvent(for: definitions)
        return SumiPreparedContentBlockingUpdate(
            policy: policy,
            updateEvent: update
        )
    }

    func commitPreparedContentBlockingUpdate(
        _ preparedUpdate: SumiPreparedContentBlockingUpdate,
        refreshProfileSubjects: Bool = true
    ) {
        compilationGeneration += 1
        trackingRefreshGeneration += 1
        currentPolicy = preparedUpdate.policy
        privacyConfigurationManager.setContentBlockingEnabled(
            preparedUpdate.policy.shouldEnableContentBlockingFeature
        )
        publish(preparedUpdate.updateEvent)
        if refreshProfileSubjects {
            scheduleActiveProfilePolicyRefreshes(delayNanoseconds: 0)
        }
    }

    private func bindRuleListProvider(_ provider: SumiContentRuleListSetProviding) {
        provider.changesPublisher
            .sink { [weak self] in
                self?.scheduleTrackingPolicyRefresh(refreshProfileSubjects: true)
            }
            .store(in: &cancellables)
    }

    private func bindTrackingProtection() {
        trackingProtectionSettings?.changesPublisher
            .sink { [weak self] in
                self?.scheduleTrackingPolicyRefresh(refreshProfileSubjects: true)
            }
            .store(in: &cancellables)

        trackingDataStore?.changesPublisher
            .sink { [weak self] in
                self?.scheduleTrackingPolicyRefresh(refreshProfileSubjects: true)
            }
            .store(in: &cancellables)

        siteDataPolicyStore?.changesPublisher
            .sink { [weak self] in
                guard let self else { return }
                self.scheduleTrackingPolicyRefresh()
                self.scheduleActiveProfilePolicyRefreshes()
            }
            .store(in: &cancellables)
    }

    private func scheduleTrackingPolicyRefresh(refreshProfileSubjects: Bool = false) {
        trackingRefreshGeneration += 1
        let generation = trackingRefreshGeneration

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self,
                  generation == self.trackingRefreshGeneration
            else { return }

            do {
                let ruleLists = try self.ruleLists(profileId: nil)
                guard generation == self.trackingRefreshGeneration else { return }
                self.setPolicy(ruleLists.isEmpty ? .disabled : .enabled(ruleLists: ruleLists))
                if refreshProfileSubjects {
                    self.scheduleActiveProfilePolicyRefreshes(delayNanoseconds: 0)
                }
            } catch {
                guard generation == self.trackingRefreshGeneration else { return }
                if refreshProfileSubjects {
                    self.scheduleActiveProfilePolicyRefreshes(delayNanoseconds: 0)
                }
            }
        }
    }

    private func scheduleActiveProfilePolicyRefreshes(delayNanoseconds: UInt64 = 150_000_000) {
        for key in Array(profileUpdateSubjects.keys) {
            if let profileId = UUID(uuidString: key) {
                scheduleProfilePolicyRefresh(
                    profileId: profileId,
                    delayNanoseconds: delayNanoseconds
                )
            }
        }
    }

    private func scheduleProfilePolicyRefresh(
        profileId: UUID,
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        let key = profileId.uuidString.lowercased()
        let generation = (profileRefreshGenerations[key] ?? 0) + 1
        profileRefreshGenerations[key] = generation

        Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self,
                  self.profileRefreshGenerations[key] == generation
            else { return }

            do {
                let ruleLists = try self.ruleLists(profileId: profileId)
                guard self.profileRefreshGenerations[key] == generation else { return }
                let update = try await self.updateEvent(for: ruleLists)
                guard self.profileRefreshGenerations[key] == generation else { return }
                if !ruleLists.isEmpty {
                    self.privacyConfigurationManager.setContentBlockingEnabled(true)
                } else if self.currentPolicy.ruleLists.isEmpty {
                    self.privacyConfigurationManager.setContentBlockingEnabled(false)
                }
                self.profileSubject(for: profileId).send(update)
            } catch {
                guard self.profileRefreshGenerations[key] == generation else { return }
                let subject = self.profileSubject(for: profileId)
                if subject.value == nil {
                    subject.send(Self.emptyUpdate())
                }
            }
        }
    }

    private func ruleLists(profileId: UUID?) throws -> [SumiContentRuleListDefinition] {
        if let ruleListProvider {
            return try ruleListProvider.ruleListSet(profileId: profileId).allDefinitions
        }

        var ruleLists: [SumiContentRuleListDefinition] = []

        if let trackingProtectionSettings,
           let trackingRuleSource,
           !trackingProtectionSettings.policy.isFullyDisabled {
            ruleLists.append(
                contentsOf: try trackingRuleSource.ruleLists(
                    for: trackingProtectionSettings.policy
                )
            )
        }

        if let siteDataRuleSource {
            ruleLists.append(contentsOf: try siteDataRuleSource.ruleLists(profileId: profileId))
        }

        return ruleLists
    }

    private func scheduleCompilation(
        for policy: SumiContentBlockingPolicy,
        previousPolicy: SumiContentBlockingPolicy? = nil
    ) {
        compilationGeneration += 1
        let generation = compilationGeneration

        Task { [weak self] in
            await self?.compileAndPublish(
                policy: policy,
                generation: generation,
                previousPolicy: previousPolicy
            )
        }
    }

    private func compileAndPublish(
        policy: SumiContentBlockingPolicy,
        generation: Int,
        previousPolicy: SumiContentBlockingPolicy?
    ) async {
        do {
            let update = try await updateEvent(for: policy.ruleLists)

            guard generation == compilationGeneration, policy == currentPolicy else { return }
            privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)
            publish(update)
        } catch {
            guard generation == compilationGeneration, policy == currentPolicy else { return }
            if let previousPolicy,
               latestUpdate?.rules.isEmpty == false {
                currentPolicy = previousPolicy
                privacyConfigurationManager.setContentBlockingEnabled(
                    previousPolicy.shouldEnableContentBlockingFeature
                )
            } else {
                currentPolicy = .disabled
                privacyConfigurationManager.setContentBlockingEnabled(false)
                publish(Self.emptyUpdate())
            }
        }
    }

    private func updateEvent(
        for definitions: [SumiContentRuleListDefinition]
    ) async throws -> ContentBlockerRulesManager.UpdateEvent {
        var compiledRules: [ContentBlockerRulesManager.Rules] = []
        compiledRules.reserveCapacity(definitions.count)

        for definition in definitions {
            compiledRules.append(try await rule(for: definition))
        }

        return Self.updateEvent(for: compiledRules)
    }

    private func profileSubject(
        for profileId: UUID
    ) -> CurrentValueSubject<ContentBlockerRulesManager.UpdateEvent?, Never> {
        let key = profileId.uuidString.lowercased()
        if let subject = profileUpdateSubjects[key] {
            return subject
        }
        let subject = CurrentValueSubject<ContentBlockerRulesManager.UpdateEvent?, Never>(nil)
        profileUpdateSubjects[key] = subject
        return subject
    }

    private func rule(for definition: SumiContentRuleListDefinition) async throws -> ContentBlockerRulesManager.Rules {
        let rulesIdentifier = SumiContentBlockerRulesIdentifier(
            name: definition.name,
            tdsEtag: definition.contentHash,
            tempListId: nil,
            allowListId: nil,
            unprotectedSitesHash: nil
        )
        let storeIdentifier = rulesIdentifier.stringValue

        if let cachedRules = compiledRulesByIdentifier[storeIdentifier] {
            return cachedRules
        }

        let ruleList: WKContentRuleList
        if let cachedRuleList = await compiler.lookUpContentRuleList(forIdentifier: storeIdentifier) {
            ruleList = cachedRuleList
        } else {
            ruleList = try await compiler.compileContentRuleList(
                forIdentifier: storeIdentifier,
                encodedContentRuleList: definition.encodedContentRuleList
            )
        }

        let rules = ContentBlockerRulesManager.Rules(
            name: definition.name,
            rulesList: ruleList,
            etag: definition.contentHash,
            identifier: Self.browserServicesKitIdentifier(for: rulesIdentifier)
        )
        compiledRulesByIdentifier[storeIdentifier] = rules
        return rules
    }

    private func publish(_ update: ContentBlockerRulesManager.UpdateEvent) {
        latestUpdate = update
        updatesSubject.send(update)
    }

    private static func updateEvent(for rules: [ContentBlockerRulesManager.Rules]) -> ContentBlockerRulesManager.UpdateEvent {
        let changes = Dictionary(uniqueKeysWithValues: rules.map { ($0.name, ContentBlockerRulesIdentifier.Difference.all) })
        return ContentBlockerRulesManager.UpdateEvent(
            rules: rules,
            changes: changes,
            completionTokens: []
        )
    }

    private static func emptyUpdate() -> ContentBlockerRulesManager.UpdateEvent {
        ContentBlockerRulesManager.UpdateEvent(
            rules: [],
            changes: [:],
            completionTokens: []
        )
    }

    private static func browserServicesKitIdentifier(
        for identifier: SumiContentBlockerRulesIdentifier
    ) -> ContentBlockerRulesIdentifier {
        ContentBlockerRulesIdentifier(
            name: identifier.name,
            tdsEtag: identifier.tdsEtag,
            tempListId: identifier.tempListId,
            allowListId: identifier.allowListId,
            unprotectedSitesHash: identifier.unprotectedSitesHash
        )
    }

}
