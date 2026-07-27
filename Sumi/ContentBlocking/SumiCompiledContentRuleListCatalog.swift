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
final class SumiCompiledContentRuleListCatalog:
    SumiCompiledContentRuleListCataloging
{
    private static let log = Logger.sumi(category: "ContentBlocking")
    private static let documentKey = "content-blocking.compiled-identifiers"
    private let database: SumiDatabase?
    private let persistentStateWasReadable: Bool
    private var identifiersByName: [String: Set<String>]

    init(database: SumiDatabase? = nil) {
        self.database = database
        guard let database else {
            persistentStateWasReadable = true
            identifiersByName = [:]
            return
        }
        do {
            let persisted = try database.read {
                try $0.documents.value(
                    [String: [String]].self,
                    forKey: Self.documentKey
                )
            }
            persistentStateWasReadable = true
            identifiersByName = (persisted ?? [:]).mapValues(Set.init)
        } catch {
            persistentStateWasReadable = false
            identifiersByName = [:]
            Self.log.error(
                "Failed to load compiled content-rule identifiers: \(error.localizedDescription, privacy: .public)"
            )
        }
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
        var candidate = identifiersByName
        for name in namesToSweep {
            let activeIdentifiers = activeIdentifiersByName[name] ?? []
            if activeIdentifiers.isEmpty {
                candidate.removeValue(forKey: name)
            } else {
                candidate[name] = activeIdentifiers
            }
        }
        persistAndPublish(candidate)
        return orphanedIdentifiers
    }

    func forgetIdentifiers(_ identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        let identifiersToForget = Set(identifiers)
        var candidate = identifiersByName
        for name in Array(candidate.keys) {
            candidate[name]?.subtract(identifiersToForget)
            if candidate[name]?.isEmpty == true {
                candidate.removeValue(forKey: name)
            }
        }
        persistAndPublish(candidate)
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

    private func persistAndPublish(_ candidate: [String: Set<String>]) {
        guard candidate != identifiersByName else { return }
        guard persistentStateWasReadable else {
            Self.log.error(
                "Rejected compiled content-rule identifier mutation because the stored baseline is unreadable."
            )
            return
        }
        do {
            try database?.transaction {
                if candidate.isEmpty {
                    try $0.documents.delete(key: Self.documentKey)
                } else {
                    try $0.documents.save(
                        candidate.mapValues { Array($0).sorted() },
                        forKey: Self.documentKey
                    )
                }
            }
        } catch {
            Self.log.error(
                "Failed to persist compiled content-rule identifiers: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        identifiersByName = candidate
    }

    private static func identifiersByName(
        for rules: [SumiContentBlockerRules]
    ) -> [String: Set<String>] {
        rules.reduce(into: [:]) { result, rules in
            result[rules.identifier.name, default: []].insert(rules.storeIdentifier)
        }
    }
}
