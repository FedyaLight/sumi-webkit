import AppKit
@testable import Sumi
import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
extension AuxiliaryWindowLifecycleTests {
    func testStaleUIDelegateCannotActOnSameWebViewReplacement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "stale-ui-delegate-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let tab = makeReceiptTestTab(in: harness)
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        let window = AuxiliaryCompactWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240)
        )
        let permissions = AuxiliaryWindowPermissionReceiptProbe()
        let original = registerReceiptTestSession(
            auxiliaryWindows: auxiliaryWindows,
            tab: tab,
            window: window,
            webView: webView,
            permissions: permissions
        )
        XCTAssertTrue(
            auxiliaryWindows.sessions.remove(original.receipt)
                === original.session
        )
        let replacement = registerReceiptTestSession(
            auxiliaryWindows: auxiliaryWindows,
            tab: tab,
            window: window,
            webView: webView,
            permissions: permissions
        )
        defer {
            webView.uiDelegate = nil
            window.delegate = nil
            _ = auxiliaryWindows.sessions.remove(replacement.receipt)
            removeReceiptTestTab(tab, from: harness)
        }
        let action = receiptPopupNavigationAction(
            sourceURL: tab.url,
            targetURL: URL(string: "https://example.com/stale-child")!,
            webView: webView
        )

        XCTAssertNil(
            original.session.uiDelegate.webView(
                webView,
                createWebViewWith: WKWebViewConfiguration(),
                for: action,
                windowFeatures: SizedAuxiliaryWindowFeatures()
            )
        )
        var openPanelResults: [[URL]?] = []
        original.session.uiDelegate.webView(
            webView,
            runOpenPanelWith: WKOpenPanelParameters(),
            initiatedByFrame: action.sourceFrame
        ) { openPanelResults.append($0) }
        var alertCompletions = 0
        original.session.uiDelegate.webView(
            webView,
            runJavaScriptAlertPanelWithMessage: "stale alert",
            initiatedByFrame: action.sourceFrame
        ) { alertCompletions += 1 }
        var confirmResults: [Bool] = []
        original.session.uiDelegate.webView(
            webView,
            runJavaScriptConfirmPanelWithMessage: "stale confirm",
            initiatedByFrame: action.sourceFrame
        ) { confirmResults.append($0) }
        var promptResults: [String?] = []
        original.session.uiDelegate.webView(
            webView,
            runJavaScriptTextInputPanelWithPrompt: "stale prompt",
            defaultText: "unsafe",
            initiatedByFrame: action.sourceFrame
        ) { promptResults.append($0) }
        original.session.uiDelegate.webViewDidClose(webView)

        XCTAssertEqual(permissions.popupEvaluationCount, 0)
        XCTAssertEqual(permissions.filePickerCount, 0)
        XCTAssertEqual(openPanelResults.count, 1)
        XCTAssertNil(openPanelResults[0])
        XCTAssertEqual(alertCompletions, 1)
        XCTAssertEqual(confirmResults, [false])
        XCTAssertEqual(promptResults.count, 1)
        XCTAssertNil(promptResults[0])
        assertReceiptTestReplacement(
            replacement,
            auxiliaryWindows: auxiliaryWindows
        )
    }

    func testPopupPermissionReentrancyCannotOpenChildForReplacement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "permission-reentrant-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let tab = makeReceiptTestTab(in: harness)
        defer { removeReceiptTestTab(tab, from: harness) }
        let webView = makeReceiptTestWebView(in: harness)
        webView.owningTab = tab
        XCTAssertTrue(
            harness.browserManager.testWebViewRuntime()
                .untrackedWebViewInstallationService
                .installUntracked(webView, for: tab).isAccepted
        )
        let committedNavigation = try await establishReceiptTestDocument(
            on: webView,
            tab: tab
        )
        let window = AuxiliaryCompactWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240)
        )
        let permissions = AuxiliaryWindowPermissionReceiptProbe()
        let original = registerReceiptTestSession(
            auxiliaryWindows: auxiliaryWindows,
            tab: tab,
            window: window,
            webView: webView,
            permissions: permissions
        )
        var replacement: AuxiliaryWindowReceiptTestRegistration?
        permissions.onPopupEvaluation = {
            guard replacement == nil else { return }
            XCTAssertTrue(
                auxiliaryWindows.sessions.remove(original.receipt)
                    === original.session
            )
            replacement = registerReceiptTestSession(
                auxiliaryWindows: auxiliaryWindows,
                tab: tab,
                window: window,
                webView: webView,
                permissions: permissions
            )
        }
        let action = receiptPopupNavigationAction(
            sourceURL: tab.url,
            targetURL: URL(string: "https://example.com/reentrant-child")!,
            webView: webView
        )

        let child = original.session.uiDelegate.webView(
            webView,
            createWebViewWith: WKWebViewConfiguration(),
            for: action,
            windowFeatures: SizedAuxiliaryWindowFeatures()
        )

        let unwrappedReplacement = try XCTUnwrap(replacement)
        defer {
            webView.uiDelegate = nil
            window.delegate = nil
            _ = auxiliaryWindows.sessions.remove(unwrappedReplacement.receipt)
        }
        XCTAssertNil(child)
        XCTAssertEqual(permissions.popupEvaluationCount, 1)
        XCTAssertEqual(auxiliaryWindows.sessions.sessionsSnapshot().count, 1)
        assertReceiptTestReplacement(
            unwrappedReplacement,
            auxiliaryWindows: auxiliaryWindows
        )
        withExtendedLifetime(committedNavigation) { /* exact document lease */ }
    }

    func testFilePickerAsyncTailRejectsSameWebViewReplacement()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "file-picker-reentrant-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let tab = makeReceiptTestTab(in: harness)
        defer { removeReceiptTestTab(tab, from: harness) }
        let webView = makeReceiptTestWebView(in: harness)
        webView.owningTab = tab
        XCTAssertTrue(
            harness.browserManager.testWebViewRuntime()
                .untrackedWebViewInstallationService
                .installUntracked(webView, for: tab).isAccepted
        )
        let committedNavigation = try await establishReceiptTestDocument(
            on: webView,
            tab: tab
        )
        let window = AuxiliaryCompactWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240)
        )
        let permissions = AuxiliaryWindowPermissionReceiptProbe()
        permissions.shouldHandleFilePicker = true
        let original = registerReceiptTestSession(
            auxiliaryWindows: auxiliaryWindows,
            tab: tab,
            window: window,
            webView: webView,
            permissions: permissions
        )
        let action = receiptPopupNavigationAction(
            sourceURL: tab.url,
            targetURL: URL(string: "https://example.com/file-picker")!,
            webView: webView
        )
        var results: [[URL]?] = []

        original.session.uiDelegate.webView(
            webView,
            runOpenPanelWith: WKOpenPanelParameters(),
            initiatedByFrame: action.sourceFrame
        ) { results.append($0) }

        XCTAssertEqual(permissions.filePickerCount, 1)
        XCTAssertTrue(results.isEmpty)
        let currentPageID = try XCTUnwrap(
            permissions.capturedFilePickerCurrentPageID
        )
        let completion = try XCTUnwrap(
            permissions.capturedFilePickerCompletion
        )
        XCTAssertNotNil(currentPageID())
        XCTAssertTrue(
            auxiliaryWindows.sessions.remove(original.receipt)
                === original.session
        )
        let replacement = registerReceiptTestSession(
            auxiliaryWindows: auxiliaryWindows,
            tab: tab,
            window: window,
            webView: webView,
            permissions: permissions
        )
        defer {
            webView.uiDelegate = nil
            window.delegate = nil
            _ = auxiliaryWindows.sessions.remove(replacement.receipt)
        }

        XCTAssertNil(currentPageID())
        completion([URL(fileURLWithPath: "/tmp/stale-file-picker-result")])

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0])
        assertReceiptTestReplacement(
            replacement,
            auxiliaryWindows: auxiliaryWindows
        )
        withExtendedLifetime(committedNavigation) { /* exact document lease */ }
    }

    func testAuxiliaryPermissionContextsRejectWrongDataStoreWithoutBridgeEffects()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "permission-wrong-store-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let tab = makeReceiptTestTab(in: harness)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        XCTAssertFalse(
            configuration.websiteDataStore === harness.profile.dataStore
        )
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.owningTab = tab
        XCTAssertTrue(
            harness.browserManager.testWebViewRuntime()
                .untrackedWebViewInstallationService
                .installUntracked(webView, for: tab).isAccepted
        )
        let committedNavigation = try await establishReceiptTestDocument(
            on: webView,
            tab: tab
        )
        XCTAssertTrue(
            harness.browserManager.webViewRoutingService.ownsLiveWebView(
                webView,
                for: tab
            )
        )
        let window = AuxiliaryCompactWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240)
        )
        let permissions = AuxiliaryWindowPermissionReceiptProbe()
        permissions.shouldHandleFilePicker = true
        let registration = registerReceiptTestSession(
            auxiliaryWindows: auxiliaryWindows,
            tab: tab,
            window: window,
            webView: webView,
            permissions: permissions
        )
        defer {
            auxiliaryWindows.teardown.teardown(
                registration.receipt,
                reason: .bulkCleanup
            )
        }
        let action = receiptPopupNavigationAction(
            sourceURL: tab.url,
            targetURL: URL(string: "https://example.com/rejected-permission")!,
            webView: webView
        )

        XCTAssertNil(
            registration.session.uiDelegate.webView(
                webView,
                createWebViewWith: WKWebViewConfiguration(),
                for: action,
                windowFeatures: SizedAuxiliaryWindowFeatures()
            )
        )
        var filePickerResults: [[URL]?] = []
        registration.session.uiDelegate.webView(
            webView,
            runOpenPanelWith: WKOpenPanelParameters(),
            initiatedByFrame: action.sourceFrame
        ) { filePickerResults.append($0) }

        XCTAssertEqual(permissions.popupEvaluationCount, 0)
        XCTAssertEqual(permissions.filePickerCount, 0)
        XCTAssertEqual(filePickerResults.count, 1)
        XCTAssertNil(filePickerResults[0])
        XCTAssertIdentical(
            auxiliaryWindows.sessions.session(for: registration.receipt),
            registration.session
        )
        XCTAssertEqual(auxiliaryWindows.sessions.sessionsSnapshot().count, 1)
        withExtendedLifetime(committedNavigation) { /* exact document lease */ }
    }

    func testCloseCallbackReplacementKeepsSamePhysicalResources()
        async throws {
        let ownerExtensionID = "close-reentrant-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(
            presentOwnerPopup(
                in: harness
            )
        )
        let original = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let permissions = AuxiliaryWindowPermissionReceiptProbe()
        var replacement: AuxiliaryWindowReceiptTestRegistration?
        var hooks = harness.extensionManager.testHooks
        hooks.didCloseAuxiliaryWindow = { sessionID in
            guard sessionID == original.id, replacement == nil else { return }
            let membership = harness.browserManager
                .tabCollectionMembershipOwner
            membership.attach(original.tab)
            membership.registerAuxiliaryMiniWindowTab(original.tab)
            (original.webView as? FocusableWKWebView)?.owningTab = original.tab
            original.tab.replaceUntrackedWebView(original.webView)
            original.window.contentView?.addSubview(original.webView)
            let registered = registerReceiptTestSession(
                auxiliaryWindows: auxiliaryWindows,
                tab: original.tab,
                window: original.window,
                webView: original.webView,
                permissions: permissions
            )
            registered.session.window.present(shouldActivateApp: false)
            replacement = registered
        }
        harness.extensionManager.testHooks = hooks
        defer {
            harness.extensionManager.clearDebugState()
            if let replacement {
                auxiliaryWindows.teardown.teardown(
                    replacement.receipt,
                    reason: .bulkCleanup
                )
            }
        }

        auxiliaryWindows.teardownAuxiliaryWindowForTesting(
            webView,
            reason: .webViewDidClose
        )

        let unwrappedReplacement = try XCTUnwrap(replacement)
        assertReceiptTestReplacement(
            unwrappedReplacement,
            auxiliaryWindows: auxiliaryWindows
        )
        XCTAssertTrue(original.tab.hasBrowserRuntime)
        XCTAssertTrue(
            harness.browserManager.auxiliaryMiniWindowTabs
                .containsExact(original.tab)
        )
        XCTAssertIdentical(
            original.tab.resolvedAssignedWebView()
                ?? original.tab.resolvedCurrentWebView(),
            original.webView
        )
        XCTAssertIdentical(
            original.webView.superview,
            original.window.contentView
        )
        XCTAssertTrue(original.window.isVisible)
    }

    func testFocusRestoreRejectsTargetReplacedDuringFocusCallback()
        async throws {
        let ownerExtensionID = "focus-reentrant-owner"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let siblingWebView = try XCTUnwrap(
            presentOwnerPopup(
                in: harness
            )
        )
        let sibling = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: siblingWebView)
        )
        let targetWebView = try XCTUnwrap(
            presentOwnerPopup(
                in: harness
            )
        )
        let target = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: targetWebView)
        )
        let targetReceipt = try XCTUnwrap(
            auxiliaryWindows.sessions.receipt(for: target)
        )
        let control = try XCTUnwrap(
            harness.attachedRuntime.bridge.auxiliaryWindows
        )
        let siblingAdapter = try XCTUnwrap(sibling.miniWindowAdapter)
        harness.extensionContext.didFocusWindow(siblingAdapter)
        var replacement: AuxiliaryWindowReceiptTestRegistration?
        var hooks = harness.extensionManager.testHooks
        hooks.didFocusAuxiliaryWindow = { sessionID in
            guard sessionID == target.id, replacement == nil else { return }
            XCTAssertTrue(
                auxiliaryWindows.sessions.remove(targetReceipt) === target
            )
            let replacementID = UUID()
            let adapter = ExtensionMiniWindowAdapter(
                sessionId: replacementID,
                tab: target.tab,
                window: target.window,
                auxiliaryWindows: control,
                windowPublications:
                    harness.attachedRuntime.publications.windowPublications,
                isPrivate: target.isPrivate,
                shouldActivateApp: target.shouldActivateApp
            )
            replacement = registerReceiptTestSession(
                auxiliaryWindows: auxiliaryWindows,
                tab: target.tab,
                window: target.window,
                webView: target.webView,
                permissions: AuxiliaryWindowPermissionReceiptProbe(),
                sessionID: replacementID,
                openerTab: target.openerTab,
                openerWindow: target.openerWindow,
                shouldActivateApp: target.shouldActivateApp,
                isPrivate: target.isPrivate,
                ownerExtensionID: ownerExtensionID,
                miniWindowAdapter: adapter
            )
        }
        harness.extensionManager.testHooks = hooks
        defer {
            harness.extensionManager.clearDebugState()
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        XCTAssertFalse(
            auxiliaryWindows.focus.restoreMostRecentWindow(
                forExtensionID: ownerExtensionID
            )
        )

        let unwrappedReplacement = try XCTUnwrap(replacement)
        assertReceiptTestReplacement(
            unwrappedReplacement,
            auxiliaryWindows: auxiliaryWindows
        )
        XCTAssertIdentical(
            auxiliaryWindows.sessions.session(for: sibling.id),
            sibling
        )
        XCTAssertNil(auxiliaryWindows.sessions.session(for: targetReceipt))
        XCTAssertEqual(
            Set(auxiliaryWindows.sessions.sessionsSnapshot().map(\.id)),
            [sibling.id, unwrappedReplacement.session.id]
        )
    }

    func testMiniWindowAdapterFocusRejectsReplacementDuringOrderFront()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let target = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let targetReceipt = try XCTUnwrap(
            auxiliaryWindows.sessions.receipt(for: target)
        )
        let adapter = try XCTUnwrap(target.miniWindowAdapter)
        let control = try XCTUnwrap(
            harness.attachedRuntime.bridge.auxiliaryWindows
        )
        target.window.orderOut(nil)
        XCTAssertFalse(target.window.isVisible)
        XCTAssertFalse(target.window.isKeyWindow)

        var replacement: AuxiliaryWindowReceiptTestRegistration?
        let visibilityTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                replacement = replaceReceiptTestSession(
                    target,
                    receipt: targetReceipt,
                    auxiliaryWindows: auxiliaryWindows,
                    control: control,
                    windowPublications:
                        harness.attachedRuntime.publications.windowPublications
                )
                return replacement != nil
            }
        )
        let visibilityObservation = target.window.observe(
            \.isVisible,
            options: [.old, .new]
        ) { _, change in
            guard change.oldValue == false,
                  change.newValue == true else {
                return
            }
            MainActor.assumeIsolated {
                visibilityTrigger.fire()
            }
        }
        defer {
            visibilityObservation.invalidate()
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        var callbackError: Error?
        adapter.focus(for: harness.extensionContext) {
            callbackError = $0
        }

        XCTAssertTrue(visibilityTrigger.didFire)
        XCTAssertNotNil(callbackError)
        assertReceiptTestReplacement(
            try XCTUnwrap(replacement),
            auxiliaryWindows: auxiliaryWindows
        )
    }

    func testMiniWindowAdapterSetFrameRejectsReplacementDuringResize()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let target = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let targetReceipt = try XCTUnwrap(
            auxiliaryWindows.sessions.receipt(for: target)
        )
        let adapter = try XCTUnwrap(target.miniWindowAdapter)
        let control = try XCTUnwrap(
            harness.attachedRuntime.bridge.auxiliaryWindows
        )
        var replacement: AuxiliaryWindowReceiptTestRegistration?
        let effectProbe = AuxiliaryWindowEffectBoundaryProbe(
            onDidResize: {
                replacement = replaceReceiptTestSession(
                    target,
                    receipt: targetReceipt,
                    auxiliaryWindows: auxiliaryWindows,
                    control: control,
                    windowPublications:
                        harness.attachedRuntime.publications.windowPublications
                )
            }
        )
        target.window.delegate = effectProbe
        defer {
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }

        var callbackError: Error?
        var resizedFrame = target.window.frame
        resizedFrame.size.width += 32
        resizedFrame.size.height += 24
        adapter.setFrame(
            resizedFrame,
            for: harness.extensionContext
        ) { callbackError = $0 }

        XCTAssertTrue(effectProbe.didResize)
        XCTAssertNotNil(callbackError)
        assertReceiptTestReplacement(
            try XCTUnwrap(replacement),
            auxiliaryWindows: auxiliaryWindows
        )
    }

    func testMiniWindowAdapterSetStateRejectsReplacementDuringMiniaturize()
        async throws {
        let harness = try await makeExtensionHarness(
            ownerExtensionID: "adapter-owner"
        )
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let webView = try XCTUnwrap(presentOwnerPopup(in: harness))
        let target = try XCTUnwrap(
            auxiliaryWindows.sessions.session(for: webView)
        )
        let targetReceipt = try XCTUnwrap(
            auxiliaryWindows.sessions.receipt(for: target)
        )
        let adapter = try XCTUnwrap(target.miniWindowAdapter)
        let control = try XCTUnwrap(
            harness.attachedRuntime.bridge.auxiliaryWindows
        )
        var replacement: AuxiliaryWindowReceiptTestRegistration?
        let miniaturizeTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                replacement = replaceReceiptTestSession(
                    target,
                    receipt: targetReceipt,
                    auxiliaryWindows: auxiliaryWindows,
                    control: control,
                    windowPublications:
                        harness.attachedRuntime.publications.windowPublications
                )
                return replacement != nil
            }
        )
        let miniaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willMiniaturizeNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                miniaturizeTrigger.fire()
            }
        }
        let settlementExpectation = expectation(
            description: "exact window did miniaturize"
        )
        let settlementTrigger = AuxiliaryWindowOneShotEffectTrigger(
            attempt: {
                settlementExpectation.fulfill()
                return true
            }
        )
        let settlementObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification,
            object: target.window,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                settlementTrigger.fire()
            }
        }
        defer {
            NotificationCenter.default.removeObserver(miniaturizeObserver)
            NotificationCenter.default.removeObserver(settlementObserver)
            auxiliaryWindows.teardown.closeAll(reason: .bulkCleanup)
        }
        XCTAssertTrue(target.window.styleMask.contains(.miniaturizable))
        XCTAssertEqual(
            target.window.standardWindowButton(.miniaturizeButton)?.isEnabled,
            true
        )
        XCTAssertTrue(target.window.isVisible)
        XCTAssertFalse(target.window.isMiniaturized)

        var callbackError: Error?
        let completionExpectation = expectation(
            description: "state transition completion"
        )
        adapter.setWindowState(
            .minimized,
            for: harness.extensionContext
        ) {
            callbackError = $0
            completionExpectation.fulfill()
        }
        await fulfillment(
            of: [completionExpectation, settlementExpectation],
            timeout: 5
        )

        XCTAssertTrue(miniaturizeTrigger.didFire)
        XCTAssertTrue(settlementTrigger.didFire)
        XCTAssertTrue(target.window.isMiniaturized)
        assertExtensionBridgeCallbackError(
            callbackError,
            equals: .miniWindowStateTransitionInvalidated
        )
        assertReceiptTestReplacement(
            try XCTUnwrap(replacement),
            auxiliaryWindows: auxiliaryWindows
        )
    }

    func testExternalPopupRejectsInvalidOwnerEvidenceBeforeAnyMutation()
        async throws {
        let ownerExtensionID = "owner-evidence-a"
        let harness = try await makeExtensionHarness(
            ownerExtensionID: ownerExtensionID
        )
        let crossOwnerID = "owner-evidence-b"
        let disabledOwnerID = "owner-evidence-disabled"
        let crossContext = try await makeExtensionContext(
            ownerExtensionID: crossOwnerID
        )
        let disabledContext = try await makeExtensionContext(
            ownerExtensionID: disabledOwnerID
        )
        harness.inspection.contextState.profiles.setContext(
            crossContext,
            extensionId: crossOwnerID,
            profileId: harness.profile.id
        )
        harness.inspection.contextState.profiles.setContext(
            disabledContext,
            extensionId: disabledOwnerID,
            profileId: harness.profile.id
        )
        harness.inspection.actionSurfaces.installedExtensions.upsert(
            auxiliaryInstalledExtension(id: crossOwnerID),
            durability: .volatileExactRuntime
        )
        harness.inspection.actionSurfaces.installedExtensions.upsert(
            auxiliaryInstalledExtension(
                id: disabledOwnerID,
                isEnabled: false
            ),
            durability: .volatileExactRuntime
        )
        let configuration = extensionPopupConfiguration(for: harness)
        let auxiliaryWindows = harness.browserManager.auxiliaryWindows
        let originalSessionIDs = Set(
            auxiliaryWindows.sessions.sessionsSnapshot().map(\.id)
        )
        let originalTabIDs = Set(
            harness.browserManager.tabCollectionMembershipOwner
                .allTabs().map(\.id)
        )
        let originalAuxiliaryTabIDs = Set(
            harness.browserManager.tabCollectionMembershipOwner
                .allIdentityWitnesses()
                .filter { $0.isAuxiliaryMiniWindow }
                .map(\.id)
        )
        let originalAdapterIDs = Set(
            harness.inspection.normalTabs.adapters
                .miniWindowAdaptersSnapshot().map(ObjectIdentifier.init)
        )
        let originalNativeWindowIDs = Set(
            NSApp.windows.map(ObjectIdentifier.init)
        )
        let contexts = [
            harness.extensionContext,
            crossContext,
            disabledContext,
        ]
        let originalContextWindows = contexts.map {
            $0.openWindows.map { ObjectIdentifier($0 as AnyObject) }
        }
        let originalContextTabs = contexts.map {
            $0.openTabs.map { ObjectIdentifier($0 as AnyObject) }
        }
        var publicationEvents = 0
        var hooks = harness.extensionManager.testHooks
        hooks.didOpenAuxiliaryWindow = { _ in publicationEvents += 1 }
        hooks.didFocusAuxiliaryWindow = { _ in publicationEvents += 1 }
        hooks.didCloseAuxiliaryWindow = { _ in publicationEvents += 1 }
        harness.extensionManager.testHooks = hooks
        defer { harness.extensionManager.clearDebugState() }

        let invalidSources: [(String, String?)] = [
            ("unknown-owner", nil),
            (crossOwnerID, ownerExtensionID),
            (disabledOwnerID, nil),
        ]
        for (sourceOwnerID, explicitOwnerID) in invalidSources {
            XCTAssertNil(
                auxiliaryWindows.popups.presentExtensionExternalWebPopup(
                    configuration: configuration,
                    request: URLRequest(
                        url: URL(string: "https://auth.example/login")!
                    ),
                    windowFeatures: WKWindowFeatures(),
                    openerTab: harness.sourceTab,
                    extensionOwnedSourceURL: URL(
                        string: "safari-web-extension://\(sourceOwnerID)/popup.html"
                    )!,
                    ownerExtensionID: explicitOwnerID
                )
            )
        }

        XCTAssertEqual(
            Set(auxiliaryWindows.sessions.sessionsSnapshot().map(\.id)),
            originalSessionIDs
        )
        XCTAssertEqual(
            Set(
                harness.browserManager
                    .tabCollectionMembershipOwner.allTabs().map(\.id)
            ),
            originalTabIDs
        )
        XCTAssertEqual(
            Set(
                harness.browserManager.tabCollectionMembershipOwner
                    .allIdentityWitnesses()
                    .filter { $0.isAuxiliaryMiniWindow }
                    .map(\.id)
            ),
            originalAuxiliaryTabIDs
        )
        XCTAssertEqual(
            Set(
                harness.inspection.normalTabs.adapters
                    .miniWindowAdaptersSnapshot().map(ObjectIdentifier.init)
            ),
            originalAdapterIDs
        )
        XCTAssertEqual(
            Set(NSApp.windows.map(ObjectIdentifier.init)),
            originalNativeWindowIDs
        )
        XCTAssertEqual(
            contexts.map {
                $0.openWindows.map { ObjectIdentifier($0 as AnyObject) }
            },
            originalContextWindows
        )
        XCTAssertEqual(
            contexts.map {
                $0.openTabs.map { ObjectIdentifier($0 as AnyObject) }
            },
            originalContextTabs
        )
        XCTAssertEqual(publicationEvents, 0)
    }

    private func makeReceiptTestTab(
        in harness: ExtensionHarness
    ) -> Tab {
        guard let tab = harness.browserManager.auxiliaryMiniWindowTabs.create(
                openerTab: harness.sourceTab,
                profileID: harness.profile.id,
                urlString: "about:blank",
                webExtensionContextOverride: nil
            )
        else {
            preconditionFailure("Receipt fixture requires an admitted auxiliary Tab")
        }
        return tab
    }

    private func makeReceiptTestWebView(
        in harness: ExtensionHarness
    ) -> FocusableWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.profile.dataStore
        return FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
    }

    private func removeReceiptTestTab(
        _ tab: Tab,
        from harness: ExtensionHarness
    ) {
        let lifecycle = harness.browserManager.auxiliaryMiniWindowTabs
        if lifecycle.containsExact(tab) {
            lifecycle.remove(tab)
        }
    }

    private func assertReceiptTestReplacement(
        _ replacement: AuxiliaryWindowReceiptTestRegistration,
        auxiliaryWindows: BrowserAuxiliaryWindowComposition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertIdentical(
            auxiliaryWindows.sessions.session(for: replacement.receipt),
            replacement.session,
            file: file,
            line: line
        )
        XCTAssertIdentical(
            replacement.session.webView.uiDelegate,
            replacement.session.uiDelegate,
            file: file,
            line: line
        )
        XCTAssertTrue(
            replacement.session.window.delegate
                === replacement.session.windowDelegate,
            file: file,
            line: line
        )
    }

    private func establishReceiptTestDocument(
        on webView: WKWebView,
        tab: Tab
    ) async throws -> NSObject {
        let didFinish = expectation(
            description: "auxiliary permission document loaded"
        )
        let delegate = AuxiliaryReceiptDocumentNavigationDelegate {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.loadHTMLString(
            "<html><body>auxiliary permission source</body></html>",
            baseURL: URL(string: "https://example.com/auxiliary-source")!
        )
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil

        let committedURL = try XCTUnwrap(webView.committedURL)
        let intent = tab.beginMainFrameNavigationIntent(to: committedURL)
        XCTAssertTrue(
            tab.mainFrameLoads.markDeferredLoad(
                on: webView,
                intent: intent
            )
        )
        XCTAssertEqual(
            tab.mainFrameLoads.claimDeferredSubmission(
                on: webView,
                revision: intent.revision,
                targetURL: committedURL
            ),
            .claimed
        )
        let navigation = NSObject()
        XCTAssertTrue(
            tab.mainFrameSubmission.bindSubmittedLoad(
                on: webView,
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                matching: nil
            )
        )
        tab.makeMainFrameLifecycleResponder().navigationDidCommit(
            SumiNavigationContext(
                navigationID: ObjectIdentifier(navigation),
                navigationLifetime: navigation,
                action: nil,
                url: committedURL,
                isCurrent: nil,
                isCommitted: true,
                isMainFrame: true,
                webView: webView
            )
        )
        XCTAssertNotNil(tab.committedDocumentRuntime.lease(for: webView))
        return navigation
    }
}

func assertExtensionBridgeCallbackError(
    _ error: Error?,
    equals expected: ExtensionBridgeAdapterCallbackError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let error else {
        XCTFail("Expected extension bridge callback error", file: file, line: line)
        return
    }
    let callbackError = error as NSError
    XCTAssertEqual(
        callbackError.userInfo[
            SumiWebExtensionCallbackErrorMapper.underlyingDomainUserInfoKey
        ] as? String,
        expected.domain,
        file: file,
        line: line
    )
    XCTAssertEqual(
        callbackError.userInfo[
            SumiWebExtensionCallbackErrorMapper.underlyingCodeUserInfoKey
        ] as? Int,
        expected.code,
        file: file,
        line: line
    )
    XCTAssertEqual(
        callbackError.localizedDescription,
        expected.message,
        file: file,
        line: line
    )
}

@MainActor
private struct AuxiliaryWindowReceiptTestRegistration {
    let session: AuxiliaryWindowSession
    let receipt: AuxiliaryWindowSessionReceipt
    let permissions: any AuxiliaryWindowPermissionHandling
}

@MainActor
private func registerReceiptTestSession(
    auxiliaryWindows: BrowserAuxiliaryWindowComposition,
    tab: Tab,
    window: AuxiliaryCompactWindow,
    webView: WKWebView,
    permissions: any AuxiliaryWindowPermissionHandling,
    sessionID: UUID = UUID(),
    openerTab: Tab? = nil,
    openerWindow: NSWindow? = nil,
    shouldActivateApp: Bool = false,
    isPrivate: Bool = false,
    ownerExtensionID: String? = nil,
    miniWindowAdapter: ExtensionMiniWindowAdapter? = nil,
    extensionEvents: (any AuxiliaryWindowExtensionEventHandling)? = nil
) -> AuxiliaryWindowReceiptTestRegistration {
    let uiDelegate = AuxiliaryWindowUIDelegate(
        sessions: auxiliaryWindows.sessions,
        popups: auxiliaryWindows.popups,
        teardown: auxiliaryWindows.teardown,
        permissions: permissions,
        nestingPolicy: auxiliaryWindows.nestingPolicy,
        nestedDepth: 0
    )
    let windowDelegate = AuxiliaryWindowSessionDelegate(
        teardown: auxiliaryWindows.teardown,
        focus: auxiliaryWindows.focus
    )
    let session = AuxiliaryWindowSession(
        id: sessionID,
        tab: tab,
        window: window,
        webView: webView,
        openerTab: openerTab,
        openerWindow: openerWindow,
        shouldActivateApp: shouldActivateApp,
        isPrivate: isPrivate,
        ownerExtensionID: ownerExtensionID,
        miniWindowAdapter: miniWindowAdapter,
        extensionEvents: extensionEvents,
        uiDelegate: uiDelegate,
        windowDelegate: windowDelegate
    )
    let receipt = auxiliaryWindows.sessions.register(session)
    uiDelegate.bind(receipt)
    windowDelegate.bind(receipt)
    miniWindowAdapter?.bind(receipt)
    webView.uiDelegate = uiDelegate
    window.delegate = windowDelegate
    return AuxiliaryWindowReceiptTestRegistration(
        session: session,
        receipt: receipt,
        permissions: permissions
    )
}

@MainActor
private func replaceReceiptTestSession(
    _ target: AuxiliaryWindowSession,
    receipt: AuxiliaryWindowSessionReceipt,
    auxiliaryWindows: BrowserAuxiliaryWindowComposition,
    control: any ExtensionAuxiliaryWindowControl,
    windowPublications: ExtensionWindowPublicationQuery
) -> AuxiliaryWindowReceiptTestRegistration? {
    guard auxiliaryWindows.sessions.remove(receipt) === target else {
        XCTFail("Expected the exact target receipt to be current")
        return nil
    }
    let replacementID = UUID()
    let adapter = ExtensionMiniWindowAdapter(
        sessionId: replacementID,
        tab: target.tab,
        window: target.window,
        auxiliaryWindows: control,
        windowPublications: windowPublications,
        isPrivate: target.isPrivate,
        shouldActivateApp: target.shouldActivateApp
    )
    return registerReceiptTestSession(
        auxiliaryWindows: auxiliaryWindows,
        tab: target.tab,
        window: target.window,
        webView: target.webView,
        permissions: AuxiliaryWindowPermissionReceiptProbe(),
        sessionID: replacementID,
        openerTab: target.openerTab,
        openerWindow: target.openerWindow,
        shouldActivateApp: target.shouldActivateApp,
        isPrivate: target.isPrivate,
        ownerExtensionID: target.ownerExtensionID,
        miniWindowAdapter: adapter
    )
}

@MainActor
final class AuxiliaryWindowOneShotEffectTrigger: @unchecked Sendable {
    private let attempt: @MainActor () -> Bool
    private(set) var didFire = false

    init(attempt: @escaping @MainActor () -> Bool) {
        self.attempt = attempt
    }

    func fire() {
        guard didFire == false,
              attempt() else {
            return
        }
        didFire = true
    }
}

@MainActor
private final class AuxiliaryWindowEffectBoundaryProbe:
    NSObject,
    NSWindowDelegate {
    private var onDidResize: (() -> Void)?
    private(set) var didResize = false

    init(onDidResize: (() -> Void)? = nil) {
        self.onDidResize = onDidResize
    }

    func windowDidResize(_ notification: Notification) {
        didResize = true
        let action = onDidResize
        onDidResize = nil
        action?()
    }
}

@MainActor
private final class AuxiliaryWindowPermissionReceiptProbe:
    AuxiliaryWindowPermissionHandling {
    private(set) var popupEvaluationCount = 0
    private(set) var filePickerCount = 0
    var onPopupEvaluation: (() -> Void)?
    var shouldHandleFilePicker = false
    private(set) var capturedFilePickerCurrentPageID:
        (@MainActor () -> String?)?
    private(set) var capturedFilePickerCompletion:
        (@MainActor @Sendable ([URL]?) -> Void)?

    func evaluatePopupPermission(
        _ request: SumiPopupPermissionRequest,
        tabContext: SumiPopupPermissionTabContext
    ) -> SumiPopupPermissionResult? {
        popupEvaluationCount += 1
        onPopupEvaluation?()
        return SumiPopupPermissionResult(action: .allow)
    }

    func handleFilePickerOpenPanel(
        _ request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext,
        webView: WKWebView?,
        currentPageID: @escaping @MainActor () -> String?,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) -> Bool {
        filePickerCount += 1
        capturedFilePickerCurrentPageID = currentPageID
        capturedFilePickerCompletion = completionHandler
        return shouldHandleFilePicker
    }
}

private final class SizedAuxiliaryWindowFeatures: WKWindowFeatures {
    override var width: NSNumber? { 320 }
}

@MainActor
private final class AuxiliaryReceiptDocumentNavigationDelegate:
    NSObject,
    WKNavigationDelegate {
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish()
    }
}

@MainActor
private func receiptPopupNavigationAction(
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
