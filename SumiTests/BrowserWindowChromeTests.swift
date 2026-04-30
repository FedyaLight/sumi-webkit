import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowChromeTests: XCTestCase {
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

    func testSumiBrowserWindowInitAppliesBrowserChromeConfiguration() {
        let window = WindowChromeTestSupport.makeBrowserWindow()

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertNil(window.toolbar)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        assertNativeBrowserControlsVisible(window)
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
        XCTAssertTrue(windowState.window === window)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertNil(window.toolbar)
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
        XCTAssertTrue(windowState.window === window)

        coordinator.detach()

        XCTAssertNil(windowState.window)
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
        XCTAssertNil(window.toolbar)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        assertNativeBrowserControlsVisible(window)
    }

    func testBrowserChromeConfiguresNativeControlIdentifiers() {
        let window = WindowChromeTestSupport.makeBrowserWindow()

        for type in WindowChromeTestSupport.standardButtonTypes {
            window.standardWindowButton(type)?.isHidden = true
            window.standardWindowButton(type)?.alphaValue = 0
            window.standardWindowButton(type)?.isEnabled = false
            window.standardWindowButton(type)?.setAccessibilityElement(false)
            window.standardWindowButton(type)?.identifier = nil
            window.standardWindowButton(type)?.setAccessibilityIdentifier(nil)
        }

        window.configureNativeStandardWindowButtonsForBrowserChrome()

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }
            XCTAssertEqual(
                button.identifier?.rawValue,
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type)
            )
            XCTAssertEqual(
                button.accessibilityIdentifier(),
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type)
            )
        }
    }

    func testBrowserChromeSyncsNativeControlsWithSidebarVisibility() {
        let window = WindowChromeTestSupport.makeBrowserWindow()

        window.syncNativeStandardWindowButtonsForBrowserChrome(visibleOutsideFullScreen: false)
        assertNativeBrowserControlsHidden(window)

        window.syncNativeStandardWindowButtonsForBrowserChrome(visibleOutsideFullScreen: true)
        assertNativeBrowserControlsVisible(window)
    }

    func testBrowserChromeAppliesNativeControlOffsetsWithoutAccumulating() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let horizontalOffset = SidebarChromeMetrics.nativeTrafficLightHorizontalOffset
        let verticalOffset = SidebarChromeMetrics.nativeTrafficLightVerticalOffset
        var originalFrames: [NSWindow.ButtonType: NSRect] = [:]

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }
            originalFrames[type] = button.frame
        }

        window.syncNativeStandardWindowButtonsForBrowserChrome(
            visibleOutsideFullScreen: true,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset
        )
        window.syncNativeStandardWindowButtonsForBrowserChrome(
            visibleOutsideFullScreen: true,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset
        )

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let originalFrame = originalFrames[type]
            else {
                XCTFail("Expected standard window button for \(type).")
                return
            }
            let expectedVerticalOffset = button.superview?.isFlipped == true ? verticalOffset : -verticalOffset
            XCTAssertEqual(button.frame.origin.x, originalFrame.origin.x + horizontalOffset)
            XCTAssertEqual(button.frame.origin.y, originalFrame.origin.y + expectedVerticalOffset)
            XCTAssertEqual(button.frame.size, originalFrame.size)
        }
    }

    func testBrowserChromeKeepsNativeControlsVisibleInFullscreen() {
        let window = WindowChromeTestSupport.makeBrowserWindow()

        window.styleMask = window.styleMask.union(.fullScreen)
        window.syncNativeStandardWindowButtonsForBrowserChrome(visibleOutsideFullScreen: false)

        assertNativeBrowserControlsVisible(window)
    }

    func testMainWindowSceneUsesHiddenTitlebarStyle() throws {
        let appSource = try Self.source(named: "App/SumiApp.swift")

        XCTAssertTrue(appSource.contains(".windowStyle(.hiddenTitleBar)"))
    }

    private func assertNativeBrowserControlsHidden(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            XCTAssertTrue(button.isHidden, file: file, line: line)
            XCTAssertEqual(button.alphaValue, 0, file: file, line: line)
            XCTAssertFalse(button.isEnabled, file: file, line: line)
            XCTAssertFalse(button.isAccessibilityElement(), file: file, line: line)
        }
    }

    private func assertNativeBrowserControlsVisible(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            XCTAssertFalse(button.isHidden, file: file, line: line)
            XCTAssertEqual(button.alphaValue, 1, file: file, line: line)
            XCTAssertTrue(button.isEnabled, file: file, line: line)
            XCTAssertTrue(button.isAccessibilityElement(), file: file, line: line)
            XCTAssertEqual(
                button.identifier?.rawValue,
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type),
                file: file,
                line: line
            )
            XCTAssertEqual(
                button.accessibilityIdentifier(),
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type),
                file: file,
                line: line
            )
        }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(named relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

}
