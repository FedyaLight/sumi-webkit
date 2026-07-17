import Foundation
import SumiDomain

@MainActor
final class SidebarDragOperationTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let resolution: SidebarDragPayloadResolver
    private let validation: SidebarDragContextValidationService
    private let executor: SidebarDragPlanExecutor

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        resolution: SidebarDragPayloadResolver,
        validation: SidebarDragContextValidationService,
        executor: SidebarDragPlanExecutor
    ) {
        self.structuralLookup = structuralLookup
        self.resolution = resolution
        self.validation = validation
        self.executor = executor
    }

    func perform(_ operation: DragOperation) -> Bool {
        structuralLookup.withTransaction {
            guard validation.validate(operation),
                  resolution.isCanonical(operation.payload) else {
                return false
            }
            let plan = SidebarDragOperationPlanner.plan(
                operation: operation,
                shortcutPin: resolution.shortcutPin
            )
            return executor.execute(plan, operation: operation)
        }
    }
}
