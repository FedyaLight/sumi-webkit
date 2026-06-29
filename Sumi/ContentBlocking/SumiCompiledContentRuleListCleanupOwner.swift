import Foundation
import OSLog

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
final class SumiCompiledContentRuleListCleanupOwner {
    private let compiler: any SumiContentRuleListCompiling
    private let catalog: SumiCompiledContentRuleListCataloging

    init(
        compiler: any SumiContentRuleListCompiling,
        catalog: SumiCompiledContentRuleListCataloging
    ) {
        self.compiler = compiler
        self.catalog = catalog
    }

    @discardableResult
    func cleanupOrphanedCompiledRuleLists(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules],
        forgetCachedRuleLists: ([String]) -> Void
    ) -> Task<Void, Never>? {
        let cachedIdentifiersToForget = catalog.cachedIdentifiersToForget(
            replacing: previousRules,
            with: activeRules
        )
        let orphanedIdentifiers = catalog.orphanedIdentifiers(
            replacing: previousRules,
            with: activeRules
        )

        forgetCachedRuleLists(Self.uniqueSortedIdentifiers(cachedIdentifiersToForget))
        return removeCompiledRuleListsFromStore(
            withIdentifiers: orphanedIdentifiers,
            reason: "SumiContentBlockingService orphaned compiled rule-list cleanup"
        )
    }

    @discardableResult
    func cleanupTransientCompiledRuleLists(
        from update: SumiContentBlockerRulesUpdate,
        activeRules: [SumiContentBlockerRules],
        forgetCachedRuleLists: ([String]) -> Void
    ) -> Task<Void, Never>? {
        let activeIdentifiers = Set(activeRules.map(\.storeIdentifier))
        let transientIdentifiers = update.rules
            .map(\.storeIdentifier)
            .filter { !activeIdentifiers.contains($0) }

        catalog.forgetIdentifiers(transientIdentifiers)
        forgetCachedRuleLists(Self.uniqueSortedIdentifiers(transientIdentifiers))
        return removeCompiledRuleListsFromStore(
            withIdentifiers: transientIdentifiers,
            reason: "SumiContentBlockingService transient compiled rule-list cleanup"
        )
    }

    @discardableResult
    func removeCompiledRuleListsFromStore(
        withIdentifiers identifiers: [String],
        reason: String
    ) -> Task<Void, Never>? {
        let uniqueIdentifiers = Self.uniqueSortedIdentifiers(identifiers)
        guard !uniqueIdentifiers.isEmpty else { return nil }

        #if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordCompiledRuleListRemoval(
                identifiers: uniqueIdentifiers,
                reason: "\(reason) queued"
            )
        #endif

        return Task { @MainActor [compiler] in
            for identifier in uniqueIdentifiers {
                do {
                    try await compiler.removeContentRuleList(forIdentifier: identifier)
                } catch {
                    Self.logStoreRemovalFailure(identifier: identifier, error: error)
                    #if DEBUG
                        SumiProtectionStartupRestoreDiagnostics.shared.recordCompiledRuleListRemoval(
                            identifiers: [identifier],
                            reason: "\(reason) failed for \(identifier): \(error.localizedDescription)"
                        )
                    #endif
                }
            }
        }
    }

    private static func uniqueSortedIdentifiers(_ identifiers: [String]) -> [String] {
        Array(Set(identifiers)).sorted()
    }

    private static func logStoreRemovalFailure(identifier: String, error: Error) {
        Logger.sumi(category: "ContentBlockingCleanup").error(
            "Failed to remove compiled content rule list \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }
}
