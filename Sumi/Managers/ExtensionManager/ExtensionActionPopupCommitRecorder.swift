import Foundation

/// Records observability only after the exact popup session is committed.
/// Reentrant telemetry cannot make a stale session appear successful.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupCommitRecorder {
    private let sessions: ExtensionActionPopupSessionLedger
    private let telemetry: ExtensionActionPopupTelemetry

    init(
        sessions: ExtensionActionPopupSessionLedger,
        telemetry: ExtensionActionPopupTelemetry
    ) {
        self.sessions = sessions
        self.telemetry = telemetry
    }

    func record(
        _ session: ExtensionActionPopupSession,
        resolution: ExtensionActionPopupAnchorResolution,
        phase: SafariExtensionPopupLifecyclePhase
    ) -> Bool {
        guard sessions.isActive(session) else { return false }
        session.markTelemetryCommitted()
        telemetry.recordOpened(extensionID: session.claim.extensionID)
        telemetry.recordPresentedObservations(
            session.telemetrySnapshot,
            popupWebView: session.popupWebView,
            phase: phase,
            resolution: resolution,
            isCurrent: { [weak sessions, weak session] in
                guard let sessions, let session else { return false }
                return sessions.isActive(session)
            }
        )
        guard sessions.isActive(session) else { return false }
        telemetry.logPresented(
            extensionID: session.claim.extensionID,
            popupWebView: session.popupWebView,
            phase: phase
        )
        return sessions.isActive(session)
    }
}
