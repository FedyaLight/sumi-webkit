import Foundation
import SumiDomain

@MainActor
final class SidebarDragOperationTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let resolution: SidebarDragPayloadResolver
    private let validation: SidebarDragContextValidationService
    private let orderProjection: any SidebarDropOrderProjecting
    private let mutation: SidebarCanonicalDragMutation

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        resolution: SidebarDragPayloadResolver,
        validation: SidebarDragContextValidationService,
        orderProjection: any SidebarDropOrderProjecting,
        mutation: SidebarCanonicalDragMutation
    ) {
        self.structuralLookup = structuralLookup
        self.resolution = resolution
        self.validation = validation
        self.orderProjection = orderProjection
        self.mutation = mutation
    }

    func perform(_ intent: SidebarDragCommitIntent) -> Bool {
        structuralLookup.withTransaction {
            guard let canonicalPayload = resolution.canonicalPayload(
                for: intent.payload
            ) else {
                return false
            }
            let canonicalIntent = SidebarDragCommitIntent(
                payload: canonicalPayload,
                scope: intent.scope,
                fromContainer: intent.fromContainer,
                toContainer: intent.toContainer,
                presentedVisualIndex: intent.presentedVisualIndex,
                presentedRegularBoundary: intent.presentedRegularBoundary
            )
            guard let mutationIndex = orderProjection.mutationIndex(
                for: canonicalIntent
            ) else { return false }
            let operation = DragOperation(
                payload: canonicalPayload,
                scope: intent.scope,
                fromContainer: intent.fromContainer,
                toContainer: intent.toContainer,
                toIndex: mutationIndex
            )
            guard validation.validate(operation) else {
                return false
            }
            return mutation.perform(operation)
        }
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
