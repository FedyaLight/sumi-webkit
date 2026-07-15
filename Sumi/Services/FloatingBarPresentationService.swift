import Foundation

@MainActor
protocol FloatingBarSplitPlaceholderHandling: AnyObject {
    func cancel(in windowState: BrowserWindowState) -> Bool
    func commit(_ placeholder: Tab, in windowID: UUID)
    func replace(with tab: Tab, in windowState: BrowserWindowState) -> Bool
}

extension EmptySplitService: FloatingBarSplitPlaceholderHandling {}

@MainActor
protocol FloatingBarStatePersisting: AnyObject {
    func persist(_ windowState: BrowserWindowState)
    func schedule(_ windowState: BrowserWindowState, delayNanoseconds: UInt64)
}

extension WindowSessionPersistenceCoordinator: FloatingBarStatePersisting {}

/// Owns the window-scoped presentation state of the floating bar. Navigation
/// commits are deliberately outside this service so draft lifecycle and
/// durable presentation state cannot absorb tab-routing policy again.
@MainActor
final class FloatingBarPresentationService {
    private let windowRegistry: @MainActor () -> WindowRegistry?
    private let hasValidCurrentSelection: @MainActor (BrowserWindowState) -> Bool
    private let splitPlaceholders:
        @MainActor () -> (any FloatingBarSplitPlaceholderHandling)?
    private let dismissThemePickerDiscardingIfNeeded: @MainActor () -> Void
    private let persistence: @MainActor () -> (any FloatingBarStatePersisting)?

    init(
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        hasValidCurrentSelection: @escaping @MainActor (BrowserWindowState) -> Bool,
        splitPlaceholders: @escaping @MainActor
            () -> (any FloatingBarSplitPlaceholderHandling)?,
        dismissThemePickerDiscardingIfNeeded: @escaping @MainActor () -> Void,
        persistence: @escaping @MainActor () -> (any FloatingBarStatePersisting)?
    ) {
        self.windowRegistry = windowRegistry
        self.hasValidCurrentSelection = hasValidCurrentSelection
        self.splitPlaceholders = splitPlaceholders
        self.dismissThemePickerDiscardingIfNeeded = dismissThemePickerDiscardingIfNeeded
        self.persistence = persistence
    }

    func focusActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        reason: FloatingBarPresentationReason
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
        reason: FloatingBarPresentationReason
    ) {
        let shouldOverrideDraft = !prefill.isEmpty
            || windowState.floatingBarDraftText.isEmpty
            || navigateCurrentTab
        if shouldOverrideDraft {
            windowState.floatingBarDraftText = prefill
            windowState.floatingBarDraftNavigatesCurrentTab = navigateCurrentTab
        }
        windowState.floatingBarPresentationReason = reason
        windowState.presentationState.isFloatingBarVisible = true
        dismissThemePickerDiscardingIfNeeded()
        persistence()?.persist(windowState)
    }

    func showNewTab(in windowState: BrowserWindowState) {
        windowState.floatingBarDraftText = ""
        windowState.floatingBarDraftNavigatesCurrentTab = false
        windowState.floatingBarPresentationReason = .emptySpace
        windowState.presentationState.isFloatingBarVisible = true
        dismissThemePickerDiscardingIfNeeded()
        persistence()?.persist(windowState)
    }

    func updateDraft(in windowState: BrowserWindowState, text: String) {
        guard windowState.floatingBarDraftText != text else { return }
        windowState.floatingBarDraftText = text
        persistence()?.schedule(windowState, delayNanoseconds: 450_000_000)
    }

    func dismiss(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool = true
    ) {
        if cancelEmptySplitPlaceholder {
            _ = splitPlaceholders()?.cancel(in: windowState)
        }
        windowState.floatingBarPresentationReason = .none
        windowState.presentationState.isFloatingBarVisible = false
        if !preserveDraft {
            windowState.floatingBarDraftText = ""
            windowState.floatingBarDraftNavigatesCurrentTab = false
        }
        persistence()?.persist(windowState)
    }

    func dismissActiveWindow(preserveDraft: Bool) {
        guard let activeWindow = windowRegistry()?.activeWindow,
              activeWindow.presentationState.isFloatingBarVisible
        else { return }

        dismiss(in: activeWindow, preserveDraft: preserveDraft)
    }

    @discardableResult
    func dismissIfVisible(in windowID: UUID, preserveDraft: Bool) -> Bool {
        guard let windowState = windowRegistry()?.windows[windowID],
              windowState.presentationState.isFloatingBarVisible
        else { return false }

        dismiss(in: windowState, preserveDraft: preserveDraft)
        return true
    }

    func dismissAfterSelection(in windowState: BrowserWindowState) {
        guard windowState.presentationState.isFloatingBarVisible
            || windowState.floatingBarPresentationReason != .none
        else { return }

        let preserveDraft: Bool
        switch windowState.floatingBarPresentationReason {
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
            windowState.floatingBarPresentationReason = .none
        }
    }

    private func clearEmptyStatePresentationIfNeeded(
        in windowState: BrowserWindowState
    ) {
        guard windowState.isShowingEmptyState
            || windowState.floatingBarPresentationReason == .emptySpace
        else { return }

        windowState.isShowingEmptyState = false
        dismiss(in: windowState, preserveDraft: false)
    }
}
