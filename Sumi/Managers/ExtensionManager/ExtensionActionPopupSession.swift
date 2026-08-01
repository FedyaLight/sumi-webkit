import AppKit
import WebKit

@available(macOS 15.5, *)
struct ExtensionActionPopupSessionClaim: Hashable {
    let revision: UInt64
    let extensionID: String
    let profileID: UUID
    let actionID: ObjectIdentifier
    let popoverID: ObjectIdentifier
    let popupWebViewID: ObjectIdentifier
}

/// Observes only the exact action popover while its session is staged or
/// visible. It leaves WebKit's private NSPopoverDelegate fully intact.
@available(macOS 15.5, *)
@MainActor
private final class ExtensionActionPopupCloseObservation: NSObject {
    private let claim: ExtensionActionPopupSessionClaim
    private let popover: NSPopover
    private let willClose: @MainActor (
        ExtensionActionPopupSessionClaim,
        NSPopover
    ) -> Void
    private let didClose: @MainActor (
        ExtensionActionPopupSessionClaim,
        NSPopover
    ) -> Void
    private var isObserving = false

    init(
        claim: ExtensionActionPopupSessionClaim,
        popover: NSPopover,
        willClose: @escaping @MainActor (
            ExtensionActionPopupSessionClaim,
            NSPopover
        ) -> Void,
        didClose: @escaping @MainActor (
            ExtensionActionPopupSessionClaim,
            NSPopover
        ) -> Void
    ) {
        self.claim = claim
        self.popover = popover
        self.willClose = willClose
        self.didClose = didClose
    }

    func start() {
        guard isObserving == false else { return }
        isObserving = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverWillClose(_:)),
            name: NSPopover.willCloseNotification,
            object: popover
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverDidClose(_:)),
            name: NSPopover.didCloseNotification,
            object: popover
        )
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func popoverWillClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        willClose(claim, popover)
    }

    @objc private func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === popover else { return }
        didClose(claim, popover)
    }

    isolated deinit {
        stop()
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSession {
    let claim: ExtensionActionPopupSessionClaim
    let evidence: ExtensionActionPopupCallbackEvidence
    let action: WKWebExtension.Action
    let popover: NSPopover
    let popupWebView: WKWebView
    let sourceReceipt: ExtensionActionPopupSourceReceipt?
    let focusReceipt: ExtensionActionPopupFocusReceipt?
    let telemetrySnapshot: ExtensionActionPopupTelemetrySnapshot
    let completion: ExtensionActionPopupCompletion

    private let closeObservation: ExtensionActionPopupCloseObservation
    private weak var sidebarTransientSessionCoordinator:
        SidebarTransientSessionCoordinator?
    private let sidebarTransientSessionToken: SidebarTransientSessionToken?
    private var hasEndedSidebarTransientSession = false
    private(set) var telemetryCommitted = false
    private(set) var presentationRetired = false
    private(set) var focusRevision: UInt64 = 0

    init(
        claim: ExtensionActionPopupSessionClaim,
        evidence: ExtensionActionPopupCallbackEvidence,
        action: WKWebExtension.Action,
        popover: NSPopover,
        popupWebView: WKWebView,
        sourceReceipt: ExtensionActionPopupSourceReceipt?,
        focusReceipt: ExtensionActionPopupFocusReceipt?,
        telemetrySnapshot: ExtensionActionPopupTelemetrySnapshot,
        completion: ExtensionActionPopupCompletion,
        sidebarTransientSessionCoordinator: SidebarTransientSessionCoordinator? = nil,
        sidebarTransientSessionToken: SidebarTransientSessionToken? = nil,
        popoverDidClose: @escaping @MainActor (
            ExtensionActionPopupSessionClaim,
            NSPopover
        ) -> Void,
        popoverWillClose: @escaping @MainActor (
            ExtensionActionPopupSessionClaim,
            NSPopover
        ) -> Void,
    ) {
        precondition(claim.actionID == ObjectIdentifier(action))
        self.claim = claim
        self.evidence = evidence
        self.action = action
        self.popover = popover
        self.popupWebView = popupWebView
        self.sourceReceipt = sourceReceipt
        self.focusReceipt = focusReceipt
        self.telemetrySnapshot = telemetrySnapshot
        self.completion = completion
        self.sidebarTransientSessionCoordinator = sidebarTransientSessionCoordinator
        self.sidebarTransientSessionToken = sidebarTransientSessionToken
        self.closeObservation = ExtensionActionPopupCloseObservation(
            claim: claim,
            popover: popover,
            willClose: popoverWillClose,
            didClose: popoverDidClose
        )
    }

    func observePopoverClosing() {
        closeObservation.start()
    }

    func markTelemetryCommitted() {
        telemetryCommitted = true
    }

    func bindFocusRevision(_ revision: UInt64) {
        precondition(focusRevision == 0)
        focusRevision = revision
    }

    func retirePresentation(
        closePhysicalPopup: Bool,
        awaitPopoverDidClose: Bool = false
    ) {
        endSidebarTransientSession()
        if presentationRetired == false {
            presentationRetired = true
            sourceReceipt?.invalidate()
        }
        if awaitPopoverDidClose == false {
            finishPopoverClosing()
        }
        if closePhysicalPopup, popover.isShown {
            popover.close()
        }
    }

    func finishPopoverClosing() {
        closeObservation.stop()
    }

    private func endSidebarTransientSession() {
        guard hasEndedSidebarTransientSession == false else { return }
        hasEndedSidebarTransientSession = true
        sidebarTransientSessionCoordinator?.endSession(
            sidebarTransientSessionToken
        )
    }
}
