import Foundation
import WebKit

struct SumiContentBlockerRules {
    let name: String
    let storeIdentifier: String
    let rulesList: WKContentRuleList
    let etag: String
    let identifier: SumiContentBlockerRulesIdentifier
}

struct SumiContentBlockerRulesUpdate: CustomDebugStringConvertible {
    typealias CompletionToken = String

    let rules: [SumiContentBlockerRules]
    let changes: [String: SumiContentBlockerRulesIdentifier.Difference]
    let completionTokens: [CompletionToken]
    let lookupSucceededIdentifiers: [String]
    let lookupFailedIdentifiers: [String]
    let ruleListLookupDuration: TimeInterval?

    init(
        rules: [SumiContentBlockerRules],
        changes: [String: SumiContentBlockerRulesIdentifier.Difference],
        completionTokens: [CompletionToken],
        lookupSucceededIdentifiers: [String] = [],
        lookupFailedIdentifiers: [String] = [],
        ruleListLookupDuration: TimeInterval? = nil
    ) {
        self.rules = rules
        self.changes = changes
        self.completionTokens = completionTokens
        self.lookupSucceededIdentifiers = lookupSucceededIdentifiers.sorted()
        self.lookupFailedIdentifiers = lookupFailedIdentifiers.sorted()
        self.ruleListLookupDuration = ruleListLookupDuration
    }

    var debugDescription: String {
        """
          rules: \(rules.map { "\($0.name):\($0.storeIdentifier):\($0.identifier) - \($0.rulesList) (\($0.etag))" }.joined(separator: ", "))
          changes: \(changes)
          completionTokens: \(completionTokens)
          lookupSucceededIdentifiers: \(lookupSucceededIdentifiers.joined(separator: ", "))
          lookupFailedIdentifiers: \(lookupFailedIdentifiers.joined(separator: ", "))
          ruleListLookupDuration: \(ruleListLookupDuration.map { "\($0)" } ?? "nil")
        """
    }
}
