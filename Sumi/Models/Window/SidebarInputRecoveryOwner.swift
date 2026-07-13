import Foundation
import Observation
import OSLog
import SumiDomain

/// Owns the fallback-only generation bump used to recover an unresolved
/// sidebar AppKit owner/input graph, coalescing repeated requests per turn.
@MainActor
@Observable
final class SidebarInputRecoveryOwner {
    struct Diagnostic: Equatable {
        let generation: UInt64
        let windowID: UUID
        let reasons: [SidebarInputRecoveryReason]

        var message: String {
            let reasonDescriptions = reasons.map(\.description).joined(separator: ",")
            return "Sidebar input recovery generation=\(generation) window=\(windowID.uuidString) reason=\(reasonDescriptions)"
        }
    }

    typealias DiagnosticHandler = @MainActor (Diagnostic) -> Void

    private static let logger = RuntimeDiagnostics.logger(category: "SidebarInputRecovery")

    private(set) var generation: UInt64 = 0

    @ObservationIgnored private let windowID: UUID
    @ObservationIgnored private let handleDiagnostic: DiagnosticHandler
    @ObservationIgnored private var isScheduled = false
    @ObservationIgnored private var pendingReasons: [SidebarInputRecoveryReason] = []

    init(
        windowID: UUID,
        handleDiagnostic: DiagnosticHandler? = nil
    ) {
        self.windowID = windowID
        self.handleDiagnostic = handleDiagnostic ?? Self.log
    }

    func scheduleRehydrate(reason: SidebarInputRecoveryReason) {
        pendingReasons.append(reason)
        guard !isScheduled else { return }

        isScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isScheduled = false

            let reasons = pendingReasons
            pendingReasons.removeAll()
            generation &+= 1
            handleDiagnostic(Diagnostic(
                generation: generation,
                windowID: windowID,
                reasons: reasons
            ))
        }
    }

    private static func log(_ diagnostic: Diagnostic) {
        logger.notice("\(diagnostic.message, privacy: .public)")
    }
}
