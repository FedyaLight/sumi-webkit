import Foundation

@MainActor
protocol CommandPaletteStatePersisting: AnyObject {
    func persist(_ windowState: BrowserWindowState)
    func schedule(_ windowState: BrowserWindowState, delayNanoseconds: UInt64)
}

extension WindowSessionPersistenceCoordinator: CommandPaletteStatePersisting {}

/// Owns the window-scoped presentation state of the command palette. Navigation
/// commits are deliberately outside this service so draft lifecycle and
/// durable presentation state cannot absorb tab-routing policy again.
@MainActor
final class CommandPalettePresentationService {
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let hasValidCurrentSelection: @MainActor (BrowserWindowState) -> Bool
    private let splitCancellation: EmptySplitSession
    private let dismissThemePickerDiscardingIfNeeded: @MainActor () -> Void
    private let persistence: @MainActor () -> (any CommandPaletteStatePersisting)?

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        hasValidCurrentSelection: @escaping @MainActor (BrowserWindowState) -> Bool,
        splitCancellation: EmptySplitSession,
        dismissThemePickerDiscardingIfNeeded: @escaping @MainActor () -> Void,
        persistence: @escaping @MainActor () -> (any CommandPaletteStatePersisting)?
    ) {
        self.windowRegistry = windowRegistry
        self.hasValidCurrentSelection = hasValidCurrentSelection
        self.splitCancellation = splitCancellation
        self.dismissThemePickerDiscardingIfNeeded = dismissThemePickerDiscardingIfNeeded
        self.persistence = persistence
    }

    func focusActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        reason: CommandPalettePresentationReason
    ) {
        guard let activeWindow = windowRegistry()?.activeWindow else { return }
        focus(
            in: activeWindow,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            reason: reason
        )
    }

    func focus(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool,
        reason: CommandPalettePresentationReason
    ) {
        let shouldOverrideDraft = !prefill.isEmpty
            || windowState.commandPaletteDraftText.isEmpty
            || navigateCurrentTab
        if shouldOverrideDraft {
            windowState.commandPaletteDraftText = prefill
            windowState.commandPaletteDraftNavigatesCurrentTab = navigateCurrentTab
        }
        windowState.commandPalettePresentationReason = reason
        windowState.presentationState.isCommandPaletteVisible = true
        dismissThemePickerDiscardingIfNeeded()
        persistence()?.persist(windowState)
    }

    func showNewTab(in windowState: BrowserWindowState) {
        windowState.commandPaletteDraftText = ""
        windowState.commandPaletteDraftNavigatesCurrentTab = false
        windowState.commandPalettePresentationReason = .emptySpace
        windowState.presentationState.isCommandPaletteVisible = true
        dismissThemePickerDiscardingIfNeeded()
        persistence()?.persist(windowState)
    }

    func updateDraft(in windowState: BrowserWindowState, text: String) {
        guard windowState.commandPaletteDraftText != text else { return }
        windowState.commandPaletteDraftText = text
        persistence()?.schedule(windowState, delayNanoseconds: 450_000_000)
    }

    func dismiss(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool = true
    ) {
        if cancelEmptySplitPlaceholder {
            _ = splitCancellation.cancel(in: windowState)
        }
        windowState.commandPalettePresentationReason = .none
        windowState.presentationState.isCommandPaletteVisible = false
        if !preserveDraft {
            windowState.commandPaletteDraftText = ""
            windowState.commandPaletteDraftNavigatesCurrentTab = false
        }
        persistence()?.persist(windowState)
    }

    func dismissActiveWindow(preserveDraft: Bool) {
        guard let activeWindow = windowRegistry()?.activeWindow,
              activeWindow.presentationState.isCommandPaletteVisible
        else { return }

        dismiss(in: activeWindow, preserveDraft: preserveDraft)
    }

    @discardableResult
    func dismissIfVisible(in windowID: UUID, preserveDraft: Bool) -> Bool {
        guard let windowState = windowRegistry()?.windows[windowID],
              windowState.presentationState.isCommandPaletteVisible
        else { return false }

        dismiss(in: windowState, preserveDraft: preserveDraft)
        return true
    }

    func dismissAfterSelection(in windowState: BrowserWindowState) {
        guard windowState.presentationState.isCommandPaletteVisible
            || windowState.commandPalettePresentationReason != .none
        else { return }

        let preserveDraft: Bool
        switch windowState.commandPalettePresentationReason {
        case .emptySpace, .splitTabPicker:
            preserveDraft = false
        case .keyboard, .none:
            preserveDraft = true
        }
        dismiss(in: windowState, preserveDraft: preserveDraft)
    }

    func sanitize(in windowState: BrowserWindowState) {
        if hasValidCurrentSelection(windowState) {
            clearEmptyStatePresentationIfNeeded(in: windowState)
        } else if !windowState.isShowingEmptyState {
            windowState.commandPalettePresentationReason = .none
        }
    }

    private func clearEmptyStatePresentationIfNeeded(
        in windowState: BrowserWindowState
    ) {
        guard windowState.isShowingEmptyState
            || windowState.commandPalettePresentationReason == .emptySpace
        else { return }

        windowState.isShowingEmptyState = false
        dismiss(in: windowState, preserveDraft: false)
    }
}
