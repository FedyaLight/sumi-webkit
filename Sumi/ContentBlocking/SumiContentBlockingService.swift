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

final class SumiWKContentRuleListCompiler: SumiContentRuleListCompiling, @unchecked Sendable {
    private let storeOverride: WKContentRuleListStore?

    init(store: WKContentRuleListStore? = nil) {
        storeOverride = store
    }

    @MainActor
    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        let store = store
        return await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { ruleList, _ in
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
        let store = store
        return try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(
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
        let store = store
        return await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { identifiers in
                continuation.resume(returning: identifiers ?? [])
            }
        }
    }

    @MainActor
    func removeContentRuleList(forIdentifier identifier: String) async throws {
        let store = store
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.removeContentRuleList(forIdentifier: identifier) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private var store: WKContentRuleListStore {
        storeOverride ?? Self.defaultStore()
    }

    @MainActor
    private static func defaultStore() -> WKContentRuleListStore {
        #if DEBUG
            if let testStore = xctestProcessIsolatedStore() {
                return testStore
            }
        #endif

        return WKContentRuleListStore.default()
    }

    #if DEBUG
        @MainActor
        private static func xctestProcessIsolatedStore() -> WKContentRuleListStore? {
            let environment = ProcessInfo.processInfo.environment
            guard environment["XCTestConfigurationFilePath"] != nil else { return nil }

            let processID = ProcessInfo.processInfo.processIdentifier
            let storeURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SumiContentRuleListStore-XCTest", isDirectory: true)
                .appendingPathComponent("\(processID)", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: storeURL,
                withIntermediateDirectories: true
            )
            return WKContentRuleListStore(url: storeURL)
        }
    #endif
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
final class SumiContentBlockingService {
    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager

    private let compiler: SumiContentRuleListCompiling
    private let ruleListMaterializer: SumiContentRuleListMaterializer
    private let updatesSubject: CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>
    private let ruleListProvider: SumiContentRuleListSetProviding?
    private let compiledRuleListCleanupOwner: SumiCompiledContentRuleListCleanupOwner
    private let scheduledTasks = SumiContentBlockingScheduledTaskOwner()
    private var currentPolicy: SumiContentBlockingPolicy
    private var compilationGeneration = 0
    private var ruleListRefreshGeneration = 0
    private var profileRefreshGenerations: [String: Int] = [:]
    private var profileUpdateSubjects: [String: CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()

    private(set) var latestUpdate: SumiContentBlockerRulesUpdate?

    var latestRuleListIdentifiers: [String] {
        latestUpdate?.rules.map(\.storeIdentifier).sorted() ?? []
    }

    init(
        policy: SumiContentBlockingPolicy = .defaultPolicy,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler(),
        ruleListProvider: SumiContentRuleListSetProviding? = nil,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging = SumiCompiledContentRuleListCatalog.shared
    ) {
        currentPolicy = policy
        self.compiler = compiler
        self.ruleListMaterializer = SumiContentRuleListMaterializer(compiler: compiler)
        self.ruleListProvider = ruleListProvider
        compiledRuleListCleanupOwner = SumiCompiledContentRuleListCleanupOwner(
            compiler: compiler,
            catalog: compiledRuleListCatalog
        )
        privacyConfigurationManager = SumiContentBlockingPrivacyConfigurationManager(
            isContentBlockingEnabled: policy.shouldEnableContentBlockingFeature
        )

        let usesDynamicRuleSource = ruleListProvider != nil

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
            scheduleRuleListProviderRefresh(delayNanoseconds: 0)
        } else if !policy.ruleLists.isEmpty {
            scheduleCompilation(for: policy)
        }
    }

    isolated deinit {
        cancelScheduledTasksForShutdown()
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
        guard ruleListProvider?.hasProfileSpecificRuleLists == true else {
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
                scheduledTasks.cancelCompilationTask()
                privacyConfigurationManager.setContentBlockingEnabled(false)
                publish(Self.emptyUpdate(), cleaningUpAfter: nil)
            }
            return
        }

        let previousPolicy = currentPolicy
        currentPolicy = policy
        privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)

        if policy.ruleLists.isEmpty {
            scheduledTasks.cancelCompilationTask()
            publish(Self.emptyUpdate(), cleaningUpAfter: latestUpdate)
        } else {
            scheduleCompilation(for: policy, previousPolicy: previousPolicy)
        }
    }

    func validateRuleLists(
        _ definitions: [SumiContentRuleListDefinition]
    ) async throws {
        let update = try await ruleListMaterializer.updateEvent(for: definitions)
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
        let update = try await ruleListMaterializer.updateEvent(for: definitions)
        return SumiPreparedContentBlockingUpdate(
            policy: policy,
            updateEvent: update
        )
    }

    /// Restores already-compiled WebKit rule lists without rehydrating their encoded JSON payloads.
    /// Use this only for persisted generations that must already exist in `WKContentRuleListStore`;
    /// callers that need repair-on-miss should fall back to `prepareRuleListUpdate`.
    func prepareExistingRuleListUpdate(
        ruleLists definitions: [SumiContentRuleListDefinition]
    ) async throws -> SumiPreparedContentBlockingUpdate {
        let metadataOnlyDefinitions = definitions.map { $0.metadataOnly() }
        let policy: SumiContentBlockingPolicy = metadataOnlyDefinitions.isEmpty
            ? .disabled
            : .enabled(ruleLists: metadataOnlyDefinitions)
        let update = try await ruleListMaterializer.existingUpdateEvent(for: metadataOnlyDefinitions)
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
        ruleListRefreshGeneration += 1
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
                self?.scheduleRuleListProviderRefresh(refreshProfileSubjects: true)
            }
            .store(in: &cancellables)
    }

    private func scheduleRuleListProviderRefresh(
        refreshProfileSubjects: Bool = false,
        delayNanoseconds: UInt64 = 150_000_000
    ) {
        ruleListRefreshGeneration += 1
        let generation = ruleListRefreshGeneration

        scheduledTasks.scheduleRuleListRefreshTask { token in
            Task { [weak self] in
                if delayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                }
                guard let self else { return }
                defer {
                    self.scheduledTasks.finishRuleListRefreshTask(token: token)
                }
                guard !Task.isCancelled,
                      generation == self.ruleListRefreshGeneration
                else { return }

                do {
                    let ruleLists = try self.ruleLists(profileId: nil)
                    guard generation == self.ruleListRefreshGeneration else { return }
                    self.setPolicy(ruleLists.isEmpty ? .disabled : .enabled(ruleLists: ruleLists))
                    if refreshProfileSubjects {
                        self.scheduleActiveProfilePolicyRefreshes(delayNanoseconds: 0)
                    }
                } catch {
                    guard generation == self.ruleListRefreshGeneration else { return }
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

        scheduledTasks.scheduleProfileRefreshTask(key: key) { token in
            Task { [weak self] in
                if delayNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: delayNanoseconds)
                }
                guard let self else { return }
                defer {
                    self.scheduledTasks.finishProfileRefreshTask(key: key, token: token)
                }
                guard !Task.isCancelled,
                      self.profileRefreshGenerations[key] == generation
                else { return }

                do {
                    let ruleLists = try self.ruleLists(profileId: profileId)
                    guard self.profileRefreshGenerations[key] == generation else { return }
                    let update = try await self.ruleListMaterializer.updateEvent(for: ruleLists)
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
    }

    private func ruleLists(profileId: UUID?) throws -> [SumiContentRuleListDefinition] {
        if let ruleListProvider {
            return try ruleListProvider.ruleListSet(profileId: profileId).allDefinitions
        }

        return currentPolicy.ruleLists
    }

    private func scheduleCompilation(
        for policy: SumiContentBlockingPolicy,
        previousPolicy: SumiContentBlockingPolicy? = nil
    ) {
        compilationGeneration += 1
        let generation = compilationGeneration

        scheduledTasks.scheduleCompilationTask { token in
            Task { [weak self] in
                guard let self else { return }
                defer {
                    self.scheduledTasks.finishCompilationTask(token: token)
                }
                guard !Task.isCancelled else { return }
                await self.compileAndPublish(
                    policy: policy,
                    generation: generation,
                    previousPolicy: previousPolicy
                )
            }
        }
    }

    private func cancelScheduledTasksForShutdown() {
        compilationGeneration += 1
        ruleListRefreshGeneration += 1
        scheduledTasks.cancelAllTasksForShutdown()
        profileRefreshGenerations = profileRefreshGenerations.mapValues { $0 + 1 }
    }

    #if DEBUG
        func drainScheduledTasksForTests(cancel: Bool = false) async {
            await scheduledTasks.drainScheduledTasksForTests(cancel: cancel)
        }
    #endif

    private func compileAndPublish(
        policy: SumiContentBlockingPolicy,
        generation: Int,
        previousPolicy: SumiContentBlockingPolicy?
    ) async {
        do {
            let update = try await ruleListMaterializer.updateEvent(for: policy.ruleLists)

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

    private func publishProfileUpdate(
        _ update: SumiContentBlockerRulesUpdate,
        for profileId: UUID
    ) {
        let subject = profileSubject(for: profileId)
        let previousUpdate = subject.value
        subject.send(update)
        cleanupOrphanedCompiledRuleLists(
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
        cleanupOrphanedCompiledRuleLists(
            replacing: previousUpdate?.rules ?? [],
            with: update.rules
        )
    }

    private func cleanupOrphanedCompiledRuleLists(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) {
        compiledRuleListCleanupOwner.cleanupOrphanedCompiledRuleLists(
            replacing: previousRules,
            with: activeRules,
            forgetCachedRuleLists: { [ruleListMaterializer] identifiers in
                ruleListMaterializer.forgetCachedCompiledRuleLists(withIdentifiers: identifiers)
            }
        )
    }

    private func cleanupTransientCompiledRuleLists(
        from update: SumiContentBlockerRulesUpdate
    ) {
        compiledRuleListCleanupOwner.cleanupTransientCompiledRuleLists(
            from: update,
            activeRules: latestUpdate?.rules ?? [],
            forgetCachedRuleLists: { [ruleListMaterializer] identifiers in
                ruleListMaterializer.forgetCachedCompiledRuleLists(withIdentifiers: identifiers)
            }
        )
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
