import Combine
import Foundation

struct SumiContentRuleListSet: Equatable, Sendable {
    let definitions: [SumiContentRuleListDefinition]

    init(definitions: [SumiContentRuleListDefinition] = []) {
        self.definitions = definitions
    }

    var allDefinitions: [SumiContentRuleListDefinition] {
        definitions
    }
}

@MainActor
protocol SumiContentRuleListSetProviding: AnyObject {
    var changesPublisher: AnyPublisher<Void, Never> { get }
    var hasProfileSpecificRuleLists: Bool { get }

    func ruleListSet(profileId: UUID?) throws -> SumiContentRuleListSet
}
