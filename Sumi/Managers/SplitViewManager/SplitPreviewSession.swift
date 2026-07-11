import CoreGraphics
import Foundation

/// Window-scoped transient split-drop previews. The session publishes only
/// when the active window's visible preview actually changes.
@MainActor
final class SplitPreviewSession {
    struct WindowState: Equatable {
        var isActive = false
        var targetRect: CGRect?
        var style: SplitDropPreviewStyle = .edge
    }

    private struct TransientState: Equatable {
        var isActive = false
        var targetRect: CGRect?
        var style: SplitDropPreviewStyle = .edge
    }

    private let activeWindowID: @MainActor () -> UUID?
    private let publishActiveWindowChange: @MainActor () -> Void
    private let refreshWindow: @MainActor (UUID) -> Void
    private var publishedActiveWindowState = WindowState()
    private var states: [UUID: TransientState] = [:]

    init(
        activeWindowID: @escaping @MainActor () -> UUID?,
        publishActiveWindowChange: @escaping @MainActor () -> Void,
        refreshWindow: @escaping @MainActor (UUID) -> Void
    ) {
        self.activeWindowID = activeWindowID
        self.publishActiveWindowChange = publishActiveWindowChange
        self.refreshWindow = refreshWindow
    }

    func state(for windowID: UUID) -> WindowState {
        let state = transientState(for: windowID)
        return WindowState(
            isActive: state.isActive,
            targetRect: state.targetRect,
            style: state.style
        )
    }

    func isActive(in windowID: UUID) -> Bool {
        transientState(for: windowID).isActive
    }

    func begin(
        targetRect: CGRect?,
        style: SplitDropPreviewStyle,
        in windowID: UUID
    ) {
        var state = transientState(for: windowID)
        state.targetRect = targetRect
        state.style = style
        state.isActive = true
        set(state, for: windowID)
        refreshWindow(windowID)
    }

    func update(
        targetRect: CGRect?,
        style: SplitDropPreviewStyle,
        in windowID: UUID
    ) {
        var state = transientState(for: windowID)
        guard state.isActive else { return }
        state.targetRect = targetRect
        state.style = style
        set(state, for: windowID)
    }

    func end(in windowID: UUID) {
        var state = transientState(for: windowID)
        guard state.isActive || state.targetRect != nil || state.style != .edge
        else {
            return
        }
        state = TransientState()
        set(state, for: windowID)
        refreshWindow(windowID)
    }

    func removeWindow(_ windowID: UUID) {
        states.removeValue(forKey: windowID)
        syncPublishedState(for: windowID)
    }

    func syncPublishedState(
        for windowID: UUID,
        force: Bool = false
    ) {
        guard activeWindowID() == windowID else { return }
        let next = state(for: windowID)
        guard force || publishedActiveWindowState != next else { return }
        publishActiveWindowChange()
        publishedActiveWindowState = next
    }

    private func transientState(for windowID: UUID) -> TransientState {
        states[windowID] ?? TransientState()
    }

    private func set(_ state: TransientState, for windowID: UUID) {
        guard transientState(for: windowID) != state else { return }
        if state == TransientState() {
            states.removeValue(forKey: windowID)
        } else {
            states[windowID] = state
        }
        syncPublishedState(for: windowID)
    }
}
