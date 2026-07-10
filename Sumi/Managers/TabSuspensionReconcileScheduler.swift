import Foundation

@MainActor
final class TabSuspensionReconcileScheduler {
    private static let maximumPendingReasons = 8

    private let reconcile: @MainActor (String) -> Void
    private var task: Task<Void, Never>?
    private var pendingReasons: Set<String> = []
    private var didTruncateReasons = false

    init(reconcile: @escaping @MainActor (String) -> Void) {
        self.reconcile = reconcile
    }

    deinit {
        task?.cancel()
    }

    func schedule(reason: String) {
        record(reason)
        guard task == nil else { return }

        task = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }

            let reason = Self.coalescedReason(
                reasons: self.pendingReasons,
                didTruncateReasons: self.didTruncateReasons
            )
            self.pendingReasons.removeAll()
            self.didTruncateReasons = false
            self.task = nil
            self.reconcile(reason)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        pendingReasons.removeAll()
        didTruncateReasons = false
    }

    private func record(_ reason: String) {
        guard !pendingReasons.contains(reason) else { return }
        guard pendingReasons.count < Self.maximumPendingReasons else {
            didTruncateReasons = true
            return
        }
        pendingReasons.insert(reason)
    }

    private static func coalescedReason(
        reasons: Set<String>,
        didTruncateReasons: Bool
    ) -> String {
        var components = reasons.sorted()
        if didTruncateReasons {
            components.append("more")
        }
        if components.isEmpty {
            components.append("unknown")
        }
        return "coalesced(\(components.joined(separator: ",")))"
    }
}
