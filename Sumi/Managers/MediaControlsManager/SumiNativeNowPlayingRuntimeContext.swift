import Foundation

@MainActor
struct SumiNativeNowPlayingBrowserRuntime {
    let windowStates: @MainActor () -> [BrowserWindowState]
    let windowState: @MainActor (UUID) -> BrowserWindowState?
    let currentTab: @MainActor (BrowserWindowState) -> Tab?
    let mediaCandidateTabs: @MainActor (BrowserWindowState) -> [Tab]
    let tab: @MainActor (UUID) -> Tab?
    let resolvedNowPlayingWebView: @MainActor (Tab, BrowserWindowState) -> SumiNowPlayingWebViewAdapter?
    let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
}

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
    static func live(runtime: SumiNativeNowPlayingBrowserRuntime) -> Self {
        Self(
            candidateTabs: {
                var candidates: [Candidate] = []
                var seen = Set<UUID>()

                for windowState in runtime.windowStates() {
                    guard !windowState.isIncognito else { continue }

                    let scopedTabs = runtime.mediaCandidateTabs(windowState)
                    let preferredTabs = scopedTabs.filter(\.audioState.isPlayingAudio)
                    let discoveryTabs = preferredTabs.isEmpty
                        ? [runtime.currentTab(windowState)].compactMap(\.self)
                        : preferredTabs

                    for tab in discoveryTabs {
                        guard seen.insert(tab.id).inserted else { continue }
                        candidates.append((tab, windowState))
                    }
                }

                return candidates
            },
            windowState: { windowId in
                runtime.windowState(windowId)
            },
            resolvedTab: { tabId, windowState in
                if windowState.isIncognito {
                    return windowState.ephemeralTabs.first(where: { $0.id == tabId })
                }

                if let visibleTab = runtime.mediaCandidateTabs(windowState)
                    .first(where: { $0.id == tabId }) {
                    return visibleTab
                }

                return runtime.tab(tabId)
            },
            resolvedNowPlayingWebView: { tab, windowState in
                runtime.resolvedNowPlayingWebView(tab, windowState)
            },
            selectTab: { tab, windowState in
                runtime.selectTab(tab, windowState)
            }
        )
    }
}
