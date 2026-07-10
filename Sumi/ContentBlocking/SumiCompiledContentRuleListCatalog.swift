import Foundation

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
final class SumiCompiledContentRuleListCatalog:
    SumiCompiledContentRuleListCataloging
{
    private let userDefaults: UserDefaults
    private let userDefaultsKey = "SumiCompiledContentRuleListIdentifiersByName.v1"
    private var identifiersByName: [String: Set<String>]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let persisted = userDefaults.dictionary(forKey: userDefaultsKey)
            as? [String: [String]] ?? [:]
        identifiersByName = persisted.mapValues(Set.init)
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
        let namesToSweep = Set(identifiersByName.keys)
            .union(activeIdentifiersByName.keys)
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
        let namesToSweep = Set(previousIdentifiersByName.keys)
            .union(activeIdentifiersByName.keys)
        var orphanedIdentifiers = Set<String>()

        for name in namesToSweep {
            let activeIdentifiers = activeIdentifiersByName[name] ?? []
            var knownIdentifiers = identifiersByName[name] ?? []
            knownIdentifiers.formUnion(previousIdentifiersByName[name] ?? [])
            orphanedIdentifiers.formUnion(
                knownIdentifiers.subtracting(activeIdentifiers)
            )
        }
        return Array(orphanedIdentifiers)
    }

    private func save() {
        userDefaults.set(
            identifiersByName.mapValues { Array($0).sorted() },
            forKey: userDefaultsKey
        )
    }

    private static func identifiersByName(
        for rules: [SumiContentBlockerRules]
    ) -> [String: Set<String>] {
        rules.reduce(into: [:]) { result, rules in
            result[rules.identifier.name, default: []].insert(rules.storeIdentifier)
        }
    }
}
