import Foundation

@MainActor
final class SidebarDragGeometryMainRunLoopOwner {
    private var scheduledDrainToken = 0
    private var isDrainScheduled = false

    func scheduleDrain(_ drain: @escaping @MainActor () -> Void) {
        guard !isDrainScheduled else { return }
        isDrainScheduled = true
        let token = scheduledDrainToken

        DispatchQueue.main.async { [weak self] in
            guard let self,
                  isDrainScheduled,
                  scheduledDrainToken == token else {
                return
            }
            isDrainScheduled = false
            drain()
        }
    }

    func drainSynchronously(_ drain: @MainActor () -> Void) {
        if isDrainScheduled {
            scheduledDrainToken &+= 1
            isDrainScheduled = false
        }
        drain()
    }
}
