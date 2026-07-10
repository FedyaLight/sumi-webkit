import Foundation
import WebKit

enum SumiProfileWebsiteDataMutationOutcome: Equatable {
    case rejected
    case completed
    case restoreFailedAfterMutation

    var didMutate: Bool {
        self != .rejected
    }
}

@MainActor
protocol SumiProfileWebsiteDataMutating: AnyObject {
    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    )

    func deleteExactHostData(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        profile: Profile
    ) async -> SumiProfileWebsiteDataMutationOutcome
}

/// High-level destructive mutation port for profile website data. This is the
/// only UI-facing path that may bridge from a user action to the low-level
/// cleanup service, and it fails closed until a live-document preparer exists.
@MainActor
final class SumiProfileWebsiteDataMutationService: SumiProfileWebsiteDataMutating {
    private let cleanupService: any SumiWebsiteDataCleanupServicing
    private var destructiveCleanupPreparer:
        (any SumiDestructiveBrowsingDataCleanupPreparing)?

    init(cleanupService: any SumiWebsiteDataCleanupServicing) {
        self.cleanupService = cleanupService
    }

    func replacingCleanupService(
        _ cleanupService: any SumiWebsiteDataCleanupServicing
    ) -> SumiProfileWebsiteDataMutationService {
        let replacement = SumiProfileWebsiteDataMutationService(
            cleanupService: cleanupService
        )
        replacement.destructiveCleanupPreparer = destructiveCleanupPreparer
        return replacement
    }

    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) {
        destructiveCleanupPreparer = preparer
    }

    func deleteExactHostData(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        profile: Profile
    ) async -> SumiProfileWebsiteDataMutationOutcome {
        let normalizedHost = host.normalizedWebsiteDataDomain
        guard normalizedHost.isEmpty == false,
              dataTypes.isEmpty == false || includingCookies,
              let destructiveCleanupPreparer else {
            return .rejected
        }

        var didMutate = false
        let didComplete = await destructiveCleanupPreparer
            .performDestructiveDataCleanup(profileIDs: [profile.id]) {
                didMutate = true
                await self.cleanupService.removeWebsiteDataForExactHost(
                    normalizedHost,
                    ofTypes: dataTypes,
                    includingCookies: includingCookies,
                    in: profile.dataStore
                )
            }

        guard didMutate else { return .rejected }
        return didComplete ? .completed : .restoreFailedAfterMutation
    }
}
