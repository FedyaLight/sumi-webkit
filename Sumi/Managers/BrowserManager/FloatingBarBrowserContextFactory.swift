import Foundation

/// Builds the SwiftUI floating-bar context from explicit browser capabilities.
/// The factory does not locate services through `BrowserManager`.
@MainActor
final class FloatingBarBrowserContextFactory {
    private let currentProfileId: @MainActor () -> UUID?
    private let faviconContext: @MainActor () -> FloatingBarFaviconContext
    private let configureSearchManager: @MainActor (SearchManager) -> Void
    private let deleteHistoryEntry: @MainActor (HistoryListItem) async -> Void
    private let presentation: FloatingBarPresentationService
    private let commit: FloatingBarCommitService
    private let offersCommandSuggestions: @MainActor (BrowserWindowState) -> Bool

    init(
        currentProfileId: @escaping @MainActor () -> UUID?,
        faviconContext: @escaping @MainActor () -> FloatingBarFaviconContext,
        configureSearchManager: @escaping @MainActor (SearchManager) -> Void,
        deleteHistoryEntry: @escaping @MainActor (HistoryListItem) async -> Void,
        presentation: FloatingBarPresentationService,
        commit: FloatingBarCommitService,
        offersCommandSuggestions: @escaping @MainActor (BrowserWindowState) -> Bool
    ) {
        self.currentProfileId = currentProfileId
        self.faviconContext = faviconContext
        self.configureSearchManager = configureSearchManager
        self.deleteHistoryEntry = deleteHistoryEntry
        self.presentation = presentation
        self.commit = commit
        self.offersCommandSuggestions = offersCommandSuggestions
    }

    var context: FloatingBarBrowserContext {
        FloatingBarBrowserContext(
            currentProfileId: currentProfileId(),
            favicon: faviconContext(),
            configureSearchManager: configureSearchManager,
            updateDraft: { [presentation] windowState, text in
                presentation.updateDraft(in: windowState, text: text)
            },
            dismiss: { [presentation] windowState, preserveDraft in
                presentation.dismiss(
                    in: windowState,
                    preserveDraft: preserveDraft
                )
            },
            deleteHistoryEntry: deleteHistoryEntry,
            commitNavigatesCurrentTab: { [commit] windowState in
                commit.commitNavigatesCurrentTab(in: windowState)
            },
            commitNavigation: { [commit] urlString, windowState in
                commit.commitNavigation(to: urlString, in: windowState)
            },
            commitSuggestion: { [commit] suggestion, windowState in
                commit.commitSuggestion(suggestion, in: windowState)
            },
            offersCommandSuggestions: offersCommandSuggestions
        )
    }

    static func historyDeletionQuery(for entry: HistoryListItem) -> HistoryQuery {
        if let visitID = entry.visitID {
            return .visits([visitID])
        }
        return .domainFilter([entry.siteDomain ?? entry.domain])
    }
}
