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
        let metrics = window.nativeWindowControlsMetrics()

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.toolbar?.identifier, SumiBrowserChromeConfiguration.toolbarIdentifier)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertNotNil(window.titlebarView)
        XCTAssertNotNil(metrics)
        XCTAssertGreaterThan(metrics?.buttonGroupWidth ?? 0, 0)
        XCTAssertGreaterThan(metrics?.buttonGroupRect.minX ?? 0, 0)
        XCTAssertEqual(metrics?.normalizedButtonFrames[.closeButton]?.minX, 0)

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.alphaValue, 1)
            XCTAssertTrue(button.isEnabled)
            XCTAssertEqual(
                button.accessibilityIdentifier(),
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type)
            )
            XCTAssertEqual(metrics?.buttonFrames[type], button.frame)
        }
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

        XCTAssertTrue(window is SumiBrowserWindow)
        XCTAssertTrue(windowState.window === window)
        XCTAssertEqual(window.toolbar?.identifier, SumiBrowserChromeConfiguration.toolbarIdentifier)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, SumiBrowserWindowShellConfiguration.defaultContentSize)
        XCTAssertNotNil(window.nativeWindowControlsMetrics())

        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertEqual(
                window.standardWindowButton(type)?.accessibilityIdentifier(),
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type)
            )
        }
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

        for type in WindowChromeTestSupport.standardButtonTypes {
            window.standardWindowButton(type)?.isHidden = true
            window.standardWindowButton(type)?.alphaValue = 0.2
            window.standardWindowButton(type)?.isEnabled = false
        }

        promoteToSumiBrowserWindowIfNeeded(window)
        WindowChromeTestSupport.retain(window)

        XCTAssertTrue(window is SumiBrowserWindow)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.toolbar?.identifier, SumiBrowserChromeConfiguration.toolbarIdentifier)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertNotNil(window.titlebarView)
        XCTAssertNotNil(window.nativeWindowControlsMetrics())

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.alphaValue, 1)
            XCTAssertTrue(button.isEnabled)
            XCTAssertEqual(
                button.accessibilityIdentifier(),
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type)
            )
        }
    }

    func testNativeWindowControlsMetricsRefreshLiveButtonFrames() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let initialMetrics = try XCTUnwrap(window.nativeWindowControlsMetrics())

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }
            button.frame = button.frame.offsetBy(dx: 16, dy: 0)
        }

        let refreshedMetrics = try XCTUnwrap(window.nativeWindowControlsMetrics())

        XCTAssertEqual(
            refreshedMetrics.buttonGroupRect.minX,
            initialMetrics.buttonGroupRect.minX + 16
        )
        XCTAssertEqual(
            refreshedMetrics.buttonGroupWidth,
            initialMetrics.buttonGroupWidth
        )
        for type in WindowChromeTestSupport.standardButtonTypes {
            let initialMinX = initialMetrics.buttonFrames[type]?.minX
            XCTAssertEqual(
                refreshedMetrics.buttonFrames[type]?.minX,
                initialMinX.map { $0 + 16 }
            )
            XCTAssertEqual(
                refreshedMetrics.normalizedButtonFrames[type],
                initialMetrics.normalizedButtonFrames[type]
            )
        }
    }

    func testNativeWindowControlsMetricsDoNotTreatContentHostAsTitlebar() throws {
        let window = WindowChromeTestSupport.makePlainWindow()
        let nativeTitlebarView = try XCTUnwrap(window.standardWindowButton(.closeButton)?.superview)
        let contentView = try XCTUnwrap(window.contentView)
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 28))

        contentView.addSubview(hostView)
        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            button.removeFromSuperview()
            hostView.addSubview(button)
        }

        XCTAssertNil(window.captureNativeWindowControlsMetricsIfButtonsInTitlebar())
        XCTAssertNil(window.titlebarView)

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            button.removeFromSuperview()
            nativeTitlebarView.addSubview(button)
        }

        XCTAssertNotNil(window.captureNativeWindowControlsMetricsIfButtonsInTitlebar())
        XCTAssertTrue(window.titlebarView === nativeTitlebarView)
    }
}
