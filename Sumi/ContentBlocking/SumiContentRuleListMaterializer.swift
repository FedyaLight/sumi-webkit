import Foundation
import WebKit

@MainActor
final class SumiContentRuleListMaterializer {
    private enum RuleStoreReadiness {
        case verifiedByStoreLookup
        case needsSmokeLookup
    }

    private struct ResolvedRule {
        let rules: SumiContentBlockerRules
        let storeReadiness: RuleStoreReadiness
    }

    private let compiler: SumiContentRuleListCompiling
    private var compiledRulesByIdentifier: [String: SumiContentBlockerRules] = [:]

    init(compiler: SumiContentRuleListCompiling) {
        self.compiler = compiler
    }

    func updateEvent(
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

    func existingUpdateEvent(
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

    func forgetCachedCompiledRuleLists(withIdentifiers identifiers: [String]) {
        let uniqueIdentifiers = Array(Set(identifiers))
        guard !uniqueIdentifiers.isEmpty else { return }

        for identifier in uniqueIdentifiers {
            compiledRulesByIdentifier.removeValue(forKey: identifier)
        }
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
            SumiProtectionStartupRestoreDiagnostics.shared.recordRepairCompileUsed(
                reason: "Compiled WebKit rule list missing for \(storeIdentifier); compiling payload-backed repair"
            )
#endif
            do {
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

    private static func updateEvent(
        for rules: [SumiContentBlockerRules],
        lookupFailedIdentifiers: [String] = [],
        ruleListLookupDuration: TimeInterval? = nil
    ) -> SumiContentBlockerRulesUpdate {
        updateEvent(
            for: rules,
            lookupSucceededIdentifiers: rules.map(\.storeIdentifier),
            lookupFailedIdentifiers: lookupFailedIdentifiers,
            ruleListLookupDuration: ruleListLookupDuration
        )
    }

    private static func updateEvent(
        for rules: [SumiContentBlockerRules],
        lookupSucceededIdentifiers: [String],
        lookupFailedIdentifiers: [String] = [],
        ruleListLookupDuration: TimeInterval? = nil
    ) -> SumiContentBlockerRulesUpdate {
        let changes = Dictionary(uniqueKeysWithValues: rules.map { ($0.name, SumiContentBlockerRulesIdentifier.Difference.all) })
        return SumiContentBlockerRulesUpdate(
            rules: rules,
            changes: changes,
            completionTokens: [],
            lookupSucceededIdentifiers: lookupSucceededIdentifiers.sorted(),
            lookupFailedIdentifiers: lookupFailedIdentifiers.sorted(),
            ruleListLookupDuration: ruleListLookupDuration
        )
    }
}
