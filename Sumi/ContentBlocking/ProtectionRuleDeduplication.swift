import Foundation

struct ProtectionRuleDeduplicationResult: Equatable, Sendable {
    let definitions: [ProtectionPlannedRuleDefinition]
    let summary: SumiProtectionDedupeSummary
}

enum ProtectionRuleDeduplication {
    static func deduplicate(
        _ plannedDefinitions: [ProtectionPlannedRuleDefinition]
    ) -> ProtectionRuleDeduplicationResult {
        var seenIdentifiers = Set<String>()
        var seenCanonicalHashes = Set<String>()
        var seenGroupHashes = Set<String>()
        var output = [ProtectionPlannedRuleDefinition]()
        var duplicateIdentifierCount = 0
        var duplicateCanonicalCount = 0
        var duplicateGroupHashCount = 0
        var canonicalUnavailableCount = 0
        var removedIdentifiers = [String]()

        for planned in plannedDefinitions {
            let identifier = planned.definition.webKitStoreIdentifier
            guard seenIdentifiers.insert(identifier).inserted else {
                duplicateIdentifierCount += 1
                removedIdentifiers.append(identifier)
                continue
            }

            let groupHashKey = "\(planned.group.rawValue):\(planned.definition.contentHash)"
            guard seenGroupHashes.insert(groupHashKey).inserted else {
                duplicateGroupHashCount += 1
                removedIdentifiers.append(identifier)
                continue
            }

            do {
                let canonicalHash = try ProtectionRuleJSON.canonicalHash(
                    from: planned.definition.encodedContentRuleList
                )
                guard seenCanonicalHashes.insert(canonicalHash).inserted else {
                    duplicateCanonicalCount += 1
                    removedIdentifiers.append(identifier)
                    continue
                }
            } catch {
                canonicalUnavailableCount += 1
            }

            output.append(planned)
        }

        return ProtectionRuleDeduplicationResult(
            definitions: output,
            summary: SumiProtectionDedupeSummary(
                inputRuleListCount: plannedDefinitions.count,
                finalRuleListCount: output.count,
                duplicateIdentifierCountRemoved: duplicateIdentifierCount,
                duplicateCanonicalJSONCountRemoved: duplicateCanonicalCount,
                duplicateGroupContentHashCountRemoved: duplicateGroupHashCount,
                canonicalJSONUnavailableCount: canonicalUnavailableCount,
                removedIdentifiers: removedIdentifiers.sorted()
            )
        )
    }
}
