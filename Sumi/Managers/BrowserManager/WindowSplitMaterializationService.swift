import Foundation
import SumiDomain

/// Resolves one durable group into a complete window-local presentation after
/// every shortcut member has crossed exact window/Space admission.
@MainActor
final class WindowSplitMaterializationService {
    private let query: WindowSplitMaterializationQuery
    private let activation: ShortcutPresentationActivationService
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        query: WindowSplitMaterializationQuery,
        activation: ShortcutPresentationActivationService,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.query = query
        self.activation = activation
        self.structuralLookup = structuralLookup
    }

    func withMaterialization(
        _ group: SumiDomain.SplitGroup,
        selection: WindowSplitSelection,
        in windowState: BrowserWindowState,
        finalizing: (MaterializedWindowSplit) -> Void
    ) -> Bool {
        guard query.containsExact(group) else { return false }
        let shortcutRequests = group.memberIDs.compactMap {
            memberID -> ShortcutPresentationActivationService.Request? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return .init(
                pinID: pinID,
                windowID: windowState.id,
                presentationSpaceID: group.container.spaceId
                    ?? windowState.currentSpaceId
            )
        }
        return structuralLookup.withTransaction {
            var result: MaterializedWindowSplit?
            guard activation.withActivation(shortcutRequests, applying: { _ in
                guard query.containsExact(group),
                      case .ready(let presentation) = query.projection().resolve(
                          selection: selection,
                          in: windowState.id
                      ),
                      let activeTab = query.activeTab(
                          for: presentation.activeMemberID,
                          in: windowState.id
                      ) else { return false }
                result = MaterializedWindowSplit(
                    presentation: presentation,
                    activeTab: activeTab
                )
                return true
            }), let result else { return false }
            finalizing(result)
            return true
        }
    }
}
