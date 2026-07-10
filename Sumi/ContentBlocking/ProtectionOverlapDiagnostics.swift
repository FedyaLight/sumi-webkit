import Foundation
import OSLog

enum ProtectionOverlapDiagnostics {
    private static let log = Logger.sumi(category: "ContentBlocking")

    static func summarize(
        _ plannedDefinitions: [ProtectionPlannedRuleDefinition],
        includeExpensiveDiagnostics: Bool
    ) -> SumiProtectionOverlapSummary {
        let tracking = plannedDefinitions.filter { $0.source == .tracking }
        let adblock = plannedDefinitions.filter { $0.source == .adblock }
        guard !tracking.isEmpty, !adblock.isEmpty else {
            return SumiProtectionOverlapSummary(
                exactCanonicalOverlapCount: 0,
                domainResourceOverlapCount: 0,
                exactComparisonAvailable: false,
                notes: ["Tracking and Adblock are not both active in this plan."]
            )
        }
        guard includeExpensiveDiagnostics else {
            return .deferred
        }

        let trackingCanonicalResults = tracking.map(canonicalResult)
        let adblockCanonicalResults = adblock.map(canonicalResult)
        let trackingCanonical = Set(trackingCanonicalResults.compactMap(\.value))
        let adblockCanonical = Set(adblockCanonicalResults.compactMap(\.value))
        let canonicalFailures = (trackingCanonicalResults + adblockCanonicalResults)
            .compactMap(\.failure)

        let trackingTokenResults = tracking.map(urlFilterTokenResult)
        let adblockTokenResults = adblock.map(urlFilterTokenResult)
        let trackingDomains = Set(trackingTokenResults.flatMap(\.values))
        let adblockDomains = Set(adblockTokenResults.flatMap(\.values))
        let tokenFailures = (trackingTokenResults + adblockTokenResults)
            .compactMap(\.failure)

        var notes = [String]()
        if !canonicalFailures.isEmpty {
            notes.append(
                "Exact cross-source dedupe is unavailable for \(canonicalFailures.count) rule list(s) that cannot be safely canonicalized."
            )
            notes.append(contentsOf: canonicalFailures.prefix(3).map(\.reportLine))
        }
        if !tokenFailures.isEmpty {
            notes.append(
                "Domain/resource overlap is partial for \(tokenFailures.count) rule list(s) that cannot be parsed as WebKit rule-list arrays."
            )
            notes.append(contentsOf: tokenFailures.prefix(3).map(\.reportLine))
        }
        if trackingDomains.isEmpty || adblockDomains.isEmpty {
            notes.append(
                "Domain/resource overlap is heuristic because not every WebKit trigger exposes a host token."
            )
        }

        return SumiProtectionOverlapSummary(
            exactCanonicalOverlapCount: trackingCanonical
                .intersection(adblockCanonical)
                .count,
            domainResourceOverlapCount: trackingDomains
                .intersection(adblockDomains)
                .count,
            exactComparisonAvailable: canonicalFailures.isEmpty,
            notes: notes
        )
    }

    private static func canonicalResult(
        for planned: ProtectionPlannedRuleDefinition
    ) -> ProtectionRuleAnalysisResult<String> {
        do {
            return ProtectionRuleAnalysisResult(
                value: try ProtectionRuleJSON.canonicalHash(
                    from: planned.definition.encodedContentRuleList
                ),
                failure: nil
            )
        } catch {
            return failedResult(
                planned,
                operation: "canonicalize",
                error: error
            )
        }
    }

    private static func urlFilterTokenResult(
        for planned: ProtectionPlannedRuleDefinition
    ) -> ProtectionRuleAnalysisResult<[String]> {
        do {
            return ProtectionRuleAnalysisResult(
                value: try ProtectionRuleJSON.urlFilterTokens(
                    from: planned.definition.encodedContentRuleList
                ),
                failure: nil
            )
        } catch {
            return failedResult(
                planned,
                operation: "extract domain tokens from",
                error: error
            )
        }
    }

    private static func failedResult<Value>(
        _ planned: ProtectionPlannedRuleDefinition,
        operation: StaticString,
        error: Error
    ) -> ProtectionRuleAnalysisResult<Value> {
        let failure = ProtectionRuleAnalysisFailure(
            identifier: planned.definition.webKitStoreIdentifier,
            reason: error.localizedDescription
        )
        log.error(
            "Protection overlap diagnostics could not \(operation, privacy: .public) rule list \(failure.identifier, privacy: .public): \(failure.reason, privacy: .public)"
        )
        return ProtectionRuleAnalysisResult(value: nil, failure: failure)
    }
}

private struct ProtectionRuleAnalysisResult<Value> {
    let value: Value?
    let failure: ProtectionRuleAnalysisFailure?
}

private extension ProtectionRuleAnalysisResult where Value: RangeReplaceableCollection {
    var values: Value { value ?? .init() }
}

private struct ProtectionRuleAnalysisFailure: Equatable {
    let identifier: String
    let reason: String

    var reportLine: String {
        "\(identifier): \(reason)"
    }
}
