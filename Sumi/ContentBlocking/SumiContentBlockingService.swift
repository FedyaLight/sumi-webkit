import BrowserServicesKit
import Combine
import CryptoKit
import Foundation
import PrivacyConfig
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

@MainActor
final class SumiContentBlockingService {
    static let shared = SumiContentBlockingService(policy: .defaultPolicy)

    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager

    private let compiler: SumiContentRuleListCompiling
    private let updatesSubject: CurrentValueSubject<ContentBlockerRulesManager.UpdateEvent?, Never>
    private var currentPolicy: SumiContentBlockingPolicy
    private var compiledRulesByIdentifier: [String: ContentBlockerRulesManager.Rules] = [:]
    private var compilationGeneration = 0

    private(set) var latestUpdate: ContentBlockerRulesManager.UpdateEvent?
    private(set) var lastCompilationError: Error?

    init(
        policy: SumiContentBlockingPolicy = .defaultPolicy,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler()
    ) {
        currentPolicy = policy
        self.compiler = compiler
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

        if !policy.ruleLists.isEmpty {
            scheduleCompilation(for: policy)
        }
    }

    var policy: SumiContentBlockingPolicy {
        currentPolicy
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

    func setPolicy(_ policy: SumiContentBlockingPolicy) {
        guard policy != currentPolicy else { return }

        currentPolicy = policy
        privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)

        if policy.ruleLists.isEmpty {
            lastCompilationError = nil
            publish(Self.emptyUpdate())
        } else {
            scheduleCompilation(for: policy)
        }
    }

    private func scheduleCompilation(for policy: SumiContentBlockingPolicy) {
        compilationGeneration += 1
        let generation = compilationGeneration

        Task { [weak self] in
            await self?.compileAndPublish(policy: policy, generation: generation)
        }
    }

    private func compileAndPublish(policy: SumiContentBlockingPolicy, generation: Int) async {
        do {
            var compiledRules: [ContentBlockerRulesManager.Rules] = []
            compiledRules.reserveCapacity(policy.ruleLists.count)

            for definition in policy.ruleLists {
                compiledRules.append(try await rule(for: definition))
            }

            guard generation == compilationGeneration, policy == currentPolicy else { return }
            lastCompilationError = nil
            privacyConfigurationManager.setContentBlockingEnabled(policy.shouldEnableContentBlockingFeature)
            publish(Self.updateEvent(for: compiledRules))
        } catch {
            guard generation == compilationGeneration, policy == currentPolicy else { return }
            lastCompilationError = error
            privacyConfigurationManager.setContentBlockingEnabled(false)
            publish(Self.emptyUpdate())
        }
    }

    private func rule(for definition: SumiContentRuleListDefinition) async throws -> ContentBlockerRulesManager.Rules {
        let rulesIdentifier = ContentBlockerRulesIdentifier(
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
            trackerData: Self.emptyTrackerData,
            encodedTrackerData: Self.encodedEmptyTrackerData,
            etag: definition.contentHash,
            identifier: rulesIdentifier
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

    private static let emptyTrackerData = TrackerData(
        trackers: [:],
        entities: [:],
        domains: [:],
        cnames: [:]
    )

    private static let encodedEmptyTrackerData: String = {
        guard let data = try? JSONEncoder().encode(emptyTrackerData),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return encoded
    }()
}

final class SumiContentBlockingPrivacyConfigurationManager: PrivacyConfigurationManaging {
    let currentConfig = Data("{}".utf8)
    let internalUserDecider: InternalUserDecider = SumiStaticInternalUserDecider()

    private let updatesSubject = PassthroughSubject<Void, Never>()
    private let lock = NSLock()
    private var configuration: SumiContentBlockingPrivacyConfiguration

    init(isContentBlockingEnabled: Bool) {
        configuration = SumiContentBlockingPrivacyConfiguration(
            isContentBlockingEnabled: isContentBlockingEnabled
        )
    }

    var updatesPublisher: AnyPublisher<Void, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    var privacyConfig: PrivacyConfiguration {
        lock.lock()
        let configuration = configuration
        lock.unlock()
        return configuration
    }

    func setContentBlockingEnabled(_ isEnabled: Bool) {
        lock.lock()
        let current = configuration
        guard current.isContentBlockingEnabled != isEnabled else {
            lock.unlock()
            return
        }
        configuration = SumiContentBlockingPrivacyConfiguration(isContentBlockingEnabled: isEnabled)
        lock.unlock()
        updatesSubject.send(())
    }

    @discardableResult
    func reload(etag: String?, data: Data?) -> PrivacyConfigurationManager.ReloadResult {
        _ = etag
        _ = data
        return .embedded
    }
}

struct SumiContentBlockingPrivacyConfiguration: PrivacyConfiguration {
    let isContentBlockingEnabled: Bool

    var identifier: String {
        isContentBlockingEnabled ? "sumi-content-blocking-enabled" : "sumi-content-blocking-disabled"
    }

    let version: String? = nil
    let userUnprotectedDomains: [String] = []
    let tempUnprotectedDomains: [String] = []
    let trackerAllowlist = PrivacyConfigurationData.TrackerAllowlist(entries: [:], state: PrivacyConfigurationData.State.disabled)

    func isEnabled(featureKey: PrivacyFeature, versionProvider: AppVersionProvider, defaultValue: Bool) -> Bool {
        featureKey == .contentBlocking ? isContentBlockingEnabled : false
    }

    func stateFor(featureKey: PrivacyFeature, versionProvider: AppVersionProvider) -> PrivacyConfigurationFeatureState {
        featureKey == .contentBlocking && isContentBlockingEnabled ? .enabled : .disabled(.featureMissing)
    }

    func isSubfeatureEnabled(
        _ subfeature: any PrivacySubfeature,
        versionProvider: AppVersionProvider,
        randomizer: (Range<Double>) -> Double,
        defaultValue: Bool
    ) -> Bool {
        _ = subfeature
        _ = randomizer
        _ = defaultValue
        return false
    }

    func stateFor(
        _ subfeature: any PrivacySubfeature,
        versionProvider: AppVersionProvider,
        randomizer: (Range<Double>) -> Double
    ) -> PrivacyConfigurationFeatureState {
        _ = subfeature
        _ = randomizer
        return .disabled(.featureMissing)
    }

    func exceptionsList(forFeature featureKey: PrivacyFeature) -> [String] {
        _ = featureKey
        return []
    }

    func isFeature(_ feature: PrivacyFeature, enabledForDomain: String?) -> Bool {
        _ = enabledForDomain
        return feature == .contentBlocking && isContentBlockingEnabled
    }

    func isProtected(domain: String?) -> Bool {
        _ = domain
        return isContentBlockingEnabled
    }

    func isUserUnprotected(domain: String?) -> Bool {
        _ = domain
        return false
    }

    func isTempUnprotected(domain: String?) -> Bool {
        _ = domain
        return false
    }

    func isInExceptionList(domain: String?, forFeature featureKey: PrivacyFeature) -> Bool {
        _ = domain
        _ = featureKey
        return false
    }

    func settings(for feature: PrivacyFeature) -> PrivacyConfigurationData.PrivacyFeature.FeatureSettings {
        _ = feature
        return [:]
    }

    func settings(for subfeature: any PrivacySubfeature) -> PrivacyConfigurationData.PrivacyFeature.SubfeatureSettings? {
        _ = subfeature
        return nil
    }

    func userEnabledProtection(forDomain: String) {
        _ = forDomain
    }

    func userDisabledProtection(forDomain: String) {
        _ = forDomain
    }

    func stateFor(
        subfeatureID: SubfeatureID,
        parentFeatureID: ParentFeatureID,
        versionProvider: AppVersionProvider,
        randomizer: (Range<Double>) -> Double
    ) -> PrivacyConfigurationFeatureState {
        _ = subfeatureID
        _ = parentFeatureID
        _ = randomizer
        return .disabled(.featureMissing)
    }

    func cohorts(for subfeature: any PrivacySubfeature) -> [PrivacyConfigurationData.Cohort]? {
        _ = subfeature
        return nil
    }

    func cohorts(subfeatureID: SubfeatureID, parentFeatureID: ParentFeatureID) -> [PrivacyConfigurationData.Cohort]? {
        _ = subfeatureID
        _ = parentFeatureID
        return nil
    }
}
