@testable import Sumi
import SumiWebRuntime
import XCTest

private func makeMediaCardID(
    tabId: UUID,
    windowId: UUID,
    residenceGeneration: UInt64 = 0
) -> SumiBackgroundMediaCardID {
    SumiBackgroundMediaCardID(
        tabId: tabId,
        windowId: windowId,
        residenceGeneration: residenceGeneration,
        webViewIdentity: ObjectIdentifier(NSObject())
    )
}

final class SumiNowPlayingBridgeTests: XCTestCase {
    func testCollapsedStackReservesOnlyCardAndPeekHeight() {
        XCTAssertEqual(SidebarMediaCardStackMetrics.reservedHeight(cardCount: 0), 0)
        XCTAssertEqual(SidebarMediaCardStackMetrics.reservedHeight(cardCount: 1), 34)
        XCTAssertEqual(SidebarMediaCardStackMetrics.reservedHeight(cardCount: 3), 50)
        XCTAssertEqual(SidebarMediaCardStackMetrics.expandedHeight(cardCount: 3), 216)
        XCTAssertEqual(SidebarMediaCardStackMetrics.expandedHeaderHeight, 30)
        XCTAssertEqual(SidebarMediaCardStackMetrics.expandedHeaderTopInset, 4)
        XCTAssertEqual(SidebarMediaCardStackMetrics.expandedMetadataBottomSpacing, 4)
        XCTAssertEqual(SidebarMediaCardStackMetrics.headerControlsOffset, -2)
        XCTAssertEqual(SidebarMediaCardStackMetrics.metadataSlotHeight(isExpanded: true), 34)
        XCTAssertEqual(SidebarMediaCardStackMetrics.metadataSlotHeight(isExpanded: false), 0)
    }

    func testStackUsesZenOffsetsWithoutChangingReservedFooterHeight() {
        XCTAssertEqual(
            SidebarMediaCardStackMetrics.verticalOffset(index: 2, isExpanded: false),
            -16
        )
        XCTAssertEqual(
            SidebarMediaCardStackMetrics.verticalOffset(index: 2, isExpanded: true),
            -148
        )
        XCTAssertEqual(SidebarMediaCardStackMotion.duration, 0.25)
        XCTAssertNil(SidebarMediaCardStackMotion.expansionAnimation(reduceMotion: true))
        XCTAssertEqual(SidebarMediaCardPresenceMotion.duration, 0.18)
        XCTAssertEqual(SidebarMediaCardPresenceMotion.verticalOffset, 6)
    }

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
    func testDisablingFeatureClearsControllerWithoutResumingPausedMedia() async {
        let tab = Tab(
            url: URL(string: "https://media.example/feature-disabled")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        var commands: [SumiNativeNowPlayingController.SumiNativeNowPlayingCommand] = []
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { command, _, _, _ in
                commands.append(command)
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window]
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }

        await controller.togglePlayPause(cardID: cardID)
        XCTAssertEqual(commands, [.pause])

        controller.setFeatureEnabled(false)
        await Task.yield()

        XCTAssertFalse(controller.isFeatureEnabled)
        XCTAssertTrue(controller.cardStates.isEmpty)
        XCTAssertEqual(commands, [.pause])
    }

    func testScheduleRefreshIsNoOpWhenFeatureDisabled() {
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )

        controller.setFeatureEnabled(false)
        controller.scheduleRefresh(delayNanoseconds: 0)

        XCTAssertTrue(controller.cardStates.isEmpty)
    }

    func testShouldMountMiniPlayerRequiresVisibleGlobalState() {
        let windowId = UUID()
        let tabId = UUID()
        let windowState = BrowserWindowState(id: windowId)
        windowState.currentTabId = tabId

        let globalState = SumiBackgroundMediaCardState(
            id: makeMediaCardID(tabId: tabId, windowId: windowId),
            tabId: tabId,
            windowId: windowId,
            title: "Title",
            subtitle: "",
            sourceHost: nil,
            tabTitle: "Title",
            playbackState: .playing,
            isMuted: false,
            faviconSource: nil,
            canPlayPause: true,
            canMute: true,
            canPictureInPicture: false
        )

        XCTAssertTrue(
            SumiBackgroundMediaCardProjection.visibleStates(
                [globalState],
                in: windowState
            ).isEmpty
        )

        windowState.currentTabId = UUID()

        XCTAssertFalse(
            SumiBackgroundMediaCardProjection.visibleStates(
                [globalState],
                in: windowState
            ).isEmpty
        )
    }

    func testVisibleCardsExcludeSelectedSourceAndMaterializeAtMostThree() {
        let windowId = UUID()
        let selectedTabId = UUID()
        let window = BrowserWindowState(id: windowId)
        window.currentTabId = selectedTabId
        let tabIDs = [selectedTabId, UUID(), UUID(), UUID(), UUID()]
        let states = tabIDs.enumerated().map { index, tabID in
            SumiBackgroundMediaCardState(
                id: makeMediaCardID(
                    tabId: tabID,
                    windowId: windowId,
                    residenceGeneration: UInt64(index)
                ),
                tabId: tabID,
                windowId: windowId,
                title: "Card \(index)",
                subtitle: "",
                sourceHost: nil,
                tabTitle: "Card \(index)",
                playbackState: .playing,
                isMuted: false,
                faviconSource: nil,
                canPlayPause: true,
                canMute: true,
                canPictureInPicture: false
            )
        }

        let visible = SumiBackgroundMediaCardProjection.visibleStates(
            states,
            in: window
        )

        XCTAssertEqual(visible.count, 3)
        XCTAssertFalse(visible.contains(where: { $0.tabId == selectedTabId }))
        XCTAssertEqual(visible.map(\.tabId), Array(tabIDs[1...3]))
    }

    func testCardStateCarriesProfileScopedFaviconSource() async throws {
        let profileId = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let profile = Profile(id: profileId, name: "Media")
        let tab = Tab(
            url: try XCTUnwrap(URL(string: "https://media.example/watch")),
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profile.id
        tab.navigationRuntime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { id in id == profile.id ? profile : nil },
            spaceProfile: { _ in nil },
            currentProfile: { nil },
            firstProfile: { nil }
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))

        let windowState = BrowserWindowState()
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { context in context.candidateTabs() },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        let webView = PagePlaybackNowPlayingWebViewStub()
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { [(tab, windowState)] },
            windowState: { id in id == windowState.id ? windowState : nil },
            windowRegistry: { nil },
            resolvedTab: { tabId, _ in tabId == tab.id ? tab : nil },
            resolvedNowPlayingWebView: { _, _ in webView },
            selectTab: { _, _ in /* no-op */ }
        )

        controller.configure(context: context)
        await controller.refreshImmediately()

        let faviconSource = try XCTUnwrap(controller.cardStates.first?.faviconSource)
        XCTAssertEqual(faviconSource.documentURL, tab.url)
        XCTAssertEqual(faviconSource.partition, .regular(profile.id))
        XCTAssertTrue(controller.cardStates.first?.canPlayPause == true)

        controller.setFeatureEnabled(false)
    }

    func testRefreshDropsCandidateThatStopsBeforeInfoReturns() async {
        let tab = Tab(
            url: URL(string: "https://media.example/stale")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let windowState = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()
        var exposesCandidates = false
        var didBeginInfoRequest = false
        var releaseInfoRequest: CheckedContinuation<Void, Never>?

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in
                exposesCandidates ? [(tab, windowState)] : []
            },
            infoProvider: { _, _, _ in
                didBeginInfoRequest = true
                await withCheckedContinuation { continuation in
                    releaseInfoRequest = continuation
                }
                return SumiNativeNowPlayingInfo(
                    title: "Stale",
                    artist: nil,
                    playbackState: .playing,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { exposesCandidates ? [(tab, windowState)] : [] },
                tabs: [tab],
                windows: [windowState],
                webView: webView
            )
        )
        await Task.yield()

        exposesCandidates = true
        let refreshTask = Task { await controller.refreshImmediately() }
        while !didBeginInfoRequest {
            await Task.yield()
        }

        tab.applyAudioState(.unmuted(isPlayingAudio: false))
        webView.audioState = .unmuted(isPlayingAudio: false)
        releaseInfoRequest?.resume()
        await refreshTask.value

        XCTAssertTrue(controller.cardStates.isEmpty)
        controller.setFeatureEnabled(false)
    }

    func testRefreshDropsMetadataFromReplacedWebViewResidence() async {
        let tab = Tab(
            url: URL(string: "https://media.example/replaced")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let originalWebView = PagePlaybackNowPlayingWebViewStub()
        let replacementWebView = PagePlaybackNowPlayingWebViewStub()
        var resolvedWebView: any SumiNowPlayingWebViewAdapter = originalWebView
        var exposesCandidate = false
        var didBeginInfoRequest = false
        var releaseInfoRequest: CheckedContinuation<Void, Never>?

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in exposesCandidate ? [(tab, window)] : [] },
            infoProvider: { _, _, _ in
                didBeginInfoRequest = true
                await withCheckedContinuation { continuation in
                    releaseInfoRequest = continuation
                }
                return SumiNativeNowPlayingInfo(
                    title: "Stale residence",
                    artist: nil,
                    playbackState: .playing,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { exposesCandidate ? [(tab, window)] : [] },
            windowState: { id in id == window.id ? window : nil },
            windowRegistry: { nil },
            resolvedTab: { id, _ in id == tab.id ? tab : nil },
            resolvedNowPlayingWebView: { _, _ in resolvedWebView },
            selectTab: { _, _ in /* no-op */ }
        )
        controller.configure(context: context)
        await Task.yield()

        exposesCandidate = true
        let refreshTask = Task { await controller.refreshImmediately() }
        while !didBeginInfoRequest {
            await Task.yield()
        }
        resolvedWebView = replacementWebView
        releaseInfoRequest?.resume()
        await refreshTask.value

        XCTAssertTrue(controller.cardStates.isEmpty)
        controller.setFeatureEnabled(false)
    }

    func testUnloadedResidenceCannotReturnFromStaleRefresh() async {
        let tab = Tab(
            url: URL(string: "https://media.example/unloaded")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let originalWebView = PagePlaybackNowPlayingWebViewStub()
        let replacementWebView = PagePlaybackNowPlayingWebViewStub()
        var resolvedWebView: any SumiNowPlayingWebViewAdapter = originalWebView

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { [(tab, window)] },
            windowState: { id in id == window.id ? window : nil },
            windowRegistry: { nil },
            resolvedTab: { id, _ in id == tab.id ? tab : nil },
            resolvedNowPlayingWebView: { _, _ in resolvedWebView },
            selectTab: { _, _ in /* no-op */ }
        )
        controller.configure(context: context)
        await controller.refreshImmediately()
        XCTAssertFalse(controller.cardStates.isEmpty)

        controller.handleTabUnloaded(tab.id)
        await controller.refreshImmediately()

        XCTAssertTrue(controller.cardStates.isEmpty)

        resolvedWebView = replacementWebView
        await controller.refreshImmediately()

        XCTAssertFalse(controller.cardStates.isEmpty)
        controller.setFeatureEnabled(false)
    }

    func testLatePauseCompletionDoesNotPauseReplacementCard() async {
        let firstTab = Tab(
            url: URL(string: "https://media.example/first")!,
            loadsCachedFaviconOnInit: false
        )
        let replacementTab = Tab(
            url: URL(string: "https://media.example/replacement")!,
            loadsCachedFaviconOnInit: false
        )
        firstTab.applyAudioState(.unmuted(isPlayingAudio: true))
        let windowState = BrowserWindowState()
        let firstWebView = PagePlaybackNowPlayingWebViewStub()
        let replacementWebView = PagePlaybackNowPlayingWebViewStub(
            audioState: .unmuted(isPlayingAudio: false)
        )
        var exposesCandidates = false
        var didBeginPause = false
        var releasePause: CheckedContinuation<Void, Never>?

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in
                exposesCandidates
                    ? [(firstTab, windowState), (replacementTab, windowState)]
                    : []
            },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { command, _, _, _ in
                guard command == .pause else { return false }
                didBeginPause = true
                await withCheckedContinuation { continuation in
                    releasePause = continuation
                }
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: SumiNativeNowPlayingRuntimeContext(
                candidateTabs: {
                    exposesCandidates
                        ? [(firstTab, windowState), (replacementTab, windowState)]
                        : []
                },
                windowState: { id in id == windowState.id ? windowState : nil },
                windowRegistry: { nil },
                resolvedTab: { id, _ in
                    [firstTab, replacementTab].first(where: { $0.id == id })
                },
                resolvedNowPlayingWebView: { tab, _ in
                    tab === firstTab ? firstWebView : replacementWebView
                },
                selectTab: { _, _ in /* no-op */ }
            )
        )
        await Task.yield()

        exposesCandidates = true
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardStates.first?.tabId, firstTab.id)
        guard let firstCardID = controller.cardStates.first?.id else {
            return XCTFail("Expected the first media card")
        }

        let pauseTask = Task { await controller.togglePlayPause(cardID: firstCardID) }
        while !didBeginPause {
            await Task.yield()
        }

        firstTab.applyAudioState(.unmuted(isPlayingAudio: false))
        firstWebView.audioState = .unmuted(isPlayingAudio: false)
        replacementTab.applyAudioState(.unmuted(isPlayingAudio: true))
        replacementWebView.audioState = .unmuted(isPlayingAudio: true)
        await controller.refreshImmediately()
        XCTAssertEqual(
            controller.cardStates.first(where: { $0.tabId == firstTab.id })?.playbackState,
            .paused
        )
        XCTAssertEqual(
            controller.cardStates.first(where: { $0.tabId == replacementTab.id })?.playbackState,
            .playing
        )

        releasePause?.resume()
        await pauseTask.value

        XCTAssertEqual(
            controller.cardStates.first(where: { $0.tabId == replacementTab.id })?.playbackState,
            .playing
        )
        controller.setFeatureEnabled(false)
    }

    func testRefreshPublishesAllPlayingTabsNewestFirst() async {
        let oldest = Tab(
            url: URL(string: "https://media.example/oldest")!,
            loadsCachedFaviconOnInit: false
        )
        let newest = Tab(
            url: URL(string: "https://media.example/newest")!,
            loadsCachedFaviconOnInit: false
        )
        oldest.applyAudioState(.unmuted(isPlayingAudio: true))
        newest.applyAudioState(.unmuted(isPlayingAudio: true))
        oldest.mediaRuntime.lastMediaActivityAt = Date(timeIntervalSince1970: 1)
        newest.mediaRuntime.lastMediaActivityAt = Date(timeIntervalSince1970: 2)
        let window = BrowserWindowState()
        let tabs = [oldest, newest]

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in tabs.map { ($0, window) } },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { tabs.map { ($0, window) } },
                tabs: tabs,
                windows: [window]
            )
        )
        await Task.yield()

        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.map(\.tabId), [newest.id, oldest.id])
        XCTAssertEqual(Set(controller.cardStates.map(\.id)).count, 2)
        controller.setFeatureEnabled(false)
    }

    func testRefreshUsesOnlyResidenceReportingExactPlayback() async {
        let tab = Tab(
            url: URL(string: "https://media.example/residences")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let pausedWindow = BrowserWindowState()
        let playingWindow = BrowserWindowState()
        let pausedWebView = PagePlaybackNowPlayingWebViewStub(
            audioState: .unmuted(isPlayingAudio: false)
        )
        let playingWebView = PagePlaybackNowPlayingWebViewStub()
        let windows = [pausedWindow, playingWindow]

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in windows.map { (tab, $0) } },
            infoProvider: { _, _, window in
                SumiNativeNowPlayingInfo(
                    title: "Exact residence",
                    artist: nil,
                    playbackState: window === playingWindow ? .playing : .paused,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { windows.map { (tab, $0) } },
            windowState: { id in windows.first(where: { $0.id == id }) },
            windowRegistry: { nil },
            resolvedTab: { id, _ in id == tab.id ? tab : nil },
            resolvedNowPlayingWebView: { _, window in
                window === playingWindow ? playingWebView : pausedWebView
            },
            selectTab: { _, _ in /* no-op */ }
        )
        controller.configure(context: context)

        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.count, 1)
        XCTAssertEqual(controller.cardStates.first?.windowId, playingWindow.id)
        controller.setFeatureEnabled(false)
    }

    func testExactAudibleStateSelectsOnlyThePlayingResidence() async {
        let tab = Tab(
            url: URL(string: "https://media.example/visited-residence")!,
            loadsCachedFaviconOnInit: false
        )
        let visitedWindow = BrowserWindowState()
        let otherWindow = BrowserWindowState()
        visitedWindow.currentTabId = tab.id
        otherWindow.currentTabId = UUID()
        let visitedWebView = PagePlaybackNowPlayingWebViewStub()
        let otherWebView = PagePlaybackNowPlayingWebViewStub(
            audioState: .unmuted(isPlayingAudio: false)
        )
        let windows = [visitedWindow, otherWindow]

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in windows.map { (tab, $0) } },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Visited residence",
                    artist: nil,
                    playbackState: .paused,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: SumiNativeNowPlayingRuntimeContext(
                candidateTabs: { windows.map { (tab, $0) } },
                windowState: { id in windows.first(where: { $0.id == id }) },
                windowRegistry: { nil },
                resolvedTab: { id, _ in id == tab.id ? tab : nil },
                resolvedNowPlayingWebView: { _, window in
                    window === visitedWindow ? visitedWebView : otherWebView
                },
                selectTab: { _, _ in /* no-op */ }
            )
        )

        controller.handleTabActivated(tab.id, in: visitedWindow.id)
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        visitedWindow.currentTabId = UUID()
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.count, 1)
        XCTAssertEqual(controller.cardStates.first?.windowId, visitedWindow.id)
        XCTAssertEqual(controller.cardStates.first?.playbackState, .playing)
        controller.setFeatureEnabled(false)
    }

    func testDismissRemovesOnlyTargetUntilPlaybackStops() async {
        let dismissedTab = Tab(
            url: URL(string: "https://media.example/dismissed")!,
            loadsCachedFaviconOnInit: false
        )
        let retainedTab = Tab(
            url: URL(string: "https://media.example/retained")!,
            loadsCachedFaviconOnInit: false
        )
        dismissedTab.applyAudioState(.unmuted(isPlayingAudio: true))
        retainedTab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let tabs = [dismissedTab, retainedTab]

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in tabs.map { ($0, window) } },
            infoProvider: { tab, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Dismiss",
                    artist: nil,
                    playbackState: tab.audioState.isPlayingAudio ? .playing : .paused,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in command == .dismiss },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { tabs.map { ($0, window) } },
                tabs: tabs,
                windows: [window]
            )
        )
        await controller.refreshImmediately()
        guard let dismissedCardID = controller.cardStates
            .first(where: { $0.tabId == dismissedTab.id })?.id
        else {
            return XCTFail("Expected a dismissible card")
        }

        await controller.dismiss(cardID: dismissedCardID)
        await controller.refreshImmediately()
        await controller.refreshImmediately()

        XCTAssertNil(controller.cardStates.first(where: { $0.tabId == dismissedTab.id }))
        XCTAssertNotNil(controller.cardStates.first(where: { $0.tabId == retainedTab.id }))

        dismissedTab.applyAudioState(.unmuted(isPlayingAudio: false))
        await controller.refreshImmediately()
        dismissedTab.applyAudioState(.unmuted(isPlayingAudio: true))
        await controller.refreshImmediately()

        XCTAssertNotNil(controller.cardStates.first(where: { $0.tabId == dismissedTab.id }))
        controller.setFeatureEnabled(false)
    }

    func testDismissedCardReturnsWhenPlaybackRestartsBeforePausedRefresh() async {
        let tab = Tab(
            url: URL(string: "https://media.example/restarted-before-refresh")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Restarted",
                    artist: nil,
                    playbackState: tab.audioState.isPlayingAudio ? .playing : .paused,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in command == .dismiss },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window]
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a dismissible card")
        }

        await controller.dismiss(cardID: cardID)
        tab.applyAudioState(.unmuted(isPlayingAudio: false))
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.first?.tabId, tab.id)
        controller.setFeatureEnabled(false)
    }

    func testRevisitedDismissedTabNeedsANewAudibleEventToReturn() async {
        let tab = Tab(
            url: URL(string: "https://media.example/revisited")!,
            loadsCachedFaviconOnInit: false
        )
        let window = BrowserWindowState()
        let otherTabID = UUID()
        window.currentTabId = otherTabID
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        var reportedPlaybackState = SumiBackgroundMediaPlaybackState.playing

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Revisited",
                    artist: nil,
                    playbackState: reportedPlaybackState,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in command == .dismiss },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window]
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a dismissible card")
        }

        await controller.dismiss(cardID: cardID)
        window.currentTabId = tab.id
        controller.handleTabActivated(tab.id, in: window.id)
        tab.applyAudioState(.unmuted(isPlayingAudio: false))
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        reportedPlaybackState = .paused
        window.currentTabId = otherTabID
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.first?.tabId, tab.id)
        XCTAssertEqual(controller.cardStates.first?.playbackState, .playing)

        window.currentTabId = tab.id
        controller.handleTabActivated(tab.id, in: window.id)
        XCTAssertTrue(controller.cardStates.isEmpty)

        window.currentTabId = otherTabID
        await controller.refreshImmediately()

        XCTAssertTrue(controller.cardStates.isEmpty)
        controller.setFeatureEnabled(false)
    }

    func testExplicitPauseRemainsRetainedUntilAddressedResume() async {
        let tab = Tab(
            url: URL(string: "https://media.example/retained-pause")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        var commands: [String] = []

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { command, _, _, _ in
                switch command {
                case .pause: commands.append("pause")
                case .play: commands.append("play")
                case .setMuted: commands.append("mute")
                case .dismiss: commands.append("dismiss")
                case .pictureInPicture: commands.append("pip")
                }
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: PagePlaybackNowPlayingWebViewStub()
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }

        await controller.togglePlayPause(cardID: cardID)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.first?.playbackState, .paused)

        await controller.togglePlayPause(cardID: cardID)

        XCTAssertEqual(controller.cardStates.first?.playbackState, .playing)
        XCTAssertEqual(commands, ["pause", "play"])
        controller.setFeatureEnabled(false)
    }

    func testExplicitPausePreservesLastKnownArtistWhenNativeMetadataDropsIt() async {
        let tab = Tab(
            url: URL(string: "https://media.example/artist-after-pause")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()
        var reportedArtist: String? = "Artist"
        var reportedPlaybackState = SumiBackgroundMediaPlaybackState.playing

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Track",
                    artist: reportedArtist,
                    playbackState: reportedPlaybackState,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in
                guard command == .pause else { return false }
                reportedArtist = nil
                reportedPlaybackState = .paused
                webView.audioState = .unmuted(isPlayingAudio: false)
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: webView
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }
        XCTAssertEqual(controller.cardStates.first?.subtitle, "Artist")

        await controller.togglePlayPause(cardID: cardID)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.first?.playbackState, .paused)
        XCTAssertEqual(controller.cardStates.first?.subtitle, "Artist")
        controller.setFeatureEnabled(false)
    }

    func testExplicitPlayKeepsCardWhileNativeAudibilityCatchesUp() async {
        let tab = Tab(
            url: URL(string: "https://media.example/play-audibility-lag")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()
        var reportedPlaybackState = SumiBackgroundMediaPlaybackState.playing

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Track",
                    artist: "Artist",
                    playbackState: reportedPlaybackState,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in
                switch command {
                case .pause:
                    reportedPlaybackState = .paused
                    webView.audioState = .unmuted(isPlayingAudio: false)
                case .play:
                    reportedPlaybackState = .playing
                case .setMuted, .dismiss, .pictureInPicture:
                    return false
                }
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: webView
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }

        await controller.togglePlayPause(cardID: cardID)
        await controller.refreshImmediately()
        await controller.togglePlayPause(cardID: cardID)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.first?.id, cardID)
        XCTAssertEqual(controller.cardStates.first?.playbackState, .playing)
        controller.setFeatureEnabled(false)
    }

    func testActivatingPausedCardSourceDoesNotResumeMedia() async {
        let tab = Tab(
            url: URL(string: "https://media.example/paused-visit")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let otherTabID = UUID()
        window.currentTabId = otherTabID
        var reportedPlaybackState = SumiBackgroundMediaPlaybackState.playing
        var commands: [String] = []

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Paused visit",
                    artist: nil,
                    playbackState: reportedPlaybackState,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in
                switch command {
                case .pause:
                    commands.append("pause")
                    reportedPlaybackState = .paused
                case .play:
                    commands.append("play")
                    reportedPlaybackState = .playing
                case .setMuted:
                    commands.append("mute")
                case .dismiss:
                    commands.append("dismiss")
                case .pictureInPicture:
                    commands.append("pip")
                }
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window]
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }

        await controller.togglePlayPause(cardID: cardID)
        XCTAssertEqual(controller.cardStates.first?.playbackState, .paused)

        window.currentTabId = tab.id
        controller.handleTabActivated(tab.id, in: window.id)
        await Task.yield()

        XCTAssertEqual(reportedPlaybackState, .paused)
        XCTAssertEqual(commands, ["pause"])
        XCTAssertTrue(controller.cardStates.isEmpty)

        window.currentTabId = otherTabID
        await controller.refreshImmediately()

        XCTAssertTrue(controller.cardStates.isEmpty)
        XCTAssertEqual(commands, ["pause"])
        controller.setFeatureEnabled(false)
    }

    func testPagePlaybackAfterActivationReplacesMiniPlayerPauseRetention() async {
        let tab = Tab(
            url: URL(string: "https://media.example/page-resume")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let otherTabID = UUID()
        window.currentTabId = otherTabID
        let webView = PagePlaybackNowPlayingWebViewStub()
        var reportedPlaybackState = SumiBackgroundMediaPlaybackState.playing

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Page resume",
                    artist: "Artist",
                    playbackState: reportedPlaybackState,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in
                guard command == .pause else { return false }
                reportedPlaybackState = .paused
                tab.applyAudioState(.unmuted(isPlayingAudio: false))
                webView.audioState = .unmuted(isPlayingAudio: false)
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: webView
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }

        await controller.togglePlayPause(cardID: cardID)
        window.currentTabId = tab.id
        controller.handleTabActivated(tab.id, in: window.id)

        reportedPlaybackState = .playing
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        webView.audioState = .unmuted(isPlayingAudio: true)
        await controller.refreshImmediately()

        window.currentTabId = otherTabID
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.first?.id, cardID)
        XCTAssertEqual(controller.cardStates.first?.playbackState, .playing)
        controller.setFeatureEnabled(false)
    }

    func testActivatingDismissedCardSourceDoesNotResumeMedia() async {
        let tab = Tab(
            url: URL(string: "https://media.example/dismissed-visit")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        window.currentTabId = UUID()
        let webView = PagePlaybackNowPlayingWebViewStub()
        var reportedPlaybackState = SumiBackgroundMediaPlaybackState.playing
        var commands: [String] = []

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Dismissed visit",
                    artist: nil,
                    playbackState: reportedPlaybackState,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in
                switch command {
                case .dismiss:
                    commands.append("dismiss")
                    reportedPlaybackState = .paused
                    tab.applyAudioState(.unmuted(isPlayingAudio: false))
                    webView.audioState = .unmuted(isPlayingAudio: false)
                case .play:
                    commands.append("play")
                    reportedPlaybackState = .playing
                case .pause:
                    commands.append("pause")
                case .setMuted:
                    commands.append("mute")
                case .pictureInPicture:
                    commands.append("pip")
                }
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: webView
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }

        await controller.dismiss(cardID: cardID)
        XCTAssertEqual(reportedPlaybackState, .paused)
        XCTAssertEqual(commands, ["dismiss"])
        XCTAssertTrue(controller.cardStates.isEmpty)

        window.currentTabId = tab.id
        controller.handleTabActivated(tab.id, in: window.id)
        await Task.yield()

        XCTAssertEqual(reportedPlaybackState, .paused)
        XCTAssertEqual(commands, ["dismiss"])
        XCTAssertTrue(controller.cardStates.isEmpty)

        window.currentTabId = UUID()
        await controller.refreshImmediately()

        XCTAssertEqual(reportedPlaybackState, .paused)
        XCTAssertEqual(commands, ["dismiss"])
        XCTAssertTrue(controller.cardStates.isEmpty)
        controller.setFeatureEnabled(false)
    }

    func testMutedTabCannotCreateCardWithoutMiniPlayerMuteIntent() async {
        let tab = Tab(
            url: URL(string: "https://media.example/already-muted")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.muted(isPlayingAudio: true))
        let window = BrowserWindowState()

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Already muted",
                    artist: nil,
                    playbackState: .playing,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: PagePlaybackNowPlayingWebViewStub(
                    audioState: .muted(isPlayingAudio: true)
                )
            )
        )

        await controller.refreshImmediately()

        XCTAssertTrue(controller.cardStates.isEmpty)
        controller.setFeatureEnabled(false)
    }

    func testMiniPlayerMuteRetainsItsCard() async {
        let tab = Tab(
            url: URL(string: "https://media.example/card-muted")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Card muted",
                    artist: nil,
                    playbackState: .playing,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { command, _, _, _ in
                guard case .setMuted(let muted) = command else { return false }
                webView.audioState = webView.audioState.withMuted(muted)
                tab.applyAudioState(tab.audioState.withMuted(muted))
                return true
            },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: webView
            )
        )
        await controller.refreshImmediately()
        guard let cardID = controller.cardStates.first?.id else {
            return XCTFail("Expected a media card")
        }

        await controller.toggleMute(cardID: cardID)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardStates.first?.tabId, tab.id)
        XCTAssertEqual(controller.cardStates.first?.isMuted, true)
        controller.setFeatureEnabled(false)
    }

    func testExternalMuteRemovesExistingCard() async {
        let tab = Tab(
            url: URL(string: "https://media.example/externally-muted")!,
            loadsCachedFaviconOnInit: false
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [(tab, window)] },
            infoProvider: { _, _, _ in
                SumiNativeNowPlayingInfo(
                    title: "Externally muted",
                    artist: nil,
                    playbackState: .playing,
                    canPictureInPicture: false
                )
            },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: makeContext(
                candidates: { [(tab, window)] },
                tabs: [tab],
                windows: [window],
                webView: webView
            )
        )
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardStates.first?.tabId, tab.id)

        tab.applyAudioState(.muted(isPlayingAudio: true))
        webView.audioState = .muted(isPlayingAudio: true)
        await controller.refreshImmediately()

        XCTAssertTrue(controller.cardStates.isEmpty)
        controller.setFeatureEnabled(false)
    }

    func testRefreshSamplesOnlyExactAudibleResidences() async {
        let playing = Tab(
            url: URL(string: "https://media.example/playing")!,
            loadsCachedFaviconOnInit: false
        )
        let idle = Tab(
            url: URL(string: "https://media.example/idle")!,
            loadsCachedFaviconOnInit: false
        )
        playing.applyAudioState(.unmuted(isPlayingAudio: true))
        let window = BrowserWindowState()
        let tabs = [playing, idle]
        let playingWebView = PagePlaybackNowPlayingWebViewStub()
        let idleWebView = PagePlaybackNowPlayingWebViewStub(
            audioState: .unmuted(isPlayingAudio: false)
        )
        var resolvedTabIDs: [UUID] = []
        var sampledTabIDs: [UUID] = []

        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in tabs.map { ($0, window) } },
            infoProvider: { tab, _, _ in
                sampledTabIDs.append(tab.id)
                return nil
            },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )
        controller.configure(
            context: SumiNativeNowPlayingRuntimeContext(
                candidateTabs: { tabs.map { ($0, window) } },
                windowState: { id in id == window.id ? window : nil },
                windowRegistry: { nil },
                resolvedTab: { id, _ in tabs.first(where: { $0.id == id }) },
                resolvedNowPlayingWebView: { tab, _ in
                    resolvedTabIDs.append(tab.id)
                    return tab === playing ? playingWebView : idleWebView
                },
                selectTab: { _, _ in /* no-op */ }
            )
        )
        await Task.yield()
        resolvedTabIDs.removeAll()
        sampledTabIDs.removeAll()

        await controller.refreshImmediately()

        XCTAssertEqual(Set(resolvedTabIDs), Set(tabs.map(\.id)))
        XCTAssertEqual(sampledTabIDs, [playing.id])
        controller.setFeatureEnabled(false)
    }

    private func makeContext(
        candidates: @escaping @MainActor () -> [SumiNativeNowPlayingRuntimeContext.Candidate],
        tabs: [Tab],
        windows: [BrowserWindowState],
        webView: (any SumiNowPlayingWebViewAdapter)? = PagePlaybackNowPlayingWebViewStub()
    ) -> SumiNativeNowPlayingRuntimeContext {
        SumiNativeNowPlayingRuntimeContext(
            candidateTabs: candidates,
            windowState: { id in windows.first(where: { $0.id == id }) },
            windowRegistry: { nil },
            resolvedTab: { id, _ in tabs.first(where: { $0.id == id }) },
            resolvedNowPlayingWebView: { _, _ in webView },
            selectTab: { _, _ in /* no-op */ }
        )
    }
}

@MainActor
final class SumiNativeNowPlayingRuntimeContextTests: XCTestCase {
    func testRuntimeCandidatesSkipIncognitoAndIncludeWindowScopedTabs() {
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
        let webView = PagePlaybackNowPlayingWebViewStub()

        let context = SumiNativeNowPlayingRuntimeContext.live(
            runtime: SumiNativeNowPlayingBrowserRuntime(
                windowStates: { [regularWindow, fallbackWindow, incognitoWindow] },
                windowState: { _ in nil },
                windowRegistry: { nil },
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
                resolvedNowPlayingWebView: { _, _ in webView },
                selectTab: { _, _ in /* No-op. */ }
            )
        )

        let candidates = context.candidateTabs()

        XCTAssertEqual(
            candidates.map(\.tab.id),
            [pausedCandidate.id, playingTab.id, fallbackCurrentTab.id]
        )
        XCTAssertIdentical(candidates[0].windowState, regularWindow)
        XCTAssertIdentical(candidates[1].windowState, regularWindow)
        XCTAssertIdentical(candidates[2].windowState, fallbackWindow)
    }

    func testRuntimeCandidateDiscoveryPreservesDistinctWindowResidences() {
        let sharedPlayingTab = makeTab("https://example.com/shared")
        sharedPlayingTab.applyAudioState(.unmuted(isPlayingAudio: true))
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()

        let context = SumiNativeNowPlayingRuntimeContext.live(
            runtime: SumiNativeNowPlayingBrowserRuntime(
                windowStates: { [firstWindow, secondWindow] },
                windowState: { _ in nil },
                windowRegistry: { nil },
                currentTab: { _ in sharedPlayingTab },
                mediaCandidateTabs: { _ in [sharedPlayingTab] },
                tab: { _ in nil },
                resolvedNowPlayingWebView: { _, _ in webView },
                selectTab: { _, _ in /* No-op. */ }
            )
        )

        let candidates = context.candidateTabs()

        XCTAssertEqual(candidates.count, 2)
        XCTAssertIdentical(candidates[0].windowState, firstWindow)
        XCTAssertIdentical(candidates[1].windowState, secondWindow)
    }

    func testRuntimeResolvedTabUsesIncognitoEphemeralThenWindowCandidateThenTabLookup() {
        let ephemeralTab = makeTab("https://private.example/tab")
        let visibleCandidate = makeTab("https://example.com/visible")
        let lookupTab = makeTab("https://example.com/lookup")
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        incognitoWindow.replaceEphemeralTabs([ephemeralTab])
        let regularWindow = BrowserWindowState()

        let context = SumiNativeNowPlayingRuntimeContext.live(
            runtime: SumiNativeNowPlayingBrowserRuntime(
                windowStates: { [regularWindow, incognitoWindow] },
                windowState: { windowId in
                    if windowId == regularWindow.id { return regularWindow }
                    if windowId == incognitoWindow.id { return incognitoWindow }
                    return nil
                },
                windowRegistry: { nil },
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

    func testPlaybackCommandDoesNotSelectOrMaterializeMissingSourceWebView() async {
        let tab = makeTab("https://example.com/media")
        let window = BrowserWindowState()
        var selectionCount = 0
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { [] },
            windowState: { _ in window },
            windowRegistry: { nil },
            resolvedTab: { _, _ in tab },
            resolvedNowPlayingWebView: { _, _ in nil },
            selectTab: { _, _ in selectionCount += 1 }
        )

        let didPlay = await tab.setSumiNativeNowPlayingPlayback(
            .playing,
            using: context,
            in: window
        )
        let didPause = await tab.setSumiNativeNowPlayingPlayback(
            .paused,
            using: context,
            in: window
        )
        XCTAssertFalse(didPlay)
        XCTAssertFalse(didPause)
        XCTAssertEqual(selectionCount, 0)
    }

    func testPictureInPictureCommandUsesResolvedWebViewWithoutSelectingSource() async {
        let tab = makeTab("https://example.com/video")
        let window = BrowserWindowState()
        let webView = PictureInPictureNowPlayingWebViewStub(toggleResult: true)
        var selectionCount = 0
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { [] },
            windowState: { _ in window },
            windowRegistry: { nil },
            resolvedTab: { _, _ in tab },
            resolvedNowPlayingWebView: { _, _ in webView },
            selectTab: { _, _ in selectionCount += 1 }
        )

        let didToggle = await tab.toggleSumiNativePictureInPicture(
            using: context,
            in: window
        )

        XCTAssertTrue(didToggle)
        XCTAssertEqual(webView.togglePictureInPictureCallCount, 1)
        XCTAssertEqual(selectionCount, 0)
    }

    func testPlaybackCommandsUseResolvedPageMediaSessionWithoutSuspendingPage() async {
        let tab = makeTab("https://example.com/media")
        let window = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { [] },
            windowState: { _ in window },
            windowRegistry: { nil },
            resolvedTab: { _, _ in tab },
            resolvedNowPlayingWebView: { _, _ in webView },
            selectTab: { _, _ in XCTFail("Playback commands must not select the tab") }
        )

        let didPause = await tab.setSumiNativeNowPlayingPlayback(
            .paused,
            using: context,
            in: window
        )
        let didPlay = await tab.setSumiNativeNowPlayingPlayback(
            .playing,
            using: context,
            in: window
        )
        let didDismiss = await tab.dismissSumiNativeNowPlayingSession(
            using: context,
            in: window
        )

        XCTAssertTrue(didPause)
        XCTAssertTrue(didPlay)
        XCTAssertTrue(didDismiss)
        XCTAssertEqual(webView.playbackStates, [.paused, .playing, .paused])
    }

    func testMuteCommandChangesOnlyResolvedPageMediaSession() {
        let tab = makeTab("https://example.com/media")
        let window = BrowserWindowState()
        let webView = PagePlaybackNowPlayingWebViewStub()
        var broadcastMuteCommands: [(Bool, UUID)] = []
        var routing = TabWebViewRoutingRuntime.inactive
        routing.setMuteState = { muted, tabID in
            broadcastMuteCommands.append((muted, tabID))
        }
        tab.navigationRuntime.webViewRouting = routing
        let context = SumiNativeNowPlayingRuntimeContext(
            candidateTabs: { [] },
            windowState: { _ in window },
            windowRegistry: { nil },
            resolvedTab: { _, _ in tab },
            resolvedNowPlayingWebView: { _, _ in webView },
            selectTab: { _, _ in XCTFail("Mute must not select the tab") }
        )

        let didMute = tab.setSumiNativeNowPlayingMuted(
            true,
            using: context,
            in: window
        )

        XCTAssertTrue(didMute)
        XCTAssertTrue(webView.audioState.isMuted)
        XCTAssertTrue(tab.audioState.isMuted)
        XCTAssertTrue(
            broadcastMuteCommands.isEmpty,
            "An exact Page Media Session command must not mute sibling residences"
        )
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            loadsCachedFaviconOnInit: false
        )
    }
}

@MainActor
private final class PictureInPictureNowPlayingWebViewStub: SumiNowPlayingWebViewAdapter {
    private let toggleResult: Bool
    private(set) var togglePictureInPictureCallCount = 0
    private var audioState = SumiWebViewAudioState.unmuted(isPlayingAudio: true)

    var sumiNowPlayingAudioState: SumiWebViewAudioState {
        audioState
    }

    init(toggleResult: Bool) {
        self.toggleResult = toggleResult
    }

    func sumiRequestNowPlayingInfo() async -> SumiNativeNowPlayingInfo {
        SumiNativeNowPlayingInfo(
            title: "Video",
            artist: nil,
            playbackState: .playing,
            canPictureInPicture: true
        )
    }

    func sumiSetNowPlayingPlayback(_: SumiBackgroundMediaPlaybackState) async -> Bool { false }

    func sumiSetNowPlayingAudioMuted(_ muted: Bool) -> Bool {
        audioState = audioState.withMuted(muted)
        return true
    }

    func sumiTogglePictureInPicture() -> Bool {
        togglePictureInPictureCallCount += 1
        return toggleResult
    }
}

@MainActor
private final class PagePlaybackNowPlayingWebViewStub: SumiNowPlayingWebViewAdapter {
    private(set) var playbackStates: [SumiBackgroundMediaPlaybackState] = []
    var audioState: SumiWebViewAudioState

    init(audioState: SumiWebViewAudioState = .unmuted(isPlayingAudio: true)) {
        self.audioState = audioState
    }

    var sumiNowPlayingAudioState: SumiWebViewAudioState {
        audioState
    }

    func sumiRequestNowPlayingInfo() async -> SumiNativeNowPlayingInfo {
        SumiNativeNowPlayingInfo(
            title: "Media",
            artist: nil,
            playbackState: .playing,
            canPictureInPicture: false
        )
    }

    func sumiSetNowPlayingPlayback(
        _ playbackState: SumiBackgroundMediaPlaybackState
    ) async -> Bool {
        playbackStates.append(playbackState)
        return true
    }

    func sumiSetNowPlayingAudioMuted(_ muted: Bool) -> Bool {
        audioState = audioState.withMuted(muted)
        return true
    }

    func sumiTogglePictureInPicture() -> Bool { false }
}
