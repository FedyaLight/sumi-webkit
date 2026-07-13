//
//  AuxiliaryWindowAdapterIdentityTests.swift
//  SumiTests
//

import AppKit
@testable import Sumi
import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
extension AuxiliaryWindowLifecycleTests {
    func testAuxiliaryTabAdapterIsInvisibleToUnrelatedSameProfileContext()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let unrelatedContext = try await makeExtensionContext(
            ownerExtensionID: "unrelated-owner"
        )
        harness.extensionManager.setExtensionContext(
            unrelatedContext,
            extensionId: "unrelated-owner",
            profileId: harness.profile.id
        )

        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: webView)
        )
        defer {
            if harness.browserManager.auxiliaryWindows.sessions
                .contains(webView) {
                harness.browserManager.auxiliaryWindows.teardown.teardown(
                    for: webView,
                    reason: .bulkCleanup
                )
            }
        }
        let tabAdapter = try XCTUnwrap(
            harness.extensionManager.adapterStore.tabAdapters[session.tab.id]
        )
        let windowAdapter = try XCTUnwrap(session.miniWindowAdapter)

        XCTAssertTrue(harness.extensionContext.openTabs.contains {
            ($0 as AnyObject) === tabAdapter
        })
        XCTAssertFalse(unrelatedContext.openTabs.contains {
            ($0 as AnyObject) === tabAdapter
        })
        XCTAssertEqual(tabAdapter.url(for: harness.extensionContext), session.tab.url)
        XCTAssertIdentical(
            tabAdapter.webView(for: harness.extensionContext),
            session.webView
        )
        XCTAssertTrue(
            (tabAdapter.window(for: harness.extensionContext) as AnyObject?)
                === windowAdapter
        )
        XCTAssertTrue(
            (windowAdapter.tabs(for: harness.extensionContext).first
                as AnyObject?) === tabAdapter
        )
        XCTAssertEqual(
            windowAdapter.frame(for: harness.extensionContext),
            session.window.frame
        )

        XCTAssertNil(tabAdapter.url(for: unrelatedContext))
        XCTAssertNil(tabAdapter.webView(for: unrelatedContext))
        XCTAssertNil(tabAdapter.window(for: unrelatedContext))
        XCTAssertFalse(tabAdapter.isLoadingComplete(for: unrelatedContext))
        XCTAssertFalse(
            tabAdapter.shouldGrantPermissionsOnUserGesture(
                for: unrelatedContext
            )
        )
        var closeError: Error?
        tabAdapter.close(for: unrelatedContext) { closeError = $0 }
        XCTAssertNotNil(closeError)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions.contains(webView)
        )

        let originalFrame = session.window.frame
        var unrelatedFrameError: Error?
        windowAdapter.setFrame(
            originalFrame.offsetBy(dx: 30, dy: 20),
            for: unrelatedContext
        ) { unrelatedFrameError = $0 }
        XCTAssertNotNil(unrelatedFrameError)
        XCTAssertEqual(session.window.frame, originalFrame)
        XCTAssertTrue(windowAdapter.tabs(for: unrelatedContext).isEmpty)
        XCTAssertEqual(windowAdapter.frame(for: unrelatedContext), .zero)

        let keyWindowBeforeRejectedFocus = NSApp.keyWindow
        var unrelatedFocusError: Error?
        windowAdapter.focus(for: unrelatedContext) {
            unrelatedFocusError = $0
        }
        XCTAssertNotNil(unrelatedFocusError)
        XCTAssertIdentical(NSApp.keyWindow, keyWindowBeforeRejectedFocus)

        var unrelatedCloseError: Error?
        windowAdapter.close(for: unrelatedContext) {
            unrelatedCloseError = $0
        }
        XCTAssertNotNil(unrelatedCloseError)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions.contains(webView)
        )

        let ownerFrame = originalFrame.offsetBy(dx: 12, dy: 8)
        var ownerFrameError: Error?
        windowAdapter.setFrame(ownerFrame, for: harness.extensionContext) {
            ownerFrameError = $0
        }
        XCTAssertNil(ownerFrameError)
        XCTAssertEqual(session.window.frame, ownerFrame)

        var ownerFocusError: Error?
        windowAdapter.focus(for: harness.extensionContext) {
            ownerFocusError = $0
        }
        XCTAssertNil(ownerFocusError)

        var ownerCloseError: Error?
        windowAdapter.close(for: harness.extensionContext) {
            ownerCloseError = $0
        }
        XCTAssertNil(ownerCloseError)
        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(webView)
        )
    }

    func testAuxiliaryTabCannotFallBackToNormalPublicationWithoutControl()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: webView)
        )
        let control = try XCTUnwrap(
            harness.extensionManager.extensionAuxiliaryWindows
        )
        harness.extensionManager.extensionAuxiliaryWindows = nil

        XCTAssertFalse(
            harness.extensionManager.windowPublications
                .tabPublicationIsCurrent(
                    session.tab,
                    profileID: harness.profile.id
                )
        )
        XCTAssertFalse(
            harness.extensionManager.tabPublicationAdmission.prepareTabOpen(
                session.tab
            )
        )

        harness.extensionManager.extensionAuxiliaryWindows = control
        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: webView,
            reason: .bulkCleanup
        )
    }

    func testRuntimeTeardownClosesAuxiliaryTabOnce() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: webView)
        )
        var closedTabCount = 0
        var closedWindowCount = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didCloseTab = {
            if $0 == session.tab.id { closedTabCount += 1 }
        }
        hooks.didCloseAuxiliaryWindow = {
            if $0 == session.id { closedWindowCount += 1 }
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        _ = harness.extensionManager.runtimePublicationReconciler.retire(
            runtime: harness.extensionManager.runtime,
            auxiliaryControl:
                harness.extensionManager.extensionAuxiliaryWindows
        )
        XCTAssertEqual(closedTabCount, 1)
        XCTAssertEqual(closedWindowCount, 1)

        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: webView,
            reason: .bulkCleanup
        )
        XCTAssertEqual(closedTabCount, 1)
        XCTAssertEqual(closedWindowCount, 1)
    }

    func testTerminalRuntimeRetirementRejectsReloadFromAuxiliaryCloseCallback()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        harness.extensionManager.reloadRuntimePublications(
            reason: "AuxiliaryWindowLifecycleTests.prepareTerminalRetirement",
            profileID: harness.profile.id
        )
        XCTAssertNotNil(
            harness.extensionManager.windowPublications
                .publishedWindowAdapter(
                    for: harness.windowState,
                    profileID: harness.profile.id
                )
        )
        XCTAssertTrue(
            harness.extensionManager.normalWindowLifecycle
                .tabPublicationIsCurrent(
                    harness.sourceTab,
                    profileID: harness.profile.id
                )
        )

        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: webView)
        )
        let generation = harness.extensionManager.tabPublicationRevisions.issue()
        var attemptedReload = false
        var publicationChangedDuringReloadAttempt = false
        var openedTabIDs: [UUID] = []
        var openedAuxiliaryWindowIDs: [UUID] = []
        var focusedNormalWindowIDs: [UUID] = []
        var focusedAuxiliaryWindowIDs: [UUID] = []
        var activatedTabIDs: [UUID] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenTab = { openedTabIDs.append($0) }
        hooks.didOpenAuxiliaryWindow = {
            openedAuxiliaryWindowIDs.append($0)
        }
        hooks.didFocusWindow = { focusedNormalWindowIDs.append($0) }
        hooks.didFocusAuxiliaryWindow = {
            focusedAuxiliaryWindowIDs.append($0)
        }
        hooks.didActivateTab = { activatedTabIDs.append($0) }
        hooks.didCloseAuxiliaryWindow = { sessionID in
            guard sessionID == session.id, attemptedReload == false else {
                return
            }
            attemptedReload = true
            let windowsBefore = Set(
                harness.extensionContext.openWindows.map {
                    ObjectIdentifier($0 as AnyObject)
                }
            )
            let tabsBefore = Set(
                harness.extensionContext.openTabs.map {
                    ObjectIdentifier($0 as AnyObject)
                }
            )

            harness.extensionManager.reloadRuntimePublications(
                reason:
                    "AuxiliaryWindowLifecycleTests.reentrantTerminalRetirement",
                profileID: harness.profile.id
            )

            publicationChangedDuringReloadAttempt = windowsBefore != Set(
                harness.extensionContext.openWindows.map {
                    ObjectIdentifier($0 as AnyObject)
                }
            ) || tabsBefore != Set(
                harness.extensionContext.openTabs.map {
                    ObjectIdentifier($0 as AnyObject)
                }
            )
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let outcome = harness.extensionManager.runtimePublicationReconciler
            .retire(
                runtime: harness.extensionManager.runtime,
                auxiliaryControl:
                    harness.extensionManager.extensionAuxiliaryWindows
            )

        XCTAssertEqual(outcome, .retired)
        XCTAssertTrue(attemptedReload)
        XCTAssertFalse(publicationChangedDuringReloadAttempt)
        XCTAssertEqual(
            harness.extensionManager.tabPublicationRevisions.issue(),
            generation,
            "A reload rejected by terminal retirement must not choose a new generation"
        )
        XCTAssertTrue(openedTabIDs.isEmpty)
        XCTAssertTrue(openedAuxiliaryWindowIDs.isEmpty)
        XCTAssertTrue(focusedNormalWindowIDs.isEmpty)
        XCTAssertTrue(focusedAuxiliaryWindowIDs.isEmpty)
        XCTAssertTrue(activatedTabIDs.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertNil(
            harness.extensionManager.windowPublications
                .publishedWindowAdapter(
                    for: harness.windowState,
                    profileID: harness.profile.id
                )
        )
        XCTAssertFalse(
            harness.extensionManager.normalWindowLifecycle
                .tabPublicationIsCurrent(
                    harness.sourceTab,
                    profileID: harness.profile.id
                )
        )
        XCTAssertFalse(
            harness.extensionManager.runtimePublicationGate
                .acceptsBrowserEvents
        )

        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: webView,
            reason: .bulkCleanup
        )
    }

    func testRuntimeReloadReopensAuxiliaryPublicationForNewGeneration()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: webView)
        )
        let tabAdapter = try XCTUnwrap(
            harness.extensionManager.adapterStore.tabAdapters[session.tab.id]
        )
        var openedTabCount = 0
        var closedTabCount = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenTab = {
            if $0 == session.tab.id { openedTabCount += 1 }
        }
        hooks.didCloseTab = {
            if $0 == session.tab.id { closedTabCount += 1 }
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        harness.extensionManager.reloadRuntimePublications(
            reason: "AuxiliaryWindowLifecycleTests.runtimeReload"
        )

        XCTAssertEqual(openedTabCount, 1)
        XCTAssertEqual(closedTabCount, 1)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions.contains(webView)
        )
        XCTAssertTrue(harness.extensionContext.openTabs.contains {
            ($0 as AnyObject) === tabAdapter
        })
        XCTAssertTrue(harness.extensionContext.openWindows.contains {
            ($0 as AnyObject) === session.miniWindowAdapter
        })

        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: webView,
            reason: .bulkCleanup
        )
        XCTAssertEqual(closedTabCount, 2)
    }

    func testRequestedTabRejectsForgedMiniWindowWithLiveIdentifiers()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: webView)
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: webView,
                reason: .bulkCleanup
            )
        }
        let forgedAdapter = ExtensionMiniWindowAdapter(
            sessionId: session.id,
            tab: session.tab,
            window: session.window,
            auxiliaryWindows: try XCTUnwrap(
                harness.extensionManager.extensionAuxiliaryWindows
            ),
            windowPublications: harness.extensionManager.windowPublications,
            isPrivate: session.isPrivate,
            shouldActivateApp: session.shouldActivateApp
        )
        XCTAssertFalse(forgedAdapter === session.miniWindowAdapter)

        XCTAssertThrowsError(
            try harness.extensionManager.requestedTabTargetResolver.resolve(
                requestedWindow: forgedAdapter,
                extensionContext: harness.extensionContext
            )
        )
    }

    func testRetiredAuxiliaryTabAdapterCannotRebindToNormalTabWithSameID()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions
                .session(for: webView)
        )
        let retiredAdapter = try XCTUnwrap(
            harness.extensionManager.adapterStore.tabAdapters[session.tab.id]
        )
        let reusedID = session.tab.id

        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: webView,
            reason: .bulkCleanup
        )
        XCTAssertNil(
            harness.extensionManager.adapterStore.tabAdapters[reusedID]
        )

        let replacement = Tab(
            id: reusedID,
            url: URL(string: "https://replacement.example")!,
            spaceId: harness.sourceTab.spaceId,
            webViewSessions: harness.browserManager.webViewSessions
        )
        replacement.profileId = harness.profile.id
        harness.browserManager.tabManager.regularTabLifecycleOwner.addTab(
            replacement
        )
        let replacementAdapter = try XCTUnwrap(
            harness.extensionManager.adapterCatalog
                .stableAdapter(for: replacement)
        )

        XCTAssertFalse(retiredAdapter === replacementAdapter)
        XCTAssertNil(retiredAdapter.tab)
        XCTAssertNil(retiredAdapter.url(for: harness.extensionContext))
        XCTAssertNil(retiredAdapter.window(for: harness.extensionContext))
        var staleCloseError: Error?
        retiredAdapter.close(for: harness.extensionContext) {
            staleCloseError = $0
        }
        XCTAssertNotNil(staleCloseError)
        XCTAssertIdentical(
            harness.extensionManager.adapterStore.tabAdapters[reusedID],
            replacementAdapter
        )

        let runtime = harness.extensionManager.runtime
        let windows = runtime.allWindowStates()
        harness.extensionManager.adapterStore.prune(
            liveTabs: harness.extensionManager.browserContentInventory.tabs(
                in: runtime
            ),
            liveWindowIDs: Set(windows.map(\.id))
        )
        XCTAssertIdentical(
            harness.extensionManager.adapterStore.tabAdapters[reusedID],
            replacementAdapter
        )
    }

    func testExtensionAuxiliaryWindowClosesItsPublishingContextAfterRuntimeReplacement() async throws {
        let ownerExtensionID = "adapter-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let extensionURL = URL(
            string: "safari-web-extension://\(ownerExtensionID)/popup.html"
        )!
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: URLRequest(
                        url: URL(string: "https://auth.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: extensionURL
                )
        )
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: popupWebView
            )
        )
        let publishedAdapter = try XCTUnwrap(session.miniWindowAdapter)

        XCTAssertTrue(
            harness.extensionContext.openWindows.contains { window in
                (window as AnyObject) === publishedAdapter
            }
        )

        let replacementContext = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        harness.extensionManager.setExtensionContext(
            replacementContext,
            extensionId: ownerExtensionID,
            profileId: harness.profile.id
        )

        XCTAssertTrue(
            harness.extensionManager.windowVisibilityResolver
                .miniWindowAdapters(
                    ownerExtensionID: ownerExtensionID,
                    profileId: harness.profile.id
                )
                .isEmpty,
            "A context replacement must immediately invalidate the old publication for queries"
        )

        harness.browserManager.auxiliaryWindows.teardown.closeAll(
            forExtensionID: ownerExtensionID
        )

        XCTAssertFalse(
            harness.extensionContext.openWindows.contains { window in
                (window as AnyObject) === publishedAdapter
            },
            "Close must balance the context that accepted didOpenWindow"
        )
        XCTAssertTrue(replacementContext.openWindows.isEmpty)
        XCTAssertNil(
            harness.extensionManager.adapterStore.existingMiniWindowAdapter(
                for: session.id
            )
        )
    }

    func testRejectedAuxiliaryPublicationRollsBackPresentedPopup() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )

        let popupWebView = harness.browserManager.auxiliaryWindows.popups
            .presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(
                    url: URL(string: "https://auth.example/login")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                ownerExtensionID: "unloaded-owner"
            )

        XCTAssertNil(popupWebView)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().isEmpty
        )
        XCTAssertTrue(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )
        XCTAssertTrue(
            harness.browserManager.tabManager.transientTabRegistryOwner
                .auxiliaryMiniWindowTabsByID.isEmpty
        )
    }

    func testRejectedExtensionWindowPublicationReturnsNoAdapter() async throws {
        let ownerExtensionID = "adapter-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let unboundContext = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        let configuration = AuxiliaryWindowConfigurationMock(
            windowType: .popup,
            tabURLs: [
                URL(
                    string: "safari-web-extension://\(ownerExtensionID)/unbound.html"
                )!,
            ],
            shouldBePrivate: false
        ).windowConfiguration

        let adapter = await harness.browserManager.auxiliaryWindows
            .extensionWindows.present(
                configuration: configuration,
                controller: harness.controller,
                extensionContext: unboundContext,
                extensionManager: harness.extensionManager,
                parentWindow: harness.windowRegistry.appKitWindow(
                    for: harness.windowState
                )
            )

        XCTAssertNil(adapter)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().isEmpty
        )
        XCTAssertTrue(
            harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().isEmpty
        )
        XCTAssertTrue(
            harness.browserManager.tabManager.transientTabRegistryOwner
                .auxiliaryMiniWindowTabsByID.isEmpty
        )
    }

    func testStaleAuxiliaryCloseCannotEvictDifferentPublishedSession()
        async throws {
        let ownerExtensionID = "adapter-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: nil,
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    ownerExtensionID: ownerExtensionID
                )
        )
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: popupWebView
            )
        )
        let publishedAdapter = try XCTUnwrap(session.miniWindowAdapter)
        defer {
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: popupWebView,
                reason: .bulkCleanup
            )
        }

        let staleSession = AuxiliaryWindowSession(
            id: session.id,
            tab: session.tab,
            window: session.window,
            webView: session.webView,
            openerTab: session.openerTab,
            openerWindow: session.openerWindow,
            shouldActivateApp: session.shouldActivateApp,
            isPrivate: session.isPrivate,
            ownerExtensionID: session.ownerExtensionID,
            miniWindowAdapter: publishedAdapter,
            extensionEvents: session.extensionEvents,
            uiDelegate: session.uiDelegate,
            windowDelegate: session.windowDelegate
        )

        harness.extensionManager.notifyAuxiliaryWindowClosed(staleSession)

        XCTAssertIdentical(
            harness.extensionManager.adapterStore.existingMiniWindowAdapter(
                for: session.id
            ),
            publishedAdapter
        )
        XCTAssertIdentical(
            harness.extensionManager.windowVisibilityResolver
                .miniWindowAdapters(
                    ownerExtensionID: ownerExtensionID,
                    profileId: harness.profile.id
                )
                .first,
            publishedAdapter
        )
    }

    func testStaleAuxiliaryClosePreservesReplacementAdapterWithSameSessionID() async throws {
        let ownerExtensionID = "adapter-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups
                .presentExtensionExternalWebPopup(
                    configuration: extensionPopupConfiguration(for: harness),
                    request: nil,
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: URL(
                        string: "safari-web-extension://\(ownerExtensionID)/popup.html"
                    )
                )
        )
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: popupWebView
            )
        )
        let retiredAdapter = try XCTUnwrap(session.miniWindowAdapter)

        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: popupWebView,
            reason: .bulkCleanup
        )

        let replacementAdapter = try XCTUnwrap(
            harness.extensionManager.adapterCatalog.miniWindowAdapter(
                for: session.id,
                tab: session.tab,
                window: NSWindow(),
                isPrivate: session.isPrivate,
                shouldActivateApp: session.shouldActivateApp
            )
        )
        defer {
            _ = harness.extensionManager.adapterStore.removeMiniWindowAdapter(
                for: session.id,
                ifIdenticalTo: replacementAdapter
            )
        }
        XCTAssertFalse(replacementAdapter === retiredAdapter)

        harness.extensionManager.notifyAuxiliaryWindowClosed(session)

        XCTAssertIdentical(
            harness.extensionManager.adapterStore.existingMiniWindowAdapter(
                for: session.id
            ),
            replacementAdapter
        )
    }
}
