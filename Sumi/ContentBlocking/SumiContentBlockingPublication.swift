import Combine
import Foundation

/// Owns observer-visible content-blocking publications and their rule-list
/// retirement side effects. Policy decisions and WebKit materialization happen
/// before this boundary.
@MainActor
final class SumiContentBlockingPublication {
    private let updatesSubject:
        CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>
    private let retirement: SumiCompiledContentRuleListRetirement
    private let materializer: SumiContentRuleListMaterializer
    private var profileSubjects:
        [String: CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>] = [:]

    private(set) var latestUpdate: SumiContentBlockerRulesUpdate?

    init(
        initialUpdate: SumiContentBlockerRulesUpdate?,
        retirement: SumiCompiledContentRuleListRetirement,
        materializer: SumiContentRuleListMaterializer
    ) {
        latestUpdate = initialUpdate
        updatesSubject = CurrentValueSubject(initialUpdate)
        self.retirement = retirement
        self.materializer = materializer
    }

    var updatesPublisher: AnyPublisher<SumiContentBlockerRulesUpdate, Never> {
        updatesSubject.compactMap { $0 }.eraseToAnyPublisher()
    }

    var latestRuleListIdentifiers: [String] {
        latestUpdate?.rules.map(\.storeIdentifier).sorted() ?? []
    }

    var activeProfileIDs: [UUID] {
        profileSubjects.keys.compactMap(UUID.init(uuidString:))
    }

    func userContentPublisher(
        scriptsProvider: SumiNormalTabUserScripts
    ) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        updatesPublisher
            .map { update in
                SumiNormalTabUserContent(
                    contentBlockingUpdate: Self.normalTabUpdate(for: update),
                    sourceProvider: scriptsProvider
                )
            }
            .eraseToAnyPublisher()
    }

    func profileUserContentPublisher(
        profileId: UUID,
        scriptsProvider: SumiNormalTabUserScripts
    ) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        profileSubject(for: profileId)
            .compactMap { $0 }
            .map { update in
                SumiNormalTabUserContent(
                    contentBlockingUpdate: Self.normalTabUpdate(for: update),
                    sourceProvider: scriptsProvider
                )
            }
            .eraseToAnyPublisher()
    }

    func stage(_ update: SumiContentBlockerRulesUpdate) -> SumiContentBlockerRulesUpdate? {
        let previousUpdate = latestUpdate
        latestUpdate = update
        return previousUpdate
    }

    func publishStaged(
        _ update: SumiContentBlockerRulesUpdate,
        replacing previousUpdate: SumiContentBlockerRulesUpdate?
    ) {
        updatesSubject.send(update)
        retireRules(replacing: previousUpdate, with: update)
    }

    func publish(
        _ update: SumiContentBlockerRulesUpdate,
        replacing previousUpdate: SumiContentBlockerRulesUpdate?
    ) {
        latestUpdate = update
        updatesSubject.send(update)
        retireRules(replacing: previousUpdate, with: update)
    }

    func publishProfile(
        _ update: SumiContentBlockerRulesUpdate,
        profileId: UUID
    ) {
        let subject = profileSubject(for: profileId)
        let previousUpdate = subject.value
        subject.send(update)
        retireRules(replacing: previousUpdate, with: update)
    }

    func publishEmptyProfileIfUninitialized(profileId: UUID) {
        let subject = profileSubject(for: profileId)
        if subject.value == nil {
            subject.send(Self.emptyUpdate())
        }
    }

    static func emptyUpdate() -> SumiContentBlockerRulesUpdate {
        SumiContentBlockerRulesUpdate(
            rules: [],
            changes: [:],
            completionTokens: [],
            lookupSucceededIdentifiers: [],
            lookupFailedIdentifiers: [],
            ruleListLookupDuration: nil
        )
    }

    private func profileSubject(
        for profileId: UUID
    ) -> CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never> {
        let key = profileId.uuidString.lowercased()
        if let subject = profileSubjects[key] {
            return subject
        }
        let subject = CurrentValueSubject<SumiContentBlockerRulesUpdate?, Never>(nil)
        profileSubjects[key] = subject
        return subject
    }

    private func retireRules(
        replacing previousUpdate: SumiContentBlockerRulesUpdate?,
        with update: SumiContentBlockerRulesUpdate
    ) {
        retirement.retireOrphanedRuleLists(
            replacing: previousUpdate?.rules ?? [],
            with: update.rules,
            forgetMaterializedRules: { [materializer] identifiers in
                materializer.forgetCachedCompiledRuleLists(
                    withIdentifiers: identifiers
                )
            }
        )
    }

    private static func normalTabUpdate(
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
