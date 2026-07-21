import AppKit
import SwiftUI

@MainActor
struct SidebarFolderPreviewRequest {
    let folderID: UUID
    let folderName: String
    let candidates: [FolderSearchCandidate]
    /// Folder header frame in the window's SwiftUI-global space.
    let anchorRect: CGRect
}

@MainActor
struct SidebarFolderPreviewPresentation: Identifiable {
    let id = UUID()
    let folderID: UUID
    let folderName: String
    let candidates: [FolderSearchCandidate]
    let anchorRect: CGRect
    let sidebarPosition: SidebarPosition
    /// Whoever held the keyboard when the panel opened. The panel focuses its
    /// search field, so it hands focus back here rather than leaning on the
    /// coordinator's global repair pass, which resets every row's mouse tracking.
    let previousFirstResponder: PreviousFirstResponder
}

/// Weak box so a stale presentation cannot keep a torn-down responder alive.
@MainActor
final class PreviousFirstResponder {
    weak var responder: NSResponder?

    init(_ responder: NSResponder?) {
        self.responder = responder
    }
}

/// Window-local owner for the collapsed-folder hover preview.
///
/// Replaces the former `NSPopover` presenter: the panel is now in-window chrome
/// rendered by `SidebarFolderPreviewOverlay`, so this owner only holds the
/// presentation, the two hover flags Zen tracks (`labelContainer:hover` and
/// `popup:hover`), and the transient-session token.
@MainActor
@Observable
final class SidebarFolderPreviewSessionOwner {
    private(set) var presentation: SidebarFolderPreviewPresentation?

    @ObservationIgnored private var anchorHovered = false
    @ObservationIgnored private var panelHovered = false
    @ObservationIgnored private var closeGraceTask: Task<Void, Never>?
    @ObservationIgnored private var sessionToken: SidebarTransientSessionToken?
    @ObservationIgnored private weak var sessionCoordinator: SidebarTransientSessionCoordinator?
    @ObservationIgnored private var notificationObservers: [NSObjectProtocol] = []
    @ObservationIgnored private weak var presentationWindow: NSWindow?
    @ObservationIgnored private var panelFrame: CGRect?
    @ObservationIgnored private var pendingGestureClose: SidebarFolderPreviewPendingClose?
    @ObservationIgnored private let outsideClickMonitor = ChromeLocalEventMonitor()

    isolated deinit {
        closeGraceTask?.cancel()
        removeNotificationObservers()
        outsideClickMonitor.remove()
    }

    var openFolderID: UUID? {
        presentation?.folderID
    }

    /// The overlay owns the placement math, so it reports the resolved frame in
    /// the window's SwiftUI-global space for the outside-click hit test.
    func setPanelFrame(_ frame: CGRect) {
        panelFrame = frame
    }

    func open(
        request: SidebarFolderPreviewRequest,
        sidebarPosition: SidebarPosition,
        source: SidebarTransientPresentationSource
    ) {
        guard !request.candidates.isEmpty else { return }

        if let presentation, presentation.folderID == request.folderID {
            // Re-entering the same header only refreshes hover bookkeeping; Zen
            // likewise leaves an already-open popup alone.
            anchorHovered = true
            closeGraceTask?.cancel()
            closeGraceTask = nil
            return
        }

        close(reason: "SidebarFolderPreviewSessionOwner.replaceActive")

        anchorHovered = true
        panelHovered = false
        pendingGestureClose = nil
        panelFrame = nil
        presentationWindow = source.window
        presentation = SidebarFolderPreviewPresentation(
            folderID: request.folderID,
            folderName: request.folderName,
            candidates: request.candidates,
            anchorRect: request.anchorRect,
            sidebarPosition: sidebarPosition,
            previousFirstResponder: PreviousFirstResponder(source.previousFirstResponder)
        )

        sessionCoordinator = source.coordinator
        sessionToken = source.coordinator?.beginSession(
            kind: .folderPreview,
            source: source,
            path: "SidebarFolderPreviewSessionOwner.open",
            conflictDismiss: { [weak self] in
                self?.close(reason: "SidebarFolderPreviewSessionOwner.conflict")
            }
        )
        installNotificationObservers(window: source.window)
        installOutsideClickMonitor()
    }

    func setAnchorHovered(folderID: UUID, hovering: Bool) {
        guard presentation?.folderID == folderID else { return }
        anchorHovered = hovering
        reconcileHover()
    }

    func setPanelHovered(_ hovering: Bool) {
        guard presentation != nil else { return }
        panelHovered = hovering
        reconcileHover()
    }

    /// Zen's `movingtab` guard: a starting drag takes the panel down immediately
    /// rather than waiting out the hover grace.
    func dismissForSidebarDrag() {
        guard presentation != nil else { return }
        close(reason: "SidebarFolderPreviewSessionOwner.sidebarDrag")
    }

    func close(folderID: UUID) {
        guard presentation?.folderID == folderID else { return }
        close(reason: "SidebarFolderPreviewSessionOwner.close")
    }

    func close(reason: String) {
        closeGraceTask?.cancel()
        closeGraceTask = nil
        removeNotificationObservers()
        outsideClickMonitor.remove()

        guard presentation != nil else { return }
        presentation = nil
        anchorHovered = false
        panelHovered = false
        pendingGestureClose = nil
        panelFrame = nil
        presentationWindow = nil

        let token = sessionToken
        let coordinator = sessionCoordinator
        sessionToken = nil
        sessionCoordinator = nil
        coordinator?.finishSession(token, reason: reason)
    }

    private func reconcileHover() {
        closeGraceTask?.cancel()
        closeGraceTask = nil

        guard !SidebarFolderPreviewHoverPolicy.shouldStayOpen(
            anchorHovered: anchorHovered,
            panelHovered: panelHovered
        ) else {
            // Only the grace's own pending close is negotiable here; a click has
            // already committed to taking the panel down.
            if pendingGestureClose == .hoverGrace {
                pendingGestureClose = nil
            }
            return
        }

        closeGraceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: SidebarFolderPreviewHoverPolicy.closeGraceNanoseconds
            )
            guard let self, !Task.isCancelled else { return }
            guard !SidebarFolderPreviewHoverPolicy.shouldStayOpen(
                anchorHovered: self.anchorHovered,
                panelHovered: self.panelHovered
            ) else { return }

            switch SidebarFolderPreviewOutsideClickRouting.graceDecision(
                isMouseButtonHeld: NSEvent.pressedMouseButtons != 0
            ) {
            case .closeAfterGesture:
                self.pendingGestureClose = .hoverGrace
            case .closeNow:
                self.close(reason: SidebarFolderPreviewPendingClose.hoverGrace.reason)
            case .ignore:
                break
            }
        }
    }

    // MARK: - Outside clicks

    /// Zen's popup is a XUL panel that rolls up on any click elsewhere. The
    /// in-window equivalent has to route that itself, and — like the floating
    /// bar's monitor — it always hands the event back so the click still reaches
    /// the sidebar row underneath.
    private func installOutsideClickMonitor() {
        outsideClickMonitor.remove()
        outsideClickMonitor.install(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseUp, .rightMouseUp, .otherMouseUp,
            ]
        ) { [weak self] event in
            self?.handlePointerEvent(event)
            return event
        }
    }

    private func handlePointerEvent(_ event: NSEvent) {
        guard let phase = Self.pointerPhase(for: event.type) else { return }

        switch SidebarFolderPreviewOutsideClickRouting.decision(
            isPresented: presentation != nil,
            phase: phase,
            isInsidePanel: isEventInsidePanel(event),
            hasPendingClose: pendingGestureClose != nil
        ) {
        case .ignore:
            return
        case .closeAfterGesture:
            // Give the keyboard back before the click is dispatched, so the row
            // that is about to take first responder never does it against a
            // field editor that is still tearing down.
            relinquishKeyboardIfPanelHoldsIt()
            pendingGestureClose = .outsideClick
        case .closeNow:
            guard let pendingGestureClose, let presentationID = presentation?.id else { return }
            self.pendingGestureClose = nil
            // A local monitor sees the mouse-up before the window dispatches it.
            // Closing here would tear the panel down while the row's `mouseUp`
            // is still on its way, so the teardown waits one turn — the same
            // "defer the mutation, hand the event back" shape the floating bar
            // uses for its outside clicks.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.presentation?.id == presentationID else { return }
                self.close(reason: pendingGestureClose.reason)
            }
        }
    }

    private static func pointerPhase(
        for eventType: NSEvent.EventType
    ) -> SidebarFolderPreviewPointerPhase? {
        switch eventType {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return .down
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return .up
        default:
            return nil
        }
    }

    private func isEventInsidePanel(_ event: NSEvent) -> Bool {
        guard let window = presentationWindow,
              event.window === window
        else { return false }

        return SidebarFolderPreviewOutsideClickRouting.isInsidePanel(
            swiftUIGlobalPoint: SidebarDragLocationMapper.swiftUIGlobalPoint(
                fromWindowPoint: event.locationInWindow,
                in: window
            ),
            panelFrame: panelFrame
        )
    }

    /// The panel's search field is the only field editor that can be up while
    /// the preview is presented — opening bails out when a text editor already
    /// owns the keyboard — but the geometry check keeps that an assertion rather
    /// than an assumption.
    private func relinquishKeyboardIfPanelHoldsIt() {
        guard let window = presentationWindow,
              let fieldEditor = window.firstResponder as? NSTextView,
              fieldEditor.isFieldEditor,
              isViewInsidePanel(fieldEditor, in: window)
        else { return }

        if let previousFirstResponder = presentation?.previousFirstResponder.responder,
           ((previousFirstResponder as? NSView)?.window ?? window) === window,
           window.makeFirstResponder(previousFirstResponder) {
            return
        }
        _ = window.makeFirstResponder(nil)
    }

    private func isViewInsidePanel(_ view: NSView, in window: NSWindow) -> Bool {
        guard let panelFrame else { return false }

        let windowRect = view.convert(view.bounds, to: nil)
        let topLeading = SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromWindowPoint: CGPoint(x: windowRect.minX, y: windowRect.maxY),
            in: window
        )
        return panelFrame.intersects(CGRect(origin: topLeading, size: windowRect.size))
    }

    private func installNotificationObservers(window: NSWindow?) {
        removeNotificationObservers()
        let center = NotificationCenter.default

        var observers: [NSObjectProtocol] = [
            center.addObserver(
                forName: .sumiShouldHideCollapsedSidebarOverlay,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.close(reason: "SidebarFolderPreviewSessionOwner.collapsedSidebarOverlayHidden")
                }
            },
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.close(reason: "SidebarFolderPreviewSessionOwner.applicationResignedActive")
                }
            },
        ]

        if let window {
            observers.append(
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: nil
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.close(reason: "SidebarFolderPreviewSessionOwner.windowWillClose")
                    }
                }
            )
        }

        notificationObservers = observers
    }

    private func removeNotificationObservers() {
        let observers = notificationObservers
        notificationObservers = []
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
