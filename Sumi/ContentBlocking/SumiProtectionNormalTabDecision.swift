import SumiDomain

struct SumiProtectionNormalTabDecision: Equatable, Sendable {
    let plan: SumiProtectionRulePlan
    let contentBlockingService: SumiContentBlockingService?

    var attachmentState: SumiProtectionAttachmentState {
        plan.attachmentState
    }

    static func == (lhs: SumiProtectionNormalTabDecision, rhs: SumiProtectionNormalTabDecision) -> Bool {
        lhs.plan == rhs.plan
            && (lhs.contentBlockingService == nil) == (rhs.contentBlockingService == nil)
    }
}
