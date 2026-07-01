@testable import Sumi
import XCTest

final class SumiNowPlayingBridgeTests: XCTestCase {
    func testMapperPrefersTitleArtistPayloadWhenAvailable() {
        let info = SumiNowPlayingInfoMapper.makeInfo(
            titleAndArtist: ("  Native Title  ", "  Native Artist "),
            playbackState: .playing
        )

        XCTAssertEqual(info.title, "Native Title")
        XCTAssertEqual(info.artist, "Native Artist")
        XCTAssertEqual(info.playbackState, .playing)
    }

    func testMapperNormalizesEmptyValues() {
        let info = SumiNowPlayingInfoMapper.makeInfo(
            titleAndArtist: ("   ", " "),
            playbackState: .paused
        )

        XCTAssertEqual(info.title, "")
        XCTAssertNil(info.artist)
        XCTAssertEqual(info.playbackState, .paused)
    }

    func testMapperKeepsPlaybackState() {
        let info = SumiNowPlayingInfoMapper.makeInfo(
            titleAndArtist: ("Native Title", nil),
            playbackState: .playing
        )

        XCTAssertEqual(info.playbackState, .playing)
    }
}

@MainActor
final class SumiNativeNowPlayingControllerFeatureGateTests: XCTestCase {
    func testDisablingFeatureSuspendsController() {
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )

        controller.setFeatureEnabled(true)
        controller.setFeatureEnabled(false)

        XCTAssertFalse(controller.isFeatureEnabled)
        XCTAssertNil(controller.cardState)
    }

    func testScheduleRefreshIsNoOpWhenFeatureDisabled() async {
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )

        controller.setFeatureEnabled(false)
        controller.scheduleRefresh(delayNanoseconds: 0)

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(controller.cardState)
    }

    func testShouldMountMiniPlayerRequiresVisibleGlobalState() {
        let windowId = UUID()
        let tabId = UUID()
        let windowState = BrowserWindowState(id: windowId)
        windowState.currentTabId = tabId

        let globalState = SumiBackgroundMediaCardState(
            id: "test",
            tabId: tabId,
            windowId: windowId,
            title: "Title",
            subtitle: "",
            sourceHost: nil,
            tabTitle: "Title",
            playbackState: .playing,
            isMuted: false,
            favicon: nil,
            canPlayPause: true,
            canMute: true
        )

        XCTAssertFalse(
            SumiBackgroundMediaCardStore.shouldMountMiniPlayer(
                globalState: globalState,
                in: windowState
            )
        )

        windowState.currentTabId = UUID()

        XCTAssertTrue(
            SumiBackgroundMediaCardStore.shouldMountMiniPlayer(
                globalState: globalState,
                in: windowState
            )
        )
    }
}

@MainActor
final class SumiNativeNowPlayingRuntimeContextTests: XCTestCase {
    func testRuntimeCandidatesSkipIncognitoPreferPlayingTabsAndFallbackToCurrentTab() {
        let playingTab = makeTab("https://example.com/playing")
        playingTab.applyAudioState(.unmuted(isPlayingAudio: true))
        let pausedCandidate = makeTab("https://example.com/paused-candidate")
        let fallbackCurrentTab = makeTab("https://example.org/current")
        let incognitoPlayingTab = makeTab("https://private.example/playing")
        incognitoPlayingTab.applyAudioState(.unmuted(isPlayingAudio: true))

        let regularWindow = BrowserWindowState()
        let fallbackWindow = BrowserWindowState()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true

        let context = SumiNativeNowPlayingRuntimeContext.live(
            runtime: SumiNativeNowPlayingBrowserRuntime(
                windowStates: { [regularWindow, fallbackWindow, incognitoWindow] },
                windowState: { _ in nil },
                currentTab: { windowState in
                    windowState === fallbackWindow ? fallbackCurrentTab : pausedCandidate
                },
                mediaCandidateTabs: { windowState in
                    if windowState === regularWindow {
                        return [pausedCandidate, playingTab]
                    }
                    if windowState === incognitoWindow {
                        return [incognitoPlayingTab]
                    }
                    return []
                },
                tab: { _ in nil },
                resolvedNowPlayingWebView: { _, _ in nil },
                selectTab: { _, _ in /* No-op. */ }
            )
        )

        let candidates = context.candidateTabs()

        XCTAssertEqual(candidates.map(\.tab.id), [playingTab.id, fallbackCurrentTab.id])
        XCTAssertIdentical(candidates[0].windowState, regularWindow)
        XCTAssertIdentical(candidates[1].windowState, fallbackWindow)
    }

    func testRuntimeCandidateDiscoveryDeduplicatesTabsAcrossWindows() {
        let sharedPlayingTab = makeTab("https://example.com/shared")
        sharedPlayingTab.applyAudioState(.unmuted(isPlayingAudio: true))
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()

        let context = SumiNativeNowPlayingRuntimeContext.live(
            runtime: SumiNativeNowPlayingBrowserRuntime(
                windowStates: { [firstWindow, secondWindow] },
                windowState: { _ in nil },
                currentTab: { _ in sharedPlayingTab },
                mediaCandidateTabs: { _ in [sharedPlayingTab] },
                tab: { _ in nil },
                resolvedNowPlayingWebView: { _, _ in nil },
                selectTab: { _, _ in /* No-op. */ }
            )
        )

        let candidates = context.candidateTabs()

        XCTAssertEqual(candidates.count, 1)
        XCTAssertIdentical(candidates.first?.windowState, firstWindow)
    }

    func testRuntimeResolvedTabUsesIncognitoEphemeralThenWindowCandidateThenTabLookup() {
        let ephemeralTab = makeTab("https://private.example/tab")
        let visibleCandidate = makeTab("https://example.com/visible")
        let lookupTab = makeTab("https://example.com/lookup")
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        incognitoWindow.ephemeralTabs = [ephemeralTab]
        let regularWindow = BrowserWindowState()

        let context = SumiNativeNowPlayingRuntimeContext.live(
            runtime: SumiNativeNowPlayingBrowserRuntime(
                windowStates: { [regularWindow, incognitoWindow] },
                windowState: { windowId in
                    if windowId == regularWindow.id { return regularWindow }
                    if windowId == incognitoWindow.id { return incognitoWindow }
                    return nil
                },
                currentTab: { _ in nil },
                mediaCandidateTabs: { windowState in
                    windowState === regularWindow ? [visibleCandidate] : []
                },
                tab: { tabId in
                    tabId == lookupTab.id ? lookupTab : nil
                },
                resolvedNowPlayingWebView: { _, _ in nil },
                selectTab: { _, _ in /* No-op. */ }
            )
        )

        XCTAssertIdentical(context.windowState(regularWindow.id), regularWindow)
        XCTAssertIdentical(context.resolvedTab(ephemeralTab.id, incognitoWindow), ephemeralTab)
        XCTAssertIdentical(context.resolvedTab(visibleCandidate.id, regularWindow), visibleCandidate)
        XCTAssertIdentical(context.resolvedTab(lookupTab.id, regularWindow), lookupTab)
        XCTAssertNil(context.resolvedTab(lookupTab.id, incognitoWindow))
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            loadsCachedFaviconOnInit: false
        )
    }
}
