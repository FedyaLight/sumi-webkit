import Foundation
import SumiDomain

/// Creates stable conversion values and reauthorizes both durable and runtime
/// snapshots. It performs no mutation.
@MainActor
final class RegularTabShortcutCandidatePreparer {
    private let planner: RegularTabShortcutConversionPlanner
    private let authorizer: TabShortcutConversionAuthorizer
    private let pinFactory: ShortcutPinRuntimeResolutionOwner

    init(
        planner: RegularTabShortcutConversionPlanner,
        authorizer: TabShortcutConversionAuthorizer,
        pinFactory: ShortcutPinRuntimeResolutionOwner
    ) {
        self.planner = planner
        self.authorizer = authorizer
        self.pinFactory = pinFactory
    }

    func prepare(
        _ tab: Tab,
        preferredWindowID: UUID?
    ) -> TabShortcutConversionPreparation {
        planner.prepareConversion(tab, preferredWindowId: preferredWindowID)
    }

    func candidate(
        for tab: Tab,
        preparation: TabShortcutConversionPreparation,
        destination: TabShortcutPinDestination
    ) -> PreparedRegularTabShortcutConversion? {
        guard let structure = preparation.structurePlan else { return nil }
        let pin = pinFactory.makeShortcutPin(
            from: tab,
            role: destination.role,
            profileId: destination.profileId,
            spaceId: destination.spaceId,
            folderId: destination.folderId,
            index: destination.index
        )
        let candidate = PreparedRegularTabShortcutConversion(
            sourceTab: tab,
            preparation: preparation,
            structure: structure,
            candidatePin: pin,
            destination: destination
        )
        return authorization(for: candidate) == nil ? nil : candidate
    }

    func authorization(
        for candidate: PreparedRegularTabShortcutConversion
    ) -> AuthorizedTabShortcutConversion? {
        guard planner.isStructureCurrent(
            candidate.preparation,
            for: candidate.sourceTab
        ) else { return nil }
        return authorizer.authorize(
            candidate.preparation,
            for: candidate.sourceTab
        )
    }
}
