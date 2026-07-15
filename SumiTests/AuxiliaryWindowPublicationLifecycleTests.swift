//
//  AuxiliaryWindowPublicationLifecycleTests.swift
//  SumiTests
//

import AppKit
@testable import Sumi
import WebKit
import XCTest

private struct AuxiliaryPublicationIdentityTuple: Equatable {
    let sessionIdentity: ObjectIdentifier
    let tabIdentity: ObjectIdentifier
    let windowIdentity: ObjectIdentifier
    let webViewIdentity: ObjectIdentifier
    let miniWindowAdapterIdentity: ObjectIdentifier
    let tabAdapterIdentity: ObjectIdentifier
}

@available(macOS 15.5, *)
@MainActor
extension AuxiliaryWindowLifecycleTests {
    func testExtensionAuxiliaryMiniWindowNotifiesOwnerContextWindowLifecycle() async throws {
        let harness = try await makeExtensionHarness(ownerExtensionID: "adapter-owner")
        let extensionURL = harness.extensionContext.baseURL
            .appendingPathComponent("popup.html")

        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertNil(harness.extensionContext.focusedWindow)

        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(url: URL(string: "https://auth.example/login")!),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: extensionURL
            )
        )
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(for: popupWebView)
        )

        let openedMiniWindow = try XCTUnwrap(
            harness.extensionContext.openWindows.first as? ExtensionMiniWindowAdapter
        )
        XCTAssertEqual(openedMiniWindow.sessionId, session.id)
        XCTAssertEqual(
            (harness.extensionContext.focusedWindow as? ExtensionMiniWindowAdapter)?.sessionId,
            session.id
        )

        harness.browserManager.auxiliaryWindows.teardown.closeAll(forExtensionID: "adapter-owner")
        XCTAssertFalse(
            harness.extensionContext.openWindows.contains { window in
                (window as? ExtensionMiniWindowAdapter)?.sessionId == session.id
            }
        )
    }

    func testAuxiliaryPublicationOpensOwnerWindowBeforeOwnerTab() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let configuration = extensionPopupConfiguration(for: harness)
        var events: [String] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { sessionID in
            events.append("window")
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.session(for: sessionID),
                let windowAdapter = session.miniWindowAdapter,
                let tabAdapter = harness.inspection.normalTabs.adapters
                    .tabAdapters[session.tab.id] else {
                return XCTFail("Prepared auxiliary publication is missing")
            }
            let browserTabs = harness.browserManager
                .extensionBridgeComposition.tabs
            XCTAssertIdentical(
                browserTabs.extensionTab(for: session.tab.id),
                session.tab
            )
            XCTAssertTrue(browserTabs.isAuxiliaryMiniWindowTab(session.tab))
            XCTAssertIdentical(
                harness.attachedRuntime.controller.controllers
                    .existingController(for: session.tab),
                configuration.webExtensionController
            )
            XCTAssertTrue(harness.extensionContext.openWindows.contains {
                ($0 as AnyObject) === windowAdapter
            })
            XCTAssertTrue(
                (windowAdapter.tabs(for: harness.extensionContext).first
                    as AnyObject?) === tabAdapter
            )
            XCTAssertFalse(
                session.tab.extensionPageRuntimeOwner
                    .hasDidOpenTabNotification(
                        for: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
                    )
            )
        }
        hooks.didOpenTab = { tabID in
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.sessionsSnapshot().first(where: {
                    $0.tab.id == tabID
                }), let windowAdapter = session.miniWindowAdapter,
                let tabAdapter = harness.inspection.normalTabs.adapters
                    .tabAdapters[tabID] else {
                return
            }
            events.append("tab")
            XCTAssertTrue(harness.extensionContext.openWindows.contains {
                ($0 as AnyObject) === windowAdapter
            })
            XCTAssertTrue(harness.extensionContext.openTabs.contains {
                ($0 as AnyObject) === tabAdapter
            })
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let webView = try XCTUnwrap(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                webView,
                reason: .bulkCleanup
            )
        }
        XCTAssertEqual(events, ["window", "tab"])
    }

    func testAuxiliaryPublicationRejectsContextReplacementDuringDidOpenWindow()
        async throws {
        let ownerExtensionID = "adapter-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let replacement = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        let configuration = extensionPopupConfiguration(for: harness)
        let preexistingWebView = try XCTUnwrap(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        let siblingWebView = try XCTUnwrap(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        defer {
            for webView in [preexistingWebView, siblingWebView] {
                harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                    webView,
                    reason: .bulkCleanup
                )
            }
        }
        let originalPublication = try auxiliaryPublicationIdentitySnapshot(
            harness
        )
        let originalSessionIDs = Set(originalPublication.keys)
        let originalTabIDs = Set(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().map(\.tab.id)
        )
        let originalWindowProjection = Set(
            harness.extensionContext.openWindows.map {
                ObjectIdentifier($0 as AnyObject)
            }
        )
        let originalTabProjection = Set(
            harness.extensionContext.openTabs.map {
                ObjectIdentifier($0 as AnyObject)
            }
        )
        let originalFocusedAdapter = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.focus
                .focusedMiniWindowAdapter(
                    forExtensionID: ownerExtensionID
                )
        )
        let originalMiniAdapterStore = Dictionary(
            uniqueKeysWithValues: harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().map {
                    ($0.sessionId, ObjectIdentifier($0))
                }
        )
        let originalTabAdapterStore = harness.inspection.normalTabs.adapters
            .tabAdapters.mapValues { ObjectIdentifier($0) }
        XCTAssertEqual(originalPublication.count, 2)
        XCTAssertEqual(originalWindowProjection.count, 2)
        XCTAssertEqual(originalTabProjection.count, 2)
        XCTAssertEqual(Set(originalMiniAdapterStore.keys), originalSessionIDs)
        var didReplace = false
        var openedTabCount = 0
        var closedTabCount = 0
        var failedSessionID: UUID?
        var failedTabID: UUID?
        var unrelatedEvents: [String] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { sessionID in
            if originalSessionIDs.contains(sessionID) {
                unrelatedEvents.append("open-window:\(sessionID)")
                return
            }
            guard didReplace == false else { return }
            guard let failedSession = harness.browserManager.auxiliaryWindows
                .sessions.session(for: sessionID) else {
                return XCTFail("Failed publication session was not indexed")
            }
            failedSessionID = sessionID
            failedTabID = failedSession.tab.id
            didReplace = true
            harness.inspection.contextState.profiles.setContext(
                replacement,
                extensionId: ownerExtensionID,
                profileId: harness.profile.id
            )
        }
        hooks.didOpenTab = { tabID in
            if originalTabIDs.contains(tabID) {
                unrelatedEvents.append("open-tab:\(tabID)")
            } else if tabID == failedTabID {
                openedTabCount += 1
            }
        }
        hooks.didCloseTab = { tabID in
            if originalTabIDs.contains(tabID) {
                unrelatedEvents.append("close-tab:\(tabID)")
            } else if tabID == failedTabID {
                closedTabCount += 1
            }
        }
        hooks.didCloseAuxiliaryWindow = { sessionID in
            if originalSessionIDs.contains(sessionID) {
                unrelatedEvents.append("close-window:\(sessionID)")
            } else {
                XCTAssertEqual(sessionID, failedSessionID)
            }
        }
        hooks.didFocusAuxiliaryWindow = { sessionID in
            if originalSessionIDs.contains(sessionID) {
                unrelatedEvents.append("focus-window:\(sessionID)")
            }
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        XCTAssertNil(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        XCTAssertTrue(didReplace)
        XCTAssertNotNil(failedSessionID)
        XCTAssertNotNil(failedTabID)
        XCTAssertEqual(openedTabCount, 0)
        XCTAssertEqual(closedTabCount, 0)
        XCTAssertTrue(unrelatedEvents.isEmpty, unrelatedEvents.joined(separator: ", "))
        XCTAssertIdentical(
            harness.browserManager.auxiliaryWindows.focus
                .focusedMiniWindowAdapter(
                    forExtensionID: ownerExtensionID
                ),
            originalFocusedAdapter
        )
        // A balanced WebKit didOpen/didClose can re-enumerate the stale
        // context's cached projections (`openTabs` is an NSSet). This rollback
        // oracle therefore freezes identity; focused-first delegate ordering
        // and Sumi's deterministic publication order are covered separately.
        XCTAssertEqual(
            Set(harness.extensionContext.openWindows.map {
                ObjectIdentifier($0 as AnyObject)
            }),
            originalWindowProjection
        )
        XCTAssertEqual(
            Set(harness.extensionContext.openTabs.map {
                ObjectIdentifier($0 as AnyObject)
            }),
            originalTabProjection
        )
        XCTAssertTrue(replacement.openWindows.isEmpty)
        XCTAssertTrue(replacement.openTabs.isEmpty)
        XCTAssertNil(replacement.focusedWindow)
        XCTAssertEqual(
            try auxiliaryPublicationIdentitySnapshot(harness),
            originalPublication
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: harness.inspection.normalTabs.adapters
                    .miniWindowAdaptersSnapshot().map {
                        ($0.sessionId, ObjectIdentifier($0))
                    }
            ),
            originalMiniAdapterStore
        )
        XCTAssertEqual(
            harness.inspection.normalTabs.adapters.tabAdapters
                .mapValues { ObjectIdentifier($0) },
            originalTabAdapterStore
        )
    }

    func testReentrantExternalPopupRejectionPreservesSameWebViewReplacement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let siblingWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: nil,
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab
            )
        )
        let sibling = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: siblingWebView
            )
        )
        var replacement: AuxiliaryWindowSession?
        var replacementReceipt: AuxiliaryWindowSessionReceipt?
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { sessionID in
            guard replacement == nil,
                  let failed = harness.browserManager.auxiliaryWindows
                    .sessions.session(for: sessionID) else {
                return
            }
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                failed.webView,
                reason: .bulkCleanup
            )
            let candidate = AuxiliaryWindowSession(
                id: UUID(),
                tab: failed.tab,
                window: failed.window,
                webView: failed.webView,
                openerTab: failed.openerTab,
                openerWindow: failed.openerWindow,
                shouldActivateApp: failed.shouldActivateApp,
                isPrivate: failed.isPrivate,
                ownerExtensionID: nil,
                miniWindowAdapter: nil,
                extensionEvents: nil,
                uiDelegate: failed.uiDelegate,
                windowDelegate: failed.windowDelegate
            )
            replacementReceipt = harness.browserManager.auxiliaryWindows
                .sessions.register(candidate)
            replacement = candidate
        }
        harness.extensionManager.testHooks = hooks
        defer {
            harness.extensionManager.clearDebugState()
            if let replacementReceipt {
                _ = harness.browserManager.auxiliaryWindows.sessions.remove(
                    replacementReceipt
                )
            }
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                siblingWebView,
                reason: .bulkCleanup
            )
        }

        XCTAssertNil(presentOwnerPopup(in: harness))

        let unwrappedReplacement = try XCTUnwrap(replacement)
        XCTAssertIdentical(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: unwrappedReplacement.webView
            ),
            unwrappedReplacement
        )
        XCTAssertIdentical(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: sibling.id
            ),
            sibling
        )
        XCTAssertEqual(
            Set(harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().map(\.id)),
            [unwrappedReplacement.id, sibling.id]
        )
    }

    func testAuxiliaryPublicationBalancesReentrantTeardownDuringDidOpenTab()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let configuration = extensionPopupConfiguration(for: harness)
        var openedTabID: UUID?
        var closedTabIDs: [UUID] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenTab = { tabID in
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.sessionsSnapshot().first(where: {
                    $0.tab.id == tabID
                }) else {
                return
            }
            openedTabID = tabID
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                session.webView,
                reason: .bulkCleanup
            )
        }
        hooks.didCloseTab = { closedTabIDs.append($0) }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        XCTAssertNil(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        let tabID = try XCTUnwrap(openedTabID)
        XCTAssertEqual(closedTabIDs.filter { $0 == tabID }, [tabID])
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().isEmpty
        )
    }

    func testAuxiliaryPublicationBalancesReentrantTeardownDuringFocus()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let configuration = extensionPopupConfiguration(for: harness)
        var focusedSessionID: UUID?
        var openedTabIDs: [UUID] = []
        var closedTabIDs: [UUID] = []
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenTab = { openedTabIDs.append($0) }
        hooks.didCloseTab = { closedTabIDs.append($0) }
        hooks.didFocusAuxiliaryWindow = { sessionID in
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.session(for: sessionID) else {
                return
            }
            focusedSessionID = sessionID
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                session.webView,
                reason: .bulkCleanup
            )
        }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        XCTAssertNil(
            presentOwnerPopup(in: harness, configuration: configuration)
        )
        XCTAssertNotNil(focusedSessionID)
        XCTAssertEqual(openedTabIDs.count, 1)
        XCTAssertEqual(closedTabIDs, openedTabIDs)
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
    }

    func testWrongDataStoreRejectsAuxiliaryPublicationWithoutCallbacks()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        var eventCount = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { _ in eventCount += 1 }
        hooks.didOpenTab = { _ in eventCount += 1 }
        hooks.didCloseTab = { _ in eventCount += 1 }
        hooks.didCloseAuxiliaryWindow = { _ in eventCount += 1 }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let wrongConfiguration = WKWebViewConfiguration()
        wrongConfiguration.websiteDataStore = .nonPersistent()
        wrongConfiguration.webExtensionController = harness.inspection.controller.provisioning
            .ensureExtensionController(for: harness.profile.id)

        XCTAssertNil(
            presentOwnerPopup(
                in: harness,
                configuration: wrongConfiguration
            )
        )
        XCTAssertEqual(eventCount, 0)
        XCTAssertTrue(harness.extensionContext.openWindows.isEmpty)
        XCTAssertTrue(harness.extensionContext.openTabs.isEmpty)
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().isEmpty
        )
    }

    func testGenericPopupTeardownEmitsNoExtensionTabClose() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        var closedTabCount = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didCloseTab = { _ in closedTabCount += 1 }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let webView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentWebPopup(
                configuration: extensionPopupConfiguration(for: harness),
                request: URLRequest(
                    url: URL(string: "https://generic.example/popup")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab
            )
        )
        harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
            webView,
            reason: .bulkCleanup
        )

        XCTAssertEqual(closedTabCount, 0)
    }

    private func auxiliaryPublicationIdentitySnapshot(
        _ harness: ExtensionHarness
    ) throws -> [UUID: AuxiliaryPublicationIdentityTuple] {
        try Dictionary(
            uniqueKeysWithValues: harness.browserManager.auxiliaryWindows
                .sessions.sessionsSnapshot().map { session in
                    let sessions = harness.browserManager.auxiliaryWindows
                        .sessions
                    XCTAssertIdentical(
                        sessions.session(for: session.webView),
                        session
                    )
                    XCTAssertIdentical(
                        sessions.session(for: session.window),
                        session
                    )
                    XCTAssertIdentical(
                        sessions.session(for: session.tab),
                        session
                    )
                    let miniWindowAdapter = try XCTUnwrap(
                        session.miniWindowAdapter
                    )
                    let storedMiniWindowAdapter = try XCTUnwrap(
                        harness.inspection.normalTabs.adapters
                            .existingMiniWindowAdapter(for: session.id)
                    )
                    let tabAdapter = try XCTUnwrap(
                        harness.inspection.normalTabs.adapters
                            .existingTabAdapter(for: session.tab.id)
                    )
                    XCTAssertIdentical(
                        miniWindowAdapter,
                        storedMiniWindowAdapter
                    )
                    return (
                        session.id,
                        AuxiliaryPublicationIdentityTuple(
                            sessionIdentity: ObjectIdentifier(session),
                            tabIdentity: ObjectIdentifier(session.tab),
                            windowIdentity: ObjectIdentifier(session.window),
                            webViewIdentity: ObjectIdentifier(session.webView),
                            miniWindowAdapterIdentity: ObjectIdentifier(
                                miniWindowAdapter
                            ),
                            tabAdapterIdentity: ObjectIdentifier(tabAdapter)
                        )
                    )
                }
        )
    }
}
