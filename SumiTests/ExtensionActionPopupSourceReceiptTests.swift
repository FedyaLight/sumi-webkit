import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSourceReceiptTests: XCTestCase {
    private struct Harness {
        let container: ModelContainer
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let extensionManager: ExtensionManager
        let sourceTab: Tab
        let profile: Profile
        let windowState: BrowserWindowState
        let extensionContext: WKWebExtensionContext
    }

    private struct MutationSnapshot: Equatable {
        let regularTabIDs: Set<UUID>
        let transientTabIDs: Set<UUID>
        let sessionIDs: Set<UUID>
    }

    func testExternalURLUsesCapturedWindowAndProfile() async throws {
        let extensionID = "action-owner"
        let harness = try await makeHarness(extensionID: extensionID)
        let sourceURL = URL(
            string: "safari-web-extension://\(extensionID)/popup.html"
        )!
        let targetURL = URL(string: "https://account.example.test/login")!
        let mainWindow = try XCTUnwrap(
            harness.windowRegistry.appKitWindow(for: harness.windowState)
        )
        let originalMainFrame = mainWindow.frame
        let spaceID = try XCTUnwrap(
            harness.browserManager.tabManager.spaceStateOwner.currentSpace?.id
        )
        let initialRegularTabCount = harness.browserManager.tabManager
            .regularTabCollectionStateOwner.tabsBySpaceSnapshot()[spaceID]?
            .count ?? 0
        let popupSource = try makePopupSource(
            harness: harness,
            extensionID: extensionID
        )
        let delegate = ExtensionActionPopupUIDelegate(
            manager: harness.extensionManager,
            popover: NSPopover(),
            sourceReceipt: popupSource.receipt
        )
        let childConfiguration = configuration(
            dataStore: harness.profile.dataStore
        )

        XCTAssertNil(
            delegate.webView(
                popupSource.webView,
                createWebViewWith: childConfiguration,
                for: navigationAction(
                    sourceURL: sourceURL,
                    targetURL: targetURL,
                    webView: popupSource.webView
                ),
                windowFeatures: WKWindowFeatures()
            )
        )
        XCTAssertTrue(
            harness.browserManager.tabManager.transientTabRegistryOwner
                .auxiliaryMiniWindowTabsByID.isEmpty
        )
        XCTAssertEqual(
            harness.browserManager.tabManager.regularTabCollectionStateOwner
                .tabsBySpaceSnapshot()[spaceID]?.count,
            initialRegularTabCount + 1
        )
        let openedTab = try XCTUnwrap(
            harness.browserManager.tabManager.regularTabCollectionStateOwner
                .allTabsSnapshot().last
        )
        XCTAssertEqual(openedTab.url, targetURL)
        XCTAssertNil(openedTab.profileId)
        XCTAssertIdentical(openedTab.resolveProfile(), harness.profile)
        XCTAssertFalse(openedTab.isAuxiliaryMiniWindow)
        XCTAssertFalse(openedTab.isPopupHost)
        XCTAssertEqual(mainWindow.frame, originalMainFrame)
    }

    func testNestedPopupKeepsCapturedProfileAndWindowAfterActiveWindowSwitch()
        async throws {
        let extensionID = "action-owner"
        let harness = try await makeHarness(extensionID: extensionID)
        let popupSource = try makePopupSource(
            harness: harness,
            extensionID: extensionID
        )
        let sourceWindow = try XCTUnwrap(
            harness.windowRegistry.appKitWindow(for: harness.windowState)
        )
        let delegate = ExtensionActionPopupUIDelegate(
            manager: harness.extensionManager,
            popover: NSPopover(),
            sourceReceipt: popupSource.receipt
        )

        let otherProfile = Profile(name: "Other Profile")
        harness.browserManager.profileManager.profiles.append(otherProfile)
        let otherSpace = Space(name: "Other Space", profileId: otherProfile.id)
        harness.browserManager.tabManager.spaceStateOwner.replaceSpaces(
            harness.browserManager.tabManager.spaceStateOwner.spaces + [otherSpace]
        )
        let otherWindowState = BrowserWindowState()
        otherWindowState.tabManager = harness.browserManager.tabManager
        otherWindowState.currentSpaceId = otherSpace.id
        otherWindowState.currentProfileId = otherProfile.id
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 240, y: 180, width: 900, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        harness.windowRegistry.bindAppKitWindow(otherWindow, to: otherWindowState)
        harness.windowRegistry.register(otherWindowState)
        let otherTab = harness.browserManager.tabManager.regularTabLifecycleOwner
            .createNewTab(
                url: "https://profile-b.example/",
                in: otherSpace,
                activate: true
            )
        otherTab.profileId = otherProfile.id
        harness.browserManager.selectTab(otherTab, in: otherWindowState)
        harness.windowRegistry.setActive(otherWindowState)

        let childWebView = try XCTUnwrap(
            delegate.webView(
                popupSource.webView,
                createWebViewWith: configuration(
                    dataStore: harness.profile.dataStore
                ),
                for: nestedNavigationAction(
                    extensionID: extensionID,
                    webView: popupSource.webView
                ),
                windowFeatures: WKWindowFeatures()
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: childWebView,
                reason: .bulkCleanup
            )
        }
        let childSession = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: childWebView
            )
        )

        XCTAssertIdentical(harness.windowRegistry.activeWindow, otherWindowState)
        XCTAssertIdentical(childSession.openerTab, harness.sourceTab)
        XCTAssertIdentical(childSession.openerWindow, sourceWindow)
        XCTAssertEqual(childSession.tab.profileId, harness.profile.id)
        XCTAssertIdentical(childSession.tab.resolveProfile(), harness.profile)
        XCTAssertIdentical(
            childWebView.configuration.websiteDataStore,
            harness.profile.dataStore
        )
        XCTAssertNotEqual(childSession.tab.profileId, otherProfile.id)
    }

    func testStaleReceiptIsRejectedBeforeTransientMutation() async throws {
        let extensionID = "action-owner"
        let harness = try await makeHarness(extensionID: extensionID)
        let popupSource = try makePopupSource(
            harness: harness,
            extensionID: extensionID
        )
        let delegate = ExtensionActionPopupUIDelegate(
            manager: harness.extensionManager,
            popover: NSPopover(),
            sourceReceipt: popupSource.receipt
        )
        let before = mutationSnapshot(harness)
        harness.windowRegistry.unregister(harness.windowState.id)

        XCTAssertNil(
            delegate.webView(
                popupSource.webView,
                createWebViewWith: configuration(
                    dataStore: harness.profile.dataStore
                ),
                for: nestedNavigationAction(
                    extensionID: extensionID,
                    webView: popupSource.webView
                ),
                windowFeatures: WKWindowFeatures()
            )
        )
        XCTAssertEqual(mutationSnapshot(harness), before)
    }

    func testDataStoreMismatchIsRejectedBeforeTransientMutation() async throws {
        let extensionID = "action-owner"
        let harness = try await makeHarness(extensionID: extensionID)
        let popupSource = try makePopupSource(
            harness: harness,
            extensionID: extensionID
        )
        let delegate = ExtensionActionPopupUIDelegate(
            manager: harness.extensionManager,
            popover: NSPopover(),
            sourceReceipt: popupSource.receipt
        )
        let before = mutationSnapshot(harness)
        let mismatchedProfile = Profile(name: "Mismatched Profile")

        XCTAssertNil(
            delegate.webView(
                popupSource.webView,
                createWebViewWith: configuration(
                    dataStore: mismatchedProfile.dataStore
                ),
                for: nestedNavigationAction(
                    extensionID: extensionID,
                    webView: popupSource.webView
                ),
                windowFeatures: WKWindowFeatures()
            )
        )
        XCTAssertEqual(mutationSnapshot(harness), before)
    }

    func testExternalURLRequiresPublishedNormalWindowProjection()
        async throws {
        let extensionID = "action-owner"
        let harness = try await makeHarness(extensionID: extensionID)
        let popupSource = try makePopupSource(
            harness: harness,
            extensionID: extensionID
        )
        let delegate = ExtensionActionPopupUIDelegate(
            manager: harness.extensionManager,
            popover: NSPopover(),
            sourceReceipt: popupSource.receipt
        )
        harness.extensionManager.normalWindowLifecycle.closed(
            harness.windowState
        )
        let before = mutationSnapshot(harness)

        XCTAssertNil(
            delegate.webView(
                popupSource.webView,
                createWebViewWith: configuration(
                    dataStore: harness.profile.dataStore
                ),
                for: navigationAction(
                    sourceURL: URL(
                        string: "safari-web-extension://\(extensionID)/popup.html"
                    ),
                    targetURL: URL(
                        string: "https://account.example.test/unpublished"
                    )!,
                    webView: popupSource.webView
                ),
                windowFeatures: WKWindowFeatures()
            )
        )
        XCTAssertEqual(mutationSnapshot(harness), before)
    }

    func testStaleNormalWindowCloseCannotRetireReplacementWithSameUUID()
        async throws {
        let harness = try await makeHarness(
            extensionID: "stale-window-close"
        )
        let staleWindow = harness.windowState
        let staleAdapter = try XCTUnwrap(
            harness.extensionManager.adapterStore.existingWindowAdapter(
                for: staleWindow.id
            )
        )

        harness.extensionManager.normalWindowLifecycle.closed(staleWindow)
        harness.windowRegistry.unregister(staleWindow.id)

        let replacementWindow = BrowserWindowState(id: staleWindow.id)
        replacementWindow.tabManager = harness.browserManager.tabManager
        replacementWindow.currentSpaceId = staleWindow.currentSpaceId
        replacementWindow.currentProfileId = staleWindow.currentProfileId
        let replacementShell = NSWindow(
            contentRect: NSRect(x: 180, y: 160, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        harness.windowRegistry.bindAppKitWindow(
            replacementShell,
            to: replacementWindow
        )
        XCTAssertEqual(
            harness.windowRegistry.register(replacementWindow),
            .registered
        )
        harness.browserManager.selectTab(
            harness.sourceTab,
            in: replacementWindow
        )
        harness.windowRegistry.setActive(replacementWindow)
        XCTAssertTrue(
            harness.extensionManager.normalWindowLifecycle.opened(
                replacementWindow
            )
        )
        let replacementAdapter = try XCTUnwrap(
            harness.extensionManager.adapterResolutionOwner
                .publishedNormalWindowAdapter(
                    for: replacementWindow,
                    extensionContext: harness.extensionContext
                )
        )
        XCTAssertNotIdentical(replacementAdapter, staleAdapter)
        XCTAssertTrue(
            replacementAdapter.tabs(for: harness.extensionContext).contains {
                ($0 as? ExtensionTabAdapter)?.tabId
                    == harness.sourceTab.id
            }
        )

        harness.extensionManager.normalWindowLifecycle.closed(staleWindow)

        XCTAssertIdentical(
            harness.extensionManager.adapterStore.existingWindowAdapter(
                for: replacementWindow.id
            ),
            replacementAdapter
        )
        XCTAssertIdentical(
            harness.extensionManager.windowPublications
                .publishedWindowAdapter(
                    for: replacementWindow,
                    profileID: harness.profile.id
                ),
            replacementAdapter
        )
        XCTAssertTrue(
            replacementAdapter.tabs(for: harness.extensionContext).contains {
                ($0 as? ExtensionTabAdapter)?.tabId
                    == harness.sourceTab.id
            }
        )
        XCTAssertTrue(staleAdapter.tabs(for: harness.extensionContext).isEmpty)
    }

    func testCrossProfileSelectionRevokesNormalWindowAdapterProjection()
        async throws {
        let extensionID = "action-owner"
        let harness = try await makeHarness(extensionID: extensionID)
        let sourceTabAdapter = try XCTUnwrap(
            harness.extensionManager.adapterResolutionOwner.stableAdapter(
                for: harness.sourceTab
            )
        )
        let publishedWindow = try XCTUnwrap(
            sourceTabAdapter.window(for: harness.extensionContext)
                as? ExtensionWindowAdapter
        )
        let shell = try XCTUnwrap(
            harness.windowRegistry.appKitWindow(for: harness.windowState)
        )
        XCTAssertEqual(
            publishedWindow.frame(for: harness.extensionContext),
            shell.frame
        )

        let executionProfile = Profile(name: "Execution Profile B")
        harness.browserManager.profileManager.profiles.append(executionProfile)
        let profileBContext = try await makeExtensionContext(
            extensionID: extensionID
        )
        harness.extensionManager.setExtensionContext(
            profileBContext,
            extensionId: extensionID,
            profileId: executionProfile.id
        )
        _ = harness.extensionManager.ensureExtensionController(
            for: executionProfile.id
        )
        XCTAssertNil(
            harness.extensionManager.adapterResolutionOwner
                .publishedNormalWindowAdapter(
                    for: harness.windowState,
                    extensionContext: profileBContext
                )
        )

        let space = try XCTUnwrap(
            harness.browserManager.tabManager.spaceStateOwner.currentSpace
        )
        let executionTab = harness.browserManager.tabManager
            .regularTabLifecycleOwner.createNewTab(
                url: "https://profile-b.example.test/",
                in: space,
                activate: false,
                executionProfileID: executionProfile.id
            )
        harness.browserManager.selectTab(executionTab, in: harness.windowState)
        harness.extensionManager.normalTabActivation.activate(
            executionTab,
            previous: harness.sourceTab
        )

        XCTAssertEqual(harness.windowState.currentProfileId, harness.profile.id)
        XCTAssertEqual(harness.windowState.currentSpaceId, space.id)
        XCTAssertEqual(executionTab.profileId, executionProfile.id)
        XCTAssertNil(sourceTabAdapter.window(for: harness.extensionContext))
        XCTAssertTrue(
            publishedWindow.tabs(for: harness.extensionContext).isEmpty
        )
        XCTAssertEqual(
            publishedWindow.frame(for: harness.extensionContext),
            .zero
        )
    }

    func testRuntimeReconciliationPublishesCompleteGenerationBeforeTabEvents()
        async throws {
        let extensionID = "atomic-generation"
        let harness = try await makeHarness(extensionID: extensionID)
        let controller = try XCTUnwrap(
            harness.extensionManager.profileRuntime
                .controllersByProfile[harness.profile.id]
        )
        let space = try XCTUnwrap(
            harness.browserManager.tabManager.spaceStateOwner.currentSpace
        )
        let backgroundTab = harness.browserManager.tabManager
            .regularTabLifecycleOwner.createNewTab(
                url: "https://background.example.test/",
                in: space,
                activate: false
            )
        backgroundTab.profileId = harness.profile.id
        let backgroundWebView = try XCTUnwrap(
            backgroundTab.makeNormalTabWebView(
                reason: "ExtensionActionPopupSourceReceiptTests.atomicGeneration"
            )
        )
        harness.browserManager.testWebViewRuntime().trackedWebViewAdmission.attemptAssignment(
            backgroundWebView,
            to: backgroundTab,
            in: harness.windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )

        let oldGeneration = harness.extensionManager.runtimeSession
            .tabOpenNotificationGeneration
        let expectedTabs = [harness.sourceTab, backgroundTab]
        for tab in expectedTabs {
            tab.extensionPageRuntimeOwner.prepareGeneration(oldGeneration)
            tab.extensionPageRuntimeOwner.markEligible(for: oldGeneration)
        }
        XCTAssertTrue(
            harness.extensionManager.normalWindowLifecycle.opened(
                harness.windowState
            )
        )

        let didLoadContext = controller.extensionContexts.contains(
            harness.extensionContext
        ) == false
        if didLoadContext {
            try controller.load(harness.extensionContext)
            addTeardownBlock {
                try controller.unload(harness.extensionContext)
            }
        }

        let expectedTabIDs = Set(expectedTabs.map(\.id))
        XCTAssertEqual(
            Set(
                harness.extensionContext.openTabs.compactMap {
                    ($0 as? ExtensionTabAdapter)?.tabId
                }
            ),
            expectedTabIDs
        )
        for tab in expectedTabs {
            XCTAssertTrue(
                harness.extensionManager.browserContentInventory.tabs(
                    in: harness.extensionManager.runtime
                ).contains {
                    $0 === tab
                },
                "Missing runtime Tab \(tab.id)"
            )
            XCTAssertTrue(
                harness.extensionManager.browserContentInventory.liveWebViews(
                    for: tab,
                    in: harness.extensionManager.runtime
                ).contains {
                    $0.configuration.webExtensionController === controller
                },
                "Missing controller-bound WebView for \(tab.id)"
            )
            XCTAssertIdentical(
                harness.extensionManager.extensionWindowQuery?
                    .preferredExtensionWindowState(containing: tab),
                harness.windowState
            )
        }

        var tabIDsVisibleAtOpen: [Set<UUID>] = []
        var activeTabWasVisibleAtOpen: [Bool] = []
        harness.extensionManager.testHooks.didOpenTab = { _ in
            guard let window = harness.extensionManager
                .adapterResolutionOwner.publishedNormalWindowAdapter(
                    for: harness.windowState,
                    extensionContext: harness.extensionContext
                )
            else {
                tabIDsVisibleAtOpen.append([])
                activeTabWasVisibleAtOpen.append(false)
                return
            }
            tabIDsVisibleAtOpen.append(
                Set(
                    window.tabs(for: harness.extensionContext).compactMap {
                        ($0 as? ExtensionTabAdapter)?.tabId
                    }
                )
            )
            activeTabWasVisibleAtOpen.append(
                window.activeTab(for: harness.extensionContext) != nil
            )
        }

        harness.extensionManager.reloadRuntimePublications(
            reason: "ExtensionActionPopupSourceReceiptTests.atomicGeneration",
            profileID: harness.profile.id
        )

        for tab in expectedTabs {
            XCTAssertTrue(
                harness.extensionManager
                    .isTabEligibleForCurrentExtensionRuntime(tab),
                "Tab did not enter the committed generation: \(tab.id)"
            )
        }

        XCTAssertEqual(tabIDsVisibleAtOpen.count, expectedTabs.count)
        XCTAssertTrue(
            tabIDsVisibleAtOpen.allSatisfy { $0 == expectedTabIDs },
            "Every didOpenTab callback must see the complete new window generation"
        )
        XCTAssertTrue(activeTabWasVisibleAtOpen.allSatisfy { $0 })
        XCTAssertEqual(
            Set(
                harness.extensionContext.openTabs.compactMap {
                    ($0 as? ExtensionTabAdapter)?.tabId
                }
            ),
            expectedTabIDs
        )
    }

    func testCallbackReloadIsCoalescedAfterCurrentGeneration() async throws {
        let harness = try await makeHarness(extensionID: "reload-handoff")
        let generationBeforeReload = harness.extensionManager.runtimeSession
            .tabOpenNotificationGeneration
        var sourceOpenCount = 0
        var requestedNestedReload = false
        var nestedReloadGeneration: (before: UInt64, after: UInt64)?

        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            sourceOpenCount += 1
            guard requestedNestedReload == false else { return }
            requestedNestedReload = true

            let before = harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration
            harness.extensionManager.reloadRuntimePublications(
                reason: "ExtensionActionPopupSourceReceiptTests.nestedReload",
                profileID: harness.profile.id
            )
            nestedReloadGeneration = (
                before: before,
                after: harness.extensionManager.runtimeSession
                    .tabOpenNotificationGeneration
            )
        }
        defer { harness.extensionManager.testHooks.didOpenTab = nil }

        harness.extensionManager.reloadRuntimePublications(
            reason: "ExtensionActionPopupSourceReceiptTests.reloadHandoff",
            profileID: harness.profile.id
        )

        XCTAssertEqual(
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration,
            generationBeforeReload + 2
        )
        XCTAssertEqual(
            nestedReloadGeneration?.before,
            nestedReloadGeneration?.after,
            "The callback reload must be deferred, not nested synchronously"
        )
        XCTAssertEqual(sourceOpenCount, 2)
        XCTAssertTrue(
            harness.extensionManager.normalWindowLifecycle
                .tabPublicationIsCurrent(
                    harness.sourceTab,
                    profileID: harness.profile.id
                )
        )
    }

    func testDidOpenDoesNotSettleAfterAdapterAuthorityChangesInCallback()
        async throws {
        let harness = try await makeHarness(
            extensionID: "open-adapter-reentry"
        )
        let tab = harness.sourceTab
        let generation = harness.extensionManager.runtimeSession
            .tabOpenNotificationGeneration
        harness.extensionManager.normalTabClosure.close(tab)
        let adapter = try XCTUnwrap(
            harness.extensionManager.adapterResolutionOwner
                .stableAdapter(for: tab)
        )
        var didCloseCount = 0
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == tab.id else { return }
            didCloseCount += 1
        }
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == tab.id else { return }
            _ = harness.extensionManager.adapterStore.removeTabAdapter(
                for: tab.id,
                ifIdenticalTo: adapter
            )
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.extensionManager.adapterStore.tabAdapters[tab.id]
                = adapter
        }

        XCTAssertFalse(
            harness.extensionManager.notifyTabOpened(tab)
        )
        XCTAssertFalse(
            tab.extensionPageRuntimeOwner
                .hasSettledDidOpenTabNotification(for: generation)
        )
        XCTAssertFalse(
            tab.extensionPageRuntimeOwner.hasAnyDidOpenTabNotification()
        )
        XCTAssertEqual(didCloseCount, 1)
        XCTAssertFalse(
            harness.extensionContext.openTabs.contains { openTab in
                (openTab as AnyObject) === adapter
            }
        )
    }

    func testDidOpenDoesNotSettleAfterContextBindingChangesInCallback()
        async throws {
        let extensionID = "open-context-reentry"
        let harness = try await makeHarness(
            extensionID: extensionID
        )
        let tab = harness.sourceTab
        let generation = harness.extensionManager.runtimeSession
            .tabOpenNotificationGeneration
        harness.extensionManager.normalTabClosure.close(tab)
        let adapter = try XCTUnwrap(
            harness.extensionManager.adapterResolutionOwner
                .stableAdapter(for: tab)
        )
        var didCloseCount = 0
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == tab.id else { return }
            didCloseCount += 1
        }
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == tab.id else { return }
            harness.extensionManager.setExtensionContext(
                harness.extensionContext,
                extensionId: extensionID,
                profileId: harness.profile.id
            )
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.extensionManager.adapterStore.tabAdapters[tab.id]
                = adapter
        }

        XCTAssertFalse(harness.extensionManager.notifyTabOpened(tab))
        XCTAssertFalse(
            tab.extensionPageRuntimeOwner
                .hasSettledDidOpenTabNotification(for: generation)
        )
        XCTAssertFalse(
            tab.extensionPageRuntimeOwner.hasAnyDidOpenTabNotification()
        )
        XCTAssertEqual(didCloseCount, 1)
    }

    func testDidOpenIsNotEmittedWhenWindowAdmissionLosesTabAuthority()
        async throws {
        let harness = try await makeHarness(
            extensionID: "open-window-admission-reentry"
        )
        let tab = harness.sourceTab
        let selectedTab = harness.browserManager.tabManager
            .regularTabLifecycleOwner.createNewTab(
                url: "about:blank",
                in: harness.browserManager.tabManager.spaceStateOwner
                    .currentSpace,
                activate: true
            )
        selectedTab.profileId = harness.profile.id
        harness.browserManager.selectTab(
            selectedTab,
            in: harness.windowState
        )
        harness.extensionManager.normalTabClosure.close(tab)
        let adapter = try XCTUnwrap(
            harness.extensionManager.adapterResolutionOwner
                .stableAdapter(for: tab)
        )
        harness.extensionManager.normalWindowLifecycle.closed(
            harness.windowState
        )

        var didOpenCount = 0
        var didCloseCount = 0
        harness.extensionManager.testHooks.didOpenNormalWindow = { windowID in
            guard windowID == harness.windowState.id else { return }
            _ = harness.extensionManager.adapterStore.removeTabAdapter(
                for: tab.id,
                ifIdenticalTo: adapter
            )
        }
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == tab.id else { return }
            didOpenCount += 1
        }
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == tab.id else { return }
            didCloseCount += 1
        }
        defer {
            harness.extensionManager.testHooks.didOpenNormalWindow = nil
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.extensionManager.adapterStore.tabAdapters[tab.id]
                = adapter
        }

        XCTAssertFalse(harness.extensionManager.notifyTabOpened(tab))
        XCTAssertEqual(didOpenCount, 0)
        XCTAssertEqual(didCloseCount, 0)
        XCTAssertFalse(
            tab.extensionPageRuntimeOwner.hasAnyDidOpenTabNotification()
        )
    }

    func testRepeatedCallbackReloadIsBoundedToOneCoalescedReplay()
        async throws {
        let harness = try await makeHarness(
            extensionID: "reload-handoff-bounded"
        )
        let generationBeforeReload = harness.extensionManager.runtimeSession
            .tabOpenNotificationGeneration
        var sourceOpenCount = 0
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            sourceOpenCount += 1
            harness.extensionManager.reloadRuntimePublications(
                reason: "ExtensionActionPopupSourceReceiptTests.repeatedNestedReload",
                profileID: harness.profile.id
            )
        }
        defer { harness.extensionManager.testHooks.didOpenTab = nil }

        harness.extensionManager.reloadRuntimePublications(
            reason: "ExtensionActionPopupSourceReceiptTests.boundedReload",
            profileID: harness.profile.id
        )

        XCTAssertEqual(
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration,
            generationBeforeReload + 2
        )
        XCTAssertEqual(sourceOpenCount, 2)

        for _ in 0 ..< 8 where sourceOpenCount < 4 {
            await Task.yield()
        }
        XCTAssertEqual(
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration,
            generationBeforeReload + 4
        )
        XCTAssertEqual(sourceOpenCount, 4)

        for _ in 0 ..< 8 {
            await Task.yield()
        }
        XCTAssertEqual(
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration,
            generationBeforeReload + 4
        )
        XCTAssertEqual(sourceOpenCount, 4)
    }

    func testSecondReplayRequestContinuesOnLaterMainActorTurn()
        async throws {
        let harness = try await makeHarness(
            extensionID: "reload-handoff-overflow"
        )
        let generationBeforeReload = harness.extensionManager.runtimeSession
            .tabOpenNotificationGeneration
        var sourceOpenCount = 0
        var focusCount = 0
        var activationCount = 0
        harness.extensionManager.testHooks.didFocusWindow = { windowID in
            guard windowID == harness.windowState.id else { return }
            focusCount += 1
        }
        harness.extensionManager.testHooks.didActivateTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            activationCount += 1
        }
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            sourceOpenCount += 1
            guard sourceOpenCount <= 2 else { return }
            harness.extensionManager.reloadRuntimePublications(
                reason: "ExtensionActionPopupSourceReceiptTests.overflow",
                profileID: harness.profile.id
            )
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didFocusWindow = nil
            harness.extensionManager.testHooks.didActivateTab = nil
        }

        harness.extensionManager.reloadRuntimePublications(
            reason: "ExtensionActionPopupSourceReceiptTests.overflowStart",
            profileID: harness.profile.id
        )

        XCTAssertEqual(
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration,
            generationBeforeReload + 2
        )
        XCTAssertEqual(sourceOpenCount, 2)
        XCTAssertEqual(focusCount, 1)
        XCTAssertEqual(activationCount, 1)

        for _ in 0 ..< 8 where sourceOpenCount < 3 {
            await Task.yield()
        }

        XCTAssertEqual(
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration,
            generationBeforeReload + 3
        )
        XCTAssertEqual(sourceOpenCount, 3)
        XCTAssertEqual(focusCount, 2)
        XCTAssertEqual(activationCount, 2)
    }

    func testPreHandoffPhysicalTabCloseRetiresExactAdapter()
        async throws {
        let harness = try await makeHarness(
            extensionID: "reload-pre-handoff-close"
        )
        let closingTab = harness.sourceTab
        let closingAdapter = try XCTUnwrap(
            harness.extensionManager.adapterStore.tabAdapters[closingTab.id]
        )
        harness.extensionManager.extensionsLoaded = false
        var didCloseCount = 0
        var didReopenCount = 0
        var closedDuringWindowCallback = false
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            if tabID == closingTab.id {
                didCloseCount += 1
            }
        }
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            if tabID == closingTab.id {
                didReopenCount += 1
            }
        }
        harness.extensionManager.testHooks.didOpenNormalWindow = { windowID in
            guard windowID == harness.windowState.id,
                  closedDuringWindowCallback == false
            else {
                return
            }
            closedDuringWindowCallback = true
            harness.browserManager.tabLifecycleService.closeOrchestration
                .closeTab(closingTab, in: harness.windowState)
        }
        defer {
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didOpenNormalWindow = nil
        }

        harness.extensionManager.reloadRuntimePublications(
            reason: "ExtensionActionPopupSourceReceiptTests.preHandoffClose",
            allowWhenExtensionsNotLoaded: true,
            profileID: harness.profile.id
        )

        XCTAssertTrue(closedDuringWindowCallback)
        // The physical close happens before browser-event handoff, so this Tab
        // never publishes in the replacement generation. Its deferred receipt
        // must retire the exact adapter without emitting an unmatched close.
        XCTAssertEqual(didCloseCount, 0)
        XCTAssertEqual(didReopenCount, 0)
        XCTAssertNil(
            harness.browserManager.tabManager.tabCollectionMembershipOwner
                .tab(for: closingTab.id)
        )
        XCTAssertNil(
            harness.extensionManager.adapterStore.tabAdapters[closingTab.id]
        )
        XCTAssertFalse(
            harness.extensionContext.openTabs.contains { openTab in
                (openTab as AnyObject) === closingAdapter
            }
        )
    }

    func testRuntimeReconciliationDoesNotActivateStaleFocusTarget()
        async throws {
        let harness = try await makeHarness(extensionID: "focus-reentry")
        var activatedTabIDs: [UUID] = []
        harness.extensionManager.testHooks.didFocusWindow = { windowID in
            guard windowID == harness.windowState.id else { return }
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration &+= 1
        }
        harness.extensionManager.testHooks.didActivateTab = { tabID in
            activatedTabIDs.append(tabID)
        }

        harness.extensionManager.reloadRuntimePublications(
            reason: "ExtensionActionPopupSourceReceiptTests.focusReentry",
            profileID: harness.profile.id
        )

        XCTAssertTrue(activatedTabIDs.isEmpty)
    }

    func testTabPropertyEventRequiresCurrentOpenPublication() async throws {
        let harness = try await makeHarness(
            extensionID: "property-publication-receipt"
        )
        let generation = harness.extensionManager.runtimeSession
            .tabOpenNotificationGeneration
        XCTAssertTrue(
            harness.sourceTab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation)
        )
        XCTAssertTrue(
            harness.extensionManager.windowPublications
                .tabPublicationIsCurrent(
                    harness.sourceTab,
                    profileID: harness.profile.id
                )
        )

        var changedProperties: [WKWebExtension.TabChangedProperties] = []
        harness.extensionManager.testHooks.didChangeTabProperties = {
            tabID, properties in
            guard tabID == harness.sourceTab.id else { return }
            changedProperties.append(properties)
        }
        harness.sourceTab.name = "Receipt Guard Title"
        harness.sourceTab.extensionPageRuntimeOwner
            .clearOpenNotificationGeneration()
        defer {
            _ = harness.sourceTab.extensionPageRuntimeOwner.markDidOpenTab(
                generation: generation
            )
            harness.extensionManager.testHooks.didChangeTabProperties = nil
        }

        harness.extensionManager.notifyTabPropertiesChanged(
            harness.sourceTab,
            properties: [.title]
        )

        XCTAssertTrue(changedProperties.isEmpty)
    }

    func testNormalTabCloseClaimsGenerationBeforeReentrantCallbackAndPreservesReplacementAdapter()
        async throws {
        let harness = try await makeHarness(extensionID: "close-reentry")
        let replacementTab = try makeInactivePublishedTab(
            harness: harness,
            url: URL(string: "https://replacement.example.test/")!
        )
        let replacementAdapter = try XCTUnwrap(
            harness.extensionManager.adapterStore.tabAdapters[
                replacementTab.id
            ]
        )
        let closingAdapter = try XCTUnwrap(
            harness.extensionManager.adapterStore.tabAdapters[
                harness.sourceTab.id
            ]
        )
        var closeCount = 0
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            closeCount += 1
            harness.extensionManager.normalTabClosure.close(harness.sourceTab)
            harness.extensionManager.adapterStore.tabAdapters[
                harness.sourceTab.id
            ] = replacementAdapter
        }
        defer {
            harness.extensionManager.testHooks.didCloseTab = nil
            if harness.extensionManager.adapterStore.tabAdapters[
                harness.sourceTab.id
            ] === replacementAdapter {
                harness.extensionManager.adapterStore.tabAdapters
                    .removeValue(forKey: harness.sourceTab.id)
            }
        }

        harness.extensionManager.normalTabClosure.close(harness.sourceTab)

        XCTAssertEqual(closeCount, 1)
        XCTAssertFalse(
            harness.sourceTab.extensionPageRuntimeOwner
                .hasAnyDidOpenTabNotification()
        )
        XCTAssertIdentical(
            harness.extensionManager.adapterStore.tabAdapters[
                harness.sourceTab.id
            ],
            replacementAdapter
        )
        XCTAssertNotIdentical(replacementAdapter, closingAdapter)
    }

    func testNormalTabActivationStopsBeforeSelectionWhenDidActivateReenters()
        async throws {
        let harness = try await makeHarness(extensionID: "activate-reentry")
        var activated: [UUID] = []
        var selected: [UUID] = []
        var deselected: [UUID] = []
        harness.extensionManager.testHooks.didActivateTab = { tabID in
            activated.append(tabID)
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration &+= 1
        }
        harness.extensionManager.testHooks.didSelectTab = {
            selected.append($0)
        }
        harness.extensionManager.testHooks.didDeselectTab = {
            deselected.append($0)
        }
        defer {
            harness.extensionManager.testHooks.didActivateTab = nil
            harness.extensionManager.testHooks.didSelectTab = nil
            harness.extensionManager.testHooks.didDeselectTab = nil
        }

        harness.extensionManager.normalTabActivation.activate(
            harness.sourceTab,
            previous: nil
        )

        XCTAssertEqual(activated, [harness.sourceTab.id])
        XCTAssertTrue(selected.isEmpty)
        XCTAssertTrue(deselected.isEmpty)
    }

    func testNormalTabActivationStopsBeforeDeselectionWhenDidSelectReenters()
        async throws {
        let harness = try await makeHarness(extensionID: "select-reentry")
        let activatedTab = try makeInactivePublishedTab(
            harness: harness,
            url: URL(string: "https://activated.example.test/")!
        )
        let spaceID = try XCTUnwrap(harness.windowState.currentSpaceId)
        harness.windowState.currentTabId = activatedTab.id
        harness.windowState.activeTabForSpace[spaceID] = activatedTab.id
        harness.browserManager.tabManager.spaceStateOwner.space(
            with: spaceID
        )?.activeTabId = activatedTab.id

        var activated: [UUID] = []
        var selected: [UUID] = []
        var deselected: [UUID] = []
        harness.extensionManager.testHooks.didActivateTab = {
            activated.append($0)
        }
        harness.extensionManager.testHooks.didSelectTab = { tabID in
            selected.append(tabID)
            harness.extensionManager.runtimeSession
                .tabOpenNotificationGeneration &+= 1
        }
        harness.extensionManager.testHooks.didDeselectTab = {
            deselected.append($0)
        }
        defer {
            harness.extensionManager.testHooks.didActivateTab = nil
            harness.extensionManager.testHooks.didSelectTab = nil
            harness.extensionManager.testHooks.didDeselectTab = nil
        }

        harness.extensionManager.normalTabActivation.activate(
            activatedTab,
            previous: harness.sourceTab
        )

        XCTAssertEqual(activated, [activatedTab.id])
        XCTAssertEqual(selected, [activatedTab.id])
        XCTAssertTrue(deselected.isEmpty)
    }

    private func makeHarness(extensionID: String) async throws -> Harness {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Action Popup Source")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionManager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            moduleRegistry: registry
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in extensionManager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        extensionsModule.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )
        XCTAssertIdentical(
            try XCTUnwrap(extensionsModule.managerIfEnabled()),
            extensionManager
        )
        extensionManager.runtimeSession.allowsRuntimeWithoutEnabledExtensions = true
        extensionManager.extensionsLoaded = true

        let space = Space(name: "Source Space", profileId: profile.id)
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        let sourceWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowRegistry.bindAppKitWindow(sourceWindow, to: windowState)
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        let sourceTab = browserManager.tabManager.regularTabLifecycleOwner
            .createNewTab(
                url: "safari-web-extension://\(extensionID)/popup.html",
                in: space,
                activate: true
            )
        sourceTab.profileId = profile.id
        browserManager.selectTab(sourceTab, in: windowState)

        let extensionContext = try await makeExtensionContext(
            extensionID: extensionID
        )
        extensionManager.setExtensionContext(
            extensionContext,
            extensionId: extensionID,
            profileId: profile.id
        )
        _ = extensionManager.ensureExtensionController(for: profile.id)
        let sourceWebView = try XCTUnwrap(
            sourceTab.makeNormalTabWebView(
                reason: "ExtensionActionPopupSourceReceiptTests.makeHarness"
            )
        )
        browserManager.testWebViewRuntime().trackedWebViewAdmission.attemptAssignment(
            sourceWebView,
            to: sourceTab,
            in: windowState.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )
        extensionManager.reloadRuntimePublications(
            reason: "ExtensionActionPopupSourceReceiptTests.makeHarness",
            profileID: profile.id
        )
        XCTAssertTrue(
            extensionManager.isTabEligibleForCurrentExtensionRuntime(sourceTab)
        )
        XCTAssertNotNil(
            extensionManager.adapterStore.existingWindowAdapter(
                for: windowState.id
            )
        )
        _ = try XCTUnwrap(
            extensionManager.adapterResolutionOwner
                .publishedNormalWindowAdapter(
                    for: windowState,
                    extensionContext: extensionContext
                )
        )

        return Harness(
            container: container,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            extensionManager: extensionManager,
            sourceTab: sourceTab,
            profile: profile,
            windowState: windowState,
            extensionContext: extensionContext
        )
    }

    private func makeExtensionContext(
        extensionID: String
    ) async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Action Popup \(extensionID)",
            "version": "1.0",
            "permissions": ["tabs", "windows"],
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try Data("<!doctype html><title>popup</title>".utf8).write(
            to: directory.appendingPathComponent("popup.html"),
            options: [.atomic]
        )
        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        return WKWebExtensionContext(for: webExtension)
    }

    private func makeInactivePublishedTab(
        harness: Harness,
        url: URL
    ) throws -> Tab {
        let controller = try XCTUnwrap(
            harness.extensionManager.profileRuntime.controller(
                for: harness.profile.id
            )
        )
        let windowAdapter = try XCTUnwrap(
            harness.extensionManager.adapterResolutionOwner
                .publishedNormalWindowAdapter(
                    for: harness.windowState,
                    extensionContext: harness.extensionContext
                )
        )
        let tab = try harness.extensionManager.requestedTabOpening.open(
            url: url,
            shouldBeActive: false,
            shouldBePinned: false,
            requestedWindow: windowAdapter,
            controller: controller,
            extensionContext: harness.extensionContext,
            reason: #function
        )
        XCTAssertTrue(
            tab.extensionPageRuntimeOwner.hasDidOpenTabNotification(
                for: harness.extensionManager.runtimeSession
                    .tabOpenNotificationGeneration
            )
        )
        return tab
    }

    private func makePopupSource(
        harness: Harness,
        extensionID: String
    ) throws -> (
        webView: WKWebView,
        receipt: ExtensionActionPopupSourceReceipt
    ) {
        let webView = WKWebView(
            frame: .zero,
            configuration: configuration(dataStore: harness.profile.dataStore)
        )
        let anchor = ExtensionActionPopupAnchor(
            extensionID: extensionID,
            profileID: harness.profile.id,
            windowID: harness.windowState.id,
            tabID: harness.sourceTab.id,
            buttonView: nil,
            validatedRectInWindow: nil
        )
        let receipt = try XCTUnwrap(
            ExtensionActionPopupSourceReceipt.capture(
                extensionID: extensionID,
                profileID: harness.profile.id,
                anchor: anchor,
                popupWebView: webView,
                manager: harness.extensionManager
            )
        )
        return (webView, receipt)
    }

    private func nestedNavigationAction(
        extensionID: String,
        webView: WKWebView
    ) -> WKNavigationAction {
        navigationAction(
            sourceURL: URL(
                string: "safari-web-extension://\(extensionID)/popup.html"
            ),
            targetURL: URL(
                string: "safari-web-extension://\(extensionID)/nested.html"
            )!,
            webView: webView
        )
    }

    private func navigationAction(
        sourceURL: URL?,
        targetURL: URL,
        webView: WKWebView
    ) -> WKNavigationAction {
        let sourceFrame = sourceURL.map {
            ExtensionActionPopupNavigationFrameMock(
                request: URLRequest(url: $0),
                securityOrigin: ExtensionActionPopupSecurityOriginMock.new(
                    url: $0
                ),
                webView: webView
            ).frameInfo
        }
        return ExtensionActionPopupNavigationActionMock(
            sourceFrame: sourceFrame,
            request: URLRequest(url: targetURL)
        ).navigationAction
    }

    private func configuration(
        dataStore: WKWebsiteDataStore
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return configuration
    }

    private func mutationSnapshot(_ harness: Harness) -> MutationSnapshot {
        MutationSnapshot(
            regularTabIDs: Set(
                harness.browserManager.tabManager
                    .regularTabCollectionStateOwner.allTabsSnapshot().map(\.id)
            ),
            transientTabIDs: Set(
                harness.browserManager.tabManager.transientTabRegistryOwner
                    .auxiliaryMiniWindowTabsByID.keys
            ),
            sessionIDs: Set(
                harness.browserManager.auxiliaryWindows.sessions
                    .sessionsSnapshot().map(\.id)
            )
        )
    }
}

@available(macOS 15.5, *)
private final class ExtensionActionPopupNavigationActionMock: NSObject {
    @objc var sourceFrame: WKFrameInfo?
    @objc var targetFrame: WKFrameInfo?
    @objc var navigationType: WKNavigationType = .linkActivated
    @objc var request: URLRequest
    @objc var isUserInitiated = false

    init(sourceFrame: WKFrameInfo?, request: URLRequest) {
        self.sourceFrame = sourceFrame
        self.request = request
    }

    var navigationAction: WKNavigationAction {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKNavigationAction.self, capacity: 1) {
                $0.pointee
            }
        }
    }
}

@available(macOS 15.5, *)
private final class ExtensionActionPopupNavigationFrameMock: NSObject {
    @objc var isMainFrame = true
    @objc var request: URLRequest?
    @objc var securityOrigin: WKSecurityOrigin
    @objc weak var webView: WKWebView?

    init(
        request: URLRequest?,
        securityOrigin: WKSecurityOrigin,
        webView: WKWebView?
    ) {
        self.request = request
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) {
                $0.pointee
            }
        }
    }
}

@available(macOS 15.5, *)
@objc
private final class ExtensionActionPopupSecurityOriginMock: WKSecurityOrigin {
    private var mockedProtocol = ""
    private var mockedHost = ""
    private var mockedPort = 0

    override var `protocol`: String { mockedProtocol }
    override var host: String { mockedHost }
    override var port: Int { mockedPort }

    static func new(url: URL) -> ExtensionActionPopupSecurityOriginMock {
        let mock = perform(NSSelectorFromString("alloc"))
            .takeUnretainedValue() as! ExtensionActionPopupSecurityOriginMock
        mock.mockedProtocol = url.scheme ?? ""
        mock.mockedHost = url.host ?? ""
        mock.mockedPort = url.port ?? 0
        return mock
    }
}
