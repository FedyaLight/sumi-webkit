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
protocol SumiCompiledContentRuleListCataloging: AnyObject {
    func cachedIdentifiersToForget(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String]

    func orphanedIdentifiers(
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
        orphanedIdentifiersWithoutMutating(
            replacing: previousRules,
            with: activeRules
        )
    }

    func orphanedIdentifiers(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let orphanedIdentifiers = orphanedIdentifiersWithoutMutating(
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
        return orphanedIdentifiers
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

    private func orphanedIdentifiersWithoutMutating(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let previousIdentifiersByName = Self.identifiersByName(for: previousRules)
        let activeIdentifiersByName = Self.identifiersByName(for: activeRules)
        let namesToSweep = Set(previousIdentifiersByName.keys).union(activeIdentifiersByName.keys)
        var orphanedIdentifiers = Set<String>()

        for name in namesToSweep {
            let activeIdentifiers = activeIdentifiersByName[name] ?? []
            var knownIdentifiers = identifiersByName[name] ?? []
            knownIdentifiers.formUnion(previousIdentifiersByName[name] ?? [])
            orphanedIdentifiers.formUnion(knownIdentifiers.subtracting(activeIdentifiers))
        }

        return Array(orphanedIdentifiers)
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
    private enum RuleStoreReadiness {
        case verifiedByStoreLookup
        case needsSmokeLookup
    }

    private struct ResolvedRule {
        let rules: SumiContentBlockerRules
        let storeReadiness: RuleStoreReadiness
    }

    private struct ScheduledTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager

    private let compiler: SumiContentRuleListCompiling
    private let updatesSubject: CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>
    private let ruleListProvider: SumiContentRuleListSetProviding?
    private let compiledRuleListCatalog: SumiCompiledContentRuleListCataloging
    private var currentPolicy: SumiContentBlockingPolicy
    private var compiledRulesByIdentifier: [String: SumiContentBlockerRules] = [:]
    private var compilationGeneration = 0
    private var ruleListRefreshGeneration = 0
    private var profileRefreshGenerations: [String: Int] = [:]
    private var profileUpdateSubjects: [String: CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var compilationTask: ScheduledTask?
    private var ruleListRefreshTask: ScheduledTask?
    private var profileRefreshTasksByKey: [String: ScheduledTask] = [:]
    private var retiredScheduledTaskTokens = Set<UUID>()
    private var finishedUnregisteredScheduledTaskTokens = Set<UUID>()

    #if DEBUG
        private var retiredScheduledTasksByToken: [UUID: Task<Void, Never>] = [:]
    #endif

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
        self.ruleListProvider = ruleListProvider
        self.compiledRuleListCatalog = compiledRuleListCatalog
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
                cancelCompilationTask()
                privacyConfigurationManager.setContentBlockingEnabled(false)
                publish(Self.emptyUpdate(), cleaningUpAfter: nil)
            }
            return
        }

        let previousPolicy = currentPolicy
        currentPolicy = policy
        privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)

        if policy.ruleLists.isEmpty {
            cancelCompilationTask()
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
        let update = try await existingUpdateEvent(for: metadataOnlyDefinitions)
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
        retireScheduledTask(ruleListRefreshTask)

        let token = UUID()
        let task = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self else { return }
            defer {
                self.finishRuleListRefreshTask(token: token)
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
        ruleListRefreshTask = ScheduledTask(token: token, task: task)
        clearRuleListRefreshTaskIfFinishedBeforeRegistration(token: token)
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
        retireScheduledTask(profileRefreshTasksByKey[key])

        let token = UUID()
        let task = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self else { return }
            defer {
                self.finishProfileRefreshTask(key: key, token: token)
            }
            guard !Task.isCancelled,
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
        profileRefreshTasksByKey[key] = ScheduledTask(token: token, task: task)
        clearProfileRefreshTaskIfFinishedBeforeRegistration(key: key, token: token)
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
        retireScheduledTask(compilationTask)

        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.finishCompilationTask(token: token)
            }
            guard !Task.isCancelled else { return }
            await self.compileAndPublish(
                policy: policy,
                generation: generation,
                previousPolicy: previousPolicy
            )
        }
        compilationTask = ScheduledTask(token: token, task: task)
        clearCompilationTaskIfFinishedBeforeRegistration(token: token)
    }

    private func cancelCompilationTask() {
        retireScheduledTask(compilationTask)
        compilationTask = nil
    }

    private func cancelScheduledTasksForShutdown() {
        compilationGeneration += 1
        ruleListRefreshGeneration += 1
        retireScheduledTask(compilationTask)
        retireScheduledTask(ruleListRefreshTask)
        for scheduledTask in profileRefreshTasksByKey.values {
            retireScheduledTask(scheduledTask)
        }
        compilationTask = nil
        ruleListRefreshTask = nil
        profileRefreshTasksByKey.removeAll(keepingCapacity: false)
        profileRefreshGenerations = profileRefreshGenerations.mapValues { $0 + 1 }
        finishedUnregisteredScheduledTaskTokens.removeAll(keepingCapacity: false)
    }

    private func retireScheduledTask(_ scheduledTask: ScheduledTask?) {
        guard let scheduledTask else { return }
        scheduledTask.task.cancel()
        retiredScheduledTaskTokens.insert(scheduledTask.token)
        #if DEBUG
            retiredScheduledTasksByToken[scheduledTask.token] = scheduledTask.task
        #endif
    }

    private func finishCompilationTask(token: UUID) {
        var didResolveTask = false
        if compilationTask?.token == token {
            compilationTask = nil
            didResolveTask = true
        }
        didResolveTask = resolveRetiredScheduledTask(token: token) || didResolveTask
        rememberFinishedScheduledTaskIfUnregistered(token: token, didResolveTask: didResolveTask)
    }

    private func finishRuleListRefreshTask(token: UUID) {
        var didResolveTask = false
        if ruleListRefreshTask?.token == token {
            ruleListRefreshTask = nil
            didResolveTask = true
        }
        didResolveTask = resolveRetiredScheduledTask(token: token) || didResolveTask
        rememberFinishedScheduledTaskIfUnregistered(token: token, didResolveTask: didResolveTask)
    }

    private func finishProfileRefreshTask(key: String, token: UUID) {
        var didResolveTask = false
        if profileRefreshTasksByKey[key]?.token == token {
            profileRefreshTasksByKey.removeValue(forKey: key)
            didResolveTask = true
        }
        didResolveTask = resolveRetiredScheduledTask(token: token) || didResolveTask
        rememberFinishedScheduledTaskIfUnregistered(token: token, didResolveTask: didResolveTask)
    }

    private func resolveRetiredScheduledTask(token: UUID) -> Bool {
        let didResolveTask = retiredScheduledTaskTokens.remove(token) != nil
        #if DEBUG
            retiredScheduledTasksByToken.removeValue(forKey: token)
        #endif
        return didResolveTask
    }

    private func rememberFinishedScheduledTaskIfUnregistered(
        token: UUID,
        didResolveTask: Bool
    ) {
        guard !didResolveTask else { return }
        finishedUnregisteredScheduledTaskTokens.insert(token)
    }

    private func clearCompilationTaskIfFinishedBeforeRegistration(token: UUID) {
        guard finishedUnregisteredScheduledTaskTokens.remove(token) != nil else { return }
        if compilationTask?.token == token {
            compilationTask = nil
        }
    }

    private func clearRuleListRefreshTaskIfFinishedBeforeRegistration(token: UUID) {
        guard finishedUnregisteredScheduledTaskTokens.remove(token) != nil else { return }
        if ruleListRefreshTask?.token == token {
            ruleListRefreshTask = nil
        }
    }

    private func clearProfileRefreshTaskIfFinishedBeforeRegistration(
        key: String,
        token: UUID
    ) {
        guard finishedUnregisteredScheduledTaskTokens.remove(token) != nil else { return }
        if profileRefreshTasksByKey[key]?.token == token {
            profileRefreshTasksByKey.removeValue(forKey: key)
        }
    }

    #if DEBUG
        func drainScheduledTasksForTests(cancel: Bool = false) async {
            while true {
                let tasks = scheduledTasksForTests()
                guard tasks.isEmpty == false else { return }
                if cancel {
                    tasks.forEach { $0.cancel() }
                }
                for task in tasks {
                    await task.value
                }
            }
        }

        private func scheduledTasksForTests() -> [Task<Void, Never>] {
            var tasks: [Task<Void, Never>] = []
            if let compilationTask {
                tasks.append(compilationTask.task)
            }
            if let ruleListRefreshTask {
                tasks.append(ruleListRefreshTask.task)
            }
            tasks.append(contentsOf: profileRefreshTasksByKey.values.map(\.task))
            tasks.append(contentsOf: retiredScheduledTasksByToken.values)
            return tasks
        }
    #endif

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
            var resolvedRule = try await rule(for: definition)
            var rules = resolvedRule.rules
            let storeIdentifier = rules.storeIdentifier
            var canLookUp = resolvedRule.storeReadiness == .verifiedByStoreLookup
            if canLookUp == false {
                canLookUp = await canLookUpCompiledRuleList(forIdentifier: storeIdentifier)
            }
            ruleListLookupDuration += Date().timeIntervalSince(lookupStart)

            if canLookUp == false {
                compiledRulesByIdentifier.removeValue(forKey: storeIdentifier)
                let retryStart = Date()
                resolvedRule = try await rule(for: definition)
                rules = resolvedRule.rules
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

    private func existingUpdateEvent(
        for definitions: [SumiContentRuleListDefinition]
    ) async throws -> SumiContentBlockerRulesUpdate {
        var compiledRules: [SumiContentBlockerRules] = []
        compiledRules.reserveCapacity(definitions.count)
        var lookupSucceededIdentifiers = [String]()
        var lookupFailedIdentifiers = [String]()
        var ruleListLookupDuration: TimeInterval = 0
        let storeIdentifiers = definitions.map { storeIdentifier(for: $0) }
#if DEBUG
        SumiProtectionStartupRestoreDiagnostics.shared.recordLookupAttempt(identifiers: storeIdentifiers)
#endif

        for definition in definitions {
            let lookupStart = Date()
            let storeIdentifier = storeIdentifier(for: definition)
            guard let ruleList = await compiler.lookUpContentRuleList(forIdentifier: storeIdentifier) else {
                ruleListLookupDuration += Date().timeIntervalSince(lookupStart)
                lookupFailedIdentifiers.append(storeIdentifier)
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordLookupMiss(storeIdentifier)
#endif
                throw SumiContentBlockingCompilationError.missingCompiledRuleList(storeIdentifier)
            }
            ruleListLookupDuration += Date().timeIntervalSince(lookupStart)
#if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordLookupHit(storeIdentifier)
#endif

            let rules = SumiContentBlockerRules(
                name: definition.name,
                storeIdentifier: storeIdentifier,
                rulesList: ruleList,
                etag: definition.contentHash,
                identifier: rulesIdentifier(for: definition)
            )
            compiledRulesByIdentifier[storeIdentifier] = rules
            compiledRules.append(rules)
            lookupSucceededIdentifiers.append(storeIdentifier)
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
#if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordLookupAttempt(identifiers: [identifier])
#endif
            if await compiler.canLookUpContentRuleList(forIdentifier: identifier) {
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordLookupHit(identifier)
#endif
                return true
            }
#if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordLookupMiss(identifier)
#endif
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

    private func rule(for definition: SumiContentRuleListDefinition) async throws -> ResolvedRule {
        let rulesIdentifier = rulesIdentifier(for: definition)
        let storeIdentifier = storeIdentifier(for: definition)

        if let cachedRules = compiledRulesByIdentifier[storeIdentifier] {
            return ResolvedRule(
                rules: cachedRules,
                storeReadiness: .needsSmokeLookup
            )
        }

        let ruleList: WKContentRuleList
        let storeReadiness: RuleStoreReadiness
#if DEBUG
        SumiProtectionStartupRestoreDiagnostics.shared.recordLookupAttempt(identifiers: [storeIdentifier])
#endif
        if let cachedRuleList = await compiler.lookUpContentRuleList(forIdentifier: storeIdentifier) {
#if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordLookupHit(storeIdentifier)
#endif
            ruleList = cachedRuleList
            storeReadiness = .verifiedByStoreLookup
        } else {
#if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordLookupMiss(storeIdentifier)
#endif
            do {
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordRepairCompileUsed(
                    reason: "Compiled WebKit rule list missing for \(storeIdentifier); compiling payload-backed repair"
                )
#endif
                ruleList = try await compiler.compileContentRuleList(
                    forIdentifier: storeIdentifier,
                    encodedContentRuleList: definition.encodedContentRuleList
                )
                storeReadiness = .needsSmokeLookup
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
        return ResolvedRule(
            rules: rules,
            storeReadiness: storeReadiness
        )
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
        let cachedIdentifiersToForget = compiledRuleListCatalog.cachedIdentifiersToForget(
            replacing: previousRules,
            with: activeRules
        )
        let orphanedIdentifiers = compiledRuleListCatalog.orphanedIdentifiers(
            replacing: previousRules,
            with: activeRules
        )
        forgetCachedCompiledRuleLists(withIdentifiers: cachedIdentifiersToForget)
        removeCompiledRuleListsFromStore(withIdentifiers: orphanedIdentifiers)
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
#if DEBUG
        SumiProtectionStartupRestoreDiagnostics.shared.recordCompiledRuleListRemoval(
            identifiers: uniqueIdentifiers,
            reason: "SumiContentBlockingService orphaned compiled rule-list cleanup"
        )
#endif
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
