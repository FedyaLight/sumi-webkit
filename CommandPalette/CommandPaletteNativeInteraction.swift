import AppKit

/// Owns native interaction lifetime for one window-bound Command Palette
/// Session. Focus, deferred input, outside-click routing, and terminal commits
/// share one generation so stale work cannot survive dismissal or replacement.
@MainActor
final class CommandPaletteNativeInteraction {
    typealias DeferredScheduler =
        @MainActor (_ operation: @escaping @MainActor () -> Void) -> Void

    private struct Session: Equatable {
        let windowID: UUID
        let generation: UInt64
    }

    private struct PendingTextChange: Equatable {
        let session: Session
        let generation: UInt64
    }

    private weak var cardView: NSView?
    private var session: Session?
    private var pendingMutationSession: Session?
    private var pendingTextChange: PendingTextChange?
    private var focusTask: Task<Void, Never>?
    private var nextSessionGeneration: UInt64 = 0
    private var nextTextGeneration: UInt64 = 0
    private let eventMonitor = ChromeLocalEventMonitor()

    deinit {
        focusTask?.cancel()
    }

    func beginSession(windowID: UUID) {
        nextSessionGeneration &+= 1
        session = Session(
            windowID: windowID,
            generation: nextSessionGeneration
        )
        pendingMutationSession = nil
        pendingTextChange = nil
        focusTask?.cancel()
        focusTask = nil
    }

    func endSession() {
        nextSessionGeneration &+= 1
        session = nil
        pendingMutationSession = nil
        pendingTextChange = nil
        focusTask?.cancel()
        focusTask = nil
        cardView = nil
        eventMonitor.remove()
    }

    func updateCardView(_ view: NSView) {
        cardView = view
    }

    func installEventMonitorIfNeeded(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> NSEvent?
    ) {
        guard !eventMonitor.isInstalled else { return }
        eventMonitor.install(matching: mask, handler: handler)
    }

    func routeMouseEvent(
        _ event: NSEvent,
        isCommandPaletteVisible: Bool,
        onOutsideClick: () -> Void
    ) -> NSEvent? {
        guard isCommandPaletteVisible,
              !isEventInsideCard(event) else {
            return event
        }
        onOutsideClick()
        return event
    }

    func scheduleFocus(
        windowID: UUID,
        operation: @escaping @MainActor () -> Void
    ) {
        guard let session,
              session.windowID == windowID else {
            return
        }

        focusTask?.cancel()
        focusTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  self.session == session else {
                return
            }
            self.focusTask = nil
            operation()
        }
    }

    @discardableResult
    func scheduleTextChange(
        in windowState: BrowserWindowState,
        text: String,
        scheduler: DeferredScheduler =
            CommandPaletteNativeInteraction.scheduleOnNextMainTurn,
        apply: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard windowState.presentationState.isCommandPaletteVisible,
              let session,
              session.windowID == windowState.id else {
            return false
        }

        nextTextGeneration &+= 1
        let pending = PendingTextChange(
            session: session,
            generation: nextTextGeneration
        )
        pendingTextChange = pending
        scheduler { [weak self, weak windowState] in
            guard let self,
                  let windowState,
                  windowState.presentationState.isCommandPaletteVisible,
                  self.session == session,
                  self.pendingTextChange == pending else {
                return
            }
            self.pendingTextChange = nil
            apply(text)
        }
        return true
    }

    @discardableResult
    func requestCommit(
        in windowState: BrowserWindowState,
        scheduler: DeferredScheduler =
            CommandPaletteNativeInteraction.scheduleOnNextMainTurn,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        requestDeferredMutation(
            in: windowState,
            scheduler: scheduler,
            perform: perform
        )
    }

    @discardableResult
    func requestDismiss(
        in windowState: BrowserWindowState,
        scheduler: DeferredScheduler =
            CommandPaletteNativeInteraction.scheduleOnNextMainTurn,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        requestDeferredMutation(
            in: windowState,
            scheduler: scheduler,
            perform: perform
        )
    }

    @discardableResult
    func requestBrowserAction(
        in windowState: BrowserWindowState,
        canPerform: @escaping @MainActor () -> Bool,
        perform: @escaping @MainActor ()
            -> CommandPaletteShortcutExecutionOutcome?,
        dismiss: @escaping @MainActor () -> Void,
        onPerformed: @escaping @MainActor () -> Void,
        onRejected: @escaping @MainActor () -> Void,
        scheduler: DeferredScheduler =
            CommandPaletteNativeInteraction.scheduleOnNextMainTurn
    ) -> Bool {
        guard canPerform() else {
            onRejected()
            return false
        }
        return requestCommit(
            in: windowState,
            scheduler: scheduler
        ) { [weak self, weak windowState] in
            guard let self, let windowState else { return }
            guard canPerform(), let outcome = perform() else {
                self.rejectPendingMutation(in: windowState)
                onRejected()
                return
            }
            switch outcome {
            case .dismissPalette:
                dismiss()
            case .paletteReplaced:
                self.beginSession(windowID: windowState.id)
            }
            onPerformed()
        }
    }

    private func rejectPendingMutation(
        in windowState: BrowserWindowState
    ) {
        guard let session,
              session.windowID == windowState.id,
              pendingMutationSession == session else {
            return
        }
        pendingMutationSession = nil
    }

    private func requestDeferredMutation(
        in windowState: BrowserWindowState,
        scheduler: DeferredScheduler,
        perform: @escaping @MainActor () -> Void
    ) -> Bool {
        guard windowState.presentationState.isCommandPaletteVisible,
              let session,
              session.windowID == windowState.id,
              pendingMutationSession == nil else {
            return false
        }

        pendingMutationSession = session
        scheduler { [weak self, weak windowState] in
            guard let self,
                  let windowState,
                  windowState.presentationState.isCommandPaletteVisible,
                  self.session == session,
                  self.pendingMutationSession == session else {
                return
            }
            perform()
        }
        return true
    }

    private func isEventInsideCard(_ event: NSEvent) -> Bool {
        guard let cardView,
              let eventWindow =
                  event.window
                  ?? NSApp.window(withWindowNumber: event.windowNumber),
              cardView.window === eventWindow else {
            return false
        }
        let localPoint = cardView.convert(event.locationInWindow, from: nil)
        return cardView.bounds.contains(localPoint)
    }

    private static func scheduleOnNextMainTurn(
        _ operation: @escaping @MainActor () -> Void
    ) {
        DispatchQueue.main.async {
            operation()
        }
    }
}
