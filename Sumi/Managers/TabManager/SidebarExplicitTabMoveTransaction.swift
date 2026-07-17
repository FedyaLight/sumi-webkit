import Foundation
import SumiDomain

@MainActor
final class SidebarExplicitTabMoveTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let resolution: SidebarDragPayloadResolver
    private let regularTabs: SidebarRegularTabPlacementTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        resolution: SidebarDragPayloadResolver,
        regularTabs: SidebarRegularTabPlacementTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.resolution = resolution
        self.regularTabs = regularTabs
    }

    func move(_ tabID: UUID, to targetSpaceID: UUID) -> Bool {
        structuralLookup.withTransaction {
            guard let tab = resolution.tab(for: tabID),
                  let currentSpaceID = tab.spaceId,
                  currentSpaceID != targetSpaceID else {
                return false
            }
            return regularTabs.place(
                tab,
                in: targetSpaceID,
                at: regularTabs.tabs(in: targetSpaceID).count
            )
        }
    }
}
