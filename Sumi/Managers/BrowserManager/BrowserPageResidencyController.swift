import Foundation

@MainActor
final class BrowserPageResidencyController {
    private let tabSuspension: TabSuspensionController
    private var pendingReasons: [String] = []
    private var scheduledReconcile: Task<Void, Never>?

    init(tabSuspension: TabSuspensionController) {
        self.tabSuspension = tabSuspension
    }

    func schedule(reason: String) {
        if pendingReasons.count < 6 {
            pendingReasons.append(reason)
        }
        guard scheduledReconcile == nil else { return }

        scheduledReconcile = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false else { return }
            let reason = pendingReasons.joined(separator: ",")
            pendingReasons.removeAll(keepingCapacity: true)
            scheduledReconcile = nil
            tabSuspension.reconcileNow(reason: reason)
        }
    }
}
