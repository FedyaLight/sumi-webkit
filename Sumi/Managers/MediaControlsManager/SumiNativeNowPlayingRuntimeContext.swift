import Foundation

@MainActor
struct SumiNativeNowPlayingRuntimeContext {
    typealias Candidate = (tab: Tab, windowState: BrowserWindowState)

    let candidateTabs: @MainActor () -> [Candidate]
    let windowState: @MainActor (UUID) -> BrowserWindowState?
    let resolvedTab: @MainActor (UUID, BrowserWindowState) -> Tab?
    let resolvedNowPlayingWebView: @MainActor (Tab, BrowserWindowState) -> SumiNowPlayingWebViewAdapter?
    let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
}

extension SumiNativeNowPlayingRuntimeContext {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            candidateTabs: { [weak browserManager] in
                guard let browserManager,
                      let windowRegistry = browserManager.windowRegistry else {
                    return []
                }

                var candidates: [Candidate] = []
                var seen = Set<UUID>()

                for windowState in windowRegistry.windows.values {
                    guard !windowState.isIncognito else { continue }

                    let scopedTabs = browserManager.windowScopedMediaCandidateTabs(in: windowState)
                    let preferredTabs = scopedTabs.filter { $0.audioState.isPlayingAudio }
                    let discoveryTabs = preferredTabs.isEmpty
                        ? [browserManager.currentTab(for: windowState)].compactMap { $0 }
                        : preferredTabs

                    for tab in discoveryTabs {
                        guard seen.insert(tab.id).inserted else { continue }
                        candidates.append((tab, windowState))
                    }
                }

                return candidates
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            resolvedTab: { [weak browserManager] tabId, windowState in
                guard let browserManager else { return nil }
                if windowState.isIncognito {
                    return windowState.ephemeralTabs.first(where: { $0.id == tabId })
                }

                if let visibleTab = browserManager.windowScopedMediaCandidateTabs(in: windowState)
                    .first(where: { $0.id == tabId }) {
                    return visibleTab
                }

                return browserManager.tabManager.tab(for: tabId)
            },
            resolvedNowPlayingWebView: { [weak browserManager] tab, windowState in
                guard let browserManager else { return nil }
                return tab.authoritativeMediaWebView(
                    using: browserManager,
                    in: windowState
                )
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
    }
}
