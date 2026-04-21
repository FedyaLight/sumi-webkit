import XCTest
@testable import Sumi

@MainActor
final class SumiNativeNowPlayingControllerTests: XCTestCase {
    func testOnlyBackgroundNonIncognitoTabsBecomeOwner() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let regularWindow = BrowserWindowState(id: UUID())
        let incognitoWindow = BrowserWindowState(id: UUID())
        incognitoWindow.isIncognito = true
        windowRegistry.register(regularWindow)
        windowRegistry.register(incognitoWindow)

        let foreground = makeTab(name: "Foreground", url: "https://sumi.example/front")
        let background = makeTab(name: "Background", url: "https://sumi.example/back")
        let privateTab = makeTab(name: "Private", url: "https://private.example")

        foreground.lastMediaActivityAt = Date(timeIntervalSince1970: 10)
        background.lastMediaActivityAt = Date(timeIntervalSince1970: 20)
        privateTab.lastMediaActivityAt = Date(timeIntervalSince1970: 30)

        attachRegularTabs(
            [foreground, background],
            currentTabId: foreground.id,
            to: regularWindow,
            browserManager: browserManager
        )
        incognitoWindow.ephemeralTabs = [privateTab]
        incognitoWindow.currentTabId = privateTab.id

        let info = activeInfo(title: "Sumi Song")
        let controller = makeController(
            infoProvider: { tab, _, _ in
                switch tab.id {
                case foreground.id, background.id, privateTab.id:
                    return info
                default:
                    return nil
                }
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, background.id)
        XCTAssertEqual(controller.cardState?.id, "sumi:\(background.id.uuidString)")
    }

    func testForegroundOwnerDoesNotRenderCard() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let foreground = makeTab(name: "Foreground", url: "https://sumi.example/front")
        foreground.lastMediaActivityAt = Date()

        attachRegularTabs(
            [foreground],
            currentTabId: foreground.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { _, _, _ in self.activeInfo(title: "Foreground Track") }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testBackgroundShortcutLiveTabCanOwnCard() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let space = browserManager.tabManager.createSpace(name: "Media")
        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        current.applyAudioState(.unmuted(isPlayingAudio: false))
        current.spaceId = space.id
        browserManager.tabManager.addTab(current)

        let source = makeTab(name: "Launcher", url: "https://music.example/launch")
        source.applyAudioState(.unmuted(isPlayingAudio: false))
        source.spaceId = space.id
        browserManager.tabManager.addTab(source)
        let pin = browserManager.tabManager.ensureSpacePinnedLauncher(for: source, in: space.id)!
        let liveTab = browserManager.tabManager.activateShortcutPin(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )
        liveTab.applyAudioState(.unmuted(isPlayingAudio: true))
        liveTab.lastMediaActivityAt = Date(timeIntervalSince1970: 40)

        windowState.currentSpaceId = space.id
        windowState.currentTabId = current.id
        windowState.currentShortcutPinId = nil

        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == liveTab.id ? self.activeInfo(title: "Shortcut Audio") : nil
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, liveTab.id)
    }

    func testMutedPlayingBackgroundTabCanOwnCard() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let mutedOwner = makeTab(name: "Muted", url: "https://sumi.example/muted")
        mutedOwner.applyAudioState(.muted(isPlayingAudio: true))
        mutedOwner.lastMediaActivityAt = Date(timeIntervalSince1970: 50)

        attachRegularTabs(
            [current, mutedOwner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == mutedOwner.id ? self.activeInfo(title: "Muted Track") : nil
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, mutedOwner.id)
        XCTAssertEqual(controller.cardState?.isMuted, true)
        XCTAssertEqual(controller.cardState?.canMute, true)
    }

    func testTiesPreferMostRecentMediaActivity() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let older = makeTab(name: "Older", url: "https://sumi.example/older")
        let newer = makeTab(name: "Newer", url: "https://sumi.example/newer")

        older.lastMediaActivityAt = Date(timeIntervalSince1970: 100)
        newer.lastMediaActivityAt = Date(timeIntervalSince1970: 200)

        attachRegularTabs(
            [current, older, newer],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == current.id ? nil : self.activeInfo(title: tab.name)
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, newer.id)
        XCTAssertEqual(controller.cardState?.title, "Newer")
    }

    func testCardIdentityStaysStableWhenNativeMetadataChanges() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var currentTitle = "Owner"
        let controller = makeController(
            infoProvider: { tab, _, _ in
                guard tab.id == owner.id else { return nil }
                return SumiNativeNowPlayingInfo(
                    title: currentTitle,
                    artist: "Artist",
                    playbackState: .playing
                )
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        let firstId = controller.cardState?.id

        currentTitle = "Owner Updated"
        await controller.refreshImmediately()
        let secondId = controller.cardState?.id

        XCTAssertEqual(firstId, "sumi:\(owner.id.uuidString)")
        XCTAssertEqual(secondId, firstId)
    }

    func testMuteFromCardFollowsTabAudioStateWithoutRetention() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var currentInfo: SumiNativeNowPlayingInfo? = activeInfo(title: "Owner")
        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? currentInfo : nil
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.tabId, owner.id)

        await controller.toggleMute()
        XCTAssertEqual(controller.cardState?.isMuted, true)
        owner.applyAudioState(.muted(isPlayingAudio: false))
        currentInfo = nil

        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testWebKitAudioStateCreatesPlayingCardEvenWhenNativePlaybackStateIsPaused() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()
        owner.applyAudioState(.unmuted(isPlayingAudio: true))

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                guard tab.id == owner.id else { return nil }
                return self.activeInfo(
                    title: "Owner",
                    playbackState: .paused
                )
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, owner.id)
        XCTAssertEqual(controller.cardState?.playbackState, .playing)
    }

    func testWebKitAudioStateCreatesFallbackCardWhenNativeSnapshotIsMissing() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.applyAudioState(.unmuted(isPlayingAudio: true))
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { _, _, _ in nil }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, owner.id)
        XCTAssertEqual(controller.cardState?.title, "Owner")
        XCTAssertEqual(controller.cardState?.playbackState, .playing)
    }

    func testMutedOutsideCardDoesNotKeepCardVisible() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var currentInfo: SumiNativeNowPlayingInfo? = activeInfo(title: "Owner")
        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? currentInfo : nil
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.tabId, owner.id)

        owner.applyAudioState(.muted(isPlayingAudio: false))
        owner.lastMediaActivityAt = Date()
        currentInfo = nil

        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testInvalidOwnerClearsImmediatelyWithoutGraceRetention() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var currentInfo: SumiNativeNowPlayingInfo? = activeInfo(title: "Owner")
        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? currentInfo : nil
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.tabId, owner.id)

        currentInfo = activeInfo(
            title: "Owner",
            playbackState: .paused
        )
        owner.applyAudioState(.unmuted(isPlayingAudio: false))

        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testPausedBackgroundTabDoesNotRenderCardWithoutCardOwnedPause() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let pausedOwner = makeTab(name: "Paused", url: "https://sumi.example/paused")
        pausedOwner.lastMediaActivityAt = Date()
        pausedOwner.applyAudioState(.unmuted(isPlayingAudio: false))

        attachRegularTabs(
            [current, pausedOwner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                guard tab.id == pausedOwner.id else { return nil }
                return self.activeInfo(
                    title: "Paused",
                    playbackState: .playing
                )
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testNativePlayingSessionWithoutWebKitAudioDoesNotRenderCard() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.applyAudioState(.unmuted(isPlayingAudio: false))
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                guard tab.id == owner.id else { return nil }
                return self.activeInfo(
                    title: "Owner",
                    playbackState: .playing
                )
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testWebKitAudioStateRendersCardWhenNativePlaybackStateIsPlaying() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.applyAudioState(.unmuted(isPlayingAudio: true))
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                guard tab.id == owner.id else { return nil }
                return self.activeInfo(
                    title: "Owner",
                    playbackState: .playing
                )
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, owner.id)
        XCTAssertEqual(controller.cardState?.playbackState, .playing)
    }

    func testPauseFromCardKeepsPausedCardVisible() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var currentInfo: SumiNativeNowPlayingInfo? = activeInfo(title: "Owner")
        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? currentInfo : nil
            },
            commandExecutor: { command, tab, _, _ in
                guard tab.id == owner.id else { return false }
                if command == .pause {
                    currentInfo = self.activeInfo(title: "Owner", playbackState: .paused)
                } else {
                    currentInfo = self.activeInfo(title: "Owner", playbackState: .playing)
                }
                return true
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.playbackState, .playing)

        await controller.togglePlayPause()
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, owner.id)
        XCTAssertEqual(controller.cardState?.playbackState, .paused)
        XCTAssertEqual(controller.cardState?.canMute, false)
    }

    func testPauseFromCardKeepsCardVisibleWhenSessionBecomesInactive() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var currentInfo: SumiNativeNowPlayingInfo? = activeInfo(title: "Owner")
        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? currentInfo : nil
            },
            commandExecutor: { command, tab, _, _ in
                guard command == .pause, tab.id == owner.id else { return false }
                owner.applyAudioState(.unmuted(isPlayingAudio: false))
                currentInfo = SumiNativeNowPlayingInfo(
                    title: "Owner",
                    artist: "Artist",
                    playbackState: .paused
                )
                return true
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.playbackState, .playing)

        await controller.togglePlayPause()
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, owner.id)
        XCTAssertEqual(controller.cardState?.playbackState, .paused)
        XCTAssertEqual(controller.cardState?.canMute, false)
    }

    func testPauseFromCardKeepsPausedIconEvenWhenNativeSnapshotIsStalePlaying() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                guard tab.id == owner.id else { return nil }
                return self.activeInfo(title: "Owner", playbackState: .playing)
            },
            commandExecutor: { command, tab, _, _ in
                command == .pause && tab.id == owner.id
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.playbackState, .playing)

        await controller.togglePlayPause()
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, owner.id)
        XCTAssertEqual(controller.cardState?.playbackState, .paused)
    }

    func testFreshPlayingTabReplacesPausedRetainedCard() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        current.applyAudioState(.unmuted(isPlayingAudio: false))
        let pausedOwner = makeTab(name: "Paused Owner", url: "https://sumi.example/paused")
        let freshOwner = makeTab(name: "Fresh Owner", url: "https://sumi.example/fresh")
        pausedOwner.lastMediaActivityAt = Date(timeIntervalSince1970: 100)
        freshOwner.applyAudioState(.unmuted(isPlayingAudio: false))
        freshOwner.lastMediaActivityAt = Date(timeIntervalSince1970: 50)

        attachRegularTabs(
            [current, pausedOwner, freshOwner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var pausedInfo: SumiNativeNowPlayingInfo? = activeInfo(title: "Paused Owner")
        var freshInfo: SumiNativeNowPlayingInfo? = nil
        let controller = makeController(
            infoProvider: { tab, _, _ in
                switch tab.id {
                case pausedOwner.id:
                    return pausedInfo
                case freshOwner.id:
                    return freshInfo
                default:
                    return nil
                }
            },
            commandExecutor: { command, tab, _, _ in
                guard command == .pause, tab.id == pausedOwner.id else { return false }
                pausedOwner.applyAudioState(.unmuted(isPlayingAudio: false))
                pausedInfo = SumiNativeNowPlayingInfo(
                    title: "Paused Owner",
                    artist: "Artist",
                    playbackState: .paused
                )
                return true
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.tabId, pausedOwner.id)

        await controller.togglePlayPause()
        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, pausedOwner.id)
        XCTAssertEqual(controller.cardState?.playbackState, .paused)

        freshOwner.applyAudioState(.unmuted(isPlayingAudio: true))
        freshOwner.lastMediaActivityAt = Date(timeIntervalSince1970: 200)
        freshInfo = activeInfo(title: "Fresh Owner")

        await controller.refreshImmediately()

        XCTAssertEqual(controller.cardState?.tabId, freshOwner.id)
        XCTAssertEqual(controller.cardState?.playbackState, .playing)
    }

    func testUnloadingCurrentMediaOwnerClearsCard() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        current.applyAudioState(.unmuted(isPlayingAudio: false))
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? self.activeInfo(title: "Owner") : nil
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.tabId, owner.id)

        owner.resetPlaybackActivity()
        controller.handleTabUnloaded(owner.id)
        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testUnloadingPausedRetainedOwnerClearsCard() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        current.applyAudioState(.unmuted(isPlayingAudio: false))
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var currentInfo: SumiNativeNowPlayingInfo? = activeInfo(title: "Owner")
        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? currentInfo : nil
            },
            commandExecutor: { command, tab, _, _ in
                guard command == .pause, tab.id == owner.id else { return false }
                owner.applyAudioState(.unmuted(isPlayingAudio: false))
                currentInfo = SumiNativeNowPlayingInfo(
                    title: "Owner",
                    artist: "Artist",
                    playbackState: .paused
                )
                return true
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.tabId, owner.id)

        await controller.togglePlayPause()
        await controller.refreshImmediately()
        XCTAssertEqual(controller.cardState?.playbackState, .paused)

        owner.resetPlaybackActivity()
        controller.handleTabUnloaded(owner.id)
        await controller.refreshImmediately()

        XCTAssertNil(controller.cardState)
    }

    func testActivateOwnerRoutesToExactTabAndWindow() async {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState(id: UUID())
        windowRegistry.register(windowState)

        let current = makeTab(name: "Current", url: "https://sumi.example/current")
        let owner = makeTab(name: "Owner", url: "https://sumi.example/owner")
        owner.lastMediaActivityAt = Date()

        attachRegularTabs(
            [current, owner],
            currentTabId: current.id,
            to: windowState,
            browserManager: browserManager
        )

        var activated: (tabId: UUID, windowId: UUID)?
        let controller = makeController(
            infoProvider: { tab, _, _ in
                tab.id == owner.id ? self.activeInfo(title: "Owner") : nil
            },
            activationHandler: { tab, _, targetWindow in
                activated = (tab.id, targetWindow.id)
            }
        )

        controller.configure(browserManager: browserManager)
        await controller.refreshImmediately()
        controller.activateOwner()

        XCTAssertEqual(activated?.tabId, owner.id)
        XCTAssertEqual(activated?.windowId, windowState.id)
    }

    private func makeController(
        infoProvider: @escaping SumiNativeNowPlayingController.InfoProvider,
        commandExecutor: @escaping SumiNativeNowPlayingController.CommandExecutor = { _, _, _, _ in true },
        activationHandler: @escaping SumiNativeNowPlayingController.ActivationHandler = { _, _, _ in }
    ) -> SumiNativeNowPlayingController {
        SumiNativeNowPlayingController(
            candidateProvider: { browserManager in
                guard let windowRegistry = browserManager.windowRegistry else { return [] }

                var candidates: [SumiNativeNowPlayingController.Candidate] = []
                for windowState in windowRegistry.windows.values {
                    if windowState.isIncognito {
                        candidates.append(contentsOf: windowState.ephemeralTabs.map { ($0, windowState) })
                    } else {
                        candidates.append(contentsOf: browserManager.windowScopedMediaCandidateTabs(in: windowState).map { ($0, windowState) })
                    }
                }
                return candidates
            },
            infoProvider: infoProvider,
            commandExecutor: commandExecutor,
            activationHandler: activationHandler
        )
    }

    private func makeTab(name: String, url: String) -> Tab {
        let tab = Tab(
            id: UUID(),
            url: URL(string: url)!,
            name: name,
            index: 0
        )
        tab.applyAudioState(.unmuted(isPlayingAudio: true))
        return tab
    }

    private func attachRegularTabs(
        _ tabs: [Tab],
        currentTabId: UUID,
        to windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) {
        let space = Space(name: "Media Space")
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space
        browserManager.tabManager.tabsBySpace[space.id] = tabs
        windowState.currentSpaceId = space.id
        windowState.currentTabId = currentTabId

        for (index, tab) in tabs.enumerated() {
            tab.spaceId = space.id
            tab.index = index
            tab.browserManager = browserManager
        }
    }

    private func activeInfo(title: String) -> SumiNativeNowPlayingInfo {
        SumiNativeNowPlayingInfo(
            title: title,
            artist: "Artist",
            playbackState: .playing
        )
    }

    private func activeInfo(
        title: String,
        playbackState: SumiBackgroundMediaPlaybackState
    ) -> SumiNativeNowPlayingInfo {
        SumiNativeNowPlayingInfo(
            title: title,
            artist: "Artist",
            playbackState: playbackState
        )
    }
}
