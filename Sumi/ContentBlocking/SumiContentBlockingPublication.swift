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
