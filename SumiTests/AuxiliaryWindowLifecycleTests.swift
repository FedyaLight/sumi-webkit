//
//  AuxiliaryWindowLifecycleTests.swift
//  SumiTests
//

import AppKit
@testable import Sumi
import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
final class AuxiliaryWindowLifecycleTests: XCTestCase {
    final class InvalidatingInitialDocumentContextLoader:
        ExtensionInitialDocumentContextReadiness {
        let invalidate: @MainActor () -> Void

        init(invalidate: @escaping @MainActor () -> Void) {
            self.invalidate = invalidate
        }

        func profileNeedsInitialDocumentExtensionContextLoad(
            profileId _: UUID
        ) -> Bool {
            true
        }

        func ensureInitialExtensionContextsLoaded(for _: UUID) async
            -> PageNavigationPrerequisiteResult {
            invalidate()
            return .ready
        }
    }

    struct Harness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let sourceTab: Tab
        let windowState: BrowserWindowState
    }

    struct ExtensionHarness {
        let container: SumiDatabase
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let extensionManager: ExtensionManager
        let inspection: ExtensionManagerTestInspection
        let attachedRuntime: ExtensionAttachedBrowserRuntimeInspection
        let sourceTab: Tab
        let profile: Profile
        let windowState: BrowserWindowState
        let appKitWindow: NSWindow
        let extensionContext: WKWebExtensionContext
        let controller: WKWebExtensionController
    }

    func testCloseAllForExtensionIdClosesExternalAuthPopupWithoutContextOverride() {
        let harness = makeHarness()
        let extensionURL = URL(string: "safari-web-extension://owner-extension-id/popup.html")!
        harness.sourceTab.url = extensionURL

        let popupWebView = harness.browserManager.auxiliaryWindows.popups.presentExtensionExternalWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://auth.example/login")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab,
            extensionOwnedSourceURL: extensionURL
        )

        XCTAssertNotNil(popupWebView)
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.sessions.ownerExtensionID(for: popupWebView!),
            "owner-extension-id"
        )
        XCTAssertNil(harness.sourceTab.webExtensionContextOverride)

        harness.browserManager.auxiliaryWindows.teardown.closeAll(forExtensionID: "owner-extension-id")
        XCTAssertFalse(harness.browserManager.auxiliaryWindows.sessions.contains(popupWebView!))
    }

    func testCloseAllForExtensionIdPreservesUnrelatedWebPopup() {
        let harness = makeHarness()

        let popupWebView = harness.browserManager.auxiliaryWindows.popups.presentWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://example.com/popup")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: harness.sourceTab
        )

        XCTAssertNotNil(popupWebView, "Expected generic web popup to open")
        XCTAssertNil(
            harness.browserManager.auxiliaryWindows.sessions.ownerExtensionID(for: popupWebView!),
            "Generic web popup must not inherit extension ownership"
        )

        harness.browserManager.auxiliaryWindows.teardown.closeAll(forExtensionID: "owner-extension-id")
        XCTAssertTrue(harness.browserManager.auxiliaryWindows.sessions.contains(popupWebView!))

        harness.browserManager.auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
    }

    func testWeakExtensionEventsFailClosedAfterEventRootDeallocation() throws {
        let harness = makeHarness()
        let popupWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(
                    url: URL(string: "https://example.com/popup")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                popupWebView,
                reason: .bulkCleanup
            )
        }
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: popupWebView
            )
        )
        var eventRoot: AuxiliaryWindowExtensionEventProbe? =
            AuxiliaryWindowExtensionEventProbe()
        weak let weakEventRoot = eventRoot
        let events = WeakAuxiliaryWindowExtensionEvents(
            target: try XCTUnwrap(eventRoot)
        )

        eventRoot = nil

        XCTAssertNil(weakEventRoot)
        XCTAssertFalse(events.notifyAuxiliaryWindowOpened(session))
    }

    func testCloseAllForExtensionIdRemovesRegisteredMiniWindowAdapter()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )

        let extensionURL = harness.extensionContext.baseURL
            .appendingPathComponent("popup.html")
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
        XCTAssertFalse(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().isEmpty
        )

        harness.browserManager.auxiliaryWindows.teardown.closeAll(
            forExtensionID: "adapter-owner"
        )
        XCTAssertTrue(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().isEmpty
        )
        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                popupWebView
            )
        )
    }

    func testBulkCloseUsesExactReceiptSnapshotAcrossSameWebViewReplacement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let firstWebView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let secondWebView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let originals = harness.browserManager.auxiliaryWindows.sessions
            .sessionsSnapshot()
        let originalIDs = Set(originals.map(\.id))
        XCTAssertEqual(originalIDs.count, 2)
        XCTAssertEqual(
            Set([ObjectIdentifier(firstWebView), ObjectIdentifier(secondWebView)]),
            Set(originals.map { ObjectIdentifier($0.webView) })
        )
        var replacement: AuxiliaryWindowSession?
        var replacementReceipt: AuxiliaryWindowSessionReceipt?
        var didReplace = false
        var hooks = harness.extensionManager.testHooks
        hooks.didCloseAuxiliaryWindow = { _ in
            guard didReplace == false else { return }
            didReplace = true
            guard let remaining = harness.browserManager.auxiliaryWindows
                .sessions.sessionsSnapshot().first(where: {
                    originalIDs.contains($0.id)
                }) else {
                return XCTFail("Bulk close did not leave an exact pending seed")
            }
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                remaining.webView,
                reason: .bulkCleanup
            )
            let candidate = AuxiliaryWindowSession(
                id: UUID(),
                tab: remaining.tab,
                window: remaining.window,
                webView: remaining.webView,
                openerTab: remaining.openerTab,
                openerWindow: remaining.openerWindow,
                shouldActivateApp: remaining.shouldActivateApp,
                isPrivate: remaining.isPrivate,
                ownerExtensionID: nil,
                miniWindowAdapter: nil,
                extensionEvents: nil,
                uiDelegate: remaining.uiDelegate,
                windowDelegate: remaining.windowDelegate
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
        }

        harness.browserManager.auxiliaryWindows.teardown.closeAll(
            forExtensionID: "adapter-owner",
            reason: .bulkCleanup
        )

        let unwrappedReplacement = try XCTUnwrap(replacement)
        XCTAssertTrue(didReplace)
        XCTAssertIdentical(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: unwrappedReplacement.webView
            ),
            unwrappedReplacement
        )
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().map(\.id),
            [unwrappedReplacement.id]
        )
    }

    func testParentWindowFrameUnchangedAfterPresentExtensionExternalWebPopupWithExtensionHarness()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let mainWindow = try XCTUnwrap(
            harness.windowRegistry.appKitWindow(for: harness.windowState)
        )
        let originalMainFrame = mainWindow.frame
        let extensionURL = harness.extensionContext.baseURL
            .appendingPathComponent("popup.html")

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
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                popupWebView,
                reason: .bulkCleanup
            )
        }

        XCTAssertEqual(mainWindow.frame, originalMainFrame)
    }

    func testPrivateExtensionPopupWindowIsBlockedBeforeAuxiliaryMaterialization() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "private-popup-owner",
            publishNormalWindow: true
        )
        let request = extensionWindowRequest(
            windowType: .popup,
            tabURLs: [
                harness.extensionContext.baseURL.appendingPathComponent(
                    "popup.html"
                ),
            ],
            shouldBePrivate: true
        )

        let callback = try auxiliaryCallback(for: harness)
        let adapter = await harness.browserManager.auxiliaryWindows.extensionWindows.present(
            request: request,
            evidence: callback.evidence,
            callbackAdmission: harness.inspection.controller.callbackAdmission,
            runtime: callback.runtime,
            parentWindow: harness.windowRegistry.appKitWindow(for: harness.windowState)
        )

        XCTAssertNil(adapter)
        XCTAssertTrue(
            harness.browserManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .allSatisfy { $0.isAuxiliaryMiniWindow == false }
        )
        XCTAssertTrue(
            harness.inspection.normalTabs.adapters.miniWindowAdaptersSnapshot()
                .isEmpty
        )
    }

    func testNonPrivateExtensionPopupWindowStillUsesProfileRuntime() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "normal-popup-owner",
            publishNormalWindow: true
        )
        let popupURL = harness.extensionContext.baseURL.appendingPathComponent(
            "popup.html"
        )
        let request = extensionWindowRequest(
            windowType: .popup,
            tabURLs: [popupURL],
            shouldBePrivate: false
        )

        await harness.inspection.normalTabs.deferredRuntime
            .initialDocumentRuntimePreparationOwner
            .ensureInitialExtensionContextsLoaded(for: harness.profile.id)
        XCTAssertFalse(
            harness.extensionManager.moduleBrowserRuntime().initialDocument
                .needsInitialContextLoad(profileID: harness.profile.id)
        )
        let callback = try auxiliaryCallback(for: harness)
        let maybePresentation = await harness.browserManager.auxiliaryWindows
            .extensionWindows.present(
                request: request,
                evidence: callback.evidence,
                callbackAdmission: harness.inspection.controller.callbackAdmission,
                runtime: callback.runtime,
                parentWindow: harness.windowRegistry.appKitWindow(for: harness.windowState)
        )
        let presentation = try XCTUnwrap(maybePresentation)
        let session = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: presentation.sessionID
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                session.webView,
                reason: .bulkCleanup
            )
        }

        XCTAssertFalse(session.isPrivate)
        XCTAssertIdentical(
            session.webView.configuration.websiteDataStore,
            harness.inspection.controller.provisioning.websiteDataStore(for: harness.profile.id)
        )
        XCTAssertIdentical(
            session.webView.configuration.webExtensionController,
            harness.inspection.controller.provisioning.ensureExtensionController(for: harness.profile.id)
        )
        XCTAssertIdentical(session.tab.resolvedCurrentWebView(), session.webView)
        XCTAssertEqual(session.webView.url, popupURL)
        XCTAssertEqual(
            session.miniWindowAdapter?.tabs(for: harness.extensionContext).count,
            1
        )
    }

    func testPopupReceiptRetiresCurrentExactSessionAndKeepsSibling()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "popup-current-receipt-owner",
            publishNormalWindow: true
        )
        let request = extensionWindowRequest(
            windowType: .popup,
            tabURLs: [],
            shouldBePrivate: false
        )
        let callback = try auxiliaryCallback(for: harness)
        let presented = await harness.browserManager.auxiliaryWindows
            .extensionWindows.present(
                request: request,
                evidence: callback.evidence,
                callbackAdmission: harness.inspection.controller.callbackAdmission,
                runtime: callback.runtime,
                parentWindow: harness.appKitWindow
            )
        let presentation = try XCTUnwrap(
            presented
        )
        let original = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: presentation.sessionID
            )
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
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                siblingWebView,
                reason: .bulkCleanup
            )
        }

        presentation.retire()

        XCTAssertNil(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: original.id
            )
        )
        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                original.webView
            )
        )
        XCTAssertIdentical(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: sibling.id
            ),
            sibling
        )

        presentation.retire()

        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().map(\.id),
            [sibling.id]
        )
    }

    func testStalePopupReceiptCannotRetireSameWebViewReplacementOrSibling()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "popup-webview-aba-owner",
            publishNormalWindow: true
        )
        let request = extensionWindowRequest(
            windowType: .popup,
            tabURLs: [],
            shouldBePrivate: false
        )
        let callback = try auxiliaryCallback(for: harness)
        let presented = await harness.browserManager.auxiliaryWindows
            .extensionWindows.present(
                request: request,
                evidence: callback.evidence,
                callbackAdmission: harness.inspection.controller.callbackAdmission,
                runtime: callback.runtime,
                parentWindow: harness.appKitWindow
            )
        let presentation = try XCTUnwrap(
            presented
        )
        let original = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: presentation.sessionID
            )
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
        XCTAssertEqual(
            presentation.sessionIdentity,
            ObjectIdentifier(original)
        )
        XCTAssertEqual(
            presentation.webViewIdentity,
            ObjectIdentifier(original.webView)
        )

        harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
            original.webView,
            reason: .bulkCleanup
        )
        let replacement = AuxiliaryWindowSession(
            id: UUID(),
            tab: original.tab,
            window: original.window,
            webView: original.webView,
            openerTab: original.openerTab,
            openerWindow: original.openerWindow,
            shouldActivateApp: original.shouldActivateApp,
            isPrivate: original.isPrivate,
            ownerExtensionID: original.ownerExtensionID,
            miniWindowAdapter: original.miniWindowAdapter,
            extensionEvents: original.extensionEvents,
            uiDelegate: original.uiDelegate,
            windowDelegate: original.windowDelegate
        )
        let replacementReceipt = harness.browserManager.auxiliaryWindows
            .sessions.register(replacement)
        defer {
            _ = harness.browserManager.auxiliaryWindows.sessions.remove(
                replacementReceipt
            )
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                siblingWebView,
                reason: .bulkCleanup
            )
        }

        presentation.retire()
        presentation.retire()

        XCTAssertIdentical(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: original.webView
            ),
            replacement
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
            [replacement.id, sibling.id]
        )
    }

    func testReentrantPopupRejectionPreservesSameWebViewReplacement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "popup-reentrant-replacement-owner",
            publishNormalWindow: true
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
        var failedSessionID: UUID?
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { sessionID in
            guard replacement == nil,
                  let failed = harness.browserManager.auxiliaryWindows
                    .sessions.session(for: sessionID) else {
                return
            }
            failedSessionID = sessionID
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
        let callback = try auxiliaryCallback(for: harness)
        let request = extensionWindowRequest(
            windowType: .popup,
            tabURLs: [],
            shouldBePrivate: false
        )

        let result = await harness.browserManager.auxiliaryWindows
            .extensionWindows.present(
                request: request,
                evidence: callback.evidence,
                callbackAdmission: harness.inspection.controller.callbackAdmission,
                runtime: callback.runtime,
                parentWindow: harness.appKitWindow
            )

        let unwrappedReplacement = try XCTUnwrap(replacement)
        XCTAssertNil(result)
        XCTAssertNotNil(failedSessionID)
        XCTAssertNotEqual(unwrappedReplacement.id, failedSessionID)
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

    func testPopupInvalidatedAfterPresentationRetiresExactSessionAndKeepsSibling()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "final-admission-owner",
            publishNormalWindow: true
        )
        let siblingWebView = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.popups.presentWebPopup(
                configuration: WKWebViewConfiguration(),
                request: URLRequest(
                    url: URL(string: "https://sibling.example.test")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab
            )
        )
        let sibling = try XCTUnwrap(
            harness.browserManager.auxiliaryWindows.sessions.session(
                for: siblingWebView
            )
        )
        defer {
            harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
                siblingWebView,
                reason: .bulkCleanup
            )
        }

        let replacement = WKWebExtensionContext(
            for: harness.extensionContext.webExtension
        )
        harness.extensionManager.testHooks.didOpenTab = { _ in
            _ = harness.inspection.contextState.profiles.setContext(
                replacement,
                extensionId: "final-admission-owner",
                profileId: harness.profile.id
            )
        }
        defer { harness.extensionManager.testHooks.didOpenTab = nil }
        let completed = expectation(description: "stale popup callback settled")
        var callbackWindow: (any WKWebExtensionWindow)?
        var callbackError: (any Error)?
        let rejectedURL = URL(
            string: "https://rejected-popup.example/request"
        )!
        let request = extensionWindowRequest(
            windowType: .popup,
            tabURLs: [rejectedURL],
            shouldBePrivate: false
        )
        let callback = try openingCallback(for: harness)

        ExtensionControllerOpeningCallbackHandler().openNewWindow(
            request: request,
            evidence: callback.evidence,
            runtime: callback.runtime
        ) { window, error in
            callbackWindow = window
            callbackError = error
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 2.0)

        XCTAssertNil(callbackWindow)
        XCTAssertNotNil(callbackError)
        XCTAssertEqual(
            harness.browserManager.auxiliaryWindows.sessions
                .sessionsSnapshot().map(\.id),
            [sibling.id]
        )
        XCTAssertTrue(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                siblingWebView
            )
        )
        XCTAssertFalse(
            harness.inspection.normalTabs.recentRequests.consume(
                rejectedURL
            ),
            "rejected popup must not consume future request suppression"
        )
    }

    func testInitialContextPreparationInvalidatingCallbackFailsBeforeAuxiliaryMaterialization()
        async throws {
        let ownerExtensionID = "initial-context-replacement-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID,
            publishNormalWindow: true
        )
        let replacementContext = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        let callback = try auxiliaryCallback(for: harness)
        let invalidatingLoader = InvalidatingInitialDocumentContextLoader {
            harness.inspection.contextState.profiles.setContext(
                replacementContext,
                extensionId: ownerExtensionID,
                profileId: harness.profile.id
            )
        }
        let runtime = ExtensionAuxiliaryWindowCallbackRuntime(
            contextLoading: invalidatingLoader,
            loadResolver: callback.runtime.loadResolver,
            contextPreloader: callback.runtime.contextPreloader,
            recentRequests: callback.runtime.recentRequests,
            configurationPreparation:
                callback.runtime.configurationPreparation,
            integration: callback.runtime.integration
        )
        let request = extensionWindowRequest(
            windowType: .popup,
            tabURLs: [
                harness.extensionContext.baseURL.appendingPathComponent(
                    "popup.html"
                ),
            ],
            shouldBePrivate: false
        )

        let adapter = await harness.browserManager.auxiliaryWindows
            .extensionWindows.present(
                request: request,
                evidence: callback.evidence,
                callbackAdmission: harness.inspection.controller.callbackAdmission,
                runtime: runtime,
                parentWindow: harness.appKitWindow
            )

        XCTAssertNil(adapter)
        XCTAssertIdentical(
            harness.inspection.contextState.profileState.context(
                for: ownerExtensionID,
                profileId: harness.profile.id
            ),
            replacementContext
        )
        XCTAssertTrue(
            harness.browserManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .allSatisfy { $0.isAuxiliaryMiniWindow == false }
        )
        XCTAssertTrue(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().isEmpty
        )
    }

    func testPrivateExtensionNormalWindowIsRejectedBeforeTabCreation() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "private-window-owner",
            allowNormalTabRuntimeWithoutInstalledExtensions: false
        )
        let initialRegularTabCount = harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot().values
            .flatMap(\.self)
            .filter { $0.isAuxiliaryMiniWindow == false }
            .count
        let initialController = harness.inspection.contextState.profiles.controllerForCurrentProfile()
        let openedWindow = expectation(description: "private extension window rejected")
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?
        let request = extensionWindowRequest(
            windowType: .normal,
            tabURLs: [URL(string: "https://account.example.test/private")!],
            shouldBePrivate: true
        )
        let callback = try openingCallback(for: harness)

        ExtensionControllerOpeningCallbackHandler().openNewWindow(
            request: request,
            evidence: callback.evidence,
            runtime: callback.runtime
        ) { window, error in
            completionWindow = window
            completionError = error
            openedWindow.fulfill()
        }

        await fulfillment(of: [openedWindow], timeout: 2.0)

        XCTAssertNil(completionWindow)
        XCTAssertNotNil(completionError)
        XCTAssertTrue(
            harness.browserManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .allSatisfy { $0.isAuxiliaryMiniWindow == false }
        )
        XCTAssertEqual(
            harness.browserManager.tabStateStore.regularTabs.tabsBySpaceSnapshot().values
                .flatMap { $0 }
                .filter { $0.isAuxiliaryMiniWindow == false }
                .count,
            initialRegularTabCount
        )
        XCTAssertIdentical(
            harness.inspection.contextState.profiles.controllerForCurrentProfile(),
            initialController,
            "Private extension windows must not replace the callback's existing controller"
        )
    }

    func testExtensionRequestedTeardownClosesAuxiliaryMiniWindowSession()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )

        let extensionURL = harness.extensionContext.baseURL
            .appendingPathComponent("popup.html")
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
        XCTAssertFalse(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().isEmpty
        )

        harness.browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(
            popupWebView,
            reason: .extensionRequestedClose
        )

        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                popupWebView
            )
        )
        XCTAssertTrue(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().isEmpty
        )
    }

    func testRemoveTabAuxiliaryRoutesThroughFullTeardown() async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )

        let extensionURL = harness.extensionContext.baseURL
            .appendingPathComponent("popup.html")
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
        XCTAssertFalse(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().isEmpty
        )
        let auxiliaryTab = try XCTUnwrap(
            harness.browserManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .first { $0.isAuxiliaryMiniWindow }
        )

        harness.browserManager.tabClosureService.removeTab(
            auxiliaryTab.id
        )

        XCTAssertFalse(
            harness.browserManager.auxiliaryWindows.sessions.contains(
                popupWebView
            )
        )
        XCTAssertTrue(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().isEmpty
        )
        XCTAssertNil(
            harness.browserManager.tabCollectionMembershipOwner
                .auxiliaryMiniWindowTab(for: auxiliaryTab.id)
        )
    }

    func makeHarness() -> Harness {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.sumiSettings = settings
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowRegistry.bindAppKitWindow(
            NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
            ),
            to: windowState
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
        browserManager.selectTab(sourceTab, in: windowState)

        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            sourceTab: sourceTab,
            windowState: windowState
        )
    }

    func makeExtensionHarness(
        ownerExtensionID: String,
        allowNormalTabRuntimeWithoutInstalledExtensions: Bool = true,
        publishNormalWindow: Bool = false
    ) async throws -> ExtensionHarness {
        let container = try makeTestContainer()
        let profile = Profile(name: "Auxiliary Owner")
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspection = ExtensionManagerInspectionCapture()
        let extensionManager = makeSafariExtensionTestExtensionManager(
            database: container,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            moduleRegistry: registry,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspection
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
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
        browserManager.windowShellContentViewFactory = { _, _ in NSView() }
        let windowSessions = browserManager.windowSessionBundle
        BrowserWindowRegistryBinding.install(
            registration: windowSessions.restoration,
            closing: BrowserWindowCloseWorkflow(
                browserRuntime: browserManager,
                recorder: windowSessions.history.recorder,
                persistence: browserManager.windowSessionPersistenceCoordinator,
                extensions: browserManager.optionalModules.extensions,
                webViews: browserManager.webViewRuntime.lifecycleService,
                emptySplitPlaceholders: browserManager.splitEmptyPlaceholders,
                splitPreviews: browserManager.splitWindowContext.previews,
                commands: browserManager.windowCommands
            ),
            activity: browserManager.windowActivation,
            allWindowsClosed: BrowserAllWindowsClosedWorkflow(
                browserRuntime: browserManager,
                sessionRestore: windowSessions.restoreService,
                siteDataPolicy: browserManager.dataServices
                    .siteDataPolicyEnforcementService,
                profiles: browserManager.profileManager
            ),
            on: windowRegistry
        )
        browserManager.startupRestoreLifecycle.markLoadFinished()
        extensionsModule.attach(runtime: BrowserExtensionsModuleRuntimeFactory.runtime(for: browserManager))
        extensionManager.attach(browserManager: browserManager)
        XCTAssertIdentical(extensionsModule.managerForTesting(), extensionManager)
        if allowNormalTabRuntimeWithoutInstalledExtensions {
            inspection.inspection.runtimeAuthorities.demand
                .recordRuntimeDemandWithoutEnabledExtensions()
        }
        inspection.inspection.actionSurfaces.publication
            .markRuntimePublicationReady()

        let space = Space(name: "Primary", profileId: profile.id)
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        let appKitWindow = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        appKitWindow.isReleasedWhenClosed = false
        windowRegistry.bindAppKitWindow(appKitWindow, to: windowState)
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        addTeardownBlock { @MainActor in
            windowRegistry.unregister(windowState.id)
            appKitWindow.close()
        }

        let extensionContext = try await makeExtensionContext(
            ownerExtensionID: ownerExtensionID
        )
        inspection.inspection.contextState.profiles.setContext(
            extensionContext,
            extensionId: ownerExtensionID,
            profileId: profile.id
        )
        inspection.inspection.actionSurfaces.installedExtensions.upsert(
            auxiliaryInstalledExtension(id: ownerExtensionID),
            durability: .volatileExactRuntime
        )

        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: extensionContext.baseURL.appendingPathComponent(
                "popup.html"
            ).absoluteString,
            in: space,
            activate: true
        )
        sourceTab.profileId = profile.id
        sourceTab.webExtensionContextOverride = extensionContext
        browserManager.selectTab(sourceTab, in: windowState)
        let controller: WKWebExtensionController
        if publishNormalWindow {
            controller = inspection.inspection.controller.provisioning
                .ensureExtensionController(
                for: profile.id
            )
            try controller.load(extensionContext)
            addTeardownBlock {
                guard controller.extensionContexts.contains(extensionContext) else {
                    return
                }
                try controller.unload(extensionContext)
            }
            let sourceWebView = try XCTUnwrap(
                sourceTab.makeNormalTabWebView(
                    reason: "AuxiliaryWindowLifecycleTests.makeExtensionHarness"
                )
            )
            browserManager.testWebViewRuntime().trackedWebViewAdmission
                .attemptAssignment(
                    sourceWebView,
                    to: sourceTab,
                    in: windowState.id,
                    replaySemanticOperation: {
                        XCTFail("Unexpected source WebView deferral")
                    }
                )
            inspection.inspection.browserPublication.reloads
                .reloadLoadedRuntime(
                reason: "AuxiliaryWindowLifecycleTests.makeExtensionHarness",
                profileID: profile.id
            )
            XCTAssertTrue(
                attachedRuntime.runtime.normalTabs.preparedTabs
                    .containsPreparedTab(sourceTab)
            )
            XCTAssertNotNil(
                inspection.inspection.normalTabs.adapters.existingWindowAdapter(
                    for: windowState.id
                )
            )
        } else {
            // Requested-tab callbacks use the profile's exact controller.
            // This fixture deliberately keeps runtime publication lazy; the
            // ordinary external Tab is published after materialization below.
            controller = inspection.inspection.controller.provisioning
                .ensureExtensionController(
                for: profile.id
            )
        }

        return ExtensionHarness(
            container: container,
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            extensionManager: extensionManager,
            inspection: inspection.inspection,
            attachedRuntime: attachedRuntime.runtime,
            sourceTab: sourceTab,
            profile: profile,
            windowState: windowState,
            appKitWindow: appKitWindow,
            extensionContext: extensionContext,
            controller: controller
        )
    }

    func extensionPopupConfiguration(
        for harness: ExtensionHarness
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.profile.dataStore
        configuration.webExtensionController = harness.inspection.controller.provisioning
            .ensureExtensionController(for: harness.profile.id)
        return configuration
    }

    func auxiliaryCallback(
        for harness: ExtensionHarness
    ) throws -> (
        evidence: ExtensionControllerCallbackEvidence,
        runtime: ExtensionAuxiliaryWindowCallbackRuntime
    ) {
        let callbacks = harness.attachedRuntime.requestedTabs.openingCallbacks
        let evidence = try XCTUnwrap(
            callbacks.admission.capture(
                context: harness.extensionContext,
                controller: harness.controller
            )
        )
        return (evidence, callbacks.auxiliaryRuntime)
    }

    func openingCallback(
        for harness: ExtensionHarness
    ) throws -> ExtensionControllerOpeningCallbackComposition.Invocation {
        let runtime = harness.attachedRuntime.requestedTabs.openingCallbacks
        let evidence = try XCTUnwrap(
            runtime.admission.capture(
                context: harness.extensionContext,
                controller: harness.controller
            )
        )
        return ExtensionControllerOpeningCallbackComposition.Invocation(
            evidence: evidence,
            runtime: runtime
        )
    }

    func extensionWindowRequest(
        windowType: WKWebExtension.WindowType,
        tabURLs: [URL],
        shouldBeFocused: Bool = false,
        shouldBePrivate: Bool
    ) -> ExtensionWindowOpeningRequest {
        ExtensionWindowOpeningRequest(
            windowType: windowType,
            frame: CGRect(
                x: CGFloat.nan,
                y: CGFloat.nan,
                width: CGFloat.nan,
                height: CGFloat.nan
            ),
            tabURLs: tabURLs,
            shouldBeFocused: shouldBeFocused,
            shouldBePrivate: shouldBePrivate
        )
    }

    func presentOwnerPopup(
        in harness: ExtensionHarness,
        configuration: WKWebViewConfiguration? = nil
    ) -> WKWebView? {
        harness.browserManager.auxiliaryWindows.popups
            .presentExtensionExternalWebPopup(
                configuration: configuration
                    ?? extensionPopupConfiguration(for: harness),
                request: URLRequest(
                    url: URL(string: "https://auth.example/login")!
                ),
                windowFeatures: WKWindowFeatures(),
                openerTab: harness.sourceTab,
                extensionOwnedSourceURL: harness.extensionContext.baseURL
                    .appendingPathComponent("popup.html")
            )
    }

    func makeExtensionContext(
        ownerExtensionID: String
    ) async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Auxiliary \(ownerExtensionID)",
            "version": "1.0",
            "permissions": ["tabs", "windows"],
            "action": ["default_popup": "popup.html"],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(to: directory.appendingPathComponent("popup.html"), options: [.atomic])

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        return WKWebExtensionContext(for: webExtension)
    }

    func auxiliaryInstalledExtension(
        id: String,
        isEnabled: Bool = true
    ) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: "Auxiliary \(id)",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: isEnabled,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/\(id)",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "auxiliary-\(id)",
            manifestRootFingerprint: "auxiliary-\(id)",
            sourceBundlePath: "/tmp/\(id)",
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

    func popupNavigationAction(
        sourceURL: URL?,
        targetURL: URL,
        webView: WKWebView
    ) -> WKNavigationAction {
        let sourceFrame = sourceURL.map {
            AuxiliaryWindowNavigationFrameMock(
                isMainFrame: true,
                request: URLRequest(url: $0),
                securityOrigin: AuxiliaryWindowSecurityOriginMock.new(url: $0),
                webView: webView
            ).frameInfo
        }
        return AuxiliaryWindowNavigationActionMock(
            sourceFrame: sourceFrame,
            targetFrame: nil,
            navigationType: .linkActivated,
            request: URLRequest(url: targetURL)
        ).navigationAction
    }

    func makeTestContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }
}

@MainActor
final class AuxiliaryWindowExtensionEventProbe:
    AuxiliaryWindowExtensionEventHandling {
    func notifyAuxiliaryWindowOpened(_: AuxiliaryWindowSession) -> Bool {
        true
    }

    func notifyAuxiliaryWindowFocused(_: AuxiliaryWindowSession) {}

    func notifyAuxiliaryWindowClosed(_: AuxiliaryWindowSession) {}
}

@available(macOS 15.5, *)
final class AuxiliaryWindowNavigationActionMock: NSObject {
    @objc var sourceFrame: WKFrameInfo?
    @objc var targetFrame: WKFrameInfo?
    @objc var navigationType: WKNavigationType
    @objc var request: URLRequest
    @objc var isUserInitiated: Bool
    @objc var modifierFlags: NSEvent.ModifierFlags
    @objc var shouldPerformDownload = false
    @objc var isContentRuleListRedirect = false
    @objc var mainFrameNavigation: WKNavigation?
    @objc var buttonNumber = 0

    init(
        sourceFrame: WKFrameInfo?,
        targetFrame: WKFrameInfo?,
        navigationType: WKNavigationType,
        request: URLRequest,
        isUserInitiated: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = []
    ) {
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.navigationType = navigationType
        self.request = request
        self.isUserInitiated = isUserInitiated
        self.modifierFlags = modifierFlags
    }

    var navigationAction: WKNavigationAction {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKNavigationAction.self, capacity: 1) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
final class AuxiliaryWindowNavigationFrameMock: NSObject {
    @objc var isMainFrame: Bool
    @objc var request: URLRequest?
    @objc var securityOrigin: WKSecurityOrigin
    @objc weak var webView: WKWebView?

    init(
        isMainFrame: Bool,
        request: URLRequest?,
        securityOrigin: WKSecurityOrigin,
        webView: WKWebView?
    ) {
        self.isMainFrame = isMainFrame
        self.request = request
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 }
        }.pointee
    }
}

@available(macOS 15.5, *)
@objc
final class AuxiliaryWindowSecurityOriginMock: WKSecurityOrigin {
    var mockedProtocol = ""
    var mockedHost = ""
    var mockedPort = 0

    override var `protocol`: String { mockedProtocol }
    override var host: String { mockedHost }
    override var port: Int { mockedPort }

    func setURL(_ url: URL) {
        mockedProtocol = url.scheme ?? ""
        mockedHost = url.host ?? ""
        mockedPort = url.port ?? 0
    }

    static func new(url: URL) -> AuxiliaryWindowSecurityOriginMock {
        let mock = perform(NSSelectorFromString("alloc"))
            .takeUnretainedValue() as! AuxiliaryWindowSecurityOriginMock
        mock.setURL(url)
        return mock
    }
}
