import Foundation
import SumiDomain

/// Integration edge between placeholder creation and command-palette focus. The
/// placeholder service itself has no URL-bar dependency, so commit/cancel can
/// depend on it without forming a service cycle.
@MainActor
final class EmptySplitCreationWorkflow {
    private let placeholders: EmptySplitService
    private let focusCommandPalette: (
        BrowserWindowState,
        CommandPalettePresentationReason
    ) -> Void

    init(
        placeholders: EmptySplitService,
        focusCommandPalette: @escaping (
            BrowserWindowState,
            CommandPalettePresentationReason
        ) -> Void
    ) {
        self.placeholders = placeholders
        self.focusCommandPalette = focusCommandPalette
    }

    @discardableResult
    func create(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState,
        reason: CommandPalettePresentationReason = .keyboard
    ) -> Bool {
        guard placeholders.create(side: side, in: windowState) else {
            return false
        }
        focusCommandPalette(windowState, reason)
        return true
    }

    func canCreate(
        side: SplitDropSide = .right,
        in windowState: BrowserWindowState
    ) -> Bool {
        placeholders.canCreate(side: side, in: windowState)
    }
}
