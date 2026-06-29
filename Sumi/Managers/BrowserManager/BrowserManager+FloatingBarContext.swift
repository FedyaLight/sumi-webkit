import Foundation

@MainActor
extension BrowserManager {
    var floatingBarBrowserContext: FloatingBarBrowserContext {
        FloatingBarBrowserContext(
            currentProfileId: currentProfile?.id,
            favicon: FloatingBarFaviconContext(
                partition: dataServices.faviconService.partition(profile: currentProfile),
                imageService: dataServices.faviconImageService
            ),
            configureSearchManager: { [weak self] searchManager in
                guard let self else { return }
                searchManager.setTabManager(tabManager)
                searchManager.setHistoryManager(historyManager)
                searchManager.setBookmarkManager(bookmarkManager)
                searchManager.updateProfileContext()
            },
            updateDraft: { [weak self] windowState, text in
                self?.updateFloatingBarDraft(in: windowState, text: text)
            },
            dismiss: { [weak self] windowState, preserveDraft in
                self?.dismissFloatingBar(in: windowState, preserveDraft: preserveDraft)
            },
            deleteHistoryEntry: { [weak self] entry in
                guard let self else { return }
                if let visitID = entry.visitID {
                    await historyManager.delete(query: .visits([visitID]))
                } else {
                    await historyManager.delete(query: .domainFilter([entry.siteDomain ?? entry.domain]))
                }
            },
            commitNavigatesCurrentTab: { [weak self] windowState in
                self?.floatingBarCommitNavigatesCurrentTab(in: windowState) ?? false
            },
            commitNavigation: { [weak self] urlString, windowState, navigatesCurrentTab in
                self?.commitFloatingBarNavigation(
                    to: urlString,
                    in: windowState,
                    navigatesCurrentTab: navigatesCurrentTab
                )
            },
            commitSuggestion: { [weak self] suggestion, windowState, navigatesCurrentTab in
                self?.commitFloatingBarSuggestion(
                    suggestion,
                    in: windowState,
                    navigatesCurrentTab: navigatesCurrentTab
                )
            }
        )
    }
}
