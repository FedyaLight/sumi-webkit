import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WindowSessionRegistrationTests: XCTestCase {
    func testPreparedWindowDoesNotPublishExtensionLifecycleBeforeRegistryCommit()
        throws {
        let fixture = try makeFixture()
        let windowState = BrowserWindowState()
        fixture.registration.prepareRegistration(windowState)
        let tab = Tab(url: URL(string: "https://initial.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        windowState.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: windowState,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        fixture.extensions.onOpen = { publishedWindow in
            XCTAssertIdentical(publishedWindow, windowState)
            XCTAssertEqual(publishedWindow.currentTabId, tab.id)
            XCTAssertTrue(receipt.validateBeforeWindowPublication())
            XCTAssertEqual(events.values, ["window"])
        }

        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: windowState,
                reason: "test"
            ),
            .extensionPrepared
        )
        XCTAssertTrue(
            fixture.extensionPublication
                .validateStagedInitialTab(
                    tab,
                    webView: webView,
                    in: windowState
                )
        )
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
        XCTAssertEqual(receipt.publishCount, 0)

        fixture.registration.commitRegistration(windowState)

        XCTAssertEqual(events.values, ["window", "tab"])
        XCTAssertEqual(receipt.publishCount, 1)
        XCTAssertEqual(receipt.cancelCount, 0)
    }

    func testRejectedWindowCancelsInitialTabWithoutPublishingEvents() throws {
        let fixture = try makeFixture()
        let windowState = BrowserWindowState()
        fixture.registration.prepareRegistration(windowState)
        let tab = Tab(url: URL(string: "https://rollback.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        windowState.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: windowState,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: windowState,
                reason: "test"
            ),
            .extensionPrepared
        )

        fixture.registration.discardRegistration(windowState)

        XCTAssertTrue(events.values.isEmpty)
        XCTAssertEqual(receipt.cancelCount, 1)
        XCTAssertEqual(receipt.publishCount, 0)
    }

    func testFailedTabPublicationRevokesWindowWithoutPreconditionCrash() throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://reentrant.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        receipt.publishes = false
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)

        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: "test"
            ),
            .extensionPrepared
        )
        fixture.registration.commitRegistration(window)

        XCTAssertEqual(events.values, ["window", "window-revoked"])
        XCTAssertEqual(fixture.extensions.revokedWindowIDs, [window.id])
        XCTAssertEqual(
            fixture.extensionPublication.initialPublicationResult(for: window),
            .suppressed
        )
        XCTAssertEqual(receipt.cancelCount, 1)
    }

    func testRuntimeJoiningBetweenStageAndCommitRestagesBeforeWindowEvent() throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://late-runtime.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .notParticipating

        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: "test"
            ),
            .nativeOnly
        )

        let receipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        fixture.registration.commitRegistration(window)

        XCTAssertEqual(events.values, ["window", "tab"])
        XCTAssertEqual(
            fixture.extensionPublication.initialPublicationResult(for: window),
            .extensionPublished
        )
    }

    func testReentrantRestageReceiptCannotBeRemovedWithoutPublishOrCancellation()
        throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://nested-restage.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .notParticipating
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: "test-native-stage"
            ),
            .nativeOnly
        )

        let outerReceipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        let nestedReceipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.initialTabPreparation = .prepared(outerReceipt)
        var didInjectNestedStage = false
        fixture.extensions.onPrepare = { preparedWindow in
            guard didInjectNestedStage == false else { return }
            didInjectNestedStage = true
            fixture.extensions.initialTabPreparation = .prepared(nestedReceipt)
            XCTAssertEqual(
                fixture.extensionPublication.stageInitialTab(
                    tab,
                    webView: webView,
                    in: preparedWindow,
                    reason: "test-nested-restage"
                ),
                .extensionPrepared
            )
        }

        fixture.registration.commitRegistration(window)

        XCTAssertTrue(didInjectNestedStage)
        XCTAssertEqual(outerReceipt.cancelCount, 1)
        XCTAssertEqual(
            nestedReceipt.publishCount + nestedReceipt.cancelCount,
            1,
            "Every prepared receipt must be consumed or rolled back exactly once"
        )
    }

    func testReentrantDiscardDuringInitialTabPreparationCannotResurrectPendingReceipt()
        throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://prepare-reentrancy.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        fixture.extensions.onPrepare = { preparedWindow in
            XCTAssertIdentical(preparedWindow, window)
            fixture.registration.discardRegistration(window)
        }

        let staging = fixture.extensionPublication.stageInitialTab(
            tab,
            webView: webView,
            in: window,
            reason: "test-reentrant-preparation"
        )
        fixture.registration.commitRegistration(window)

        XCTAssertEqual(staging, .rejected)
        XCTAssertEqual(receipt.cancelCount, 1)
        XCTAssertEqual(receipt.publishCount, 0)
        XCTAssertTrue(events.values.isEmpty)
        XCTAssertNil(
            fixture.extensionPublication.initialPublicationResult(for: window)
        )
    }

    func testReentrantDiscardDuringInitialTabCallbackCannotPublishStaleCommitResult()
        throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://publish-reentrancy.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        receipt.onPublish = {
            fixture.registration.discardRegistration(window)
        }
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: "test-reentrant-publication"
            ),
            .extensionPrepared
        )

        fixture.registration.commitRegistration(window)

        XCTAssertEqual(
            events.values,
            ["window", "tab", "tab-revoked", "window-revoked"]
        )
        XCTAssertEqual(receipt.publishCount, 1)
        XCTAssertEqual(receipt.revokeCount, 1)
        XCTAssertNil(
            fixture.extensionPublication.initialPublicationResult(for: window),
            "A close/discard from the synchronous Tab callback must remain authoritative"
        )
    }

    func testRuntimeTeardownDuringInitialTabCallbackCannotLeavePublishedCommitResult()
        throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://runtime-teardown.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        receipt.onPublish = {
            fixture.extensions.isPublicationCurrent = false
        }
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: "test-runtime-teardown"
            ),
            .extensionPrepared
        )

        fixture.registration.commitRegistration(window)

        XCTAssertEqual(
            events.values,
            ["window", "tab", "tab-revoked", "window-revoked"]
        )
        XCTAssertEqual(fixture.extensions.revokedWindowIDs, [window.id])
        XCTAssertEqual(receipt.revokeCount, 1)
        XCTAssertEqual(
            fixture.extensionPublication.initialPublicationResult(for: window),
            .suppressed
        )
    }

    func testRegistryRepairBalancesExactTabBeforeWindowPublication() throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://repair.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: "test-registry-repair"
            ),
            .extensionPrepared
        )
        fixture.registration.commitRegistration(window)

        fixture.extensionPublication.discardRegistrations(notIn: [])

        XCTAssertEqual(
            events.values,
            ["window", "tab", "tab-revoked", "window-revoked"]
        )
        XCTAssertEqual(receipt.revokeCount, 1)
        XCTAssertNil(
            fixture.extensionPublication.initialPublicationResult(for: window)
        )
    }

    func testPreparingExactCommittedWindowIsIdempotentUntilRegistryRepair()
        throws {
        let fixture = try makeFixture()
        let window = BrowserWindowState()
        fixture.registration.prepareRegistration(window)
        let tab = Tab(url: URL(string: "https://idempotent.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.currentTabId = tab.id
        let events = ExtensionPublicationEventRecorder()
        let receipt = RecordingInitialTabPublication(
            window: window,
            tab: tab,
            webView: webView,
            events: events
        )
        fixture.extensions.events = events
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: "test-idempotent-prepare"
            ),
            .extensionPrepared
        )
        fixture.registration.commitRegistration(window)

        fixture.extensionPublication.prepareRegistration(window)
        XCTAssertEqual(
            fixture.extensionPublication.initialPublicationResult(for: window),
            .extensionPublished
        )
        fixture.extensionPublication.discardRegistrations(notIn: [])

        XCTAssertEqual(
            events.values,
            ["window", "tab", "tab-revoked", "window-revoked"]
        )
        XCTAssertEqual(receipt.revokeCount, 1)
        XCTAssertNil(
            fixture.extensionPublication.initialPublicationResult(for: window)
        )
    }

    func testUUIDImpostorCannotCancelExactInitialTabReceipt() throws {
        let fixture = try makeFixture()
        let original = BrowserWindowState()
        fixture.registration.prepareRegistration(original)
        let tab = Tab(url: URL(string: "https://identity.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        original.currentTabId = tab.id
        let receipt = RecordingInitialTabPublication(
            window: original,
            tab: tab,
            webView: webView,
            events: ExtensionPublicationEventRecorder()
        )
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: original,
                reason: "test"
            ),
            .extensionPrepared
        )

        fixture.registration.discardRegistration(
            BrowserWindowState(id: original.id)
        )

        XCTAssertEqual(receipt.cancelCount, 0)
        fixture.registration.discardRegistration(original)
        XCTAssertEqual(receipt.cancelCount, 1)
    }

    func testUUIDImpostorCannotReplacePendingInitialTabReceipt() throws {
        let fixture = try makeFixture()
        let sharedID = UUID()
        let original = BrowserWindowState(id: sharedID)
        let impostor = BrowserWindowState(id: sharedID)
        fixture.extensionPublication.prepareRegistration(original)
        let tab = Tab(url: URL(string: "https://pending-identity.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        original.currentTabId = tab.id
        let receipt = RecordingInitialTabPublication(
            window: original,
            tab: tab,
            webView: webView,
            events: ExtensionPublicationEventRecorder()
        )
        fixture.extensions.initialTabPreparation = .prepared(receipt)
        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: original,
                reason: "test-pending-identity"
            ),
            .extensionPrepared
        )

        fixture.extensionPublication.prepareRegistration(impostor)

        XCTAssertTrue(
            fixture.extensionPublication.validateStagedInitialTab(
                tab,
                webView: webView,
                in: original
            )
        )
        fixture.extensionPublication.discardRegistration(original)
        XCTAssertEqual(receipt.cancelCount, 1)
    }

    func testSuppressedInitialTabPublishesNoExtensionWindowOrTab() throws {
        let fixture = try makeFixture()
        let windowState = BrowserWindowState()
        fixture.registration.prepareRegistration(windowState)
        let tab = Tab(url: URL(string: "https://cross-profile.example")!)
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        windowState.currentTabId = tab.id
        fixture.extensions.initialTabPreparation = .suppressed

        XCTAssertEqual(
            fixture.extensionPublication.stageInitialTab(
                tab,
                webView: webView,
                in: windowState,
                reason: "test"
            ),
            .suppressed
        )
        fixture.registration.commitRegistration(windowState)

        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
    }

    func testWindowWithoutExactInitialTabNeverPublishesExtensionLifecycle()
        throws {
        let fixture = try makeFixture()
        let windowState = BrowserWindowState()

        fixture.registration.prepareRegistration(windowState)

        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
        XCTAssertTrue(
            fixture.tabManager.tabResidenceAuthority.owns(windowState)
        )

        fixture.registration.commitRegistration(windowState)

        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
    }

    func testIncognitoRegistrationPreservesEphemeralIdentityAndSkipsDurableRestore()
        throws {
        let fixture = try makeFixture(
            snapshot: makeSnapshot(
                currentSpaceID: UUID(),
                currentProfileID: UUID()
            )
        )
        let windowState = BrowserWindowState()
        let ephemeralProfile = Profile.createEphemeral()
        let ephemeralSpace = Space(
            name: "Private",
            profileId: ephemeralProfile.id
        )
        ephemeralSpace.isEphemeral = true
        let ephemeralTabID = UUID()
        windowState.isIncognito = true
        windowState.ephemeralProfile = ephemeralProfile
        windowState.replaceEphemeralSpaces([ephemeralSpace])
        windowState.currentProfileId = ephemeralProfile.id
        windowState.currentSpaceId = ephemeralSpace.id
        windowState.currentTabId = ephemeralTabID
        fixture.registration.restore(windowState)
        fixture.restoreService.handleTabManagerDataLoaded(
            windows: [windowState]
        )

        XCTAssertIdentical(windowState.ephemeralProfile, ephemeralProfile)
        XCTAssertEqual(windowState.ephemeralSpaces.map(\.id), [ephemeralSpace.id])
        XCTAssertEqual(windowState.currentProfileId, ephemeralProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, ephemeralSpace.id)
        XCTAssertEqual(windowState.currentTabId, ephemeralTabID)
        XCTAssertFalse(windowState.restorationState.isAwaitingInitialResolution)
        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
        XCTAssertEqual(fixture.startup.reconcileCallCount, 0)
    }

    func testBatchHydratesEveryWindowBeforePublishingAndReconcilesStartupOnce()
        throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(currentProfile: profile)
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        fixture.registration.restoreRegisteredWindows(
            [firstWindow, secondWindow]
        )

        XCTAssertTrue(
            fixture.tabManager.tabResidenceAuthority.owns(firstWindow)
        )
        XCTAssertTrue(
            fixture.tabManager.tabResidenceAuthority.owns(secondWindow)
        )
        XCTAssertEqual(firstWindow.currentProfileId, profile.id)
        XCTAssertEqual(secondWindow.currentProfileId, profile.id)
        XCTAssertEqual(firstWindow.currentSpaceId, space.id)
        XCTAssertEqual(secondWindow.currentSpaceId, space.id)
        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
        XCTAssertEqual(fixture.startup.reconcileCallCount, 1)
    }

    func testAwaitingRegistrationDoesNotInventAnExtensionProjectionAfterResolution()
        throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(
            currentProfile: profile,
            snapshot: makeSnapshot(
                currentSpaceID: space.id,
                currentProfileID: profile.id
            )
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()

        fixture.registration.restore(windowState)

        XCTAssertTrue(windowState.restorationState.isAwaitingInitialResolution)
        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
        XCTAssertEqual(fixture.startup.reconcileCallCount, 0)

        fixture.tabManager.startupRestoreLifecycle.markLoadFinished()
        fixture.restoreService.handleTabManagerDataLoaded(
            windows: [windowState]
        )
        fixture.registration.completePendingRegistrations(
            registeredWindows: [windowState]
        )
        fixture.registration.completePendingRegistrations(
            registeredWindows: [windowState]
        )

        XCTAssertFalse(windowState.restorationState.isAwaitingInitialResolution)
        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
    }

    func testPendingRegistrationCannotPublishReplacementWithSameUUID()
        throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(
            currentProfile: profile,
            snapshot: makeSnapshot(
                currentSpaceID: space.id,
                currentProfileID: profile.id
            )
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let originalWindow = BrowserWindowState()
        fixture.registration.restore(originalWindow)
        XCTAssertTrue(originalWindow.restorationState.isAwaitingInitialResolution)

        let replacement = BrowserWindowState(id: originalWindow.id)
        fixture.registration.completePendingRegistrations(
            registeredWindows: [replacement]
        )

        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
    }

    func testDiscardedPendingRegistrationCannotPublishLater() throws {
        let profile = Profile(name: "Regular")
        let space = Space(name: "Workspace", profileId: profile.id)
        let fixture = try makeFixture(
            currentProfile: profile,
            snapshot: makeSnapshot(
                currentSpaceID: space.id,
                currentProfileID: profile.id
            )
        )
        fixture.tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()
        fixture.registration.restore(windowState)
        XCTAssertTrue(windowState.restorationState.isAwaitingInitialResolution)

        fixture.registration.discardRegistration(windowState)
        windowState.restorationState.isAwaitingInitialResolution = false
        fixture.registration.completePendingRegistrations(
            registeredWindows: [windowState]
        )

        XCTAssertTrue(fixture.extensions.openedWindowIDs.isEmpty)
    }

    func testActivationHasNoEffectsUntilExactDeferredWindowIsResolved() {
        let sessionKey = "SumiTests.activation.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let snapshotStore = WindowSessionSnapshotStore(key: sessionKey)
        let browserManager = BrowserManager(
            windowSessionSnapshotStore: snapshotStore
        )
        let extensions = RecordingWindowExtensionLifecycle()
        let activation = BrowserWindowActivationService(
            sidebarPresentation: browserManager.chromeBundle
                .sidebarPresentationOwner,
            persistence: browserManager.windowSessionPersistenceCoordinator,
            activePageResolver: browserManager.shellRuntime.activePageResolver,
            findManager: browserManager.findManager,
            extensions: extensions,
            focusedContext: BrowserWindowFocusedContextSynchronizer(
                windowState: browserManager.windowStateReconciler,
                profileAdoption: browserManager.profileAdoption
            ),
            nowPlaying: browserManager.nativeNowPlayingController,
            backgroundMedia: browserManager
                .backgroundMediaOptimizationService
        )
        let windowState = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )

        activation.activate(windowState)
        activation.activate(windowState)

        XCTAssertTrue(extensions.focusedWindowIDs.isEmpty)
        XCTAssertNil(snapshotStore.loadSnapshot())

        windowState.restorationState.isAwaitingInitialResolution = false
        activation.completeDeferredActivation(for: windowState)
        activation.completeDeferredActivation(for: windowState)

        XCTAssertEqual(extensions.focusedWindowIDs, [windowState.id])
        XCTAssertNotNil(snapshotStore.loadSnapshot())
    }

    private func makeFixture(
        currentProfile: Profile? = nil,
        snapshot: WindowSessionSnapshot? = nil
    ) throws -> RegistrationFixture {
        let tabManager = BrowserManager()
        let sessionKey = "SumiTests.registration.\(UUID().uuidString)"
        if let snapshot {
            XCTAssertTrue(
                WindowSessionSnapshotStore(key: sessionKey).persist(snapshot)
            )
        }
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }
        let restoreDelegate = TestWindowSessionDelegate(
            runtime: tabManager,
            windowRegistry: tabManager.windowRegistry
        )
        let restoreService = restoreDelegate.makeRestoreService(
            lastWindowSessionKey: sessionKey
        )
        let currentProfileAuthority = BrowserCurrentProfileAuthority(
            currentProfile
        )
        let extensions = RecordingWindowExtensionLifecycle()
        let startup = RecordingStartupSessionReconciler()
        let extensionPublication = WindowExtensionPublicationTransaction(
            preparation: extensions,
            publication: extensions
        )
        let registration = BrowserWindowSessionRestorationService(
            restoration: restoreService,
            tabResidences: tabManager.tabResidenceAuthority,
            extensionPublication: extensionPublication,
            currentProfile: currentProfileAuthority,
            startupSessions: startup
        )
        return RegistrationFixture(
            tabManager: tabManager,
            restoreDelegate: restoreDelegate,
            restoreService: restoreService,
            extensions: extensions,
            extensionPublication: extensionPublication,
            startup: startup,
            registration: registration
        )
    }

    private func makeSnapshot(
        currentSpaceID: UUID,
        currentProfileID: UUID
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: currentSpaceID,
            currentProfileId: currentProfileID,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: true,
            commandPaletteReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(
                BrowserWindowState.sidebarDefaultWidth
            ),
            sidebarContentWidth: Double(
                BrowserWindowState.sidebarContentWidth(
                    for: BrowserWindowState.sidebarDefaultWidth
                )
            ),
            isSidebarVisible: true,
            commandPaletteDraft: CommandPaletteDraftState(
                text: "",
                navigateCurrentTab: false
            )
        )
    }
}

@MainActor
private struct RegistrationFixture {
    let tabManager: BrowserManager
    let restoreDelegate: TestWindowSessionDelegate
    let restoreService: WindowSessionRestoreService
    let extensions: RecordingWindowExtensionLifecycle
    let extensionPublication: WindowExtensionPublicationTransaction
    let startup: RecordingStartupSessionReconciler
    let registration: BrowserWindowSessionRestorationService
}

@MainActor
private final class RecordingWindowExtensionLifecycle:
    BrowserWindowExtensionPublishing,
    BrowserWindowExtensionFocusNotifying,
    InitialTabExtensionPreparing {
    private(set) var openedWindowIDs: [UUID] = []
    private(set) var revokedWindowIDs: [UUID] = []
    private(set) var focusedWindowIDs: [UUID] = []
    var onOpen: ((BrowserWindowState) -> Void)?
    var onPrepare: ((BrowserWindowState) -> Void)?
    var events: ExtensionPublicationEventRecorder?
    var initialTabPreparation: InitialTabExtensionPreparation =
        .notParticipating
    var isPublicationCurrent = true

    func prepareInitialTabExtensionPublication(
        window: BrowserWindowState,
        tab _: Tab,
        webView _: FocusableWKWebView,
        reason _: String
    ) -> InitialTabExtensionPreparation {
        let preparation = initialTabPreparation
        onPrepare?(window)
        return preparation
    }

    func publishWindowIfLoaded(
        _ windowState: BrowserWindowState
    ) -> BrowserWindowExtensionPublicationOutcome {
        events?.values.append("window")
        onOpen?(windowState)
        openedWindowIDs.append(windowState.id)
        return .published(
            RecordingWindowPublicationLease(
                isOwned: { [weak self, weak windowState] in
                    guard let self, let windowState else { return false }
                    return self.openedWindowIDs.contains(windowState.id)
                },
                isCurrent: { [weak self, weak windowState] in
                    guard let self, let windowState else { return false }
                    return self.isPublicationCurrent
                        && self.openedWindowIDs.contains(windowState.id)
                },
                revoke: { [weak self, weak windowState] in
                    guard let self, let windowState else { return }
                    self.revokeWindowPublicationIfLoaded(windowState)
                }
            )
        )
    }

    func revokeWindowPublicationIfLoaded(_ windowState: BrowserWindowState) {
        openedWindowIDs.removeAll { $0 == windowState.id }
        revokedWindowIDs.append(windowState.id)
        events?.values.append("window-revoked")
    }

    func notifyWindowFocusedIfLoaded(_ windowState: BrowserWindowState) {
        focusedWindowIDs.append(windowState.id)
    }
}

@MainActor
private final class RecordingWindowPublicationLease:
    BrowserWindowExtensionPublication {
    private let owned: @MainActor () -> Bool
    private let current: @MainActor () -> Bool
    private let revoke: @MainActor () -> Void

    init(
        isOwned: @escaping @MainActor () -> Bool,
        isCurrent: @escaping @MainActor () -> Bool,
        revoke: @escaping @MainActor () -> Void
    ) {
        self.owned = isOwned
        self.current = isCurrent
        self.revoke = revoke
    }

    func isCurrent() -> Bool { current() }
    func revokeIfCurrent() {
        guard owned() else { return }
        revoke()
    }
}

@MainActor
private final class ExtensionPublicationEventRecorder {
    var values: [String] = []
}

@MainActor
private final class RecordingInitialTabPublication:
    InitialTabExtensionPublication {
    private let window: BrowserWindowState
    private let tab: Tab
    private let webView: FocusableWKWebView
    private let events: ExtensionPublicationEventRecorder
    var validates = true
    var publishes = true
    var onPublish: (() -> Void)?
    private(set) var publishCount = 0
    private(set) var cancelCount = 0
    private(set) var revokeCount = 0

    init(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        events: ExtensionPublicationEventRecorder
    ) {
        self.window = window
        self.tab = tab
        self.webView = webView
        self.events = events
    }

    func matches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool {
        self.window === window
            && self.tab === tab
            && self.webView === webView
    }

    func validateBeforeWindowPublication() -> Bool {
        validates
    }

    func publishInitialTab(
        afterWindowOpened window: BrowserWindowState
    ) -> Bool {
        guard publishes,
              window === self.window,
              events.values == ["window"]
        else {
            return false
        }
        publishCount += 1
        events.values.append("tab")
        onPublish?()
        return true
    }

    func cancel() -> Bool {
        cancelCount += 1
        return true
    }

    func revokePublishedIfCurrent() -> Bool {
        guard publishCount > revokeCount else { return false }
        revokeCount += 1
        events.values.append("tab-revoked")
        return true
    }
}

@MainActor
private final class RecordingStartupSessionReconciler:
    BrowserStartupSessionReconciling {
    private(set) var reconcileCallCount = 0

    func reconcileStartupSessionIfPossible() {
        reconcileCallCount += 1
    }
}
