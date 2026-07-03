import CoreGraphics
import Foundation

/// Owns the per-window transient split-drop preview state and the published snapshot for
/// the active window, notifying observers only when the visible preview actually changes.
@MainActor
final class SplitPreviewStateOwner {
    struct WindowSplitPreviewState: Equatable {
        var isActive: Bool = false
        var targetRect: CGRect?
        var style: SplitDropPreviewStyle = .edge
    }

    private struct TransientWindowSplitState: Equatable {
        var isPreviewActive: Bool = false
        var previewTargetRect: CGRect?
        var previewStyle: SplitDropPreviewStyle = .edge
    }

    private let activeWindowId: @MainActor () -> UUID?
    private let notifyActiveWindowPreviewChanged: @MainActor () -> Void
    private let refreshWindow: @MainActor (UUID) -> Void

    private var activeWindowPreviewState = WindowSplitPreviewState()
    private var transientWindowSplitStates: [UUID: TransientWindowSplitState] = [:]

    init(
        activeWindowId: @escaping @MainActor () -> UUID?,
        notifyActiveWindowPreviewChanged: @escaping @MainActor () -> Void,
        refreshWindow: @escaping @MainActor (UUID) -> Void
    ) {
        self.activeWindowId = activeWindowId
        self.notifyActiveWindowPreviewChanged = notifyActiveWindowPreviewChanged
        self.refreshWindow = refreshWindow
    }

    func previewState(for windowId: UUID) -> WindowSplitPreviewState {
        let transient = transientState(for: windowId)
        return WindowSplitPreviewState(
            isActive: transient.isPreviewActive,
            targetRect: transient.previewTargetRect,
            style: transient.previewStyle
        )
    }

    func isPreviewActive(for windowId: UUID) -> Bool {
        transientState(for: windowId).isPreviewActive
    }

    func beginPreview(
        targetRect: CGRect?,
        style: SplitDropPreviewStyle,
        for windowId: UUID
    ) {
        var transient = transientState(for: windowId)
        transient.previewTargetRect = targetRect
        transient.previewStyle = style
        transient.isPreviewActive = true
        setTransientState(transient, for: windowId)
        refreshWindow(windowId)
    }

    func updatePreview(
        targetRect: CGRect?,
        style: SplitDropPreviewStyle,
        for windowId: UUID
    ) {
        var transient = transientState(for: windowId)
        guard transient.isPreviewActive else { return }
        transient.previewTargetRect = targetRect
        transient.previewStyle = style
        setTransientState(transient, for: windowId)
    }

    func endPreview(for windowId: UUID) {
        var transient = transientState(for: windowId)
        guard transient.isPreviewActive
            || transient.previewTargetRect != nil
            || transient.previewStyle != .edge
        else { return }
        transient.isPreviewActive = false
        transient.previewTargetRect = nil
        transient.previewStyle = .edge
        setTransientState(transient, for: windowId)
        refreshWindow(windowId)
    }

    func cleanupWindow(_ windowId: UUID) {
        transientWindowSplitStates.removeValue(forKey: windowId)
        syncPublishedStateIfNeeded(for: windowId)
    }

    func syncPublishedStateIfNeeded(for windowId: UUID, forceNotify: Bool = false) {
        guard activeWindowId() == windowId else { return }
        let next = previewState(for: windowId)
        guard forceNotify || activeWindowPreviewState != next else { return }

        notifyActiveWindowPreviewChanged()
        activeWindowPreviewState = next
    }

    private func transientState(for windowId: UUID) -> TransientWindowSplitState {
        transientWindowSplitStates[windowId] ?? TransientWindowSplitState()
    }

    private func setTransientState(_ state: TransientWindowSplitState, for windowId: UUID) {
        let previous = transientState(for: windowId)
        guard previous != state else { return }
        if state.isPreviewActive == false,
           state.previewTargetRect == nil {
            transientWindowSplitStates.removeValue(forKey: windowId)
        } else {
            transientWindowSplitStates[windowId] = state
        }
        syncPublishedStateIfNeeded(for: windowId)
    }
}
