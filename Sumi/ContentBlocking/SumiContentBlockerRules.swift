import Foundation
import WebKit

struct SumiContentBlockerRules {
    let name: String
    let rulesList: WKContentRuleList
    let etag: String
    let identifier: SumiContentBlockerRulesIdentifier
}

struct SumiContentBlockerRulesUpdate: CustomDebugStringConvertible {
    typealias CompletionToken = String

    let rules: [SumiContentBlockerRules]
    let changes: [String: SumiContentBlockerRulesIdentifier.Difference]
    let completionTokens: [CompletionToken]

    var debugDescription: String {
        """
          rules: \(rules.map { "\($0.name):\($0.identifier) - \($0.rulesList) (\($0.etag))" }.joined(separator: ", "))
          changes: \(changes)
          completionTokens: \(completionTokens)
        """
    }
}
