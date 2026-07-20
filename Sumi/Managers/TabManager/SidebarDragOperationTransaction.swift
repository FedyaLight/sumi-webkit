import Foundation
import SumiDomain

@MainActor
final class SidebarDragOperationTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let resolution: SidebarDragPayloadResolver
    private let validation: SidebarDragContextValidationService
    private let mutation: SidebarCanonicalDragMutation

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        resolution: SidebarDragPayloadResolver,
        validation: SidebarDragContextValidationService,
        mutation: SidebarCanonicalDragMutation
    ) {
        self.structuralLookup = structuralLookup
        self.resolution = resolution
        self.validation = validation
        self.mutation = mutation
    }

    func perform(_ operation: DragOperation) -> Bool {
        structuralLookup.withTransaction {
            guard let canonicalPayload = resolution.canonicalPayload(
                for: operation.payload
            ) else {
                return false
            }
            let canonicalOperation = DragOperation(
                payload: canonicalPayload,
                scope: operation.scope,
                fromContainer: operation.fromContainer,
                toContainer: operation.toContainer,
                toIndex: operation.toIndex
            )
            guard validation.validate(canonicalOperation) else {
                return false
            }
            return mutation.perform(canonicalOperation)
        }
    }
}
