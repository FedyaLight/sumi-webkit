import Combine
import CryptoKit
import Foundation
import WebKit

struct SumiContentRuleListDefinition: Equatable, Sendable {
    let name: String
    let encodedContentRuleList: String
    let storeIdentifierOverride: String?
    private let contentHashOverride: String?

    init(
        name: String,
        encodedContentRuleList: String,
        storeIdentifierOverride: String? = nil,
        contentHashOverride: String? = nil
    ) {
        self.name = name
        self.encodedContentRuleList = encodedContentRuleList
        self.storeIdentifierOverride = storeIdentifierOverride
        self.contentHashOverride = contentHashOverride
    }

    var contentHash: String {
        if let contentHashOverride {
            return contentHashOverride
        }
        let digest = SHA256.hash(data: Data(encodedContentRuleList.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    var webKitStoreIdentifier: String {
        storeIdentifierOverride ?? SumiContentBlockerRulesIdentifier(
            name: name,
            tdsEtag: contentHash,
            tempListId: nil,
            allowListId: nil,
            unprotectedSitesHash: nil
        ).stringValue
    }

    func metadataOnly() -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: name,
            encodedContentRuleList: "",
            storeIdentifierOverride: storeIdentifierOverride,
            contentHashOverride: contentHash
        )
    }

    static func == (lhs: SumiContentRuleListDefinition, rhs: SumiContentRuleListDefinition) -> Bool {
        lhs.name == rhs.name
            && lhs.storeIdentifierOverride == rhs.storeIdentifierOverride
            && lhs.contentHash == rhs.contentHash
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

protocol SumiContentRuleListCompiling: AnyObject, Sendable {
    @MainActor
    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList?

    @MainActor
    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool

    @MainActor
    func compileContentRuleList(forIdentifier identifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList

    @MainActor
    func availableContentRuleListIdentifiers() async -> [String]

    @MainActor
    func removeContentRuleList(forIdentifier identifier: String) async throws
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
    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        await lookUpContentRuleList(forIdentifier: identifier) != nil
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

    @MainActor
    func availableContentRuleListIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().getAvailableContentRuleListIdentifiers { identifiers in
                continuation.resume(returning: identifiers ?? [])
            }
        }
    }

    @MainActor
    func removeContentRuleList(forIdentifier identifier: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            WKContentRuleListStore.default().removeContentRuleList(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum SumiContentBlockingCompilationError: Error, LocalizedError {
    case missingCompiledRuleList(String)
    case failedToCompileRuleList(String, String)

    var identifier: String {
        switch self {
        case .missingCompiledRuleList(let identifier),
             .failedToCompileRuleList(let identifier, _):
            return identifier
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingCompiledRuleList(let identifier):
            return "Compiled content rule list could not be looked up: \(identifier)"
        case .failedToCompileRuleList(let identifier, let reason):
            return "Failed to compile content rule list \(identifier): \(reason)"
        }
    }
}

struct SumiPreparedContentBlockingUpdate {
    let policy: SumiContentBlockingPolicy
    let updateEvent: SumiContentBlockerRulesUpdate
}

@MainActor
protocol SumiCompiledContentRuleListCataloging: AnyObject {
    func cachedIdentifiersToForget(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String]

    func staleIdentifiers(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String]

    func forgetIdentifiers(_ identifiers: [String])
}

@MainActor
final class SumiCompiledContentRuleListCatalog: SumiCompiledContentRuleListCataloging {
    static let shared = SumiCompiledContentRuleListCatalog()

    private let userDefaults: UserDefaults
    private let userDefaultsKey = "SumiCompiledContentRuleListIdentifiersByName.v1"
    private var identifiersByName: [String: Set<String>]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let persisted = userDefaults.dictionary(forKey: userDefaultsKey) as? [String: [String]] ?? [:]
        identifiersByName = persisted.mapValues { Set($0) }
    }

    func cachedIdentifiersToForget(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        staleIdentifiersWithoutMutating(
            replacing: previousRules,
            with: activeRules
        )
    }

    func staleIdentifiers(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let staleIdentifiers = staleIdentifiersWithoutMutating(
            replacing: previousRules,
            with: activeRules
        )
        let activeIdentifiersByName = Self.identifiersByName(for: activeRules)
        let namesToSweep = Set(identifiersByName.keys).union(activeIdentifiersByName.keys)
        for name in namesToSweep {
            let activeIdentifiers = activeIdentifiersByName[name] ?? []
            if activeIdentifiers.isEmpty {
                identifiersByName.removeValue(forKey: name)
            } else {
                identifiersByName[name] = activeIdentifiers
            }
        }
        save()
        return staleIdentifiers
    }

    func forgetIdentifiers(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        let identifiersToForget = Set(identifiers)
        for name in Array(identifiersByName.keys) {
            identifiersByName[name]?.subtract(identifiersToForget)
            if identifiersByName[name]?.isEmpty == true {
                identifiersByName.removeValue(forKey: name)
            }
        }
        save()
    }

    private func staleIdentifiersWithoutMutating(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let previousIdentifiersByName = Self.identifiersByName(for: previousRules)
        let activeIdentifiersByName = Self.identifiersByName(for: activeRules)
        let namesToSweep = Set(previousIdentifiersByName.keys).union(activeIdentifiersByName.keys)
        var staleIdentifiers = Set<String>()

        for name in namesToSweep {
            let activeIdentifiers = activeIdentifiersByName[name] ?? []
            var knownIdentifiers = identifiersByName[name] ?? []
            knownIdentifiers.formUnion(previousIdentifiersByName[name] ?? [])
            staleIdentifiers.formUnion(knownIdentifiers.subtracting(activeIdentifiers))
        }

        return Array(staleIdentifiers)
    }

    private func save() {
        let persisted = identifiersByName.mapValues { Array($0).sorted() }
        userDefaults.set(persisted, forKey: userDefaultsKey)
    }

    private static func identifiersByName(
        for rules: [SumiContentBlockerRules]
    ) -> [String: Set<String>] {
        rules.reduce(into: [:]) { result, rules in
            result[rules.identifier.name, default: []].insert(rules.storeIdentifier)
        }
    }
}

@MainActor
final class SumiContentBlockingService {
    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager

    private let compiler: SumiContentRuleListCompiling
    private let updatesSubject: CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>
    private let ruleListProvider: SumiContentRuleListSetProviding?
    private let trackingProtectionSettings: SumiTrackingProtectionSettings?
    private let trackingRuleSource: SumiTrackingProtectionRuleProviding?
    private let trackingDataStore: SumiTrackingProtectionDataStore?
    private let siteDataPolicyStore: SumiSiteDataPolicyStore?
    private let siteDataRuleSource: SumiSiteDataContentRuleProviding?
    private let compiledRuleListCatalog: SumiCompiledContentRuleListCataloging
    private var currentPolicy: SumiContentBlockingPolicy
    private var compiledRulesByIdentifier: [String: SumiContentBlockerRules] = [:]
    private var compilationGeneration = 0
    private var trackingRefreshGeneration = 0
    private var profileRefreshGenerations: [String: Int] = [:]
    private var profileUpdateSubjects: [String: CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private(set) var latestUpdate: SumiContentBlockerRulesUpdate?

    var latestRuleListIdentifiers: [String] {
        latestUpdate?.rules.map(\.storeIdentifier).sorted() ?? []
    }

    var latestLookupSucceededIdentifiers: [String] {
        latestUpdate?.lookupSucceededIdentifiers ?? []
    }

    var latestLookupFailedIdentifiers: [String] {
        latestUpdate?.lookupFailedIdentifiers ?? []
    }

    init(
        policy: SumiContentBlockingPolicy = .defaultPolicy,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        ruleListProvider: SumiContentRuleListSetProviding? = nil,
        trackingProtectionSettings: SumiTrackingProtectionSettings? = nil,
        trackingRuleSource: SumiTrackingProtectionRuleProviding? = nil,
        trackingDataStore: SumiTrackingProtectionDataStore? = nil,
        siteDataPolicyStore: SumiSiteDataPolicyStore? = nil,
        siteDataRuleSource: SumiSiteDataContentRuleProviding? = nil,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging = SumiCompiledContentRuleListCatalog.shared
    ) {
        currentPolicy = policy
        self.compiler = compiler
        self.ruleListProvider = ruleListProvider
        self.trackingProtectionSettings = trackingProtectionSettings
        self.trackingRuleSource = trackingRuleSource
        self.trackingDataStore = trackingDataStore
        self.siteDataPolicyStore = siteDataPolicyStore
        self.siteDataRuleSource = siteDataRuleSource
        self.compiledRuleListCatalog = compiledRuleListCatalog
        privacyConfigurationManager = SumiContentBlockingPrivacyConfigurationManager(
            isContentBlockingEnabled: policy.shouldEnableContentBlockingFeature
        )

        let usesDynamicRuleSource = ruleListProvider != nil
            || trackingProtectionSettings != nil
            || trackingRuleSource != nil
            || trackingDataStore != nil
            || siteDataPolicyStore != nil
            || siteDataRuleSource != nil

        let initialUpdate: SumiContentBlockerRulesUpdate?
        if policy.ruleLists.isEmpty, !usesDynamicRuleSource {
            initialUpdate = Self.emptyUpdate()
        } else {
            initialUpdate = nil
        }
        latestUpdate = initialUpdate
        updatesSubject = CurrentValueSubject(initialUpdate)

        if let ruleListProvider {
            bindRuleListProvider(ruleListProvider)
            scheduleTrackingPolicyRefresh(delayNanoseconds: 0)
        } else if usesDynamicRuleSource {
            bindTrackingProtection()
            scheduleTrackingPolicyRefresh(delayNanoseconds: 0)
        } else if !policy.ruleLists.isEmpty {
            scheduleCompilation(for: policy)
        }
    }

    var updatesPublisher: AnyPublisher<SumiContentBlockerRulesUpdate, Never> {
        updatesSubject.compactMap { $0 }.eraseToAnyPublisher()
    }

    func userContentPublisher(for scriptsProvider: SumiNormalTabUserScripts) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        updatesPublisher
            .map { update in
                SumiNormalTabUserContent(
                    contentBlockingUpdate: Self.normalTabContentBlockingUpdate(for: update),
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
                    contentBlockingUpdate: Self.normalTabContentBlockingUpdate(for: update),
                    sourceProvider: scriptsProvider
                )
            }
            .eraseToAnyPublisher()
    }

    func setPolicy(_ policy: SumiContentBlockingPolicy) {
        guard policy != currentPolicy else {
            if latestUpdate == nil, policy.ruleLists.isEmpty {
                privacyConfigurationManager.setContentBlockingEnabled(false)
                publish(Self.emptyUpdate(), cleaningUpAfter: nil)
            }
            return
        }

        let previousPolicy = currentPolicy
        currentPolicy = policy
        privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)

        if policy.ruleLists.isEmpty {
            publish(Self.emptyUpdate(), cleaningUpAfter: latestUpdate)
        } else {
            scheduleCompilation(for: policy, previousPolicy: previousPolicy)
        }
    }

    func validateRuleLists(
        _ definitions: [SumiContentRuleListDefinition]
    ) async throws {
        let update = try await updateEvent(for: definitions)
        cleanupTransientCompiledRuleLists(from: update)
    }

    func prepareRuleListUpdate(
        ruleLists definitions: [SumiContentRuleListDefinition],
        retainEncodedRuleListsInPreparedPolicy: Bool = true
    ) async throws -> SumiPreparedContentBlockingUpdate {
        let policy: SumiContentBlockingPolicy = definitions.isEmpty
            ? .disabled
            : .enabled(
                ruleLists: retainEncodedRuleListsInPreparedPolicy
                    ? definitions
                    : definitions.map { $0.metadataOnly() }
            )
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
        publish(preparedUpdate.updateEvent, cleaningUpAfter: latestUpdate)
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

    private func scheduleTrackingPolicyRefresh(
        refreshProfileSubjects: Bool = false,
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        trackingRefreshGeneration += 1
        let generation = trackingRefreshGeneration

        Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
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
                if self.latestUpdate == nil {
                    self.currentPolicy = .disabled
                    self.privacyConfigurationManager.setContentBlockingEnabled(false)
                    self.publish(Self.emptyUpdate(), cleaningUpAfter: nil)
                }
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
                self.publishProfileUpdate(update, for: profileId)
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
            currentPolicy = Self.metadataOnlyPolicy(policy)
            privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)
            publish(update, cleaningUpAfter: latestUpdate)
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
                publish(Self.emptyUpdate(), cleaningUpAfter: latestUpdate)
            }
        }
    }

    private func updateEvent(
        for definitions: [SumiContentRuleListDefinition]
    ) async throws -> SumiContentBlockerRulesUpdate {
        var compiledRules: [SumiContentBlockerRules] = []
        compiledRules.reserveCapacity(definitions.count)
        var lookupSucceededIdentifiers = [String]()
        var lookupFailedIdentifiers = [String]()
        var ruleListLookupDuration: TimeInterval = 0

        for definition in definitions {
            let lookupStart = Date()
            var rules = try await rule(for: definition)
            let storeIdentifier = storeIdentifier(for: definition)
            var canLookUp = await canLookUpCompiledRuleList(forIdentifier: storeIdentifier)
            ruleListLookupDuration += Date().timeIntervalSince(lookupStart)

            if canLookUp == false {
                compiledRulesByIdentifier.removeValue(forKey: storeIdentifier)
                let retryStart = Date()
                rules = try await rule(for: definition)
                canLookUp = await canLookUpCompiledRuleList(forIdentifier: storeIdentifier)
                ruleListLookupDuration += Date().timeIntervalSince(retryStart)
            }

            if canLookUp {
                compiledRules.append(rules)
                lookupSucceededIdentifiers.append(storeIdentifier)
            } else {
                lookupFailedIdentifiers.append(storeIdentifier)
                throw SumiContentBlockingCompilationError.missingCompiledRuleList(storeIdentifier)
            }
        }

        return Self.updateEvent(
            for: compiledRules,
            lookupSucceededIdentifiers: lookupSucceededIdentifiers,
            lookupFailedIdentifiers: lookupFailedIdentifiers,
            ruleListLookupDuration: ruleListLookupDuration
        )
    }

    private func canLookUpCompiledRuleList(forIdentifier identifier: String) async -> Bool {
        for _ in 0..<3 {
            if await compiler.canLookUpContentRuleList(forIdentifier: identifier) {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func profileSubject(
        for profileId: UUID
    ) -> CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never> {
        let key = profileId.uuidString.lowercased()
        if let subject = profileUpdateSubjects[key] {
            return subject
        }
        let subject = CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>(nil)
        profileUpdateSubjects[key] = subject
        return subject
    }

    private func rule(for definition: SumiContentRuleListDefinition) async throws -> SumiContentBlockerRules {
        let rulesIdentifier = rulesIdentifier(for: definition)
        let storeIdentifier = storeIdentifier(for: definition)

        if let cachedRules = compiledRulesByIdentifier[storeIdentifier] {
            return cachedRules
        }

        let ruleList: WKContentRuleList
        if let cachedRuleList = await compiler.lookUpContentRuleList(forIdentifier: storeIdentifier) {
            ruleList = cachedRuleList
        } else {
            do {
                ruleList = try await compiler.compileContentRuleList(
                    forIdentifier: storeIdentifier,
                    encodedContentRuleList: definition.encodedContentRuleList
                )
            } catch {
                throw SumiContentBlockingCompilationError.failedToCompileRuleList(
                    storeIdentifier,
                    error.localizedDescription
                )
            }
        }

        let rules = SumiContentBlockerRules(
            name: definition.name,
            storeIdentifier: storeIdentifier,
            rulesList: ruleList,
            etag: definition.contentHash,
            identifier: rulesIdentifier
        )
        compiledRulesByIdentifier[storeIdentifier] = rules
        return rules
    }

    private func rulesIdentifier(
        for definition: SumiContentRuleListDefinition
    ) -> SumiContentBlockerRulesIdentifier {
        SumiContentBlockerRulesIdentifier(
            name: definition.name,
            tdsEtag: definition.contentHash,
            tempListId: nil,
            allowListId: nil,
            unprotectedSitesHash: nil
        )
    }

    private func storeIdentifier(for definition: SumiContentRuleListDefinition) -> String {
        definition.webKitStoreIdentifier
    }

    private func publishProfileUpdate(
        _ update: SumiContentBlockerRulesUpdate,
        for profileId: UUID
    ) {
        let subject = profileSubject(for: profileId)
        let previousUpdate = subject.value
        subject.send(update)
        cleanupStaleCompiledRuleLists(
            replacing: previousUpdate?.rules ?? [],
            with: update.rules
        )
    }

    private func publish(
        _ update: SumiContentBlockerRulesUpdate,
        cleaningUpAfter previousUpdate: SumiContentBlockerRulesUpdate? = nil
    ) {
        latestUpdate = update
        updatesSubject.send(update)
        cleanupStaleCompiledRuleLists(
            replacing: previousUpdate?.rules ?? [],
            with: update.rules
        )
    }

    private func cleanupStaleCompiledRuleLists(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) {
        let cachedIdentifiersToForget = compiledRuleListCatalog.cachedIdentifiersToForget(
            replacing: previousRules,
            with: activeRules
        )
        let staleIdentifiers = compiledRuleListCatalog.staleIdentifiers(
            replacing: previousRules,
            with: activeRules
        )
        forgetCachedCompiledRuleLists(withIdentifiers: cachedIdentifiersToForget)
        removeCompiledRuleListsFromStore(withIdentifiers: staleIdentifiers)
    }

    private func cleanupTransientCompiledRuleLists(
        from update: SumiContentBlockerRulesUpdate
    ) {
        let activeIdentifiers = Set(latestUpdate?.rules.map(\.storeIdentifier) ?? [])
        let transientIdentifiers = update.rules
            .map(\.storeIdentifier)
            .filter { !activeIdentifiers.contains($0) }
        compiledRuleListCatalog.forgetIdentifiers(transientIdentifiers)
        forgetCachedCompiledRuleLists(withIdentifiers: transientIdentifiers)
        removeCompiledRuleListsFromStore(withIdentifiers: transientIdentifiers)
    }

    private func forgetCachedCompiledRuleLists(withIdentifiers identifiers: [String]) {
        let uniqueIdentifiers = Array(Set(identifiers))
        guard !uniqueIdentifiers.isEmpty else { return }

        for identifier in uniqueIdentifiers {
            compiledRulesByIdentifier.removeValue(forKey: identifier)
        }
    }

    private func removeCompiledRuleListsFromStore(withIdentifiers identifiers: [String]) {
        let uniqueIdentifiers = Array(Set(identifiers))
        guard !uniqueIdentifiers.isEmpty else { return }

        Task { @MainActor [compiler] in
            for identifier in uniqueIdentifiers {
                try? await compiler.removeContentRuleList(forIdentifier: identifier)
            }
        }
    }

    private static func metadataOnlyPolicy(
        _ policy: SumiContentBlockingPolicy
    ) -> SumiContentBlockingPolicy {
        switch policy {
        case .disabled:
            return .disabled
        case .enabled(let ruleLists):
            return .enabled(ruleLists: ruleLists.map { $0.metadataOnly() })
        }
    }

    private static func updateEvent(
        for rules: [SumiContentBlockerRules],
        lookupSucceededIdentifiers: [String]? = nil,
        lookupFailedIdentifiers: [String] = [],
        ruleListLookupDuration: TimeInterval? = nil
    ) -> SumiContentBlockerRulesUpdate {
        let changes = Dictionary(uniqueKeysWithValues: rules.map { ($0.name, SumiContentBlockerRulesIdentifier.Difference.all) })
        return SumiContentBlockerRulesUpdate(
            rules: rules,
            changes: changes,
            completionTokens: [],
            lookupSucceededIdentifiers: (lookupSucceededIdentifiers ?? rules.map(\.storeIdentifier)).sorted(),
            lookupFailedIdentifiers: lookupFailedIdentifiers.sorted(),
            ruleListLookupDuration: ruleListLookupDuration
        )
    }

    private static func emptyUpdate() -> SumiContentBlockerRulesUpdate {
        SumiContentBlockerRulesUpdate(
            rules: [],
            changes: [:],
            completionTokens: [],
            lookupSucceededIdentifiers: [],
            lookupFailedIdentifiers: [],
            ruleListLookupDuration: nil
        )
    }

    private static func normalTabContentBlockingUpdate(
        for update: SumiContentBlockerRulesUpdate
    ) -> SumiNormalTabContentBlockingUpdate {
        SumiNormalTabContentBlockingUpdate(
            globalRuleLists: update.rules.reduce(into: [:]) { result, rules in
                result[rules.storeIdentifier] = rules.rulesList
            },
            updateRuleCount: update.rules.count,
            lookupSucceededIdentifiers: update.lookupSucceededIdentifiers,
            lookupFailedIdentifiers: update.lookupFailedIdentifiers,
            ruleListLookupDuration: update.ruleListLookupDuration
        )
    }

}
