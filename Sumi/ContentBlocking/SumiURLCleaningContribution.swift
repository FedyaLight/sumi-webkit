import Foundation

struct SumiURLCleaningContribution: Equatable, Sendable {
    let generationID: String
    let rulesURL: URL
    let disabledDomains: [String]
}

@MainActor
protocol SumiURLCleaningContributionHosting: AnyObject {
    func reconcileInternalURLCleaning(
        _ contribution: SumiURLCleaningContribution?,
        profileID: UUID
    )
}
