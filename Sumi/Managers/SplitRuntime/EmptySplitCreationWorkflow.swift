import Foundation
import SumiDomain

/// Integration edge between placeholder creation and floating-bar focus. The
/// placeholder service itself has no URL-bar dependency, so commit/cancel can
/// depend on it without forming a service cycle.
@MainActor
final class EmptySplitCreationWorkflow {
    private let placeholders: EmptySplitService
    private let focusFloatingBar: (
        BrowserWindowState,
        FloatingBarPresentationReason
    ) -> Void

    init(
        placeholders: EmptySplitService,
        focusFloatingBar: @escaping (
            BrowserWindowState,
            FloatingBarPresentationReason
        ) -> Void
    ) {
        self.placeholders = placeholders
        self.focusFloatingBar = focusFloatingBar
    }

    @discardableResult
    func create(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState,
        reason: FloatingBarPresentationReason = .keyboard
    ) -> Bool {
        guard placeholders.create(side: side, in: windowState) else {
            return false
        }
        focusFloatingBar(windowState, reason)
        return true
    }
}
