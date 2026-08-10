import Foundation

@MainActor
struct SumiNativeNowPlayingBrowserRuntime {
    let windowStates: @MainActor () -> [BrowserWindowState]
    let windowState: @MainActor (UUID) -> BrowserWindowState?
    let windowRegistry: @MainActor () -> WindowRegistry?
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
    let windowRegistry: @MainActor () -> WindowRegistry?
    let resolvedTab: @MainActor (UUID, BrowserWindowState) -> Tab?
    let resolvedNowPlayingWebView: @MainActor (Tab, BrowserWindowState) -> SumiNowPlayingWebViewAdapter?
    let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
}

extension SumiNativeNowPlayingRuntimeContext {
    static func live(runtime: SumiNativeNowPlayingBrowserRuntime) -> Self {
        Self(
            candidateTabs: {
                var candidates: [Candidate] = []
                var seen = Set<SumiMediaResidenceKey>()

                for windowState in runtime.windowStates() {
                    guard !windowState.isIncognito else { continue }

                    let scopedTabs = runtime.mediaCandidateTabs(windowState)
                    let discoveryTabs = scopedTabs.isEmpty
                        ? [runtime.currentTab(windowState)].compactMap(\.self)
                        : scopedTabs

                    for tab in discoveryTabs {
                        let residenceKey = SumiMediaResidenceKey(
                            tabId: tab.id,
                            windowId: windowState.id
                        )
                        guard seen.insert(residenceKey).inserted else { continue }
                        candidates.append((tab, windowState))
                    }
                }

                return candidates
            },
            windowState: { windowId in
                runtime.windowState(windowId)
            },
            windowRegistry: {
                runtime.windowRegistry()
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
