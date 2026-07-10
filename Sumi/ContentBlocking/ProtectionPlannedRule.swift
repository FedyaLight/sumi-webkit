import Foundation
import SumiDomain

enum ProtectionRuleSource: Sendable {
    case tracking
    case adblock
}

struct ProtectionPlannedRuleDefinition: Equatable, Sendable {
    let group: SumiProtectionGroupKind
    let source: ProtectionRuleSource
    let definition: SumiContentRuleListDefinition
}
