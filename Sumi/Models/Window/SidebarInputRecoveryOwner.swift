import Foundation

/// Owns the fallback-only generation bump used to recover an unresolved
/// sidebar AppKit owner/input graph, coalescing repeated requests per turn.
@MainActor
@Observable
final class SidebarInputRecoveryOwner {
    /// Fallback-only generation bump for unresolved sidebar AppKit owner/input graph recovery.
    private(set) var generation: UInt64 = 0

    @ObservationIgnored private let windowID: UUID
    @ObservationIgnored private var isScheduled: Bool = false
    @ObservationIgnored private var pendingReasons: [SidebarInputRecoveryReason] = []

    init(windowID: UUID) {
        self.windowID = windowID
    }

    func scheduleRehydrate(reason: SidebarInputRecoveryReason) {
        pendingReasons.append(reason)
        guard !isScheduled else { return }

        isScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isScheduled = false

            let reasons = self.pendingReasons
            self.pendingReasons.removeAll()
            self.generation &+= 1
            let reasonDescriptions = reasons.map(\.description)

            RuntimeDiagnostics.emit(
                "🧭 Sidebar input recovery generation=\(self.generation) window=\(self.windowID.uuidString) reason=\(reasonDescriptions.joined(separator: ","))"
            )
        }
    }
}
