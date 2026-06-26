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
        XCTAssertTrue(webViewCoordinatorSource.contains("sumiWebViewNeedsMediaTouchBarRecovery"))
        XCTAssertTrue(webViewCoordinatorSource.contains("installNowPlayingSessionObservationIfNeeded"))
        XCTAssertTrue(webViewCoordinatorSource.contains("postMediaTouchBarRecoveryRequest"))
        XCTAssertTrue(webViewCoordinatorSource.contains("requestFullscreenMediaExit"))
        XCTAssertTrue(webViewCoordinatorSource.contains("webView.sumiTabContentView.removeFromSuperview()"))
        XCTAssertFalse(webViewCoordinatorSource.contains("closeAllMediaPresentations"))

        let compositorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(compositorSource.contains("recoverMediaTouchBarAfterWebKitReparent"))
        XCTAssertTrue(compositorSource.contains("resetWebKitMediaTouchBar"))
        XCTAssertTrue(compositorSource.contains("host.attachDisplayedContentIfNeeded()"))
        XCTAssertFalse(compositorSource.contains("webView.sumiCloseInactiveFullscreenWindowControllerIfNeeded()"))
        XCTAssertTrue(compositorSource.contains("webView.touchBar = nil"))
        XCTAssertTrue(compositorSource.contains("window.makeFirstResponder(webView)"))

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

    func testVisualHandoffProtectionIsReleasedExplicitly() {
        let coordinator = WebViewCoordinator()
        let webView = WKWebView()

        coordinator.beginVisualHandoffProtection(for: webView)
        XCTAssertTrue(coordinator.isWebViewProtectedFromCompositorMutation(webView))

        coordinator.finishVisualHandoffProtection(for: webView)
        XCTAssertFalse(coordinator.isWebViewProtectedFromCompositorMutation(webView))
    }

    func testCloneWebViewPrimaryWindowSelectionDoesNotDependOnDictionaryOrder() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )
        let creationSlice = try sourceSlice(
            source,
            from: "func getOrCreateWebView",
            to: "private func deferWebViewCreationForInitialDocumentWarmupIfNeeded"
        )

        XCTAssertTrue(creationSlice.contains("primaryWindowIdForClone"))
        XCTAssertFalse(creationSlice.contains("otherWindows.first"))
        XCTAssertFalse(creationSlice.contains("first!.key"))

        let policySlice = try sourceSlice(
            source,
            from: "private func primaryWindowIdForClone",
            to: "private func deferWebViewCreationForInitialDocumentWarmupIfNeeded"
        )

        XCTAssertTrue(policySlice.contains("tab.primaryWindowId"))
        XCTAssertTrue(policySlice.contains("otherWindows[primaryWindowId] != nil"))
        XCTAssertTrue(policySlice.contains("otherWindows.keys.min"))
        XCTAssertTrue(policySlice.contains("uuidString <"))
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
        let splitShortcutsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/BrowserManager/BrowserManager+SplitShortcuts.swift"
            ),
            encoding: .utf8
        )
        let compositorSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )

        let regularClose = try sourceSlice(
            browserManagerSource,
            from: "func closeTab(_ tab: Tab, in windowState: BrowserWindowState)",
            to: "isolated deinit"
        )
        XCTAssertLessThan(
            try XCTUnwrap(regularClose.range(of: "performImmediateVisualHandoffIfPossible")).lowerBound,
            try XCTUnwrap(regularClose.range(of: "tabManager.removeTab(tab.id)")).lowerBound
        )

        let shortcutClose = try sourceSlice(
            browserManagerSource,
            from: "private func closeShortcutLiveTab",
            to: "private func captureClosedShortcutLiveInstance"
        )
        XCTAssertLessThan(
            try XCTUnwrap(shortcutClose.range(of: "performImmediateVisualHandoffIfPossible")).lowerBound,
            try XCTUnwrap(shortcutClose.range(of: "tabManager.deactivateShortcutLiveTab")).lowerBound
        )

        let spaceSwitch = try sourceSlice(
            browserManagerSource,
            from: "func setActiveSpace(_ space: Space, in windowState: BrowserWindowState)",
            to: "private func selectionTargetForSpaceActivation"
        )
        XCTAssertTrue(spaceSwitch.contains("performImmediateVisualHandoffIfPossible(in: windowState)"))

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
        XCTAssertTrue(compositorSource.contains("placeVisualHandoffCover"))
        XCTAssertTrue(compositorSource.contains("scheduleVisualHandoffCoverRelease"))

        let compositorApply = try sourceSlice(
            compositorSource,
            from: "private func apply(displayState: WebsiteDisplayState, currentTab: Tab?)",
            to: "private func performImmediateVisualHandoffIfPossible()"
        )
        XCTAssertTrue(compositorApply.contains("beginSinglePaneVisualHandoffIfNeeded"))
        XCTAssertTrue(compositorApply.contains("beginVisualHandoffCovers(excluding: Set(group.tabIds))"))
        XCTAssertTrue(compositorSource.contains("guard displayedHost(for: tab.id) == nil else { return false }"))

        let coverRelease = try sourceSlice(
            compositorSource,
            from: "private func scheduleVisualHandoffCoverRelease()",
            to: "private func releaseVisualHandoffCovers()"
        )
        XCTAssertTrue(coverRelease.contains("CATransaction.flush()"))
        XCTAssertTrue(coverRelease.contains("containerView.displayIfNeeded()"))
        XCTAssertTrue(coverRelease.contains("visualHandoffCoverReleaseGeneration == generation"))

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
            from: "private func webViewHost(for tab: Tab, slot: PaneSlot)",
            to: "private func attach(_ host: SumiWebViewContainerView"
        )
        XCTAssertTrue(webViewHost.contains("if let displayedHost = displayedHost(for: tab.id)"))
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

        let callSites = [
            (
                "func cleanupWindow(_ windowId: UUID, tabManager: TabManager)",
                "func cleanupAllWebViews(tabManager: TabManager)",
                ["enqueueDeferredProtectedCommand(", "continue"]
            ),
            (
                "func cleanupAllWebViews(tabManager: TabManager)",
                "// MARK: - History Swipe Protection",
                ["enqueueDeferredProtectedCommand(", "continue"]
            ),
            (
                "func removeAllWebViews(\n        for tab: Tab,",
                "@discardableResult\n    func suspendWebViews",
                ["enqueueDeferredProtectedCommand(", "return false"]
            ),
            (
                "private func evictHiddenWebViewsIfNeeded(",
                "private func notifyTabActivatedIfCurrent",
                ["enqueueDeferredProtectedCommand(", "continue"]
            ),
        ]

        for (start, end, protectedDeferralTokens) in callSites {
            let callSite = try sourceSlice(source, from: start, to: end)
            try assertTokenOrder(
                callSite,
                protectedDeferralTokens
                    + ["cleanupUnprotectedTrackedWebView(", "refreshPrimaryTrackedWebView"]
            )
        }

        let deferredWrapper = try sourceSlice(
            source,
            from: "private func cleanupTrackedWebView(\n        _ webView: WKWebView,\n        owner: TrackedWebViewOwner\n    )",
            to: "private func cleanupUnprotectedTrackedWebView"
        )
        try assertTokenOrder(
            deferredWrapper,
            [
                "finishDestructiveDataCleanupNavigation(on: webView)",
                "cleanupUnprotectedTrackedWebView(",
                "refreshPrimaryTrackedWebView"
            ]
        )

        let unprotectedHelper = try sourceSlice(
            source,
            from: "private func cleanupUnprotectedTrackedWebView(",
            to: "@discardableResult\n    private func closeTrackedWebViewFromWebKit"
        )
        try assertTokenOrder(
            unprotectedHelper,
            [
                "removeWebViewFromContainers(webView)",
                "unregisterTrackedWebViewSlot(owner: owner, expectedWebView: webView)",
                "tab.cleanupCloneWebView(webView)"
            ]
        )
        try assertTokenOrder(
            unprotectedHelper,
            [
                "unregisterTrackedWebViewSlot(owner: owner, expectedWebView: webView)",
                "performFallbackWebViewCleanup("
            ]
        )
        XCTAssertFalse(unprotectedHelper.contains("finishDestructiveDataCleanupNavigation"))
        XCTAssertFalse(unprotectedHelper.contains("refreshPrimaryTrackedWebView"))
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

    func testWebViewCoordinatorDeferredProtectedCommandsStayBehindNarrowStore() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
            ),
            encoding: .utf8
        )

        let storeSource = try sourceSlice(
            source,
            from: "private struct DeferredProtectedWebViewCommandStore",
            to: "@MainActor\n@Observable\nclass WebViewCoordinator"
        )
        XCTAssertTrue(storeSource.contains("private var buffersBySourceWebViewID"))
        XCTAssertFalse(storeSource.contains("activeHistorySwipeProtections"))
        XCTAssertFalse(storeSource.contains("visualHandoffProtectedWebViewIDs"))
        XCTAssertFalse(storeSource.contains("fullscreenProtection"))
        XCTAssertFalse(storeSource.contains("weakWebViewsByIdentifier"))
        XCTAssertFalse(storeSource.contains("resolveWebView"))
        XCTAssertFalse(storeSource.contains("executeDeferredProtectedCommand"))
        XCTAssertFalse(storeSource.contains("dropDeferredProtectedCommand"))

        let coordinatorStart = try XCTUnwrap(
            source.range(of: "@MainActor\n@Observable\nclass WebViewCoordinator")
        ).lowerBound
        let coordinatorSource = String(source[coordinatorStart...])
        XCTAssertTrue(
            coordinatorSource.contains(
                "private var deferredProtectedWebViewCommands = DeferredProtectedWebViewCommandStore()"
            )
        )
        XCTAssertFalse(coordinatorSource.contains("deferredProtectedWebViewCommands["))
        XCTAssertFalse(coordinatorSource.contains("deferredProtectedWebViewCommands.keys"))

        let enqueueSource = try sourceSlice(
            source,
            from: "private func enqueueDeferredCommandIfNeeded",
            to: "private func noteWeakWebView"
        )
        try assertTokenOrder(
            enqueueSource,
            [
                "noteWeakWebView(webView)",
                "guard shouldDefer(sourceWebViewID)",
                "pruneInvalidDeferredProtectedCommands(reason: \"enqueue.preflight\")",
                "guard isDeferredProtectedCommandValid(command)",
                "deferredProtectedWebViewCommands.enqueue(",
                "switch enqueueResult.outcome"
            ]
        )

        let flushSource = try sourceSlice(
            source,
            from: "private func flushDeferredProtectedCommands",
            to: "private func isCancelledHistorySwipe"
        )
        try assertTokenOrder(
            flushSource,
            [
                "guard activeHistorySwipeProtections[webViewID] == nil",
                "visualHandoffProtectedWebViewIDs.contains(webViewID) == false",
                "fullscreenProtection.isProtected(webViewID) == false",
                "pruneInvalidDeferredProtectedCommands(reason: \"flush.preflight\")",
                "deferredProtectedWebViewCommands.drainCommands(for: webViewID)",
                "Task { @MainActor",
                "executeDeferredProtectedCommand("
            ]
        )

        let pruneSource = try sourceSlice(
            source,
            from: "private func pruneInvalidDeferredProtectedCommands",
            to: "private func isDeferredProtectedCommandValid"
        )
        try assertTokenOrder(
            pruneSource,
            [
                "pruneStaleWebViewBookkeeping",
                "for sourceWebViewID in deferredProtectedWebViewCommands.sourceWebViewIDs",
                "guard resolveWebView(with: sourceWebViewID) != nil",
                "deferredProtectedWebViewCommands.drainCommands(for: sourceWebViewID)",
                "dropDeferredProtectedCommand(",
                "deferredProtectedWebViewCommands.pruneCommands(for: sourceWebViewID)",
                "dropDeferredProtectedCommand("
            ]
        )
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
                "Sumi/Components/WebsiteView/WebsiteCompositorView.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(source.range(of: "// MARK: - Container View"))
            .lowerBound
        let containerSource = String(source[start...])

        XCTAssertTrue(containerSource.contains("BrowserContentViewportShadowView"))
        XCTAssertTrue(containerSource.contains("addSubview(chromeShadowView"))
        XCTAssertTrue(containerSource.contains("positioned: .above, relativeTo: chromeShadowView"))
        XCTAssertTrue(containerSource.contains("subview !== chromeShadowView"))
        XCTAssertFalse(containerSource.contains("layer?.mask"))
        XCTAssertFalse(containerSource.contains("override var isOpaque"))
    }

    func testRoundedWebContentViewportUsesNativeLayerClippingWithoutWebPageInjectionOrSnapshots() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let featurePaths = [
            "Sumi/Components/WebsiteView/BrowserContentViewportCutouts.swift",
            "Sumi/Components/WebsiteView/WebsiteView.swift",
            "Sumi/Components/WebsiteView/WebsiteCompositorView.swift",
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
        XCTAssertTrue(featureSource.contains("updateDisplayedHostViewportStyles()"))
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
