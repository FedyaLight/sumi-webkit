import AppKit
import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowChromeTests: XCTestCase {
    func testBrowserChromeGeometryDefaultsPreserveViewportCornerMetrics() {
        let geometry = BrowserChromeGeometry()
        let expectedMetrics = BrowserChromeGeometry.CornerMetrics.default

        XCTAssertEqual(BrowserChromeGeometry.defaultOuterRadius, expectedMetrics.defaultOuterRadius)
        XCTAssertEqual(BrowserChromeGeometry.elementSeparation, expectedMetrics.elementSeparation)
        XCTAssertEqual(BrowserChromeGeometry.minimumContentRadius, expectedMetrics.minimumContentRadius)
        XCTAssertEqual(geometry.outerRadius, expectedMetrics.defaultOuterRadius)
        XCTAssertEqual(geometry.elementSeparation, expectedMetrics.elementSeparation)
        XCTAssertEqual(
            geometry.contentCornerRadii.maxRadius,
            expectedMetrics.contentRadius(
                outerRadius: expectedMetrics.defaultOuterRadius,
                elementSeparation: expectedMetrics.elementSeparation
            )
        )
    }

    func testBrowserChromeGeometrySequoiaFallbackPreservesViewportCornerMetrics() {
        let metrics = BrowserChromeGeometry.CornerMetrics.platformDefault(isMacOSTahoeOrNewer: false)
        let geometry = BrowserChromeGeometry(
            outerRadius: metrics.defaultOuterRadius,
            elementSeparation: metrics.elementSeparation,
            cornerMetrics: metrics
        )

        XCTAssertEqual(metrics.defaultOuterRadius, 7)
        XCTAssertEqual(metrics.elementSeparation, 8)
        XCTAssertEqual(metrics.minimumContentRadius, 5)
        XCTAssertEqual(geometry.outerRadius, 7)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentCornerRadii.maxRadius, 5)
    }

    func testBrowserChromeGeometryTahoeFallbackUsesConservativeViewportCornerMetrics() {
        let metrics = BrowserChromeGeometry.CornerMetrics.platformDefault(isMacOSTahoeOrNewer: true)
        let geometry = BrowserChromeGeometry(
            outerRadius: metrics.defaultOuterRadius,
            elementSeparation: metrics.elementSeparation,
            cornerMetrics: metrics
        )

        XCTAssertEqual(metrics.defaultOuterRadius, 14)
        XCTAssertEqual(metrics.elementSeparation, 8)
        XCTAssertEqual(metrics.minimumContentRadius, 5)
        XCTAssertEqual(geometry.outerRadius, 14)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentCornerRadii.maxRadius, 10)
    }

    func testBrowserChromeGeometryDerivesContentRadiusFromOuterRadiusAndSeparation() {
        let geometry = BrowserChromeGeometry(outerRadius: 14)

        XCTAssertEqual(geometry.outerRadius, 14)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentCornerRadii.maxRadius, 10)
    }

    func testBrowserChromeGeometryClampsContentRadiusToMinimum() {
        let geometry = BrowserChromeGeometry(outerRadius: 2)

        XCTAssertEqual(geometry.outerRadius, 2)
        XCTAssertEqual(geometry.contentCornerRadii.maxRadius, 5)
    }

    func testBrowserChromeGeometrySettingsUseDefaultOuterRadiusForSentinelBorderRadius() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.themeBorderRadius = -1
        let geometry = BrowserChromeGeometry(settings: settings)
        let expectedMetrics = BrowserChromeGeometry.CornerMetrics.default

        XCTAssertEqual(geometry.outerRadius, expectedMetrics.defaultOuterRadius)
        XCTAssertEqual(
            geometry.contentCornerRadii.maxRadius,
            expectedMetrics.contentRadius(
                outerRadius: expectedMetrics.defaultOuterRadius,
                elementSeparation: expectedMetrics.elementSeparation
            )
        )
    }

    func testBrowserChromeGeometrySettingsUseCustomBorderRadiusAsOuterRadius() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.themeBorderRadius = 18
        let geometry = BrowserChromeGeometry(settings: settings)

        XCTAssertEqual(geometry.outerRadius, 18)
        XCTAssertEqual(geometry.contentCornerRadii.maxRadius, 14)
    }

    func testBrowserChromeGeometryCustomBorderRadiusOverridesTahoePlatformDefault() {
        let metrics = BrowserChromeGeometry.CornerMetrics.platformDefault(isMacOSTahoeOrNewer: true)
        let customOuterRadius = metrics.outerRadius(themeBorderRadius: 18)
        let geometry = BrowserChromeGeometry(
            outerRadius: customOuterRadius,
            elementSeparation: metrics.elementSeparation,
            cornerMetrics: metrics
        )

        XCTAssertEqual(customOuterRadius, 18)
        XCTAssertEqual(geometry.outerRadius, 18)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentCornerRadii.maxRadius, 14)
    }

    func testBrowserChromeGeometryDefaultsExposeUniformInsetsAndCornerRadii() {
        let geometry = BrowserChromeGeometry()
        let separation = geometry.elementSeparation

        XCTAssertEqual(geometry.contentEdgeInsets, .uniform(separation))
        XCTAssertEqual(geometry.contentCornerRadii, .uniform(geometry.contentCornerRadii.maxRadius))
        XCTAssertTrue(geometry.contentCornerRadii.isUniform)
    }

    func testBrowserChromeGeometrySettingsKeepUniformChromeWhenFramelessDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.framelessChrome = false
        let geometry = BrowserChromeGeometry(settings: settings)

        let separation = geometry.elementSeparation
        XCTAssertEqual(geometry.contentEdgeInsets, .uniform(separation))
        XCTAssertEqual(geometry.contentCornerRadii, .uniform(geometry.contentCornerRadii.maxRadius))
        XCTAssertTrue(geometry.contentCornerRadii.isUniform)
        XCTAssertEqual(geometry.contentCornerRadii.bottomLeading, geometry.contentCornerRadii.maxRadius)
        XCTAssertEqual(geometry.contentCornerRadii.bottomTrailing, geometry.contentCornerRadii.maxRadius)
    }

    func testBrowserChromeGeometrySettingsUseTopOnlyChromeWhenFramelessEnabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.framelessChrome = true
        let geometry = BrowserChromeGeometry(settings: settings)

        let separation = geometry.elementSeparation
        // Only the top inset survives; sides and bottom are flush.
        XCTAssertEqual(geometry.contentEdgeInsets, .topOnly(separation))
        XCTAssertEqual(geometry.contentEdgeInsets.top, separation)
        XCTAssertEqual(geometry.contentEdgeInsets.bottom, 0)
        XCTAssertEqual(geometry.contentEdgeInsets.leading, 0)
        XCTAssertEqual(geometry.contentEdgeInsets.trailing, 0)
        // Only top corners are rounded; bottom corners are square.
        XCTAssertEqual(geometry.contentCornerRadii, .topOnly(geometry.contentCornerRadii.maxRadius))
        XCTAssertEqual(geometry.contentCornerRadii.topLeading, geometry.contentCornerRadii.maxRadius)
        XCTAssertEqual(geometry.contentCornerRadii.topTrailing, geometry.contentCornerRadii.maxRadius)
        XCTAssertEqual(geometry.contentCornerRadii.bottomLeading, 0)
        XCTAssertEqual(geometry.contentCornerRadii.bottomTrailing, 0)
    }

    func testChromeCornerRadiiMapsToTopOnlyAppKitCornerMask() {
        let radii = ChromeCornerRadii.topOnly(10)
        let mask = radii.caCornerMask

        XCTAssertTrue(mask.contains(.layerMinXMaxYCorner))
        XCTAssertTrue(mask.contains(.layerMaxXMaxYCorner))
        XCTAssertFalse(mask.contains(.layerMinXMinYCorner))
        XCTAssertFalse(mask.contains(.layerMaxXMinYCorner))
    }

    func testChromeCornerRadiiUniformMaskCoversAllCorners() {
        let mask = ChromeCornerRadii.uniform(10).caCornerMask

        XCTAssertTrue(mask.contains(.layerMinXMaxYCorner))
        XCTAssertTrue(mask.contains(.layerMaxXMaxYCorner))
        XCTAssertTrue(mask.contains(.layerMinXMinYCorner))
        XCTAssertTrue(mask.contains(.layerMaxXMinYCorner))
    }

    func testChromeCornerRadiiZeroRadiusProducesEmptyMask() {
        XCTAssertTrue(ChromeCornerRadii.uniform(0).caCornerMask.isEmpty)
        XCTAssertTrue(ChromeCornerRadii.topOnly(0).caCornerMask.isEmpty)
    }

    func testBrowserContentViewportShapeOwnsRoundedHitTesting() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let uniform = BrowserContentViewportShape.path(
            in: rect,
            cornerRadii: .uniform(10)
        )
        let topOnly = BrowserContentViewportShape.path(
            in: rect,
            cornerRadii: .topOnly(10)
        )

        XCTAssertFalse(uniform.contains(CGPoint(x: 1, y: 1)))
        XCTAssertFalse(uniform.contains(CGPoint(x: 1, y: 99)))
        XCTAssertTrue(uniform.contains(CGPoint(x: 50, y: 50)))
        XCTAssertTrue(topOnly.contains(CGPoint(x: 1, y: 1)))
        XCTAssertFalse(topOnly.contains(CGPoint(x: 1, y: 99)))
    }

    func testBrowserContentViewportClipOwnsMaskBackgroundAndRoundedHitRegion() {
        let backgroundColor = NSColor.systemPurple
        let view = BrowserContentViewportClipView(
            style: BrowserContentSurfaceStyle(
                geometry: BrowserChromeGeometry(outerRadius: 24),
                backgroundColor: backgroundColor
            )
        )
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        view.layoutSubtreeIfNeeded()

        XCTAssertTrue(view.clipsToBounds)
        XCTAssertTrue(view.layer?.masksToBounds == true)
        XCTAssertEqual(view.layer?.cornerRadius, 20)
        XCTAssertEqual(view.layer?.backgroundColor, backgroundColor.cgColor)
        XCTAssertNil(view.hitTest(NSPoint(x: 1, y: 99)))
        XCTAssertIdentical(view.hitTest(NSPoint(x: 50, y: 50)), view)
    }

    func testChromeCornerRadiiClampAtViewportHalfExtent() {
        XCTAssertEqual(
            ChromeCornerRadii.uniform(20).clamped(to: CGSize(width: 10, height: 40)),
            .uniform(5)
        )
        XCTAssertEqual(
            ChromeCornerRadii.topOnly(20).clamped(to: CGSize(width: 40, height: 12)),
            .topOnly(6)
        )
    }

    private func assertMinimumWindowConstraints(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(window.minSize, window.contentMinSize, file: file, line: line)
        XCTAssertEqual(
            window.minSize.width,
            SumiBrowserWindowShellConfiguration.minimumContentSize.width,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            window.minSize.height,
            SumiBrowserWindowShellConfiguration.minimumContentSize.height,
            file: file,
            line: line
        )
    }

    private func assertBrowserToolbarConfiguration(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact, file: file, line: line)
        XCTAssertEqual(window.toolbar?.displayMode, .iconOnly, file: file, line: line)
        XCTAssertTrue(window.toolbar?.items.isEmpty == true, file: file, line: line)
        XCTAssertTrue(window.toolbar?.isVisible == true, file: file, line: line)
    }

    func testFullScreenChromeReturnsTheTitlebarAreaToAppKit() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)

        window.applyBrowserChromeConfiguration(displayMode: .fullScreen)
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .automatic)
        assertBrowserToolbarConfiguration(window)
        guard let contentView = window.contentView else {
            XCTFail("A browser window must keep its AppKit content view in fullscreen.")
            return
        }
        XCTAssertEqual(
            contentView.frame.height,
            window.contentLayoutRect.height,
            accuracy: 0.5
        )

        window.applyBrowserChromeConfiguration(displayMode: .normal)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        assertBrowserToolbarConfiguration(window)
    }

    func testSumiBrowserWindowInitAppliesBrowserChromeConfiguration() {
        let window = WindowChromeTestSupport.makeBrowserWindow()

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        assertBrowserToolbarConfiguration(window)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        assertNativeBrowserControlsHidden(window)
    }

    func testBrowserWindowBridgeViewAttachPromotesWindowSynchronouslyOnAttach() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        let coordinator = BrowserWindowBridge.Coordinator(
            windowState: windowState,
            windowRegistry: windowRegistry
        )
        let bridgeView = BrowserWindowBridgeView(frame: .zero)

        bridgeView.coordinator = coordinator
        window.contentView?.addSubview(bridgeView)
        WindowChromeTestSupport.retain(window)

        XCTAssertFalse(window is SumiBrowserWindow)
        XCTAssertIdentical(windowRegistry.appKitWindow(for: windowState), window)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        assertBrowserToolbarConfiguration(window)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, SumiBrowserWindowShellConfiguration.defaultContentSize)
        assertNativeBrowserControlsHidden(window)
    }

    func testBrowserWindowBridgeCoordinatorDetachClearsWindowState() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        let coordinator = BrowserWindowBridge.Coordinator(
            windowState: windowState,
            windowRegistry: windowRegistry
        )

        coordinator.attach(to: window)
        WindowChromeTestSupport.retain(window)
        XCTAssertIdentical(windowRegistry.appKitWindow(for: windowState), window)

        coordinator.detach()

        XCTAssertNil(windowRegistry.appKitWindow(for: windowState))
    }

    func testBrowserWindowBridgeCoordinatorUnregistersWindowOnWillCloseNotification() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        var closedWindowIds: [UUID] = []
        let coordinator = BrowserWindowBridge.Coordinator(
            windowState: windowState,
            windowRegistry: windowRegistry
        )

        installWindowRegistryTestEventSink(
            on: windowRegistry,
            closeWindow: { closedWindowIds.append($0.id) }
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        coordinator.attach(to: window)
        WindowChromeTestSupport.retain(window)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertEqual(closedWindowIds, [windowState.id])
        XCTAssertNil(windowRegistry.windows[windowState.id])
        XCTAssertNil(windowRegistry.activeWindowId)
        XCTAssertNil(windowRegistry.appKitWindow(for: windowState))
    }

    func testPromoteToSumiBrowserWindowIfNeededAppliesBrowserChromeConfiguration() {
        let window = WindowChromeTestSupport.makePlainWindow()

        promoteToSumiBrowserWindowIfNeeded(window)
        WindowChromeTestSupport.retain(window)

        XCTAssertFalse(window is SumiBrowserWindow)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        assertBrowserToolbarConfiguration(window)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        assertNativeBrowserControlsHidden(window)
    }

    func testNativePerformCloseWorksWhileStandardButtonIsPlacedInBrowserChrome() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let titlebarSuperview = window.standardWindowButton(.closeButton)?.superview
        placeTrafficLightsInChrome(of: window)
        let willClose = expectation(description: "Browser chrome close posts will-close notification.")
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            willClose.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertIdentical(
            window.standardWindowButton(.closeButton)?.superview,
            titlebarSuperview,
            "Chrome placement translates the button; it must never leave the titlebar."
        )
        window.performClose(nil)

        wait(for: [willClose], timeout: 0.2)
    }

    func testNativePerformCloseRespectsDelegateWhileStandardButtonIsPlacedInBrowserChrome() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let titlebarSuperview = window.standardWindowButton(.closeButton)?.superview
        placeTrafficLightsInChrome(of: window)
        let delegate = WindowShouldCloseDelegate(shouldClose: false)
        let willClose = expectation(description: "Browser chrome close should not post will-close notification.")
        willClose.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            willClose.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        window.delegate = delegate

        XCTAssertIdentical(
            window.standardWindowButton(.closeButton)?.superview,
            titlebarSuperview,
            "Chrome placement translates the button; it must never leave the titlebar."
        )
        window.performClose(nil)

        XCTAssertEqual(delegate.windowShouldCloseCount, 1)
        wait(for: [willClose], timeout: 0.1)
    }

    private func placeTrafficLightsInChrome(of window: NSWindow) {
        window.browserTrafficLightPlacement.apply(
            rendering: .chrome
        )
    }

    func testContentViewCanBeConstructedWithoutLifecycleForwarding() {
        let browserManager = BrowserManager()
        let updaterService = SumiUpdaterService(backendFactory: { _ in nil })

        let contentView = ContentView(
            webContentContext: .make(
                browserManager: browserManager
            ),
            sidebarContext: .make(
                browserManager: browserManager,
                updaterService: updaterService,
                nowPlayingController: SumiNativeNowPlayingController()
            ),
            commandPaletteContext:
                browserManager.urlBarBundle.commandPaletteBrowserContext.context,
            nativeModalContext: .make(browserManager: browserManager),
            findContext: .make(browserManager: browserManager),
            splitContext: .make(browserManager: browserManager),
            themeChromeContext: .make(browserManager: browserManager),
            initialWorkspaceTheme: .default
        )

        withExtendedLifetime(browserManager) {
            XCTAssertTrue(type(of: contentView) == ContentView.self)
        }
    }

    func testWindowFeatureContextsReadLiveStateThroughExactRoleServices() {
        let browserManager = BrowserManager()
        let themeContext = WindowThemeChromeContext.make(browserManager: browserManager)
        let nativeModalContext = WindowNativeModalContext.make(browserManager: browserManager)

        XCTAssertFalse(themeContext.hasCurrentSpace)
        XCTAssertNil(nativeModalContext.presentation)

        let space = Space(name: "Live window context")
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let presentation = BrowserNativeModalPresentation(
            windowID: UUID(),
            window: nil,
            kind: .browsingData,
            source: nil,
            transientSessionToken: nil
        )
        browserManager.nativeModalPresentationState.replace(with: presentation)

        XCTAssertTrue(themeContext.hasCurrentSpace)
        XCTAssertEqual(
            themeContext.workspaceTheme(for: space.id),
            space.workspaceTheme
        )
        XCTAssertIdentical(nativeModalContext.presentation, presentation)
        XCTAssertTrue(nativeModalContext.isPresented(in: presentation.windowID))

        browserManager.spaceStateOwner.replaceCurrentSpace(nil)
        browserManager.nativeModalPresentationState.replace(with: nil)

        XCTAssertFalse(themeContext.hasCurrentSpace)
        XCTAssertNil(nativeModalContext.presentation)
    }

    func testWindowNativeModalContextObservesTransactionDismissal() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        browserManager.windowRegistry.register(windowState)
        browserManager.windowRegistry.setActive(windowState)
        let context = WindowNativeModalContext.make(
            browserManager: browserManager
        )
        var presentedIDs: [UUID?] = []
        let observation = context.presentationState.$presentation
            .dropFirst()
            .sink { presentedIDs.append($0?.id) }

        XCTAssertTrue(
            browserManager.chromeBundle.nativeDialogPresentationOwner
                .presentNoticeSheet(
                    BrowserNoticeSheetModel(
                        title: "Notice",
                        message: "Dismiss me"
                    )
                )
        )
        let presentedID = context.presentation?.id

        context.dismiss()

        XCTAssertEqual(presentedIDs, [presentedID, nil])
        XCTAssertNil(context.presentation)
        withExtendedLifetime(observation) {}
    }

    func testSplitPaneControlsOnlyHitTestWhenVisible() {
        let controls = SplitPaneControlsView(frame: NSRect(x: 0, y: 0, width: 64, height: 26))

        XCTAssertNil(controls.hitTest(NSPoint(x: 8, y: 8)))

        controls.setVisible(true, animated: false)
        XCTAssertNotNil(controls.hitTest(NSPoint(x: 8, y: 8)))

        controls.setVisible(false, animated: false)
        XCTAssertNil(controls.hitTest(NSPoint(x: 8, y: 8)))
    }

    func testSplitPaneExpandSeparatesPinnedAndEssentialPresentedMembers() throws {
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                database: try makeInMemoryStartupDatabase()
            )
        )
        let spaceID = UUID()
        let profileID = UUID()
        let windowState = BrowserWindowState()
        let presentedTab = Tab(loadsCachedFaviconOnInit: false)
        let cases: [(container: SplitGroupContainer, isEssential: Bool)] = [
            (
                .shortcutSidebar(
                    spaceId: spaceID,
                    profileId: nil,
                    folderId: nil,
                    index: 0
                ),
                false
            ),
            (.essentialSidebar(profileId: profileID, index: 0), true),
        ]

        for (container, isEssential) in cases {
            let pins = (0..<2).map { index in
                ShortcutPin(
                    id: UUID(),
                    role: isEssential ? .essential : .spacePinned,
                    profileId: isEssential ? profileID : nil,
                    spaceId: isEssential ? nil : spaceID,
                    index: index,
                    launchURL: URL(string: "https://split-\(index).example")!,
                    title: "Split \(index)"
                )
            }
            if isEssential {
                browser.structuralCollectionMutationOwner.setPinnedTabs(
                    pins,
                    for: profileID
                )
            } else {
                browser.structuralCollectionMutationOwner
                    .setSpacePinnedShortcuts(pins, for: spaceID)
            }
            let memberID = SplitMemberID.shortcutPin(pins[0].id)
            let group = try XCTUnwrap(SplitGroup.make(
                members: pins.map { .shortcutPin($0.id) },
                layoutKind: .vertical,
                container: container
            ))
            XCTAssertTrue(
                browser.splitGroupMutations.insert(group, persist: false)
            )

            let controls = SplitPaneControlsView(
                frame: NSRect(
                    origin: .zero,
                    size: SplitPaneControlsView.preferredSize
                )
            )
            controls.configure(
                tab: presentedTab,
                windowState: windowState,
                sidebarDragState: SidebarDragState(),
                onSeparate: {
                    browser.splitLayout.separate(
                        memberID,
                        from: group.id,
                        in: windowState
                    )
                }
            )
            controls.setVisible(true, animated: false)

            let expandButton = try XCTUnwrap(
                button(
                    in: controls,
                    accessibilityIdentifier: "split-pane-expand-tab"
                )
            )
            expandButton.performClick(nil)

            XCTAssertNil(
                browser.splitGroupStore.group(id: group.id),
                "\(container) split was not separated"
            )
        }
    }

    func testNativeSplitTreeDelegateCapabilityLookupDoesNotRecurse() {
        let splitView = NativeSplitTreeView(
            axis: .row,
            path: [],
            sizes: [0.5, 0.5]
        )

        XCTAssertFalse(splitView.delegate === splitView)
        XCTAssertFalse(splitView.responds(to: #selector(
            NSSplitViewDelegate.splitView(_:canCollapseSubview:)
        )))
    }

    private func assertNativeBrowserControlsHidden(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var titlebarView: NSView?
        var titlebarContainer: NSView?
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            titlebarView = titlebarView ?? button.superview
            titlebarContainer = titlebarContainer ?? button.superview?.superview
            XCTAssertTrue(button.isHidden, file: file, line: line)
            XCTAssertEqual(button.alphaValue, 1, file: file, line: line)
            XCTAssertFalse(button.isTransparent, file: file, line: line)
            XCTAssertTrue(button.isAccessibilityHidden(), file: file, line: line)
            XCTAssertTrue(button.identifier?.rawValue.isEmpty ?? true, file: file, line: line)
            XCTAssertTrue(button.accessibilityIdentifier().isEmpty, file: file, line: line)
        }
        XCTAssertFalse(
            titlebarView?.isHidden ?? true,
            "The AppKit-owned titlebar hierarchy must remain in its native lifecycle",
            file: file,
            line: line
        )
        XCTAssertFalse(
            titlebarContainer?.isHidden ?? true,
            "The AppKit-owned titlebar container must remain in its native lifecycle",
            file: file,
            line: line
        )
    }

    private func button(
        in view: NSView,
        accessibilityIdentifier: String
    ) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityIdentifier() == accessibilityIdentifier {
            return button
        }
        for subview in view.subviews {
            if let button = button(
                in: subview,
                accessibilityIdentifier: accessibilityIdentifier
            ) {
                return button
            }
        }
        return nil
    }
}

@MainActor
private final class WindowShouldCloseDelegate: NSObject, NSWindowDelegate {
    private let shouldClose: Bool
    private(set) var windowShouldCloseCount = 0

    init(shouldClose: Bool) {
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        windowShouldCloseCount += 1
        return shouldClose
    }
}
