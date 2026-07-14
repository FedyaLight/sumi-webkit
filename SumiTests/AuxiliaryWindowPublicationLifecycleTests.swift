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
        let extensionURL = URL(string: "safari-web-extension://adapter-owner/popup.html")!

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
                let tabAdapter = harness.extensionManager.adapterStore
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
                harness.extensionManager.existingTabControllers
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
                        for: harness.extensionManager.tabPublicationRevisions.issue()
                    )
            )
        }
        hooks.didOpenTab = { tabID in
            guard let session = harness.browserManager.auxiliaryWindows
                .sessions.sessionsSnapshot().first(where: {
                    $0.tab.id == tabID
                }), let windowAdapter = session.miniWindowAdapter,
                let tabAdapter = harness.extensionManager.adapterStore
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
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: webView,
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
                harness.browserManager.auxiliaryWindows.teardown.teardown(
                    for: webView,
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
        let originalWindowProjection = harness.extensionContext.openWindows.map {
            ObjectIdentifier($0 as AnyObject)
        }
        let originalTabProjection = harness.extensionContext.openTabs.map {
            ObjectIdentifier($0 as AnyObject)
        }
        let originalMiniAdapterStore = Dictionary(
            uniqueKeysWithValues: harness.extensionManager.adapterStore
                .miniWindowAdaptersSnapshot().map {
                    ($0.sessionId, ObjectIdentifier($0))
                }
        )
        let originalTabAdapterStore = harness.extensionManager.adapterStore
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
            harness.extensionManager.setExtensionContext(
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
        XCTAssertEqual(
            harness.extensionContext.openWindows.map {
                ObjectIdentifier($0 as AnyObject)
            },
            originalWindowProjection
        )
        XCTAssertEqual(
            harness.extensionContext.openTabs.map {
                ObjectIdentifier($0 as AnyObject)
            },
            originalTabProjection
        )
        XCTAssertTrue(replacement.openWindows.isEmpty)
        XCTAssertTrue(replacement.openTabs.isEmpty)
        XCTAssertEqual(
            try auxiliaryPublicationIdentitySnapshot(harness),
            originalPublication
        )
        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: harness.extensionManager.adapterStore
                    .miniWindowAdaptersSnapshot().map {
                        ($0.sessionId, ObjectIdentifier($0))
                    }
            ),
            originalMiniAdapterStore
        )
        XCTAssertEqual(
            harness.extensionManager.adapterStore.tabAdapters
                .mapValues { ObjectIdentifier($0) },
            originalTabAdapterStore
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
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: session.webView,
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
            harness.browserManager.auxiliaryWindows.teardown.teardown(
                for: session.webView,
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
        wrongConfiguration.webExtensionController = harness.extensionManager
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
        harness.browserManager.auxiliaryWindows.teardown.teardown(
            for: webView,
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
                        harness.extensionManager.adapterStore
                            .existingMiniWindowAdapter(for: session.id)
                    )
                    let tabAdapter = try XCTUnwrap(
                        harness.extensionManager.adapterStore
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
