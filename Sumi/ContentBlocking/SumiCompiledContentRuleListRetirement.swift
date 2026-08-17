import Foundation
import OSLog

/// Retires rule lists no longer reachable from the active publication. Catalog
/// decisions are synchronous; WebKit removals run asynchronously and failures
/// are isolated per identifier.
@MainActor
final class SumiCompiledContentRuleListRetirement {
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
    func retireOrphanedRuleLists(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules],
        forgetMaterializedRules: ([String]) -> Void
    ) -> Task<Void, Never>? {
        let cachedIdentifiers = catalog.cachedIdentifiersToForget(
            replacing: previousRules,
            with: activeRules
        )
        let orphanedIdentifiers = catalog.orphanedIdentifiers(
            replacing: previousRules,
            with: activeRules
        )
        forgetMaterializedRules(Self.uniqueIdentifiers(cachedIdentifiers))
        return removeCompiledRuleLists(
            identifiers: orphanedIdentifiers,
            reason: "orphaned content rule-list retirement"
        )
    }

    @discardableResult
    func removeCompiledRuleLists(
        identifiers: [String],
        reason: String
    ) -> Task<Void, Never>? {
        let identifiers = Self.uniqueIdentifiers(identifiers)
        guard !identifiers.isEmpty else { return nil }

        return Task { @MainActor [compiler] in
            for identifier in identifiers {
                do {
                    try await compiler.removeContentRuleList(
                        forIdentifier: identifier
                    )
                } catch {
                    Self.logRemovalFailure(identifier: identifier, error: error)
                }
            }
        }
    }

    private static func uniqueIdentifiers(_ identifiers: [String]) -> [String] {
        Array(Set(identifiers)).sorted()
    }

    private static func logRemovalFailure(identifier: String, error: Error) {
        Logger.sumi(category: "ContentBlockingCleanup").error(
            "Failed to remove compiled content rule list \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }
}
