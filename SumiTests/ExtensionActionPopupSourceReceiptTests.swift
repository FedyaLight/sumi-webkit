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
        let inspection: ExtensionManagerTestInspection
        let attachedRuntime: ExtensionAttachedBrowserRuntimeInspection
        let sourceTab: Tab
        let profile: Profile
        let windowState: BrowserWindowState
        let extensionContext: WKWebExtensionContext
    }

    func testStaleNormalWindowCloseCannotRetireReplacementWithSameUUID()
        async throws {
        let harness = try await makeHarness(
            extensionID: "stale-window-close"
        )
        let staleWindow = harness.windowState
        let staleAdapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.existingWindowAdapter(
                for: staleWindow.id
            )
        )

        harness.attachedRuntime.publications.normalWindows.closed(staleWindow)
        harness.windowRegistry.unregister(staleWindow.id)

        let replacementWindow = BrowserWindowState(id: staleWindow.id)
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(on: replacementWindow)
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
            harness.attachedRuntime.publications.normalWindows.opened(
                replacementWindow
            )
        )
        let replacementAdapter = try XCTUnwrap(
            harness.attachedRuntime.adapters
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

        harness.attachedRuntime.publications.normalWindows.closed(staleWindow)

        XCTAssertIdentical(
            harness.inspection.normalTabs.adapters.existingWindowAdapter(
                for: replacementWindow.id
            ),
            replacementAdapter
        )
        XCTAssertIdentical(
            harness.attachedRuntime.publications.windowPublications
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
            harness.attachedRuntime.adapters.stableAdapter(
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
        harness.inspection.contextState.profiles.setContext(
            profileBContext,
            extensionId: extensionID,
            profileId: executionProfile.id
        )
        _ = harness.inspection.controller.provisioning.ensureExtensionController(
            for: executionProfile.id
        )
        XCTAssertNil(
            harness.attachedRuntime.adapters
                .publishedNormalWindowAdapter(
                    for: harness.windowState,
                    extensionContext: profileBContext
                )
        )

        let space = try XCTUnwrap(
            harness.browserManager.spaceStateOwner.currentSpace
        )
        let executionTab = harness.browserManager
            .regularTabLifecycleOwner.createNewTab(
                url: "https://profile-b.example.test/",
                in: space,
                activate: false,
                executionProfileID: executionProfile.id
            )
        harness.browserManager.selectTab(executionTab, in: harness.windowState)
        harness.attachedRuntime.publications.tabActivation.activate(
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
            harness.inspection.contextState.profiles
                .controllersByProfile[harness.profile.id]
        )
        let space = try XCTUnwrap(
            harness.browserManager.spaceStateOwner.currentSpace
        )
        let backgroundTab = harness.browserManager
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

        let oldGeneration = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        let expectedTabs = [harness.sourceTab, backgroundTab]
        for tab in expectedTabs {
            tab.extensionPageRuntimeOwner.prepareGeneration(oldGeneration)
            tab.extensionPageRuntimeOwner.markEligible(for: oldGeneration)
        }
        XCTAssertTrue(
            harness.attachedRuntime.publications.normalWindows.opened(
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
            [harness.sourceTab.id],
            "A prepared but unsettled background Tab must remain hidden outside an open callback"
        )
        for tab in expectedTabs {
            XCTAssertTrue(
                harness.attachedRuntime.bridge.tabs
                    .allExtensionTabs.contains {
                    $0 === tab
                },
                "Missing runtime Tab \(tab.id)"
            )
            XCTAssertTrue(
                harness.attachedRuntime.bridge.webViews
                    .extensionLiveWebViews(for: tab).contains {
                    $0.configuration.webExtensionController === controller
                },
                "Missing controller-bound WebView for \(tab.id)"
            )
            XCTAssertIdentical(
                harness.attachedRuntime.bridge.windows
                    .preferredExtensionWindowState(containing: tab),
                harness.windowState
            )
        }

        var tabIDsVisibleAtOpen: [Set<UUID>] = []
        var activeTabWasVisibleAtOpen: [Bool] = []
        harness.extensionManager.testHooks.didOpenTab = { _ in
            guard let window = harness.attachedRuntime.adapters.publishedNormalWindowAdapter(
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

        harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "ExtensionActionPopupSourceReceiptTests.atomicGeneration",
            profileID: harness.profile.id
        )

        for tab in expectedTabs {
            XCTAssertTrue(
                harness.attachedRuntime.normalTabs.preparedTabs
                    .containsPreparedTab(tab),
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
        let generationBeforeReload = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        var sourceOpenCount = 0
        var requestedNestedReload = false
        var nestedReloadGeneration: (
            before: ExtensionTabPublicationRevision,
            after: ExtensionTabPublicationRevision
        )?

        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            sourceOpenCount += 1
            guard requestedNestedReload == false else { return }
            requestedNestedReload = true

            let before = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
                reason: "ExtensionActionPopupSourceReceiptTests.nestedReload",
                profileID: harness.profile.id
            )
            nestedReloadGeneration = (
                before: before,
                after: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            )
        }
        defer { harness.extensionManager.testHooks.didOpenTab = nil }

        harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "ExtensionActionPopupSourceReceiptTests.reloadHandoff",
            profileID: harness.profile.id
        )

        XCTAssertEqual(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue().generation,
            generationBeforeReload.generation + 2
        )
        XCTAssertEqual(
            nestedReloadGeneration?.before,
            nestedReloadGeneration?.after,
            "The callback reload must be deferred, not nested synchronously"
        )
        XCTAssertEqual(sourceOpenCount, 2)
        XCTAssertTrue(
            harness.attachedRuntime.publications.normalWindows
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
        let generation = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        try retireCurrentOpenForRepublication(
            harness: harness,
            tab: tab,
            generation: generation
        )
        let adapter = try XCTUnwrap(
            harness.attachedRuntime.adapters
                .stableAdapter(for: tab)
        )
        var didCloseCount = 0
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == tab.id else { return }
            didCloseCount += 1
        }
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == tab.id else { return }
            _ = harness.inspection.normalTabs.adapters.removeTabAdapter(
                for: tab.id,
                ifIdenticalTo: adapter
            )
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.inspection.normalTabs.adapters.tabAdapters[tab.id]
                = adapter
        }

        XCTAssertFalse(
            harness.attachedRuntime.normalTabs.tabOpening.publishOpen(tab)
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
        let generation = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        try retireCurrentOpenForRepublication(
            harness: harness,
            tab: tab,
            generation: generation
        )
        let adapter = try XCTUnwrap(
            harness.attachedRuntime.adapters
                .stableAdapter(for: tab)
        )
        var didCloseCount = 0
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == tab.id else { return }
            didCloseCount += 1
        }
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == tab.id else { return }
            harness.inspection.contextState.profiles.setContext(
                harness.extensionContext,
                extensionId: extensionID,
                profileId: harness.profile.id
            )
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.inspection.normalTabs.adapters.tabAdapters[tab.id]
                = adapter
        }

        XCTAssertFalse(harness.attachedRuntime.normalTabs.tabOpening.publishOpen(tab))
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
        let selectedTab = harness.browserManager
            .regularTabLifecycleOwner.createNewTab(
                url: "about:blank",
                in: harness.browserManager.spaceStateOwner
                    .currentSpace,
                activate: true
            )
        selectedTab.profileId = harness.profile.id
        harness.browserManager.selectTab(
            selectedTab,
            in: harness.windowState
        )
        harness.attachedRuntime.publications.tabClosure.close(tab)
        let adapter = try XCTUnwrap(
            harness.attachedRuntime.adapters
                .stableAdapter(for: tab)
        )
        harness.attachedRuntime.publications.normalWindows.closed(
            harness.windowState
        )

        var didOpenCount = 0
        var didCloseCount = 0
        harness.extensionManager.testHooks.didOpenNormalWindow = { windowID in
            guard windowID == harness.windowState.id else { return }
            _ = harness.inspection.normalTabs.adapters.removeTabAdapter(
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
            harness.inspection.normalTabs.adapters.tabAdapters[tab.id]
                = adapter
        }

        XCTAssertFalse(harness.attachedRuntime.normalTabs.tabOpening.publishOpen(tab))
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
        let generationBeforeReload = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        var sourceOpenCount = 0
        harness.extensionManager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            sourceOpenCount += 1
            harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
                reason: "ExtensionActionPopupSourceReceiptTests.repeatedNestedReload",
                profileID: harness.profile.id
            )
        }
        defer { harness.extensionManager.testHooks.didOpenTab = nil }

        harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "ExtensionActionPopupSourceReceiptTests.boundedReload",
            profileID: harness.profile.id
        )

        XCTAssertEqual(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue().generation,
            generationBeforeReload.generation + 2
        )
        XCTAssertEqual(sourceOpenCount, 2)

        for _ in 0..<8 where sourceOpenCount < 4 {
            await Task.yield()
        }
        XCTAssertEqual(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue().generation,
            generationBeforeReload.generation + 4
        )
        XCTAssertEqual(sourceOpenCount, 4)

        for _ in 0..<8 {
            await Task.yield()
        }
        XCTAssertEqual(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue().generation,
            generationBeforeReload.generation + 4
        )
        XCTAssertEqual(sourceOpenCount, 4)
    }

    func testSecondReplayRequestContinuesOnLaterMainActorTurn()
        async throws {
        let harness = try await makeHarness(
            extensionID: "reload-handoff-overflow"
        )
        let generationBeforeReload = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
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
            harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
                reason: "ExtensionActionPopupSourceReceiptTests.overflow",
                profileID: harness.profile.id
            )
        }
        defer {
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didFocusWindow = nil
            harness.extensionManager.testHooks.didActivateTab = nil
        }

        harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "ExtensionActionPopupSourceReceiptTests.overflowStart",
            profileID: harness.profile.id
        )

        XCTAssertEqual(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue().generation,
            generationBeforeReload.generation + 2
        )
        XCTAssertEqual(sourceOpenCount, 2)
        XCTAssertEqual(focusCount, 1)
        XCTAssertEqual(activationCount, 1)

        for _ in 0..<8 where sourceOpenCount < 3 {
            await Task.yield()
        }

        XCTAssertEqual(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue().generation,
            generationBeforeReload.generation + 3
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
            harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id]
        )
        let openingController = try XCTUnwrap(
            harness.inspection.contextState.profiles.controller(
                for: harness.profile.id
            )
        )
        let replacementController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        let replacementTab = try makeInactivePublishedTab(
            harness: harness,
            url: URL(string: "https://replacement.example.test/")!
        )
        let replacementAdapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[
                replacementTab.id
            ]
        )
        harness.inspection.actionSurfaces.publication.resetRuntimePublicationReadiness()
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
            // The window callback belongs to `openingController`. Rebinding
            // the profile before physical close must not redirect the close
            // to a controller that never exposed this adapter.
            harness.inspection.contextState.profiles.setController(
                replacementController,
                for: harness.profile.id
            )
            harness.browserManager.tabCloseOrchestration
                .closeTab(closingTab, in: harness.windowState)
            harness.inspection.contextState.profiles.setController(
                openingController,
                for: harness.profile.id
            )
            // Exact WebKit retirement is independent from store retirement.
            // A replacement installed before deferred drain must survive.
            harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id] =
                replacementAdapter
        }
        defer {
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.extensionManager.testHooks.didOpenTab = nil
            harness.extensionManager.testHooks.didOpenNormalWindow = nil
            if harness.inspection.normalTabs.adapters.tabAdapters[
                closingTab.id
            ] === replacementAdapter {
                harness.inspection.normalTabs.adapters.tabAdapters
                    .removeValue(forKey: closingTab.id)
            }
        }

        harness.inspection.browserPublication.reloads.finalizeRuntimeLoad(
            reason: "ExtensionActionPopupSourceReceiptTests.preHandoffClose",
            profileID: harness.profile.id
        )

        XCTAssertTrue(closedDuringWindowCallback)
        // The first close retires the old generation. didOpenWindow then makes
        // the prepared adapter visible to WebKit before per-Tab handoff; the
        // deferred physical close must balance that implicit open exactly once.
        XCTAssertEqual(didCloseCount, 2)
        XCTAssertEqual(didReopenCount, 0)
        XCTAssertNil(
            harness.browserManager.tabCollectionMembershipOwner
                .tab(for: closingTab.id)
        )
        XCTAssertIdentical(
            harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id],
            replacementAdapter
        )
        XCTAssertFalse(
            closingTab.extensionPageRuntimeOwner.canPublishFutureOpenNotification()
        )
        XCTAssertFalse(
            harness.extensionContext.openTabs.contains { openTab in
                (openTab as AnyObject) === closingAdapter
            }
        )
    }

    func testImplicitWindowOpenCloseReceiptIsOneShotAcrossReentry()
        async throws {
        let harness = try await makeHarness(
            extensionID: "reload-implicit-close-reentry"
        )
        let closingTab = harness.sourceTab
        let closingAdapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id]
        )
        harness.inspection.actionSurfaces.publication.resetRuntimePublicationReadiness()

        var firstReceipt: ExtensionNormalTabCloseReceipt?
        var secondReceipt: ExtensionNormalTabCloseReceipt?
        var didCloseCount = 0
        var shouldReenter = false
        var didExerciseImplicitClose = false
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == closingTab.id else { return }
            didCloseCount += 1
            guard shouldReenter else { return }
            shouldReenter = false
            if let firstReceipt {
                harness.attachedRuntime.publications.tabClosure.close(firstReceipt)
            }
            if let secondReceipt {
                harness.attachedRuntime.publications.tabClosure.close(secondReceipt)
            }
        }
        harness.extensionManager.testHooks.didOpenNormalWindow = { windowID in
            guard windowID == harness.windowState.id,
                  didExerciseImplicitClose == false
            else {
                return
            }
            didExerciseImplicitClose = true
            firstReceipt = harness.attachedRuntime.publications.tabClosure
                .prepareClose(closingTab)
            secondReceipt = harness.attachedRuntime.publications.tabClosure
                .prepareClose(closingTab)
            guard let firstReceipt, let secondReceipt else {
                XCTFail("Expected two exact implicit-close receipts")
                return
            }
            shouldReenter = true
            harness.attachedRuntime.publications.tabClosure.close(firstReceipt)
            harness.attachedRuntime.publications.tabClosure.close(firstReceipt)
            harness.attachedRuntime.publications.tabClosure.close(secondReceipt)
        }
        defer {
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.extensionManager.testHooks.didOpenNormalWindow = nil
        }

        harness.inspection.browserPublication.reloads.finalizeRuntimeLoad(
            reason: "ExtensionActionPopupSourceReceiptTests.implicitCloseReentry",
            profileID: harness.profile.id
        )

        XCTAssertTrue(didExerciseImplicitClose)
        // One close retires the previous generation; exactly one more balances
        // the implicit didOpenWindow exposure despite duplicate receipts and
        // synchronous reentry.
        XCTAssertEqual(didCloseCount, 2)
        XCTAssertNil(
            harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id]
        )
        XCTAssertFalse(
            closingTab.extensionPageRuntimeOwner.canPublishFutureOpenNotification()
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
            _ = harness.inspection.runtimeAuthorities.tabPublicationRevisions.advance(
                ifCurrent: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            )
        }
        harness.extensionManager.testHooks.didActivateTab = { tabID in
            activatedTabIDs.append(tabID)
        }

        harness.inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "ExtensionActionPopupSourceReceiptTests.focusReentry",
            profileID: harness.profile.id
        )

        XCTAssertTrue(activatedTabIDs.isEmpty)
    }

    func testTabPropertyEventRequiresCurrentOpenPublication() async throws {
        let harness = try await makeHarness(
            extensionID: "property-publication-receipt"
        )
        let generation = harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        XCTAssertTrue(
            harness.sourceTab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation)
        )
        XCTAssertTrue(
            harness.attachedRuntime.publications.windowPublications
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

        harness.attachedRuntime.normalTabs.tabProperties.publishChange(
            for: harness.sourceTab,
            requested: [.title]
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
            harness.inspection.normalTabs.adapters.tabAdapters[
                replacementTab.id
            ]
        )
        let closingAdapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[
                harness.sourceTab.id
            ]
        )
        var closeCount = 0
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == harness.sourceTab.id else { return }
            closeCount += 1
            harness.attachedRuntime.publications.tabClosure.close(harness.sourceTab)
            harness.inspection.normalTabs.adapters.tabAdapters[
                harness.sourceTab.id
            ] = replacementAdapter
        }
        defer {
            harness.extensionManager.testHooks.didCloseTab = nil
            if harness.inspection.normalTabs.adapters.tabAdapters[
                harness.sourceTab.id
            ] === replacementAdapter {
                harness.inspection.normalTabs.adapters.tabAdapters
                    .removeValue(forKey: harness.sourceTab.id)
            }
        }

        harness.attachedRuntime.publications.tabClosure.close(harness.sourceTab)

        XCTAssertEqual(closeCount, 1)
        XCTAssertFalse(
            harness.sourceTab.extensionPageRuntimeOwner
                .hasAnyDidOpenTabNotification()
        )
        XCTAssertIdentical(
            harness.inspection.normalTabs.adapters.tabAdapters[
                harness.sourceTab.id
            ],
            replacementAdapter
        )
        XCTAssertNotIdentical(replacementAdapter, closingAdapter)
    }

    func testPhysicalCloseUsesOriginalPublicationAfterControllerAndAdapterRebind()
        async throws {
        let harness = try await makeHarness(
            extensionID: "close-exact-publication"
        )
        let closingTab = harness.sourceTab
        let openingController = try XCTUnwrap(
            harness.inspection.contextState.profiles.controller(
                for: harness.profile.id
            )
        )
        let closingAdapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id]
        )
        let replacementTab = try makeInactivePublishedTab(
            harness: harness,
            url: URL(string: "https://replacement.example.test/")!
        )
        let replacementAdapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[
                replacementTab.id
            ]
        )
        let replacementController = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        var closeCount = 0
        harness.extensionManager.testHooks.didCloseTab = { tabID in
            guard tabID == closingTab.id else { return }
            closeCount += 1
        }
        defer {
            harness.extensionManager.testHooks.didCloseTab = nil
            harness.inspection.contextState.profiles.setController(
                openingController,
                for: harness.profile.id
            )
            if harness.inspection.normalTabs.adapters.tabAdapters[
                closingTab.id
            ] === replacementAdapter {
                harness.inspection.normalTabs.adapters.tabAdapters
                    .removeValue(forKey: closingTab.id)
            }
        }

        harness.inspection.contextState.profiles.setController(
            replacementController,
            for: harness.profile.id
        )
        harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id] =
            replacementAdapter
        harness.attachedRuntime.publications.tabClosure.close(closingTab)

        XCTAssertEqual(closeCount, 1)
        XCTAssertFalse(
            harness.extensionContext.openTabs.contains { openTab in
                (openTab as AnyObject) === closingAdapter
            }
        )
        XCTAssertIdentical(
            harness.inspection.normalTabs.adapters.tabAdapters[closingTab.id],
            replacementAdapter
        )
        XCTAssertFalse(
            closingTab.extensionPageRuntimeOwner.hasAnyDidOpenTabNotification()
        )
        XCTAssertFalse(
            closingTab.extensionPageRuntimeOwner.canPublishFutureOpenNotification()
        )
    }

    func testNormalTabActivationStopsBeforeSelectionWhenDidActivateReenters()
        async throws {
        let harness = try await makeHarness(extensionID: "activate-reentry")
        var activated: [UUID] = []
        var selected: [UUID] = []
        var deselected: [UUID] = []
        harness.extensionManager.testHooks.didActivateTab = { tabID in
            activated.append(tabID)
            _ = harness.inspection.runtimeAuthorities.tabPublicationRevisions.advance(
                ifCurrent: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            )
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

        harness.attachedRuntime.publications.tabActivation.activate(
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
        harness.browserManager.spaceStateOwner.space(
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
            _ = harness.inspection.runtimeAuthorities.tabPublicationRevisions.advance(
                ifCurrent: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            )
        }
        harness.extensionManager.testHooks.didDeselectTab = {
            deselected.append($0)
        }
        defer {
            harness.extensionManager.testHooks.didActivateTab = nil
            harness.extensionManager.testHooks.didSelectTab = nil
            harness.extensionManager.testHooks.didDeselectTab = nil
        }

        harness.attachedRuntime.publications.tabActivation.activate(
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
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspectionCapture = ExtensionManagerInspectionCapture()
        let extensionManager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            moduleRegistry: registry,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspectionCapture
        )
        let inspection = inspectionCapture.inspection
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
            try XCTUnwrap(extensionsModule.managerForTesting()),
            extensionManager
        )
        inspection.runtimeAuthorities.demand
            .recordRuntimeDemandWithoutEnabledExtensions()
        inspection.actionSurfaces.publication.markRuntimePublicationReady()
        inspection.actionSurfaces.installedExtensions.upsert(
            makeInstalledExtension(extensionID: extensionID),
            durability: .volatileExactRuntime
        )

        let space = Space(name: "Source Space", profileId: profile.id)
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
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
        let sourceTab = browserManager.regularTabLifecycleOwner
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
        inspection.contextState.profiles.setContext(
            extensionContext,
            extensionId: extensionID,
            profileId: profile.id
        )
        let controller = inspection.controller.provisioning
            .ensureExtensionController(for: profile.id)
        try controller.load(extensionContext)
        addTeardownBlock {
            guard controller.extensionContexts.contains(extensionContext) else {
                return
            }
            try controller.unload(extensionContext)
        }
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
        inspection.browserPublication.reloads.reloadLoadedRuntime(
            reason: "ExtensionActionPopupSourceReceiptTests.makeHarness",
            profileID: profile.id
        )
        XCTAssertTrue(
            attachedRuntime.runtime.normalTabs.preparedTabs
                .containsPreparedTab(sourceTab)
        )
        XCTAssertNotNil(
            inspection.normalTabs.adapters.existingWindowAdapter(
                for: windowState.id
            )
        )
        _ = try XCTUnwrap(
            attachedRuntime.runtime.adapters
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
            inspection: inspection,
            attachedRuntime: attachedRuntime.runtime,
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
            harness.inspection.contextState.profiles.controller(
                for: harness.profile.id
            )
        )
        let windowAdapter = try XCTUnwrap(
            harness.attachedRuntime.adapters
                .publishedNormalWindowAdapter(
                    for: harness.windowState,
                    extensionContext: harness.extensionContext
                )
        )
        let tab = try harness.attachedRuntime
            .requestedTabs.opening.open(
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
                for: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            )
        )
        return tab
    }

    private func retireCurrentOpenForRepublication(
        harness: Harness,
        tab: Tab,
        generation: ExtensionTabPublicationRevision
    ) throws {
        let controller = try XCTUnwrap(
            harness.inspection.contextState.profiles.controller(
                for: harness.profile.id
            )
        )
        let adapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[tab.id]
        )
        XCTAssertTrue(
            tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(generation: generation)
        )
        controller.didCloseTab(adapter, windowIsClosing: false)
        XCTAssertTrue(
            harness.inspection.normalTabs.adapters.removeTabAdapter(
                for: tab.id,
                ifIdenticalTo: adapter
            )
        )
    }

    private func makeInstalledExtension(
        extensionID: String
    ) -> InstalledExtension {
        InstalledExtension(
            id: extensionID,
            name: "Action Popup \(extensionID)",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/\(extensionID)",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source-\(extensionID)",
            manifestRootFingerprint: "manifest-\(extensionID)",
            sourceBundlePath: "",
            optionsPagePath: nil,
            defaultPopupPath: "popup.html",
            hasBackground: false,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: true,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: true
            ),
            manifest: [:]
        )
    }
}
