import XCTest

@testable import Sumi

@MainActor
final class TabRuntimeRoutingTests: XCTestCase {
    func testSetMutedUsesInjectedRoutingWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let routing = RecordingTabWebViewRouting()
        tab.webViewRoutingRuntime = routing.runtime

        tab.setMuted(true)

        XCTAssertEqual(routing.muteCalls, [.init(muted: true, tabId: tab.id)])
        XCTAssertTrue(tab.audioState.isMuted)
    }

    func testRefreshUsesInjectedRoutingWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            loadsCachedFaviconOnInit: false
        )
        let routing = RecordingTabWebViewRouting()
        tab.webViewRoutingRuntime = routing.runtime

        tab.navigationCommandOwner.refresh(tab)

        XCTAssertEqual(routing.reloadCalls, [tab.id])
    }

    func testAudioStateUsesInjectedMediaCallbacksWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let callbacks = RecordingTabMediaCallbacks()
        tab.mediaRuntimeCallbacks = callbacks.runtime

        tab.applyAudioState(.unmuted(isPlayingAudio: true))

        XCTAssertEqual(callbacks.nowPlayingRefreshDelays, [0])
        XCTAssertEqual(callbacks.backgroundMediaReasons, ["tab-audio-state-changed"])
    }

    func testUnloadWebViewUsesInjectedMediaCallbacksWithoutBrowserManager() {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let callbacks = RecordingTabMediaCallbacks()
        tab.mediaRuntimeCallbacks = callbacks.runtime

        tab.unloadWebView()

        XCTAssertEqual(callbacks.unloadedTabIds, [tab.id])
    }

    func testTitleUpdateUsesInjectedPersistenceWithoutBrowserManager() {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            name: "Original",
            loadsCachedFaviconOnInit: false
        )
        let persistence = RecordingTabPersistenceCallbacks()
        tab.persistenceRuntimeCallbacks = persistence.runtime

        XCTAssertTrue(tab.acceptResolvedDisplayTitle("Updated"))

        XCTAssertEqual(persistence.persistedTabIds, [tab.id])
    }
}

@MainActor
private final class RecordingTabWebViewRouting {
    struct MuteCall: Equatable {
        let muted: Bool
        let tabId: UUID
    }

    private(set) var syncCalls: [(UUID, ObjectIdentifier?)] = []
    private(set) var reloadCalls: [UUID] = []
    private(set) var muteCalls: [MuteCall] = []

    var runtime: TabWebViewRoutingRuntime {
        TabWebViewRoutingRuntime(
            syncTabAcrossWindows: { [weak self] tabId, webView in
                self?.syncCalls.append(
                    (tabId, webView.map(ObjectIdentifier.init))
                )
            },
            reloadTabAcrossWindows: { [weak self] tabId in
                self?.reloadCalls.append(tabId)
            },
            setMuteState: { [weak self] muted, tabId in
                self?.muteCalls.append(.init(muted: muted, tabId: tabId))
            }
        )
    }
}

@MainActor
private final class RecordingTabMediaCallbacks {
    private(set) var nowPlayingRefreshDelays: [UInt64] = []
    private(set) var backgroundMediaReasons: [String] = []
    private(set) var unloadedTabIds: [UUID] = []

    var runtime: TabMediaRuntimeCallbacks {
        TabMediaRuntimeCallbacks(
            scheduleNowPlayingRefresh: { [weak self] delay in
                self?.nowPlayingRefreshDelays.append(delay)
            },
            scheduleBackgroundMediaReconcile: { [weak self] reason in
                self?.backgroundMediaReasons.append(reason)
            },
            notifyNowPlayingTabUnloaded: { [weak self] tabId in
                self?.unloadedTabIds.append(tabId)
            }
        )
    }
}

@MainActor
private final class RecordingTabPersistenceCallbacks {
    private(set) var navigationStateTabIds: [UUID] = []
    private(set) var persistedTabIds: [UUID] = []

    var runtime: TabRuntimePersistenceCallbacks {
        TabRuntimePersistenceCallbacks(
            updateNavigationState: { [weak self] tab in
                self?.navigationStateTabIds.append(tab.id)
            },
            scheduleRuntimeStatePersistence: { [weak self] tab in
                self?.persistedTabIds.append(tab.id)
            }
        )
    }
}
