import Foundation
import SumiWebRuntime

@MainActor
final class WindowWebContentSplitRepairScheduler {
    private let browserContext: any WindowWebContentBrowserContext
    private let mutationGate: WindowWebContentCompositorMutationGate
    private var pendingGroupID: UUID?

    init(
        browserContext: any WindowWebContentBrowserContext,
        mutationGate: WindowWebContentCompositorMutationGate
    ) {
        self.browserContext = browserContext
        self.mutationGate = mutationGate
    }

    func schedule(
        groupID: UUID,
        containerRegistration: WebViewCompositorContainerRegistration
    ) {
        guard mutationGate.owns(containerRegistration) else { return }
        guard pendingGroupID != groupID else { return }
        pendingGroupID = groupID

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer {
                if self.pendingGroupID == groupID {
                    self.pendingGroupID = nil
                }
            }
            guard self.mutationGate.owns(containerRegistration) else { return }
            self.browserContext.removeSplitGroup(id: groupID)
        }
    }

    func cancel() {
        pendingGroupID = nil
    }
}
