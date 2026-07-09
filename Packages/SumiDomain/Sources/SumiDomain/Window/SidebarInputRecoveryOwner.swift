import Foundation
import Observation
import OSLog

/// Owns the fallback-only generation bump used to recover an unresolved
/// sidebar AppKit owner/input graph, coalescing repeated requests per turn.
@MainActor
@Observable
public final class SidebarInputRecoveryOwner {
    /// Fallback-only generation bump for unresolved sidebar AppKit owner/input graph recovery.
    public private(set) var generation: UInt64 = 0

    @ObservationIgnored private let windowID: UUID
    @ObservationIgnored private var isScheduled: Bool = false
    @ObservationIgnored private var pendingReasons: [SidebarInputRecoveryReason] = []

    public init(windowID: UUID) {
        self.windowID = windowID
    }

    public func scheduleRehydrate(reason: SidebarInputRecoveryReason) {
        pendingReasons.append(reason)
        guard !isScheduled else { return }

        isScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isScheduled = false

            let reasons = self.pendingReasons
            self.pendingReasons.removeAll()
            self.generation &+= 1
            let reasonDescriptions = reasons.map(\.description)

            Logger(subsystem: "com.sumi.browser", category: "SidebarInputRecovery").notice(
                "Sidebar input recovery generation=\(self.generation, privacy: .public) window=\(self.windowID.uuidString, privacy: .public) reason=\(reasonDescriptions.joined(separator: ","), privacy: .public)"
            )
        }
    }
}
