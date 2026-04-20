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
        XCTAssertEqual(window.toolbar?.identifier, SumiBrowserChromeConfiguration.toolbarIdentifier)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertTrue(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertNotNil(window.titlebarView)

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.alphaValue, 1)
            XCTAssertTrue(button.isEnabled)
            XCTAssertNotNil(window.cachedNativeWindowButtonFrame(for: type))
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
        XCTAssertTrue(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, SumiBrowserWindowShellConfiguration.defaultContentSize)

        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertNotNil(window.cachedNativeWindowButtonFrame(for: type))
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
        XCTAssertTrue(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertNotNil(window.titlebarView)

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.alphaValue, 1)
            XCTAssertTrue(button.isEnabled)
            XCTAssertNotNil(window.cachedNativeWindowButtonFrame(for: type))
        }
    }
}
