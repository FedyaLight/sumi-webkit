import AppKit
import WebKit
import XCTest
@testable import Sumi

@MainActor
final class SumiDDGWebKitRegressionTests: XCTestCase {
    func testRemovedSumiWebKitHooksStayRemovedFromProductionSources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let productionRoots = ["App", "Navigation", "Settings", "Sumi"].map {
            repositoryRoot.appendingPathComponent($0, isDirectory: true)
        }
        let forbiddenTokens = [
            "commandClick",
            "shouldRedirectToGlance",
            "activeFullscreenVideoSessions",
            "attachHost(",
            "moveToCompositorContainer",
            "reconcileHostedSubviews",
            "fullscreenStateDidChange",
            "webViewFullscreenStateDidChange",
            "setAllMediaPlaybackSuspended",
            "closeAllMediaPresentations",
            "applyMediaSessionPolicy",
            "dataStore.isPersistent",
            "commandHover",
            "GlanceActivationMethod",
            "glanceActivationMethod",
            "FocusableWKWebViewContextMenuLifecycleDelegate",
            "FocusableWKWebView.contextMenu",
            "Promoting FocusableWKWebView",
            "configurePaintlessChrome",
            "WebColumnPaintlessChrome",
            "allowsInlineMediaPlayback",
            "mediaDevicesEnabled",
        ]

        var violations: [String] = []
        for root in productionRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard ["swift", "h", "m", "mm"].contains(fileURL.pathExtension) else { continue }
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for token in forbiddenTokens where contents.contains(token) {
                    let relativePath = fileURL.path.replacingOccurrences(
                        of: repositoryRoot.path + "/",
                        with: ""
                    )
                    violations.append("\(relativePath): \(token)")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    func testFocusableWebViewDoesNotForceFirstResponderOrInstallSidebarContextMenuLifecycle() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Utils/WebKit/FocusableWKWebView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "final class FocusableWKWebView"))
            .lowerBound
        let end = try XCTUnwrap(source.range(of: "@MainActor\nextension WKWebView"))
            .lowerBound
        let webViewSource = String(source[start..<end])

        XCTAssertFalse(webViewSource.contains("makeFirstResponder(self)"))
        XCTAssertFalse(webViewSource.contains("override var acceptsFirstResponder"))
        XCTAssertFalse(webViewSource.contains("NSMenuDelegate"))
        XCTAssertTrue(webViewSource.contains("swizzled_immediateActionAnimationController"))
    }

    func testMediaTouchBarRecoveryUsesDDGStyleWebKitOwnershipWithoutReplacingMediaCard() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let focusableWebViewSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Utils/WebKit/FocusableWKWebView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(focusableWebViewSource.contains("sumiTabContentView"))
        XCTAssertTrue(focusableWebViewSource.contains("_fullScreenPlaceholderView"))
        XCTAssertTrue(focusableWebViewSource.contains("sumiFullscreenWindowController"))
        XCTAssertTrue(focusableWebViewSource.contains("addMediaPlaybackControlsView"))
        XCTAssertTrue(focusableWebViewSource.contains("_addMediaPlaybackControlsView:"))
        XCTAssertTrue(focusableWebViewSource.contains("removeMediaPlaybackControlsView"))
        XCTAssertTrue(focusableWebViewSource.contains("_removeMediaPlaybackControlsView"))
        XCTAssertTrue(focusableWebViewSource.contains("AVTouchBarPlaybackControlsProvider"))
        XCTAssertTrue(focusableWebViewSource.contains("playbackControlsController"))
        XCTAssertFalse(focusableWebViewSource.contains("Sumi.WebKitClientMediaControls"))
        XCTAssertFalse(focusableWebViewSource.contains("makeScrubberFallbackTouchBar"))
        XCTAssertFalse(focusableWebViewSource.contains("mediaTimelineJavaScript"))
        XCTAssertFalse(focusableWebViewSource.contains("elapsedLabel"))
        XCTAssertFalse(focusableWebViewSource.contains("remainingLabel"))
        XCTAssertFalse(focusableWebViewSource.contains("closeFullScreenWindowController"))
        XCTAssertFalse(focusableWebViewSource.contains("sumiCloseInactiveFullscreenWindowControllerIfNeeded"))
        XCTAssertFalse(focusableWebViewSource.contains("webViewDidAddMediaControlsManager"))
        XCTAssertFalse(focusableWebViewSource.contains("makeSumiMediaFallbackTouchBar"))
        XCTAssertFalse(focusableWebViewSource.contains("NSTouchBarDelegate"))
        XCTAssertFalse(focusableWebViewSource.contains("_setWantsMediaPlaybackControlsView"))

        let webViewCoordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let mediaProtectionOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewMediaProtectionOwner.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(webViewCoordinatorSource.contains("private let mediaProtectionOwner = WebViewMediaProtectionOwner()"))
        XCTAssertTrue(webViewCoordinatorSource.contains("installMediaProtectionObservationsIfNeeded"))
        XCTAssertTrue(webViewCoordinatorSource.contains("host.removeFromSuperview()"))
        XCTAssertFalse(webViewCoordinatorSource.contains("private var nowPlayingSessionCancellablesByWebViewID"))
        XCTAssertFalse(webViewCoordinatorSource.contains("private func postMediaTouchBarRecoveryRequest"))
        XCTAssertFalse(webViewCoordinatorSource.contains("private func requestFullscreenMediaExit"))
        XCTAssertFalse(webViewCoordinatorSource.contains("closeAllMediaPresentations"))
        XCTAssertTrue(mediaProtectionOwnerSource.contains("sumiWebViewNeedsMediaTouchBarRecovery"))
        XCTAssertTrue(mediaProtectionOwnerSource.contains("installNowPlayingSessionObservationIfNeeded"))
        XCTAssertTrue(mediaProtectionOwnerSource.contains("postMediaTouchBarRecoveryRequest"))
        XCTAssertTrue(mediaProtectionOwnerSource.contains("requestFullscreenMediaExit"))

        let containerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/SumiWebViewContainerView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(containerSource.contains("preservesDisplayedContentOnNextRemoval"))
        XCTAssertTrue(containerSource.contains("webView.sumiTabContentView.removeFromSuperview()"))

        let compositorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        let recoverySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WindowMediaTouchBarRecoveryController.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(compositorSource.contains("private lazy var mediaTouchBarRecoveryController"))
        XCTAssertTrue(compositorSource.contains("mediaTouchBarRecoveryController.start()"))
        XCTAssertTrue(compositorSource.contains("mediaTouchBarRecoveryController.stop()"))
        XCTAssertTrue(compositorSource.contains("recoverMediaTouchBarAfterWebKitReparent"))
        XCTAssertTrue(compositorSource.contains("resetWebKitMediaTouchBar"))
        XCTAssertTrue(compositorSource.contains("host.attachDisplayedContentIfNeeded()"))
        XCTAssertFalse(compositorSource.contains("webView.sumiCloseInactiveFullscreenWindowControllerIfNeeded()"))
        XCTAssertTrue(compositorSource.contains("webView.touchBar = nil"))
        XCTAssertTrue(compositorSource.contains("window.makeFirstResponder(webView)"))
        XCTAssertTrue(recoverySource.contains("final class WindowMediaTouchBarRecoveryController"))
        XCTAssertTrue(recoverySource.contains("private static let retryDelays: [TimeInterval] = [0, 0.2, 0.5]"))
        XCTAssertTrue(recoverySource.contains("publisher(for: .sumiWebViewNeedsMediaTouchBarRecovery)"))
        try assertTokenOrder(
            Substring(recoverySource),
            [
                "notificationWindowID == windowID",
                "let tabID = notification.userInfo?[SumiMediaTouchBarRecoveryNotificationKey.tabID] as? UUID",
                "recover(tabID, webView)",
                "for delay in Self.retryDelays",
                "DispatchQueue.main.asyncAfter(deadline: .now() + delay)",
                "self?.recover(tabID, webView)"
            ]
        )

        let audioStateSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Utils/WebKit/SumiWebViewAudioState.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(audioStateSource.contains("sumiHasActiveNowPlayingSession"))
        XCTAssertTrue(audioStateSource.contains("_hasActiveNowPlayingSession"))

        let mediaCardSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/Sidebar/MediaControls/MediaControlsView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(mediaCardSource.contains("SumiBackgroundMediaCardView"))
        XCTAssertTrue(mediaCardSource.contains("onPlayPause"))
        XCTAssertTrue(mediaCardSource.contains("onToggleMute"))
    }

    func testFocusableWebViewContainsDDGMouseTrackingLoadSheddingHook() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Utils/WebKit/FocusableWKWebView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "final class FocusableWKWebView"))
            .lowerBound
        let end = try XCTUnwrap(source.range(of: "@MainActor\nextension WKWebView"))
            .lowerBound
        let webViewSource = String(source[start..<end])

        XCTAssertTrue(webViewSource.contains("webKitMouseTrackingLoadSheddingEnabled"))
        XCTAssertTrue(webViewSource.contains("override func addTrackingArea(_ trackingArea: NSTrackingArea)"))
        XCTAssertTrue(webViewSource.contains("WKMouseTrackingObserver"))
        XCTAssertTrue(webViewSource.contains("observe(\\.isLoading"))
        XCTAssertTrue(webViewSource.contains("webKitMouseTrackingLoadSheddingObserver?.invalidate()"))
        XCTAssertTrue(webViewSource.contains("let trackingAreaID = ObjectIdentifier(trackingArea)"))
        XCTAssertTrue(webViewSource.contains("ObjectIdentifier(trackingArea) == trackingAreaID"))
        XCTAssertTrue(webViewSource.contains("Task { @MainActor"))
        XCTAssertTrue(webViewSource.contains("guard trackingAreas.contains(trackingArea)"))
        XCTAssertTrue(webViewSource.contains("guard !trackingAreas.contains(trackingArea)"))
        XCTAssertTrue(webViewSource.contains("removeTrackingArea(trackingArea)"))
        XCTAssertTrue(webViewSource.contains("superAddTrackingArea(trackingArea)"))
        XCTAssertFalse(webViewSource.contains("findInPageInteractionTrackingArea"))
        XCTAssertFalse(webViewSource.contains("refreshFindInPageInteractionTrackingArea"))
        XCTAssertFalse(webViewSource.contains("pageInteractionWillBegin"))
        XCTAssertFalse(webViewSource.contains("_ignoresMouseMoveEvents"))
        XCTAssertFalse(webViewSource.contains("ignoresMouseMoveEvents"))
    }

    func testTransientChromeMouseTrackingSuppressionDoesNotOwnCursor() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Utils/WebKit/FocusableWKWebView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "final class FocusableWKWebView"))
            .lowerBound
        let end = try XCTUnwrap(source.range(of: "@MainActor\nextension WKWebView"))
            .lowerBound
        let webViewSource = String(source[start..<end])

        XCTAssertTrue(webViewSource.contains("setTransientChromeMouseTrackingSuppressed"))
        XCTAssertFalse(webViewSource.contains("NSCursor.arrow.set()"))
    }

    func testFindChromeUsesNativeCursorRectsInsteadOfTextActivationOverlay() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewControllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/FindInPage/FindInPageViewController.swift"
            ),
            encoding: .utf8
        )
        let representableSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/FindInPage/FindInPageChromeRepresentable.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(viewControllerSource.contains("private final class FindInPageTextField: NSTextField"))
        XCTAssertTrue(viewControllerSource.contains("sumi_chromeAddCursorRect(bounds, cursor: .iBeam)"))
        XCTAssertTrue(viewControllerSource.contains("sumi_chromeAddCursorRect(textActivationRect, cursor: .iBeam)"))
        XCTAssertTrue(representableSource.contains("private final class FindInPageChromeContainerView: NSView"))
        XCTAssertTrue(representableSource.contains("WebContentMouseTrackingShield.setActive(isShielding, for: self)"))
        XCTAssertTrue(representableSource.contains("FindInPageChromeContainerView(frame:"))
        XCTAssertFalse(representableSource.contains("WebContentHoverShieldSensorView()"))
        XCTAssertFalse(viewControllerSource.contains("FindInPageTextActivationView"))
        XCTAssertFalse(viewControllerSource.contains("NSEvent.mouseEvent("))
    }

    func testFindChromeFocusedTextFieldUsesIBeamFieldEditor() throws {
        let viewController = FindInPageViewController.create()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: FindInPageChromeLayout.panelWidth, height: FindInPageChromeLayout.panelHeight),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = viewController.view
        defer {
            window.close()
            window.contentView = nil
        }

        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(viewController.textField))
        viewController.textField.selectText(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let editor = try XCTUnwrap(viewController.textField.currentEditor())
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(editor.isFieldEditor)
        XCTAssertTrue(String(describing: type(of: editor)).contains("FindInPageFieldEditor"))

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewControllerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/FindInPage/FindInPageViewController.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(viewControllerSource.contains("private final class FindInPageFieldEditor: NSTextView"))
        XCTAssertTrue(viewControllerSource.contains("override func resetCursorRects()"))
        XCTAssertTrue(viewControllerSource.contains("ChromeCursorKind.iBeam.set()"))
        XCTAssertTrue(viewControllerSource.contains("func setIBeamCursorIfMouseInside()"))
        XCTAssertTrue(viewControllerSource.contains("func invalidateIBeamCursorRects()"))
        XCTAssertFalse(viewControllerSource.contains("refreshIBeamCursorIfMouseInside()"))
    }

    func testFloatingBarHoverShieldDoesNotOwnCursor() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let floatingBarSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "FloatingBar/FloatingBarView.swift"
            ),
            encoding: .utf8
        )
        let mouseShieldSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Utils/MouseEventShieldView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(floatingBarSource.contains("cursorPolicy: .none"))
        XCTAssertTrue(mouseShieldSource.contains("enum MouseEventShieldCursorPolicy"))
        XCTAssertTrue(mouseShieldSource.contains("guard isInteractive, cursorPolicy == .arrow else { return }"))
        XCTAssertTrue(mouseShieldSource.contains("private func setCursorIfNeeded()"))
    }

    func testFocusableWebViewDoesNotDuplicateWebKitMouseTrackingObserverArea() {
        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: WKWebViewConfiguration()
        )
        let owner = FakeWebKitMouseTrackingObserver()
        let trackingArea = NSTrackingArea(
            rect: webView.bounds,
            options: [.activeAlways, .mouseMoved],
            owner: owner,
            userInfo: nil
        )

        webView.addTrackingArea(trackingArea)
        webView.addTrackingArea(trackingArea)

        XCTAssertEqual(webView.trackingAreas.filter { $0 === trackingArea }.count, 1)
    }

    func testFocusableWebViewPrivateFindResumesDelegateCallback() async throws {
        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: WKWebViewConfiguration()
        )
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        try await loadHTML(
            """
            <!doctype html>
            <html>
            <body>
                <p>needle</p>
                <p>Needle</p>
                <p>needle</p>
            </body>
            </html>
            """,
            into: webView
        )

        let resultRecorder = FindResultRecorder()
        let didFind = expectation(description: "private find delegate callback resumed")
        Task { @MainActor in
            resultRecorder.result = await webView.find(
                "needle",
                with: [.caseInsensitive, .wrapAround, .showFindIndicator, .showOverlay],
                maxCount: 1000
            )
            didFind.fulfill()
        }

        await fulfillment(of: [didFind], timeout: 3)
        XCTAssertEqual(resultRecorder.result, .found(matches: 3))
    }

    func testImmediateVisualHandoffHandlerIsWindowScopedAndRemovedWithContainer() {
        let coordinator = WebViewCoordinator()
        let windowID = UUID()
        var handoffCount = 0

        coordinator.setImmediateVisualHandoffHandler({
            handoffCount += 1
            return true
        }, for: windowID)

        XCTAssertTrue(coordinator.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)

        coordinator.removeCompositorContainerView(for: windowID)

        XCTAssertFalse(coordinator.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)
    }

    func testCompositorHandoffStatePrunesStaleContainerAndHandlerTogether() {
        let handoffState = WebViewCompositorHandoffState()
        let windowID = UUID()
        var container: NSView? = NSView()
        var handoffCount = 0

        handoffState.setContainerView(container, for: windowID)
        handoffState.setImmediateVisualHandoffHandler({
            handoffCount += 1
            return true
        }, for: windowID)

        XCTAssertNotNil(handoffState.containerView(for: windowID))
        XCTAssertTrue(handoffState.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)

        container = nil

        XCTAssertNil(handoffState.containerView(for: windowID))
        XCTAssertFalse(handoffState.performImmediateVisualHandoffIfPossible(in: windowID))
        XCTAssertEqual(handoffCount, 1)
    }

    func testWebViewCoordinatorVisibleRuntimeBookkeepingStaysBehindOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let ownerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/VisibleWebViewRuntimeOwner.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(ownerSource.contains("final class VisibleWebViewRuntimeOwner"))
        XCTAssertTrue(ownerSource.contains("private let compositorHandoffState = WebViewCompositorHandoffState()"))
        XCTAssertTrue(ownerSource.contains("private var scheduledPrepareWindowIds"))

        let ownerCleanupSource = try sourceSlice(
            ownerSource,
            from: "func removeCompositorContainerView(",
            to: "func compositorContainers()"
        )
        try assertTokenOrder(
            ownerCleanupSource,
            [
                "compositorHandoffState.removeContainerView",
                "scheduledPrepareWindowIds.remove",
                "webViewRegistry.removeVisibilityHistory",
                "pruneInvalidDeferredCommands"
            ]
        )

        let ownerPrepareSource = try sourceSlice(
            ownerSource,
            from: "func prepareVisibleWebViews(",
            to: "func schedulePrepareVisibleWebViews("
        )
        try assertTokenOrder(
            ownerPrepareSource,
            [
                "visibleTabIDs(",
                "webViewRegistry.noteVisibleTabs",
                "browserManager.compositorManager.markTabAccessed",
                "createWebView(",
                "evictHiddenWebViews(",
                "scheduleProactiveTimerReconcile",
                "backgroundMediaOptimizationService.scheduleReconcile"
            ]
        )

        let ownerScheduleSource = try sourceSlice(
            ownerSource,
            from: "func schedulePrepareVisibleWebViews(",
            to: "func visibleTabIDs("
        )
        try assertTokenOrder(
            ownerScheduleSource,
            [
                "guard scheduledPrepareWindowIds.insert",
                "DispatchQueue.main.async",
                "self.scheduledPrepareWindowIds.remove",
                "browserManager.refreshCompositor"
            ]
        )

        let coordinatorStart = try XCTUnwrap(
            coordinatorSource.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorClassSource = String(coordinatorSource[coordinatorStart...])
        XCTAssertTrue(coordinatorClassSource.contains("private let visibleWebViewRuntimeOwner = VisibleWebViewRuntimeOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private let compositorHandoffState"))
        XCTAssertFalse(coordinatorClassSource.contains("private var scheduledPrepareWindowIds"))

        let coordinatorPrepareSource = try sourceSlice(
            coordinatorSource,
            from: "func prepareVisibleWebViews(",
            to: "func schedulePrepareVisibleWebViews("
        )
        XCTAssertTrue(coordinatorPrepareSource.contains("visibleWebViewRuntimeOwner.prepareVisibleWebViews("))
        XCTAssertFalse(coordinatorPrepareSource.contains("VisibleTabPreparationPlan.visibleTabIDs"))
        XCTAssertFalse(coordinatorPrepareSource.contains("webViewRegistry.noteVisibleTabs"))
        XCTAssertFalse(coordinatorPrepareSource.contains("scheduleProactiveTimerReconcile"))
    }

    func testWebViewCoordinatorTrackingLifecycleStaysBehindOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let ownerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewTrackingLifecycleOwner.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(ownerSource.contains("final class WebViewTrackingLifecycleOwner"))
        XCTAssertTrue(ownerSource.contains("typealias ContainerRemoval"))
        XCTAssertTrue(ownerSource.contains("typealias RuntimeObservationInstaller"))
        XCTAssertTrue(ownerSource.contains("typealias RuntimeObservationUninstaller"))
        XCTAssertTrue(ownerSource.contains("typealias DeferredCommandPruner"))

        let ownerRegisterSource = try sourceSlice(
            ownerSource,
            from: "func registerTrackedWebView(",
            to: "@discardableResult\n    func unregisterTrackedWebViewSlot"
        )
        try assertTokenOrder(
            ownerRegisterSource,
            [
                "webViewRegistry.indexedOwner(containing: webView)",
                "unregisterTrackedWebViewSlot(",
                "removeFromSuperview: true",
                "webViewRegistry.webView(for: owner)",
                "removeRecentVisibility: false",
                "webViewRegistry.setWebView(webView, for: owner)",
                "installRuntimeObservations(webView)",
                "webViewRegistry.assertTrackingConsistency(\"registerTrackedWebView\")"
            ]
        )

        let ownerUnregisterSource = try sourceSlice(
            ownerSource,
            from: "func unregisterTrackedWebViewSlot(",
            to: "\n    }\n}"
        )
        try assertTokenOrder(
            ownerUnregisterSource,
            [
                "let trackedWebView = webViewRegistry.webView(for: owner)",
                "webViewRegistry.removeReverseIndex(for: expectedWebView, ifOwnedBy: owner)",
                "let resolvedWebView = trackedWebView ?? expectedWebView",
                "removeFromContainers(resolvedWebView)",
                "webViewRegistry.removeWebView(",
                "uninstallRuntimeObservationsIfUntracked(resolvedWebView)",
                "pruneInvalidDeferredCommands(\"unregisterTrackedWebViewSlot\")",
                "webViewRegistry.assertTrackingConsistency(\"unregisterTrackedWebViewSlot\")"
            ]
        )

        let coordinatorStart = try XCTUnwrap(
            coordinatorSource.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorClassSource = String(coordinatorSource[coordinatorStart...])
        XCTAssertTrue(coordinatorClassSource.contains("private let webViewTrackingLifecycleOwner = WebViewTrackingLifecycleOwner()"))

        let coordinatorRegisterSource = try sourceSlice(
            coordinatorSource,
            from: "private func registerTrackedWebView(",
            to: "@discardableResult\n    private func unregisterTrackedWebViewSlot"
        )
        XCTAssertTrue(coordinatorRegisterSource.contains("webViewTrackingLifecycleOwner.registerTrackedWebView("))
        XCTAssertFalse(coordinatorRegisterSource.contains("webViewRegistry.indexedOwner(containing: webView)"))
        XCTAssertFalse(coordinatorRegisterSource.contains("webViewRegistry.setWebView(webView, for: owner)"))

        let coordinatorUnregisterSource = try sourceSlice(
            coordinatorSource,
            from: "@discardableResult\n    private func unregisterTrackedWebViewSlot",
            to: "private func trackedOwner(containing webView: WKWebView)"
        )
        XCTAssertTrue(coordinatorUnregisterSource.contains("webViewTrackingLifecycleOwner.unregisterTrackedWebViewSlot("))
        XCTAssertFalse(coordinatorUnregisterSource.contains("webViewRegistry.removeWebView("))
        XCTAssertFalse(coordinatorUnregisterSource.contains("webViewRegistry.assertTrackingConsistency(\"unregisterTrackedWebViewSlot\")"))
    }

    func testWebViewCoordinatorCrossWindowSyncStaysBehindOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let ownerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCrossWindowSyncOwner.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(ownerSource.contains("final class WebViewCrossWindowSyncOwner"))
        XCTAssertTrue(ownerSource.contains("enum WebViewSyncLoadPolicy"))
        XCTAssertTrue(ownerSource.contains("private var syncingTabIds"))

        let ownerSyncSource = try sourceSlice(
            ownerSource,
            from: "func syncTab(",
            to: "func reloadTab("
        )
        try assertTokenOrder(
            ownerSyncSource,
            [
                "guard !syncingTabIds.contains(tabId)",
                "syncingTabIds.insert(tabId)",
                "defer { syncingTabIds.remove(tabId) }",
                "isProtected(webView)",
                "WebViewSyncLoadPolicy.shouldLoadTarget",
                "load(webView)"
            ]
        )

        let ownerReloadSource = try sourceSlice(
            ownerSource,
            from: "func reloadTab(",
            to: "func setMuteState("
        )
        try assertTokenOrder(
            ownerReloadSource,
            [
                "isProtected(webView)",
                "reload(webView)"
            ]
        )

        let coordinatorStart = try XCTUnwrap(
            coordinatorSource.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorClassSource = String(coordinatorSource[coordinatorStart...])
        XCTAssertTrue(coordinatorClassSource.contains("private let crossWindowSyncOwner = WebViewCrossWindowSyncOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private var isSyncingTab"))
        XCTAssertFalse(coordinatorSource.contains("enum WebViewSyncLoadPolicy"))

        let coordinatorSyncSource = try sourceSlice(
            coordinatorSource,
            from: "func syncTab(",
            to: "/// Reload a tab"
        )
        XCTAssertTrue(coordinatorSyncSource.contains("crossWindowSyncOwner.syncTab("))
        XCTAssertTrue(coordinatorSyncSource.contains("getAllWebViews(for: tabId)"))
        XCTAssertTrue(coordinatorSyncSource.contains("isWebViewProtectedFromCompositorMutation"))
        XCTAssertTrue(coordinatorSyncSource.contains("performMainFrameNavigationAfterHydrationIfNeeded"))
        XCTAssertFalse(coordinatorSyncSource.contains("WebViewSyncLoadPolicy.shouldLoadTarget"))
        XCTAssertFalse(coordinatorSyncSource.contains("syncingTabIds"))

        let coordinatorReloadSource = try sourceSlice(
            coordinatorSource,
            from: "func reloadTab(",
            to: "/// Set mute state"
        )
        XCTAssertTrue(coordinatorReloadSource.contains("tab.refresh()"))
        XCTAssertTrue(coordinatorReloadSource.contains("crossWindowSyncOwner.reloadTab("))
        XCTAssertTrue(coordinatorReloadSource.contains("getAllWebViews(for: tabId)"))
        XCTAssertTrue(coordinatorReloadSource.contains("isWebViewProtectedFromCompositorMutation"))
        XCTAssertTrue(coordinatorReloadSource.contains("performMainFrameNavigationAfterHydrationIfNeeded"))
    }

    func testCompositorHandoffStatePromotedHostCompletionRunsOnceAfterMatchingTake() throws {
        let handoffState = WebViewCompositorHandoffState()
        let tab = Tab(url: try XCTUnwrap(URL(string: "https://example.com")))
        let windowID = UUID()
        let webView = WKWebView()
        let host = SumiWebViewContainerView(tab: tab, webView: webView)
        var completionCount = 0

        handoffState.registerPromotedHost(
            host,
            for: tab.id,
            in: windowID,
            attachmentCompletion: {
                completionCount += 1
            }
        )

        XCTAssertNil(handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            expectedWebView: WKWebView()
        ))

        let takenHost = handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            expectedWebView: webView
        )
        XCTAssertTrue(takenHost === host)
        XCTAssertNil(handoffState.takePromotedHost(
            for: tab.id,
            in: windowID,
            expectedWebView: webView
        ))

        handoffState.completePromotedHostAttachment(for: tab.id, in: windowID)
        handoffState.completePromotedHostAttachment(for: tab.id, in: windowID)

        XCTAssertEqual(completionCount, 1)
    }

    func testVisualHandoffProtectionIsReleasedExplicitly() {
        let coordinator = WebViewCoordinator()
        let webView = WKWebView()

        coordinator.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(coordinator.isWebViewProtectedFromCompositorMutation(webView))

        coordinator.finishVisualHandoffProtection(for: webView)
        XCTAssertFalse(coordinator.isWebViewProtectedFromCompositorMutation(webView))
    }

    func testWebsiteDisplayStateActiveSplitGroupRequiresCurrentTabMembership() throws {
        let current = UUID()
        let secondary = UUID()
        let outside = UUID()
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [current, secondary],
            layoutKind: .vertical
        ))

        let activeState = WebsiteDisplayState(
            splitGroup: group,
            currentId: current,
            compositorVersion: 1,
            currentTabUnloaded: false,
            visibleTabIds: [current, secondary],
            isSplitDropCaptureActive: false
        )
        XCTAssertEqual(activeState.activeSplitGroup?.id, group.id)

        let outsideState = WebsiteDisplayState(
            splitGroup: group,
            currentId: outside,
            compositorVersion: 1,
            currentTabUnloaded: false,
            visibleTabIds: [outside],
            isSplitDropCaptureActive: false
        )
        XCTAssertNil(outsideState.activeSplitGroup)

        let nilCurrentState = WebsiteDisplayState(
            splitGroup: group,
            currentId: nil,
            compositorVersion: 1,
            currentTabUnloaded: true,
            visibleTabIds: [],
            isSplitDropCaptureActive: false
        )
        XCTAssertNil(nilCurrentState.activeSplitGroup)
    }

    func testWindowWebContentUsesBrowserContextBoundary() throws {
        let browserContext = CompositorBrowserContextStub()
        let windowState = BrowserWindowState()
        let webViewCoordinator = WebViewCoordinator()

        let wrapper = TabCompositorWrapper(
            browserContext: browserContext,
            webViewCoordinator: webViewCoordinator,
            hoveredLink: .constant(nil),
            splitGroup: nil,
            isSplitDropCaptureActive: false,
            chromeGeometry: BrowserChromeGeometry(),
            windowState: windowState,
            contentBackgroundColor: .white
        )

        XCTAssertFalse(wrapper.isSplitDropCaptureActive)
    }

    func testCloneWebViewPrimaryWindowSelectionDoesNotDependOnDictionaryOrder() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let ownerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCreationPlanningOwner.swift"
            ),
            encoding: .utf8
        )
        let creationSlice = try sourceSlice(
            coordinatorSource,
            from: "func getOrCreateWebView",
            to: "/// Creates the \"primary\" WebView"
        )

        XCTAssertTrue(creationSlice.contains("webViewCreationPlanningOwner.creationPlan("))
        XCTAssertTrue(creationSlice.contains(".deferForInitialDocumentWarmup"))
        XCTAssertTrue(creationSlice.contains("webViewCreationPlanningOwner.startInitialDocumentWarmupIfNeeded"))
        XCTAssertFalse(creationSlice.contains("InitialDocumentWarmupGate"))
        XCTAssertFalse(creationSlice.contains("primaryWindowIdForClone"))
        XCTAssertFalse(creationSlice.contains("otherWindows.first"))
        XCTAssertFalse(creationSlice.contains("first!.key"))

        let policySlice = try sourceSlice(
            ownerSource,
            from: "static func primaryWindowIdForClone",
            to: "private func adoptableExistingPrimaryWebView"
        )

        XCTAssertTrue(policySlice.contains("preferredPrimaryWindowId"))
        XCTAssertTrue(policySlice.contains("candidates.contains(preferredPrimaryWindowId)"))
        XCTAssertTrue(policySlice.contains("candidates.min"))
        XCTAssertTrue(policySlice.contains("uuidString <"))

        let warmupGateSlice = try sourceSlice(
            ownerSource,
            from: "private struct InitialDocumentWarmupGate",
            to: "enum NormalTabWebViewCreationPlan"
        )
        XCTAssertTrue(warmupGateSlice.contains("private var inFlightProfileIds"))
        XCTAssertTrue(warmupGateSlice.contains("private var attemptedProfileIds"))
        XCTAssertTrue(warmupGateSlice.contains("needsInitialDocumentExtensionContextLoadIfNeeded"))
        XCTAssertTrue(ownerSource.contains("case waitForInFlight"))

        let preferred = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let stableFallback = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let laterFallback = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        XCTAssertEqual(
            WebViewCreationPlanningOwner.primaryWindowIdForClone(
                preferredPrimaryWindowId: preferred,
                otherWindowIds: [stableFallback, preferred]
            ),
            preferred
        )
        XCTAssertEqual(
            WebViewCreationPlanningOwner.primaryWindowIdForClone(
                preferredPrimaryWindowId: nil,
                otherWindowIds: [laterFallback, stableFallback]
            ),
            stableFallback
        )
    }

    func testTabNormalWebViewPolicyRebuildsUseSharedReplacementFlow() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let tabSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Models/Tab/Tab.swift"
            ),
            encoding: .utf8
        )

        let contentBlockingRebuild = try sourceSlice(
            tabSource,
            from: "func rebuildNormalWebViewForContentBlockingPolicyIfNeeded",
            to: "@discardableResult\n    func rebuildNormalWebViewForAutoplayIfNeeded"
        )
        let autoplayRebuild = try sourceSlice(
            tabSource,
            from: "func rebuildNormalWebViewForAutoplayIfNeeded",
            to: "@discardableResult\n    private func rebuildNormalWebViewForConfigurationPolicy"
        )
        let sharedRebuild = try sourceSlice(
            tabSource,
            from: "private func rebuildNormalWebViewForConfigurationPolicy",
            to: "private func notifyContentBlockingReloadRequirementChangedIfNeeded"
        )
        let reloadPolicyStateOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Models/Tab/TabReloadPolicyStateOwner.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(contentBlockingRebuild.contains("rebuildNormalWebViewForConfigurationPolicy("))
        XCTAssertTrue(autoplayRebuild.contains("rebuildNormalWebViewForConfigurationPolicy(reason: reason)"))
        XCTAssertTrue(contentBlockingRebuild.contains("noteProtectionWebViewRebuildFailed"))
        XCTAssertTrue(contentBlockingRebuild.contains("updateSafariContentBlockerReloadRequirementForCurrentSite()"))
        XCTAssertTrue(contentBlockingRebuild.contains("updateProtectionReloadRequirementForCurrentSite()"))
        XCTAssertTrue(contentBlockingRebuild.contains("noteProtectionWebViewRebuildSucceeded"))
        XCTAssertTrue(contentBlockingRebuild.contains("updateAutoplayReloadRequirementForCurrentSite()"))
        XCTAssertTrue(autoplayRebuild.contains("updateAutoplayReloadRequirementForCurrentSite()"))
        XCTAssertFalse(autoplayRebuild.contains("updateProtectionReloadRequirementForCurrentSite()"))
        XCTAssertFalse(tabSource.contains("evaluateAutoplayPolicyChange"))
        XCTAssertTrue(reloadPolicyStateOwnerSource.contains("evaluateAutoplayPolicyChange"))
        XCTAssertTrue(reloadPolicyStateOwnerSource.contains("autoplayPolicyRequiresNormalWebViewRebuild"))

        XCTAssertFalse(contentBlockingRebuild.contains("coordinator?.removeAllWebViews"))
        XCTAssertFalse(autoplayRebuild.contains("coordinator?.removeAllWebViews"))

        try assertTokenOrder(
            sharedRebuild,
            [
                "guard let previousWebView = existingWebView",
                "let coordinator = browserManager?.webViewCoordinator",
                "let previousWindowId = primaryWindowId ?? coordinator?.windowID(containing: previousWebView)",
                "let hadTrackedWebViews = coordinator?.windowIDs(for: id).isEmpty == false",
                "guard let replacementWebView = makeNormalTabWebView(reason: reason)",
                "invalidateCurrentPermissionPageForWebViewReplacement(reason: reason)",
                "let removedTrackedWebViews = coordinator?.removeAllWebViews(for: self) ?? false",
                "if hadTrackedWebViews && !removedTrackedWebViews",
                "onTrackedWebViewRemovalFailure()",
                "cleanupCloneWebView(previousWebView)",
                "_webView = nil",
                "primaryWindowId = nil",
                "coordinator?.setWebView(replacementWebView, for: id, in: previousWindowId)",
                "assignWebViewToWindow(replacementWebView, windowId: previousWindowId)",
                "browserManager?.refreshCompositor(for: windowState)",
                "_webView = replacementWebView"
            ]
        )
    }

    func testClosingAndSpaceSwitchPathsPerformVisualHandoffBeforeRuntimeCleanup() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let browserManagerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/BrowserManager/BrowserManager.swift"
            ),
            encoding: .utf8
        )
        let browserWindowSpaceStateOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/BrowserManager/BrowserWindowSpaceStateOwner.swift"
            ),
            encoding: .utf8
        )
        let tabCloseOrchestrationOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/BrowserManager/BrowserTabCloseOrchestrationOwner.swift"
            ),
            encoding: .utf8
        )
        let splitShortcutsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/BrowserManager/BrowserManager+SplitShortcuts.swift"
            ),
            encoding: .utf8
        )
        let shortcutLiveTabCloseSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/BrowserManager/BrowserShortcutLiveTabCloseOwner.swift"
            ),
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        let coverSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WindowWebContentVisualHandoffCoverController.swift"
            ),
            encoding: .utf8
        )

        let regularClose = try sourceSlice(
            tabCloseOrchestrationOwnerSource,
            from: "private func closeRegularTab(_ tab: Tab, in windowState: BrowserWindowState)",
            to: "private func closeIncognitoTab"
        )
        XCTAssertLessThan(
            try XCTUnwrap(regularClose.range(of: "performImmediateVisualHandoffIfPossible")).lowerBound,
            try XCTUnwrap(regularClose.range(of: "tabManager.removeTab(tab.id)")).lowerBound
        )

        let shortcutClose = try sourceSlice(
            shortcutLiveTabCloseSource,
            from: "func close(_ tab: Tab, in windowState: BrowserWindowState)",
            to: "private func captureClosedShortcutLiveInstance"
        )
        XCTAssertLessThan(
            try XCTUnwrap(shortcutClose.range(of: "performImmediateVisualHandoffIfPossible")).lowerBound,
            try XCTUnwrap(shortcutClose.range(of: "tabManager.deactivateShortcutLiveTab")).lowerBound
        )

        let spaceSwitch = try sourceSlice(
            browserWindowSpaceStateOwnerSource,
            from: "func setActiveSpace(_ space: Space, in windowState: BrowserWindowState)",
            to: "func selectionTargetForSpaceActivation"
        )
        try assertTokenOrder(
            spaceSwitch,
            [
                "dependencies.applyTabSelection",
                "dependencies.performImmediateVisualHandoffIfPossible(windowState)",
                "dependencies.adoptProfileForSpaceChange(windowState)"
            ]
        )
        let spaceStateOwnerWiring = try sourceSlice(
            browserManagerSource,
            from: "private lazy var windowSpaceStateOwner = BrowserWindowSpaceStateOwner",
            to: "lazy var tabCloseFallbackPlanner"
        )
        XCTAssertTrue(spaceStateOwnerWiring.contains("_ = self.performImmediateVisualHandoffIfPossible(in: windowState)"))

        let splitUnload = try sourceSlice(
            splitShortcutsSource,
            from: "func unloadShortcutHostedSplitGroup",
            to: "@discardableResult"
        )
        XCTAssertLessThan(
            try XCTUnwrap(splitUnload.range(of: "performImmediateVisualHandoffIfPossible")).lowerBound,
            try XCTUnwrap(splitUnload.range(of: "tabManager.deactivateShortcutLiveTab")).lowerBound
        )

        let splitMemberRestore = try sourceSlice(
            splitShortcutsSource,
            from: "func restoreShortcutSplitMember",
            to: "func unloadShortcutHostedSplitGroup"
        )
        XCTAssertLessThan(
            try XCTUnwrap(splitMemberRestore.range(of: "performImmediateVisualHandoffIfPossible")).lowerBound,
            try XCTUnwrap(splitMemberRestore.range(of: "tabManager.deactivateShortcutLiveTab")).lowerBound
        )

        XCTAssertTrue(compositorSource.contains("setImmediateVisualHandoffHandler"))
        XCTAssertTrue(compositorSource.contains("private func performImmediateVisualHandoffIfPossible()"))
        XCTAssertTrue(compositorSource.contains("private final class WindowWebContentVisualHandoffFlowOwner"))
        XCTAssertTrue(compositorSource.contains("placeVisualHandoffCover"))
        XCTAssertTrue(compositorSource.contains("scheduleVisualHandoffCoverRelease"))
        XCTAssertFalse(compositorSource.contains("final class WindowWebContentVisualHandoffCoverController"))
        XCTAssertTrue(coverSource.contains("final class WindowWebContentVisualHandoffCoverController"))

        let compositorApply = try sourceSlice(
            compositorSource,
            from: "private func apply(displayState: WebsiteDisplayState, currentTab: Tab?)",
            to: "private func performImmediateVisualHandoffIfPossible()"
        )
        XCTAssertTrue(compositorApply.contains("visualHandoffFlow.presentationDecision"))
        XCTAssertTrue(compositorApply.contains("beginVisualHandoffCovers(for: decision)"))
        XCTAssertTrue(compositorApply.contains("scheduleSplitRepair(groupId: repairSplitGroupId)"))
        try assertTokenOrder(
            compositorApply,
            [
                "let didBeginVisualHandoff = beginVisualHandoffCovers(for: decision)",
                "scheduleSplitRepair(groupId: repairSplitGroupId)",
                "showSinglePane(tab: tab)",
                "scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)"
            ]
        )
        try assertTokenOrder(
            compositorApply,
            [
                "showSplitGroup(group, tabs: tabs)",
                "scheduleVisualHandoffCoverRelease(if: didBeginVisualHandoff)"
            ]
        )

        let visualHandoffFlow = try sourceSlice(
            compositorSource,
            from: "private final class WindowWebContentVisualHandoffFlowOwner",
            to: "@MainActor\nfinal class WindowWebContentController"
        )
        XCTAssertTrue(
            visualHandoffFlow.contains("runtime.displayedHost(tab.id) == nil")
        )
        XCTAssertTrue(
            visualHandoffFlow.contains("hostedWebViewCount(in: singlePaneRoot")
        )

        let coverRelease = try sourceSlice(
            coverSource,
            from: "func scheduleRelease()",
            to: "func releaseCovers()"
        )
        XCTAssertTrue(coverRelease.contains("CATransaction.flush()"))
        XCTAssertTrue(coverRelease.contains("containerView.displayIfNeeded()"))
        XCTAssertTrue(coverRelease.contains("releaseGeneration == generation"))

        let splitLayout = try sourceSlice(
            compositorSource,
            from: "private func showSplitGroup(_ group: SplitGroup, tabs: [Tab])",
            to: "private func restoreFocusIfNeeded"
        )
        XCTAssertLessThan(
            try XCTUnwrap(splitLayout.range(of: "for tab in tabs")).lowerBound,
            try XCTUnwrap(splitLayout.range(of: "clearSinglePane()")).lowerBound
        )

        let webViewHost = try sourceSlice(
            compositorSource,
            from: "private func webViewHost(for tab: Tab, slot: WindowWebContentPaneSlot)",
            to: "private func scheduleSplitRepair(groupId: UUID)"
        )
        XCTAssertTrue(webViewHost.contains("if let displayedHost = hostLifecycleOwner.displayedHost(for: tab.id)"))
    }

    func testWebsiteCompositorVisualHandoffOwnerKeepsPresentationOrderingExplicit() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        let registrySource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WindowWebContentHostRegistry.swift"
            ),
            encoding: .utf8
        )
        let coverSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WindowWebContentVisualHandoffCoverController.swift"
            ),
            encoding: .utf8
        )
        let splitHostLayoutSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WindowWebContentSplitHostLayoutView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private lazy var hostLifecycleOwner = WindowWebContentHostLifecycleOwner("))
        XCTAssertTrue(source.contains("private final class WindowWebContentHostLifecycleOwner"))
        XCTAssertTrue(source.contains("private lazy var visualHandoffFlow = WindowWebContentVisualHandoffFlowOwner("))
        XCTAssertTrue(source.contains("private final class WindowWebContentVisualHandoffFlowOwner"))
        XCTAssertTrue(source.contains("WindowWebContentVisualHandoffCoverController("))
        XCTAssertTrue(source.contains("WindowWebContentSplitHostLayoutView("))
        XCTAssertTrue(splitHostLayoutSource.contains("final class WindowWebContentSplitHostLayoutView: NSView, WindowWebContentVisualHandoffCoverContainer"))
        XCTAssertTrue(registrySource.contains("enum WindowWebContentPaneSlot"))
        XCTAssertTrue(registrySource.contains("final class WindowWebContentHostRegistry"))
        XCTAssertTrue(registrySource.contains("func protectedHost(for webView: WKWebView)"))
        XCTAssertFalse(registrySource.contains("DispatchWorkItem"))
        XCTAssertFalse(registrySource.contains("CATransaction"))
        XCTAssertFalse(registrySource.contains("placeVisualHandoffCover"))
        XCTAssertTrue(coverSource.contains("protocol WindowWebContentVisualHandoffCoverContainer"))
        XCTAssertTrue(coverSource.contains("final class WindowWebContentVisualHandoffCoverController"))

        let releaseCallback = try sourceSlice(
            source,
            from: "private lazy var visualHandoffCovers",
            to: "private lazy var mediaTouchBarRecoveryController"
        )
        try assertTokenOrder(
            releaseCallback,
            [
                "containerView.removeVisualHandoffCover(host)",
                "hostLifecycleOwner.removeParkedProtectedHost(for: webViewID)",
                "webViewCoordinator.finishVisualHandoffProtection(for: host.webView)"
            ]
        )

        let visualHandoff = try sourceSlice(
            source,
            from: "private func beginVisualHandoffCovers",
            to: "private func scheduleVisualHandoffCoverRelease(if didBeginVisualHandoff: Bool)"
        )
        try assertTokenOrder(
            visualHandoff,
            [
                "webViewCoordinator.beginVisualHandoffProtection(for: host.webView)",
                "hostLifecycleOwner.prepareForVisualHandoff(host)",
                "visualHandoffCovers.placeCover(host"
            ]
        )
        let hostOwner = try sourceSlice(
            source,
            from: "private final class WindowWebContentHostLifecycleOwner",
            to: "struct TabCompositorWrapper"
        )
        try assertTokenOrder(
            hostOwner,
            [
                "func prepareForVisualHandoff(_ host: SumiWebViewContainerView)",
                "hostRegistry.clearReferences(to: host)",
                "hostRegistry.parkProtectedHost(host)"
            ]
        )

        let coverController = try sourceSlice(
            coverSource,
            from: "final class WindowWebContentVisualHandoffCoverController",
            to: "func releaseCovers()"
        )
        XCTAssertTrue(coverController.contains("private var coverHosts: [ObjectIdentifier: SumiWebViewContainerView] = [:]"))
        XCTAssertTrue(coverController.contains("private var releaseWorkItem: DispatchWorkItem?"))
        XCTAssertTrue(coverController.contains("private var releaseGeneration = 0"))
        try assertTokenOrder(
            coverController,
            [
                "containerView.placeVisualHandoffCover(host",
                "coverHosts[ObjectIdentifier(host.webView)] = host"
            ]
        )
        try assertTokenOrder(
            coverController,
            [
                "CATransaction.flush()",
                "containerView.layoutSubtreeIfNeeded()",
                "containerView.displayIfNeeded()",
                "self.releaseCovers()"
            ]
        )
        try assertTokenOrder(
            coverSource[coverSource.startIndex..<coverSource.endIndex],
            [
                "let covers = coverHosts",
                "coverHosts.removeAll(keepingCapacity: true)",
                "releaseCover(webViewID, host)"
            ]
        )

        let attach = try sourceSlice(
            String(hostOwner),
            from: "func attach(_ host: SumiWebViewContainerView",
            to: "func clearPaneHost(_ slot: WindowWebContentPaneSlot)"
        )
        try assertTokenOrder(
            attach,
            [
                "hostRegistry.removeParkedProtectedHost(for: host.webView)",
                "host.attachDisplayedContentIfNeeded()",
                "if isProtected",
                "hostRegistry.parkProtectedHost(host)",
                "webViewCoordinator.completePromotedHostAttachment"
            ]
        )
    }

    func testTabWebViewCleanupOwnerPreservesShutdownOrdering() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Models/Tab/TabWebViewCleanupOwner.swift"
            ),
            encoding: .utf8
        )

        let shutdown = try sourceSlice(
            source,
            from: "static func perform(\n        on webView: WKWebView,\n        scope: Scope,",
            to: "@MainActor\n    static func perform(\n        on webView: WKWebView,\n        tabId: UUID,"
        )
        try assertTokenOrder(
            shutdown,
            [
                "webView.stopLoading()",
                "stopNativeMedia(on: webView)",
                "cleanupWebViewIfLoaded(",
                "controller.cleanUpBeforeClosing()",
                "prepareForReleaseIfNeeded(webView, scope: scope)",
                "additionalTabCleanup?()",
                "webView.navigationDelegate = nil",
                "webView.uiDelegate = nil",
                "webView.removeFromSuperview()",
                "removeWebViewFromContainers(webView)"
            ]
        )

        let cleanup = try sourceSlice(
            source,
            from: "static func cleanupWebView(_ webView: WKWebView, context: Context)",
            to: "@MainActor\n    static func performComprehensiveCleanup(context: Context)"
        )
        try assertTokenOrder(
            cleanup,
            [
                ".webViewDeallocated(",
                "deferProtectedWebViewCleanup(",
                "SumiWebViewShutdown.perform(",
                "context.unbindAudioState(webView)",
                "context.removeNavigationStateObservers(webView)",
                "context.removeNavigationDelegateBundle(webView)"
            ]
        )

        let unload = try sourceSlice(
            source,
            from: "static func unloadWebView(context: Context)",
            to: "@MainActor\n    private static func notifyNowPlayingTabUnloaded"
        )
        try assertTokenOrder(
            unload,
            [
                "context.invalidateCurrentPermissionPageForWebViewReplacement",
                "context.removeAllWebViews(true)",
                "cleanupWebView(webView, context: context)",
                "context.clearCurrentWebView()",
                "context.resetPlaybackActivity()",
                "context.setLoadingIdle()",
                "notifyNowPlayingTabUnloaded(tabId: context.tabId)"
            ]
        )
    }

    func testWebViewCoordinatorCleanupKeepsProtectedDeferralAndRefreshPolicySeparate() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let cleanupOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewTrackedCleanupExecutionOwner.swift"
            ),
            encoding: .utf8
        )
        let cleanupScopeOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCleanupScopeOwner.swift"
            ),
            encoding: .utf8
        )
        let hiddenCloneEvictionOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewHiddenCloneEvictionOwner.swift"
            ),
            encoding: .utf8
        )

        let delegatedCallSites = [
            (
                "func cleanupWindow(_ windowId: UUID, tabManager: TabManager)",
                "func cleanupAllWebViews(tabManager: TabManager)",
                ["cleanupScopeOwner.cleanupWindow("]
            ),
            (
                "func cleanupAllWebViews(tabManager: TabManager)",
                "// MARK: - History Swipe Protection",
                ["cleanupScopeOwner.cleanupAllWebViews("]
            ),
            (
                "private func evictHiddenWebViewsIfNeeded(",
                "private func notifyTabActivatedIfCurrent",
                ["hiddenCloneEvictionOwner.evictHiddenWebViews("]
            ),
        ]

        for (start, end, delegationTokens) in delegatedCallSites {
            let callSite = try sourceSlice(source, from: start, to: end)
            try assertTokenOrder(callSite, delegationTokens)
        }

        let inlineCallSites = [
            (
                "func removeAllWebViews(\n        for tab: Tab,",
                "@discardableResult\n    func suspendWebViews",
                ["enqueueDeferredProtectedCommand(", "return false"]
            ),
        ]

        for (start, end, protectedDeferralTokens) in inlineCallSites {
            let callSite = try sourceSlice(source, from: start, to: end)
            try assertTokenOrder(
                callSite,
                protectedDeferralTokens
                    + ["cleanupUnprotectedTrackedWebView(", "refreshPrimaryTrackedWebView"]
            )
        }

        let cleanupScopeSource = try sourceSlice(
            cleanupScopeOwnerSource,
            from: "private func cleanup(",
            to: "\n    }\n}"
        )
        try assertTokenOrder(
            cleanupScopeSource,
            [
                "runtime.isWebViewProtectedFromCompositorMutation(webView)",
                "runtime.enqueueDeferredProtectedCommand(",
                "continue",
                "runtime.cleanupUnprotectedTrackedWebView(",
                "runtime.refreshPrimaryTrackedWebView("
            ]
        )
        XCTAssertFalse(cleanupScopeSource.contains("WebViewMediaProtectionOwner"))
        XCTAssertFalse(cleanupScopeSource.contains("WindowWebViewRegistry"))
        XCTAssertFalse(cleanupScopeSource.contains("WebViewTrackedCleanupExecutionOwner"))

        XCTAssertTrue(hiddenCloneEvictionOwnerSource.contains("final class WebViewHiddenCloneEvictionOwner"))
        XCTAssertTrue(hiddenCloneEvictionOwnerSource.contains("typealias LiveWebViews"))
        XCTAssertTrue(hiddenCloneEvictionOwnerSource.contains("typealias ProtectedCommandEnqueuer"))

        let hiddenCloneEvictionSource = try sourceSlice(
            hiddenCloneEvictionOwnerSource,
            from: "func evictHiddenWebViews(",
            to: "\n    }\n}"
        )
        try assertTokenOrder(
            hiddenCloneEvictionSource,
            [
                "let hiddenEntries = entries.filter",
                "visibleTabIDs.contains(owner.tabID) == false",
                "guard hiddenEntries.isEmpty == false else { return }",
                "browserManager.tabSuspensionService",
                "for (owner, webView) in hiddenEntries.sorted",
                "guard globallyVisibleTabIDs.contains(owner.tabID) else { continue }",
                "guard let tab = runtime.tabForID(owner.tabID) else { continue }",
                "guard runtime.liveWebViews(tab).count > 1 else { continue }",
                "runtime.isWebViewProtectedFromCompositorMutation(webView)",
                "runtime.enqueueDeferredProtectedCommand(",
                "continue",
                "runtime.cleanupUnprotectedTrackedWebView(",
                "runtime.refreshPrimaryTrackedWebView("
            ]
        )
        XCTAssertFalse(hiddenCloneEvictionOwnerSource.contains("WebViewMediaProtectionOwner"))
        XCTAssertFalse(hiddenCloneEvictionOwnerSource.contains("WindowWebViewRegistry"))
        XCTAssertFalse(hiddenCloneEvictionOwnerSource.contains("WebViewTrackedCleanupExecutionOwner"))
        XCTAssertFalse(hiddenCloneEvictionOwnerSource.contains("WebViewCleanupScopeOwner"))

        let deferredWrapper = try sourceSlice(
            source,
            from: "private func cleanupTrackedWebView(\n        _ webView: WKWebView,\n        owner: TrackedWebViewOwner\n    )",
            to: "private func cleanupUnprotectedTrackedWebView"
        )
        try assertTokenOrder(
            deferredWrapper,
            [
                "cleanupUnprotectedTrackedWebView(",
                "refreshPrimaryTrackedWebView"
            ]
        )
        XCTAssertFalse(deferredWrapper.contains("finishDestructiveDataCleanupNavigation"))

        let unprotectedHelper = try sourceSlice(
            source,
            from: "private func cleanupUnprotectedTrackedWebView(",
            to: "@discardableResult\n    private func closeTrackedWebViewFromWebKit"
        )
        try assertTokenOrder(
            unprotectedHelper,
            [
                "trackedCleanupExecutionOwner.cleanupUnprotectedTrackedWebView(",
                "runtime: trackedCleanupExecutionRuntime()"
            ]
        )
        XCTAssertFalse(unprotectedHelper.contains("refreshPrimaryTrackedWebView"))

        try assertTokenOrder(
            cleanupOwnerSource[...],
            [
                "runtime.finishDestructiveCleanupSuppression(webView)",
                "runtime.removeFromContainers(webView)",
                "trackingLifecycleOwner.unregisterTrackedWebViewSlot(",
                "tab.cleanupCloneWebView(webView)"
            ]
        )
        try assertTokenOrder(
            cleanupOwnerSource[...],
            [
                "trackingLifecycleOwner.unregisterTrackedWebViewSlot(",
                "runtime.fallbackCleanup(webView, owner.tabID, browserManager)"
            ]
        )
        XCTAssertFalse(cleanupOwnerSource.contains("refreshPrimaryTrackedWebView"))
    }

    func testDeferredProtectedCommandBufferCollapsesDuplicateKeysInPlace() {
        var buffer = DeferredProtectedCommandBuffer()
        let tabID = UUID()
        let firstPreferredWindowID = UUID()
        let latestPreferredWindowID = UUID()

        XCTAssertEnqueueOutcome(
            buffer.enqueue(.rebuildLiveWebViews(
                tabID: tabID,
                preferredPrimaryWindowID: firstPreferredWindowID
            )),
            is: .enqueued
        )
        XCTAssertEnqueueOutcome(buffer.enqueue(.cleanupAllWebViews), is: .enqueued)
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.rebuildLiveWebViews(
                tabID: tabID,
                preferredPrimaryWindowID: latestPreferredWindowID
            )),
            is: .collapsed
        )
        XCTAssertEqual(buffer.count, 2)

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, 2)
        guard case let .rebuildLiveWebViews(drainedTabID, drainedPreferredWindowID) = drained[0],
              case .cleanupAllWebViews = drained[1]
        else {
            return XCTFail("Expected duplicate command replacement to keep original FIFO slot")
        }
        XCTAssertEqual(drainedTabID, tabID)
        XCTAssertEqual(drainedPreferredWindowID, latestPreferredWindowID)
    }

    func testDeferredProtectedCommandBufferDropsAtCapacityWithoutMutatingExistingCommands() {
        var buffer = DeferredProtectedCommandBuffer()
        let commandIDs = (0..<DeferredProtectedCommandBuffer.maxCommands).map { _ in UUID() }

        for commandID in commandIDs {
            XCTAssertEnqueueOutcome(
                buffer.enqueue(.removeAllWebViews(tabID: commandID)),
                is: .enqueued
            )
        }
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.maxCommands)

        let droppedTabID = UUID()
        XCTAssertEnqueueOutcome(
            buffer.enqueue(.removeAllWebViews(tabID: droppedTabID)),
            is: .droppedAtCapacity
        )
        XCTAssertEqual(buffer.count, DeferredProtectedCommandBuffer.maxCommands)

        let drained = buffer.drain()
        XCTAssertEqual(drained.count, DeferredProtectedCommandBuffer.maxCommands)
        for (command, expectedTabID) in zip(drained, commandIDs) {
            guard case let .removeAllWebViews(drainedTabID) = command else {
                return XCTFail("Expected capacity drop to leave queued commands unchanged")
            }
            XCTAssertEqual(drainedTabID, expectedTabID)
        }
    }

    func testDeferredProtectedCommandBufferPruneReturnsDroppedCommandsAndKeepsSurvivorsInOrder() {
        var buffer = DeferredProtectedCommandBuffer()
        let firstTabID = UUID()
        let droppedWindowID = UUID()
        let lastTabID = UUID()

        XCTAssertEnqueueOutcome(buffer.enqueue(.removeAllWebViews(tabID: firstTabID)), is: .enqueued)
        XCTAssertEnqueueOutcome(buffer.enqueue(.cleanupWindow(windowID: droppedWindowID)), is: .enqueued)
        XCTAssertEnqueueOutcome(buffer.enqueue(.rebuildLiveWebViews(
            tabID: lastTabID,
            preferredPrimaryWindowID: nil
        )), is: .enqueued)

        let droppedCommands = buffer.prune { command in
            if case .cleanupWindow = command { return true }
            return false
        }

        XCTAssertEqual(droppedCommands.count, 1)
        guard case let .cleanupWindow(drainedDroppedWindowID) = droppedCommands[0] else {
            return XCTFail("Expected prune to return the dropped command")
        }
        XCTAssertEqual(drainedDroppedWindowID, droppedWindowID)

        let survivors = buffer.drain()
        XCTAssertEqual(survivors.count, 2)
        guard case let .removeAllWebViews(drainedFirstTabID) = survivors[0],
              case let .rebuildLiveWebViews(drainedLastTabID, drainedPreferredWindowID) = survivors[1]
        else {
            return XCTFail("Expected prune to keep survivors in FIFO order")
        }
        XCTAssertEqual(drainedFirstTabID, firstTabID)
        XCTAssertEqual(drainedLastTabID, lastTabID)
        XCTAssertNil(drainedPreferredWindowID)
    }

    func testWebViewCoordinatorDeferredProtectedCommandsStayBehindProtectedCommandOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let ownerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewProtectedCommandOwner.swift"
            ),
            encoding: .utf8
        )
        let mediaOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewMediaProtectionOwner.swift"
            ),
            encoding: .utf8
        )
        let executionOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewDeferredProtectedCommandExecutionOwner.swift"
            ),
            encoding: .utf8
        )
        let commandSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/DeferredWebViewCommand.swift"
            ),
            encoding: .utf8
        )

        let storeSource = try sourceSlice(
            ownerSource,
            from: "private struct DeferredProtectedWebViewCommandStore",
            to: "@MainActor\nfinal class WebViewProtectedCommandOwner"
        )
        XCTAssertTrue(storeSource.contains("private var buffersBySourceWebViewID"))
        XCTAssertTrue(commandSource.contains("struct DeferredProtectedCommandBuffer"))
        XCTAssertTrue(commandSource.contains("enum DeferredWebViewCommand"))
        XCTAssertFalse(storeSource.contains("activeHistorySwipeProtections"))
        XCTAssertFalse(storeSource.contains("visualHandoffProtectedWebViewIDs"))
        XCTAssertFalse(storeSource.contains("fullscreenProtection"))
        XCTAssertFalse(storeSource.contains("weakWebViewsByIdentifier"))
        XCTAssertFalse(storeSource.contains("resolveWebView"))
        XCTAssertFalse(storeSource.contains("executeDeferredProtectedCommand"))
        XCTAssertFalse(storeSource.contains("dropDeferredProtectedCommand"))

        let coordinatorStart = try XCTUnwrap(
            coordinatorSource.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorClassSource = String(coordinatorSource[coordinatorStart...])
        XCTAssertTrue(coordinatorClassSource.contains("private let mediaProtectionOwner = WebViewMediaProtectionOwner()"))
        XCTAssertTrue(coordinatorClassSource.contains("private let deferredProtectedCommandExecutionOwner = WebViewDeferredProtectedCommandExecutionOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private let protectedCommandOwner = WebViewProtectedCommandOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private var activeHistorySwipeProtections"))
        XCTAssertFalse(coordinatorClassSource.contains("private var visualHandoffProtectedWebViewIDs"))
        XCTAssertFalse(coordinatorClassSource.contains("private let fullscreenProtection"))
        XCTAssertFalse(coordinatorClassSource.contains("private var deferredProtectedWebViewCommands"))
        XCTAssertFalse(coordinatorClassSource.contains("private func isDeferredProtectedCommandValid"))
        XCTAssertFalse(coordinatorClassSource.contains("private func executeDeferredProtectedCommand"))
        XCTAssertFalse(coordinatorClassSource.contains("private func dropDeferredProtectedCommand"))
        XCTAssertFalse(coordinatorClassSource.contains("struct DeferredProtectedCommandBuffer"))
        XCTAssertTrue(mediaOwnerSource.contains("private let protectedCommandOwner = WebViewProtectedCommandOwner()"))
        XCTAssertTrue(executionOwnerSource.contains("struct WebViewDeferredProtectedCommandExecutionOwner"))

        let enqueueSource = try sourceSlice(
            coordinatorSource,
            from: "private func enqueueDeferredProtectedCommand",
            to: "private func installMediaProtectionObservationsIfNeeded"
        )
        try assertTokenOrder(
            enqueueSource,
            [
                "deferredProtectedCommandExecutionOwner.enqueue(",
                "mediaProtectionOwner: mediaProtectionOwner",
                "runtime: deferredProtectedCommandRuntime()"
            ]
        )

        let mediaOwnerEnqueueSource = try sourceSlice(
            mediaOwnerSource,
            from: "func enqueueDeferredCommandIfNeeded(",
            to: "func commandsToFlushIfUnprotected"
        )
        try assertTokenOrder(
            mediaOwnerEnqueueSource,
            [
                "protectedCommandOwner.enqueueDeferredCommandIfNeeded(",
                "resolveWebView:",
                "isCommandValid:",
                "dropCommand:",
                "didPruneStaleWebViewIDs:"
            ]
        )

        let ownerEnqueueSource = try sourceSlice(
            ownerSource,
            from: "func enqueueDeferredCommandIfNeeded(",
            to: "func commandsToFlushIfUnprotected"
        )
        try assertTokenOrder(
            ownerEnqueueSource,
            [
                "note(webView)",
                "guard isProtected(sourceWebViewID)",
                "didPruneStaleWebViewIDs(",
                "pruneInvalidDeferredCommands(",
                "guard isCommandValid(command)",
                "deferredProtectedWebViewCommands.enqueue(",
                "switch enqueueResult.outcome"
            ]
        )

        let flushSource = try sourceSlice(
            coordinatorSource,
            from: "private func flushDeferredProtectedCommands",
            to: "// MARK: - Smart WebView Assignment"
        )
        try assertTokenOrder(
            flushSource,
            [
                "deferredProtectedCommandExecutionOwner.flushCommandsIfUnprotected(",
                "mediaProtectionOwner: mediaProtectionOwner",
                "runtime: deferredProtectedCommandRuntime()"
            ]
        )

        let coordinatorRuntimeSource = try sourceSlice(
            coordinatorSource,
            from: "private func deferredProtectedCommandRuntime",
            to: "private func finishDestructiveCleanupSuppression"
        )
        try assertTokenOrder(
            coordinatorRuntimeSource,
            [
                "resolveWebView(with: webViewID)",
                "resolvedTab(with: tabID)",
                "browserManager?.tabManager != nil",
                "webViewRegistry.trackedWebViews(in: windowID)",
                "compositorContainerView(for: windowID)",
                "webViewRegistry.isEmpty == false",
                "browserManager?.windowRegistry?.windows[windowID] != nil",
                "performDeferredProtectedCommand(command)",
                "finishDestructiveCleanupSuppression(for: webViewIDs)"
            ]
        )

        let executionOwnerFlushSource = try sourceSlice(
            executionOwnerSource,
            from: "func flushCommandsIfUnprotected",
            to: "func pruneInvalidCommands"
        )
        try assertTokenOrder(
            executionOwnerFlushSource,
            [
                "mediaProtectionOwner.commandsToFlushIfUnprotected(",
                "didPruneStaleWebViewIDs: runtime.finishCleanupSuppression",
                "Task { @MainActor",
                "\"WebViewCoordinator.flushDeferredProtectedCommands\"",
                "execute(",
                "reason: \"flush.invalidTarget\""
            ]
        )

        let executionOwnerExecuteSource = try sourceSlice(
            executionOwnerSource,
            from: "private func execute",
            to: "private func isCommandValid"
        )
        try assertTokenOrder(
            executionOwnerExecuteSource,
            [
                "guard isCommandValid(command, context: runtime.validationContext)",
                "\"executeDeferredCommand sourceWebView=\\(sourceWebViewID) command={\\(command.debugSummary)}\"",
                "return runtime.executeCommand(command)"
            ]
        )

        let executionOwnerValidationSource = try sourceSlice(
            executionOwnerSource,
            from: "private func isCommandValid",
            to: "private func drop"
        )
        try assertTokenOrder(
            executionOwnerValidationSource,
            [
                "case .cleanupWindow(let windowID):",
                "context.hasCleanupWindowTarget(windowID)",
                "case .evictHiddenWebViews(let windowID):",
                "context.hasWindow(windowID)"
            ]
        )

        let executionOwnerDropSource = try sourceSlice(
            executionOwnerSource,
            from: "private func drop",
            to: "\n}"
        )
        try assertTokenOrder(
            executionOwnerDropSource,
            [
                "PerformanceTrace.emitEvent(\"WebViewCoordinator.dropDeferredProtectedCommand\")",
                "\"dropDeferredCommand reason=\\(reason) sourceWebView=\\(sourceWebViewID) command={\\(command.debugSummary)}\""
            ]
        )

        let ownerFlushSource = try sourceSlice(
            ownerSource,
            from: "func commandsToFlushIfUnprotected",
            to: "@discardableResult\n    func pruneInvalidDeferredCommands"
        )
        try assertTokenOrder(
            ownerFlushSource,
            [
                "guard isProtected(webViewID) == false",
                "didPruneStaleWebViewIDs(",
                "pruneInvalidDeferredCommands(",
                "deferredProtectedWebViewCommands.drainCommands(for: webViewID)"
            ]
        )
    }

    func testWebViewCoordinatorWeakWebViewBookkeepingStaysBehindProtectedCommandOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let ownerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewProtectedCommandOwner.swift"
            ),
            encoding: .utf8
        )
        let mediaOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewMediaProtectionOwner.swift"
            ),
            encoding: .utf8
        )

        let registrySource = try sourceSlice(
            ownerSource,
            from: "private struct WeakWebViewRegistry",
            to: "private struct DeferredProtectedWebViewCommandStore"
        )
        XCTAssertTrue(registrySource.contains("private var webViewsByIdentifier"))
        XCTAssertTrue(registrySource.contains("mutating func note(_ webView: WKWebView)"))
        XCTAssertTrue(registrySource.contains("mutating func resolve(with identifier: ObjectIdentifier)"))
        XCTAssertTrue(registrySource.contains("mutating func pruneStaleIdentifiers() -> [ObjectIdentifier]"))
        XCTAssertFalse(registrySource.contains("activeHistorySwipeProtections"))
        XCTAssertFalse(registrySource.contains("visualHandoffProtectedWebViewIDs"))
        XCTAssertFalse(registrySource.contains("fullscreenProtection"))
        XCTAssertFalse(registrySource.contains("deferredProtectedWebViewCommands"))
        XCTAssertFalse(registrySource.contains("DeferredProtectedWebViewCommandStore"))
        XCTAssertFalse(registrySource.contains("webViewRegistry.trackedWebView"))

        let coordinatorStart = try XCTUnwrap(
            coordinatorSource.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorClassSource = String(coordinatorSource[coordinatorStart...])
        XCTAssertTrue(coordinatorClassSource.contains("private let mediaProtectionOwner = WebViewMediaProtectionOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private let protectedCommandOwner = WebViewProtectedCommandOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("WeakWebViewRegistry"))
        XCTAssertFalse(coordinatorClassSource.contains("weakWebViewsByIdentifier"))
        XCTAssertFalse(coordinatorClassSource.contains("noteWeakWebView"))
        XCTAssertFalse(coordinatorClassSource.contains("private func resolveWeakWebView"))
        XCTAssertTrue(mediaOwnerSource.contains("private let protectedCommandOwner = WebViewProtectedCommandOwner()"))

        let resolveSource = try sourceSlice(
            coordinatorSource,
            from: "private func resolveWebView",
            to: "private func resolvedTab"
        )
        try assertTokenOrder(
            resolveSource,
            [
                "if let webView = webViewRegistry.trackedWebView(with: identifier)",
                "mediaProtectionOwner.note(webView)",
                "return webView",
                "return mediaProtectionOwner.resolveWeakWebView(with: identifier)"
            ]
        )

        let ownerPruneSource = try sourceSlice(
            ownerSource,
            from: "func pruneStaleBookkeeping",
            to: "private func isCancelledHistorySwipe"
        )
        try assertTokenOrder(
            ownerPruneSource,
            [
                "let staleIDs = weakWebViewRegistry.pruneStaleIdentifiers()",
                "activeHistorySwipeProtections.removeValue(forKey: id)",
                "visualHandoffProtectedWebViewIDs.remove(id)",
                "fullscreenProtection.remove(id)",
                "deferredProtectedWebViewCommands.removeAllCommands(for: id)"
            ]
        )
        XCTAssertFalse(ownerPruneSource.contains("webViewRegistry.trackedWebView"))

        let coordinatorPruneSource = try sourceSlice(
            coordinatorSource,
            from: "private func pruneStaleWebViewBookkeeping",
            to: "private func pruneInvalidDeferredProtectedCommands"
        )
        try assertTokenOrder(
            coordinatorPruneSource,
            [
                "finishDestructiveCleanupSuppression(",
                "mediaProtectionOwner.pruneStaleBookkeeping(reason: reason)"
            ]
        )
    }

    func testWebViewCoordinatorMediaProtectionBookkeepingStaysBehindMediaProtectionOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let mediaOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewMediaProtectionOwner.swift"
            ),
            encoding: .utf8
        )

        let coordinatorStart = try XCTUnwrap(
            coordinatorSource.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorClassSource = String(coordinatorSource[coordinatorStart...])
        XCTAssertTrue(coordinatorClassSource.contains("private let mediaProtectionOwner = WebViewMediaProtectionOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private let protectedCommandOwner = WebViewProtectedCommandOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private var nowPlayingSessionCancellablesByWebViewID"))
        XCTAssertFalse(coordinatorClassSource.contains("private func requestFullscreenMediaExit"))
        XCTAssertFalse(coordinatorClassSource.contains("private func postMediaTouchBarRecoveryRequest"))
        XCTAssertFalse(coordinatorClassSource.contains("private func beginFullscreenProtectionIfNeeded"))
        XCTAssertFalse(coordinatorClassSource.contains("private func finishFullscreenProtectionIfNeeded"))

        XCTAssertTrue(mediaOwnerSource.contains("final class WebViewMediaProtectionOwner"))
        XCTAssertTrue(mediaOwnerSource.contains("private let protectedCommandOwner = WebViewProtectedCommandOwner()"))
        XCTAssertTrue(mediaOwnerSource.contains("private var nowPlayingSessionCancellablesByWebViewID"))
        XCTAssertTrue(mediaOwnerSource.contains("private func requestFullscreenMediaExit"))
        XCTAssertTrue(mediaOwnerSource.contains("private func postMediaTouchBarRecoveryRequest"))

        let closeActiveSource = try sourceSlice(
            coordinatorSource,
            from: "func closeActiveFullscreenMedia",
            to: "func isWebViewProtectedFromCompositorMutation"
        )
        try assertTokenOrder(
            closeActiveSource,
            [
                "mediaProtectionOwner.closeActiveFullscreenMedia(in: windowId)",
                "resolveWebView(with: webViewID)"
            ]
        )

        let installSource = try sourceSlice(
            coordinatorSource,
            from: "private func installMediaProtectionObservationsIfNeeded",
            to: "private func uninstallMediaProtectionObservationsIfUntracked"
        )
        try assertTokenOrder(
            installSource,
            [
                "mediaProtectionOwner.installFullscreenStateObservationIfNeeded(",
                "trackedOwner:",
                "fallbackWindowID:",
                "flushDeferredProtectedCommands:",
                "refreshCompositor:",
                "mediaProtectionOwner.installNowPlayingSessionObservationIfNeeded("
            ]
        )

        try assertTokenOrder(
            Substring(mediaOwnerSource),
            [
                "func closeActiveFullscreenMedia(",
                "protectedCommandOwner.activeFullscreenWebViewIDs(in: windowID)",
                "requestFullscreenMediaExit(on: webView)",
                "func closeFullscreenMediaIfNeeded(on webView: WKWebView)",
                "protectedCommandOwner.isFullscreenProtected(webViewID)",
                "private func requestFullscreenMediaExit"
            ]
        )
        try assertTokenOrder(
            Substring(mediaOwnerSource),
            [
                "func installNowPlayingSessionObservationIfNeeded(",
                "nowPlayingSessionCancellablesByWebViewID[webViewID] = webView",
                "publisher(for: \\.sumiHasActiveNowPlayingSession",
                "postMediaTouchBarRecoveryRequest("
            ]
        )
        try assertTokenOrder(
            Substring(mediaOwnerSource),
            [
                "func installFullscreenStateObservationIfNeeded(",
                "protectedCommandOwner.installFullscreenStateObservationIfNeeded(",
                "updateFullscreenProtection(",
                "private func beginFullscreenProtectionIfNeeded",
                "private func finishFullscreenProtectionIfNeeded"
            ]
        )
    }

    func testDestructiveCleanupPreparationOwnerTracksWebViewIdentity() {
        let firstWebView = WKWebView()
        let secondWebView = WKWebView()
        let owner = WebViewDestructiveCleanupPreparationOwner()

        XCTAssertFalse(owner.isSuppressingNavigation(on: firstWebView))
        XCTAssertFalse(owner.isSuppressingNavigation(on: secondWebView))

        owner.beginNavigationSuppression(on: firstWebView)
        XCTAssertTrue(owner.isSuppressingNavigation(on: firstWebView))
        XCTAssertFalse(owner.isSuppressingNavigation(on: secondWebView))

        owner.finishNavigationSuppression(on: firstWebView)
        XCTAssertFalse(owner.isSuppressingNavigation(on: firstWebView))

        owner.beginNavigationSuppression(on: firstWebView)
        owner.finishNavigationSuppression(webViewID: ObjectIdentifier(firstWebView))
        XCTAssertFalse(owner.isSuppressingNavigation(on: firstWebView))
    }

    func testWebViewCoordinatorReleasesDestructiveCleanupSuppressionWithTrackedCleanup() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let ownerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewDestructiveCleanupPreparationOwner.swift"
            ),
            encoding: .utf8
        )
        let cleanupOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewTrackedCleanupExecutionOwner.swift"
            ),
            encoding: .utf8
        )

        let suppressionSource = try sourceSlice(
            ownerSource,
            from: "final class WebViewDestructiveCleanupPreparationOwner",
            to: "func prepare(_ webView: WKWebView, tab: Tab)"
        )
        XCTAssertTrue(suppressionSource.contains("private var blankingWebViewIDs"))
        XCTAssertFalse(suppressionSource.contains("WKNavigation"))
        XCTAssertFalse(suppressionSource.contains("load("))

        let preparationSource = try sourceSlice(
            ownerSource,
            from: "func prepare(_ webView: WKWebView, tab: Tab)",
            to: "\n}"
        )
        try assertTokenOrder(
            preparationSource,
            [
                "tab.stopLoading(on: webView)",
                "webView.pauseAllMediaPlayback",
                "beginNavigationSuppression(on: webView)",
                "webView.load(URLRequest(url: SumiSurface.emptyTabURL))"
            ]
        )

        let coordinatorStart = try XCTUnwrap(
            coordinatorSource.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorClassSource = String(coordinatorSource[coordinatorStart...])
        XCTAssertTrue(coordinatorClassSource.contains("private let destructiveCleanupPreparationOwner = WebViewDestructiveCleanupPreparationOwner()"))
        XCTAssertFalse(coordinatorClassSource.contains("private var blankingWebViewIDs"))

        let cleanupSource = try sourceSlice(
            cleanupOwnerSource,
            from: "func cleanupUnprotectedTrackedWebView(",
            to: "    }\n}"
        )
        try assertTokenOrder(
            cleanupSource,
            [
                "runtime.finishDestructiveCleanupSuppression(webView)",
                "runtime.removeFromContainers(webView)",
                "trackingLifecycleOwner.unregisterTrackedWebViewSlot("
            ]
        )

        let stalePruneSource = try sourceSlice(
            coordinatorSource,
            from: "private func pruneStaleWebViewBookkeeping",
            to: "private func pruneInvalidDeferredProtectedCommands"
        )
        try assertTokenOrder(
            stalePruneSource,
            [
                "finishDestructiveCleanupSuppression(",
                "mediaProtectionOwner.pruneStaleBookkeeping(reason: reason)"
            ]
        )

        let suppressionReleaseSource = try sourceSlice(
            coordinatorSource,
            from: "private func finishDestructiveCleanupSuppression",
            to: "@discardableResult\n    private func performDeferredProtectedCommand"
        )
        try assertTokenOrder(
            suppressionReleaseSource,
            [
                "for webViewID in webViewIDs",
                "destructiveCleanupPreparationOwner.finishNavigationSuppression(webViewID: webViewID)"
            ]
        )
    }

    func testWebViewCoordinatorDestructiveCleanupScanPolicyStaysBehindOwner() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinatorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let scanOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewDestructiveCleanupPreparationScanOwner.swift"
            ),
            encoding: .utf8
        )
        let preparationOwnerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewDestructiveCleanupPreparationOwner.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(scanOwnerSource.contains("final class WebViewDestructiveCleanupPreparationScanOwner"))
        XCTAssertTrue(scanOwnerSource.contains("typealias LiveWebViewsResolver = (Tab) -> [WKWebView]"))
        XCTAssertTrue(scanOwnerSource.contains("typealias CompositorMutationProtectionChecker = (WKWebView) -> Bool"))

        let scanSource = try sourceSlice(
            scanOwnerSource,
            from: "func prepare(",
            to: "private func isTabEligible"
        )
        try assertTokenOrder(
            scanSource,
            [
                "var seenTabIDs = Set<UUID>()",
                "var result = PreparationResult()",
                "guard seenTabIDs.insert(tab.id).inserted",
                "guard isTabEligible(tab, profileIDs: profileIDs)",
                "let tabLiveWebViews = liveWebViews(tab)",
                "let eligibleWebViews = tabLiveWebViews.filter",
                "isWebViewProtectedFromCompositorMutation(webView) == false",
                "guard !eligibleWebViews.isEmpty else",
                "result.skippedProtectedWebViewCount += tabLiveWebViews.count",
                "tab.cancelPendingMainFrameNavigation()",
                "cleanupPreparationOwner.prepare(webView, tab: tab)",
                "result.preparedWebViewCount += 1"
            ]
        )

        let eligibilitySource = try sourceSlice(
            scanOwnerSource,
            from: "private func isTabEligible",
            to: "\n    }\n}"
        )
        try assertTokenOrder(
            eligibilitySource,
            [
                "tab.resolveProfile()?.id ?? tab.profileId",
                "profileIDs.contains(profileId)",
                "tab.representsSumiNativeSurface == false"
            ]
        )

        let coordinatorPreparationSource = try sourceSlice(
            coordinatorSource,
            from: "func prepareForDestructiveDataCleanup(profileIDs: Set<UUID>) async",
            to: "func windowIDs(for tabId: UUID) -> [UUID]"
        )
        try assertTokenOrder(
            coordinatorPreparationSource,
            [
                "guard !profileIDs.isEmpty else { return }",
                "guard let browserManager else { return }",
                "destructiveCleanupPreparationScanOwner.prepare(",
                "pinnedTabs: browserManager.tabManager.allPinnedTabsAllProfiles",
                "tabs: browserManager.tabManager.allTabs()",
                "liveWebViews(for: tab)",
                "isWebViewProtectedFromCompositorMutation(webView)",
                "cleanupPreparationOwner: destructiveCleanupPreparationOwner",
                "RuntimeDiagnostics.debug(category: \"WebViewCoordinator\")"
            ]
        )
        XCTAssertFalse(coordinatorPreparationSource.contains("var seenTabIDs"))
        XCTAssertFalse(coordinatorPreparationSource.contains("tab.cancelPendingMainFrameNavigation()"))
        XCTAssertFalse(coordinatorPreparationSource.contains("filter {"))

        XCTAssertTrue(preparationOwnerSource.contains("private var blankingWebViewIDs"))
        XCTAssertTrue(preparationOwnerSource.contains("func prepare(_ webView: WKWebView, tab: Tab)"))
        XCTAssertFalse(scanOwnerSource.contains("blankingWebViewIDs"))
        XCTAssertFalse(scanOwnerSource.contains("beginNavigationSuppression"))
        XCTAssertFalse(scanOwnerSource.contains("finishNavigationSuppression"))
    }

    func testWebViewContainerLayoutDoesNotReparentDisplayedContent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/SumiWebViewContainerView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "override func layout()"))
            .lowerBound
        let end = try XCTUnwrap(source.range(of: "override func removeFromSuperview()"))
            .lowerBound
        let layoutSource = String(source[start..<end])

        XCTAssertFalse(layoutSource.contains("attachDisplayedContentIfNeeded"))
        XCTAssertTrue(layoutSource.contains("webView.sumiTabContentView.frame = bounds"))
    }

    func testLiveWebViewPathDoesNotUseSwiftUIClippingOrShadowSurface() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "TabCompositorWrapper("))
            .lowerBound
        let end = try XCTUnwrap(source.range(of: "@ViewBuilder", range: start..<source.endIndex))
            .lowerBound
        let liveWebViewPath = String(source[start..<end])

        XCTAssertFalse(liveWebViewPath.contains(".browserContentSurface("))
        XCTAssertFalse(liveWebViewPath.contains(".clipShape("))
        XCTAssertFalse(liveWebViewPath.contains(".shadow("))
        XCTAssertFalse(liveWebViewPath.contains(".background(contentSurfaceBackground)"))
        XCTAssertFalse(liveWebViewPath.contains(".browserContentViewportBackground("))
        XCTAssertTrue(liveWebViewPath.contains("chromeGeometry: chromeGeometry"))
    }

    func testWebsiteCompositorOwnsChromeShadowOutsideWebViewHost() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WindowWebContentSplitHostLayoutView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "// MARK: - Split Host Layout View"))
            .lowerBound
        let containerSource = String(source[start...])

        XCTAssertTrue(containerSource.contains("BrowserContentViewportShadowView"))
        XCTAssertTrue(containerSource.contains("addSubview(chromeShadowView"))
        XCTAssertTrue(containerSource.contains("positioned: .above, relativeTo: chromeShadowView"))
        XCTAssertTrue(containerSource.contains("subview !== chromeShadowView"))
        XCTAssertFalse(containerSource.contains("layer?.mask"))
        XCTAssertFalse(containerSource.contains("override var isOpaque"))
    }

    func testNativeSplitTreeViewBoundaryOwnsNativeDividerMechanics() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let compositorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        let splitHostLayoutSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WindowWebContentSplitHostLayoutView.swift"
            ),
            encoding: .utf8
        )
        let nativeSplitSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/NativeSplitTreeView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(compositorSource.contains("final class NativeSplitTreeView"))
        XCTAssertTrue(splitHostLayoutSource.contains("NativeSplitTreeView(axis: axis"))
        XCTAssertTrue(splitHostLayoutSource.contains("splitView.updateStoredSizes"))

        XCTAssertTrue(nativeSplitSource.contains("final class NativeSplitTreeView: NSSplitView, NSSplitViewDelegate"))
        XCTAssertTrue(nativeSplitSource.contains("func updateStoredSizes"))
        XCTAssertTrue(nativeSplitSource.contains("func splitViewDidResizeSubviews"))
        XCTAssertTrue(nativeSplitSource.contains("private static func normalizedSizes"))
        XCTAssertFalse(nativeSplitSource.contains("WindowWebContentController"))
        XCTAssertFalse(nativeSplitSource.contains("WebViewCoordinator"))
        XCTAssertFalse(nativeSplitSource.contains("SplitDropCaptureView"))
    }

    func testNativeSplitTreeViewRestoresStoredSizesAndReportsUserResize() throws {
        let splitView = NativeSplitTreeView(axis: .row, path: [1, 0], sizes: [0.25, 0.75])
        let leftPane = NSView()
        let rightPane = NSView()
        var reportedResize: (path: [Int], sizes: [Double])?

        splitView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        splitView.addSubview(leftPane)
        splitView.addSubview(rightPane)
        splitView.resizeHandler = { path, sizes in
            reportedResize = (path, sizes)
        }

        splitView.layoutSubtreeIfNeeded()

        XCTAssertNil(reportedResize)
        XCTAssertEqual(leftPane.frame.width, 100, accuracy: 4)
        XCTAssertEqual(rightPane.frame.width, 300, accuracy: 4)

        reportedResize = nil
        splitView.setPosition(280, ofDividerAt: 0)
        if reportedResize == nil {
            splitView.splitViewDidResizeSubviews(
                Notification(name: NSSplitView.didResizeSubviewsNotification, object: splitView)
            )
        }

        let resize = try XCTUnwrap(reportedResize)
        XCTAssertEqual(resize.path, [1, 0])
        XCTAssertEqual(resize.sizes.reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(resize.sizes[0], 0.60)
        XCTAssertLessThan(resize.sizes[1], 0.40)
    }

    func testRoundedWebContentViewportUsesNativeLayerClippingWithoutWebPageInjectionOrSnapshots() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let featurePaths = [
            "Sumi/Components/WebsiteView/BrowserContentViewportCutouts.swift",
            "Sumi/Components/WebsiteView/WebsiteView.swift",
            "Sumi/Components/WebsiteView/WebsiteCompositorView.swift",
            "Sumi/Components/WebsiteView/WindowWebContentSplitHostLayoutView.swift",
            "Sumi/Components/WebsiteView/NativeSplitTreeView.swift",
            "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift",
            "Sumi/Managers/WebViewCoordinator/SumiWebViewContainerView.swift",
        ]
        let featureSource = try featurePaths.map {
            try String(
                contentsOf: repositoryRoot.appendingPathComponent($0),
                encoding: .utf8
            )
        }.joined(separator: "\n")

        XCTAssertTrue(featureSource.contains("BrowserContentViewportShadowView"))
        XCTAssertTrue(featureSource.contains("shadowSurfaceLayer.shadowPath"))
        XCTAssertTrue(featureSource.contains("containsPointInsideRoundedViewport"))
        XCTAssertTrue(featureSource.contains("override func hitTest"))
        XCTAssertTrue(featureSource.contains("layer.masksToBounds = maxRadius > 0"))
        XCTAssertTrue(featureSource.contains("layer.cornerRadius = maxRadius"))
        XCTAssertTrue(featureSource.contains("layer.maskedCorners = radii.caCornerMask"))
        XCTAssertTrue(featureSource.contains("setAccessibilityElement(false)"))
        XCTAssertTrue(featureSource.contains("setAccessibilityHidden(true)"))
        XCTAssertTrue(featureSource.contains("hostLifecycleOwner.updateViewportStyle("))
        XCTAssertFalse(featureSource.contains("BrowserContentCornerCutoutView"))
        XCTAssertFalse(featureSource.contains("BrowserContentViewportCutoutBackgroundSampler"))
        XCTAssertFalse(featureSource.contains("drawViewportShadow"))
        XCTAssertFalse(featureSource.contains("cutoutPath.addClip()"))

        let forbiddenTokens = [
            "evaluateJavaScript",
            "WKUserScript",
            "addUserScript",
            "takeSnapshot",
            "bitmapImageRepForCachingDisplay",
            "cacheDisplay",
            "masksToBounds = true",
            "layer?.mask =",
            ".mask(",
        ]

        let violations = forbiddenTokens.filter { featureSource.contains($0) }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    @MainActor
    private final class CompositorBrowserContextStub: WindowWebContentBrowserContext {
        func currentTab(for windowState: BrowserWindowState) -> Tab? {
            nil
        }

        func tab(for tabId: UUID) -> Tab? {
            nil
        }

        func splitGroup(for windowId: UUID) -> SplitGroup? {
            nil
        }

        func schedulePrepareVisibleWebViews(for windowState: BrowserWindowState) {}

        func enqueueWindowMutationDuringHistorySwipe(
            _ kind: HistorySwipeDeferredWindowMutationKind,
            for windowState: BrowserWindowState
        ) {}

        func removeSplitGroup(id: UUID) {}

        func updateSplitLayoutSizes(
            groupId: UUID,
            path: [Int],
            sizes: [Double],
            for windowId: UUID
        ) {}

        func configureSplitDropCapture(_ view: SplitDropCaptureView, windowId: UUID) {}

        func configureSplitControls(
            _ controls: SplitPaneControlsView,
            tab: Tab,
            windowState: BrowserWindowState
        ) {}
    }

    private func sourceSlice(_ source: String, from startToken: String, to endToken: String) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startToken)).lowerBound
        let end = try XCTUnwrap(source.range(of: endToken, range: start..<source.endIndex)).lowerBound
        return source[start..<end]
    }

    private func assertTokenOrder(
        _ source: Substring,
        _ tokens: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var previousIndex: Substring.Index?
        var searchStart = source.startIndex
        for token in tokens {
            let range = try XCTUnwrap(
                source.range(of: token, range: searchStart..<source.endIndex),
                "Missing token: \(token)",
                file: file,
                line: line
            )
            let index = range.lowerBound
            if let previousIndex {
                XCTAssertLessThan(previousIndex, index, file: file, line: line)
            }
            previousIndex = index
            searchStart = range.upperBound
        }
    }

    private func XCTAssertEnqueueOutcome(
        _ actual: DeferredProtectedCommandEnqueueOutcome,
        is expected: DeferredProtectedCommandEnqueueOutcome,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (.enqueued, .enqueued),
             (.collapsed, .collapsed),
             (.droppedAtCapacity, .droppedAtCapacity):
            break
        default:
            XCTFail("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }

    private func loadHTML(_ html: String, into webView: WKWebView) async throws {
        let didFinish = expectation(description: "find test page loaded")
        let delegate = FindNavigationDelegateBox {
            didFinish.fulfill()
        }

        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.com"))
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil
    }
}

@MainActor
private final class FindResultRecorder {
    var result: FocusableWKWebView.FindResult?
}

private final class FindNavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}

private final class FakeWebKitMouseTrackingObserver: NSObject {
    override var className: String {
        "WKMouseTrackingObserver"
    }
}
