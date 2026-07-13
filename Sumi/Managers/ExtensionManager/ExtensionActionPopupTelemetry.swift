import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionActionPopupTelemetrySnapshot {
    let evidence: ExtensionActionPopupCallbackEvidence
    let manifest: [String: Any]
    let seesSourceTab: Bool
    let recordsDiagnostics: Bool
}

/// Prepares observation data while external callback authority is current,
/// then balances post-commit open/close observations by local session claim.
/// It never decides popup lifecycle behavior.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupTelemetry {
    private let manifest: @MainActor (String) -> [String: Any]
    private let existingAdapter: @MainActor (UUID) -> ExtensionTabAdapter?
    private let isPublished: @MainActor (Tab) -> Bool
    private let logSession: @MainActor (
        String,
        SafariExtensionPopupLifecyclePhase,
        WKWebView?
    ) -> Void

    init(
        manifest: @escaping @MainActor (String) -> [String: Any],
        existingAdapter: @escaping @MainActor (UUID) -> ExtensionTabAdapter?,
        isPublished: @escaping @MainActor (Tab) -> Bool,
        logSession: @escaping @MainActor (
            String,
            SafariExtensionPopupLifecyclePhase,
            WKWebView?
        ) -> Void
    ) {
        self.manifest = manifest
        self.existingAdapter = existingAdapter
        self.isPublished = isPublished
        self.logSession = logSession
    }

    func prepare(
        evidence: ExtensionActionPopupCallbackEvidence,
        source: ExtensionActionPopupSourceReceipt?
    ) -> ExtensionActionPopupTelemetrySnapshot {
        guard RuntimeDiagnostics.isVerboseEnabled else {
            return ExtensionActionPopupTelemetrySnapshot(
                evidence: evidence,
                manifest: [:],
                seesSourceTab: false,
                recordsDiagnostics: false
            )
        }
        let sourceTab = source?.resolveFocusSource()?.tab
        let seesSourceTab: Bool
        if let sourceTab {
            let adapterExists = existingAdapter(sourceTab.id)?.represents(sourceTab)
                == true
            seesSourceTab = adapterExists && isPublished(sourceTab)
        } else {
            seesSourceTab = false
        }
        return ExtensionActionPopupTelemetrySnapshot(
            evidence: evidence,
            manifest: manifest(evidence.extensionID),
            seesSourceTab: seesSourceTab,
            recordsDiagnostics: true
        )
    }

    func recordOpened(extensionID: String) {
        SumiNativeMessagingRuntimeCounters.recordPopupOpened(
            extensionId: extensionID
        )
    }

    func recordPresentedObservations(
        _ snapshot: ExtensionActionPopupTelemetrySnapshot,
        popupWebView: WKWebView?,
        phase: SafariExtensionPopupLifecyclePhase,
        resolution: ExtensionActionPopupAnchorResolution,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard snapshot.recordsDiagnostics else { return }
        let evidence = snapshot.evidence
        let extensionID = evidence.extensionID
        guard isCurrent() else { return }
        SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
            seesCurrentTab: snapshot.seesSourceTab,
            extensionId: extensionID,
            reason: "presentActionPopupExactSource"
        )
        guard isCurrent() else { return }
        SafariExtensionAutofillFillDiagnostics.recordInlinePopupFocusSteal(
            extensionId: extensionID,
            reason: "presentActionPopup"
        )
        guard isCurrent() else { return }
        SafariExtensionAutofillFillDiagnostics.recordScriptingAvailability(
            extensionContext: evidence.context,
            manifest: snapshot.manifest
        )
        guard isCurrent() else { return }
        SafariExtensionAutofillFillDiagnostics.recordPopoverPresentation(
            anchorResolved: resolution.anchorResolved,
            extensionId: extensionID
        )
        guard isCurrent() else { return }
        SafariExtensionAutofillFillDiagnostics.setPopupActive(
            true,
            extensionId: extensionID
        )
    }

    func logPresented(
        extensionID: String,
        popupWebView: WKWebView?,
        phase: SafariExtensionPopupLifecyclePhase
    ) {
        logSession(extensionID, phase, popupWebView)
    }

    func recordClosed(
        extensionID: String,
        replacementVisible: Bool
    ) {
        SumiNativeMessagingRuntimeCounters.recordPopupClosed(
            extensionId: extensionID
        )
        if replacementVisible == false {
            SafariExtensionAutofillFillDiagnostics.setPopupActive(
                false,
                extensionId: extensionID
            )
        }
        SafariExtensionAutofillFillDiagnostics.logSnapshotIfEnabled(
            context: "extensionActionPopupDidClose"
        )
    }

    func logClosed(extensionID: String) {
        logSession(extensionID, .closed, nil)
    }
}
