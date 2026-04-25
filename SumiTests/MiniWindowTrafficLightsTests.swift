import AppKit
import XCTest

@testable import Sumi

@MainActor
final class MiniWindowTrafficLightsTests: XCTestCase {
    func testMiniWindowTrafficLightsContainerUsesFallbackSizeBeforeAttachingToWindow() {
        let host = MiniWindowTrafficLightsContainerView(frame: .zero)

        XCTAssertEqual(host.intrinsicContentSize.width, 60)
        XCTAssertEqual(host.intrinsicContentSize.height, 18)
    }

    func testMiniWindowTrafficLightsContainerClaimsButtonsAndUsesMiniWindowSpacing() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        var expectedMinX: CGFloat = 0
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let nativeFrame = nativeFrames?[type]
            else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === host)
            XCTAssertEqual(button.frame.minX, expectedMinX)
            XCTAssertEqual(button.frame.minY, floor((host.bounds.height - nativeFrame.height) / 2))
            XCTAssertEqual(button.frame.size, nativeFrame.size)
            expectedMinX += nativeFrame.width + 8
        }
    }

    func testMiniWindowTrafficLightsContainerRepairsHostedLayoutAfterAppearanceNotification() {
        assertMiniWindowTrafficLightsContainerRepairsHostedLayout(
            after: .sumiWindowDidChangeEffectiveAppearance,
            postsWindowObject: true
        )
    }

    func testMiniWindowTrafficLightsContainerRepairsHostedLayoutAfterApplicationAppearanceNotification() {
        assertMiniWindowTrafficLightsContainerRepairsHostedLayout(
            after: .sumiApplicationDidChangeEffectiveAppearance,
            postsWindowObject: false
        )
    }

    private func assertMiniWindowTrafficLightsContainerRepairsHostedLayout(
        after notificationName: Notification.Name,
        postsWindowObject: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        guard let closeButton = window.standardWindowButton(.closeButton) else {
            XCTFail("Expected close button.", file: file, line: line)
            return
        }
        let expectedFrame = closeButton.frame

        closeButton.frame = closeButton.frame.offsetBy(dx: 13, dy: 4)
        NotificationCenter.default.post(
            name: notificationName,
            object: postsWindowObject ? window : nil
        )

        XCTAssertTrue(closeButton.superview === host, file: file, line: line)
        XCTAssertEqual(closeButton.frame, expectedFrame, file: file, line: line)
    }

    func testMiniWindowTrafficLightsContainerDoesNotOverwriteNativeFramesFromTransientTitlebarAppearanceShift() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        guard let nativeTitlebarView = window.titlebarView else {
            XCTFail("Expected native titlebar view.")
            return
        }

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let nativeFrame = nativeFrames?[type]
            else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            button.removeFromSuperview()
            nativeTitlebarView.addSubview(button)
            button.frame = nativeFrame.offsetBy(dx: -14, dy: 0)
        }

        NotificationCenter.default.post(
            name: .sumiWindowDidChangeEffectiveAppearance,
            object: window
        )

        var expectedMinX: CGFloat = 0
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let nativeFrame = nativeFrames?[type]
            else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === host)
            XCTAssertEqual(button.frame.minX, expectedMinX)
            XCTAssertEqual(button.frame.size, nativeFrame.size)
            expectedMinX += nativeFrame.width + 8
        }

        host.prepareForRemoval()

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === nativeTitlebarView)
            XCTAssertEqual(button.frame, nativeFrames?[type])
        }
    }

    func testMiniWindowTrafficLightsContainerReclaimsButtonsAfterLateAppearanceTitlebarPass() throws {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = try XCTUnwrap(
            window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames
        )
        let nativeTitlebarView = try XCTUnwrap(window.titlebarView)

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        NotificationCenter.default.post(
            name: .sumiWindowDidChangeEffectiveAppearance,
            object: window
        )

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let nativeFrame = try XCTUnwrap(nativeFrames[type])

            button.removeFromSuperview()
            nativeTitlebarView.addSubview(button)
            button.frame = nativeFrame.offsetBy(dx: -14, dy: 0)
        }

        runMainLoopBriefly()

        assertButtonsHostedWithMiniWindowSpacing(in: host, window: window, nativeFrames: nativeFrames)
    }

    func testMiniWindowTrafficLightsContainerRepairsHostedFrameDriftFromFrameNotificationSynchronously() throws {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = try XCTUnwrap(
            window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames
        )

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        closeButton.frame = closeButton.frame.offsetBy(dx: -10, dy: 0)

        assertButtonsHostedWithMiniWindowSpacing(in: host, window: window, nativeFrames: nativeFrames)
    }

    func testMiniWindowTrafficLightsContainerReclaimsReparentedButtonsOnWindowUpdate() throws {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = try XCTUnwrap(
            window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames
        )
        let nativeTitlebarView = try XCTUnwrap(window.titlebarView)

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            button.removeFromSuperview()
            nativeTitlebarView.addSubview(button)
        }

        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)

        assertButtonsHostedWithMiniWindowSpacing(in: host, window: window, nativeFrames: nativeFrames)
    }

    func testMiniWindowTrafficLightsContainerRepairsHostedButtonStateChangedBySheetPass() throws {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = try XCTUnwrap(
            window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames
        )

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        let zoomButton = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        zoomButton.isHidden = true
        zoomButton.alphaValue = 0.2
        zoomButton.isEnabled = false
        zoomButton.isBordered = true
        zoomButton.translatesAutoresizingMaskIntoConstraints = false

        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)

        assertButtonsHostedWithMiniWindowSpacing(in: host, window: window, nativeFrames: nativeFrames)
        XCTAssertFalse(zoomButton.isHidden)
        XCTAssertEqual(zoomButton.alphaValue, 0)
        XCTAssertFalse(zoomButton.isBordered)
        XCTAssertTrue(zoomButton.translatesAutoresizingMaskIntoConstraints)

        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: window)
        runMainLoopForSheetTransition()

        XCTAssertEqual(zoomButton.alphaValue, 1)
        XCTAssertTrue(zoomButton.isEnabled)
    }

    func testMiniWindowTrafficLightsContainerShieldsHostedButtonsDuringSheetTransition() throws {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = try XCTUnwrap(
            window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames
        )

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        let initialSubviewCount = host.subviews.count
        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)

        XCTAssertGreaterThan(host.subviews.count, initialSubviewCount)
        let shieldView = try XCTUnwrap(host.subviews.last)
        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            XCTAssertFalse(button === shieldView)
        }
        assertButtonsHostedWithMiniWindowSpacing(
            in: host,
            window: window,
            nativeFrames: nativeFrames
        )

        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: window)
        runMainLoopForSheetTransition()

        XCTAssertFalse(host.subviews.contains { $0 === shieldView })
        assertButtonsHostedWithMiniWindowSpacing(
            in: host,
            window: window,
            nativeFrames: nativeFrames
        )
    }

    func testMiniWindowTrafficLightsContainerRefreshesStaleStartupFramesBeforeNormalRelayout() throws {
        let window = WindowChromeTestSupport.makePlainWindow()
        let nativeMetrics = try XCTUnwrap(window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes))
        let nativeFrames = nativeMetrics.buttonFrames
        let nativeTitlebarView = try XCTUnwrap(window.titlebarView)
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let nativeFrame = try XCTUnwrap(nativeFrames[type])
            button.frame = nativeFrame.offsetBy(dx: -14, dy: 0)
        }

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let nativeFrame = try XCTUnwrap(nativeFrames[type])
            button.removeFromSuperview()
            nativeTitlebarView.addSubview(button)
            button.frame = nativeFrame
        }

        host.needsLayout = true
        host.layoutSubtreeIfNeeded()

        var expectedMinX: CGFloat = 0
        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let nativeFrame = try XCTUnwrap(nativeFrames[type])

            XCTAssertTrue(button.superview === host)
            XCTAssertEqual(button.frame.minX, expectedMinX)
            XCTAssertEqual(button.frame.size, nativeFrame.size)
            expectedMinX += nativeFrame.width + 8
        }
    }

    func testMiniWindowTrafficLightsContainerPrepareForRemovalRestoresButtonsToTitlebar() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        let nativeTitlebarView = window.titlebarView

        host.prepareForRemoval()

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === nativeTitlebarView)
            XCTAssertEqual(button.frame, nativeFrames?[type])
        }
    }

    func testMiniWindowTrafficLightsContainerPrepareForRemovalDuringWindowCloseKeepsButtonsHosted() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames
        let nativeTitlebarView = window.titlebarView

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()
        window.prepareNativeWindowControlsForBrowserChromeWindowTeardown()
        host.prepareForRemoval()

        XCTAssertTrue(window.isBrowserChromeNativeWindowControlsTeardownInProgress)
        assertButtonsHostedWithMiniWindowSpacing(
            in: host,
            window: window,
            nativeFrames: nativeFrames ?? [:]
        )
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertFalse(window.standardWindowButton(type)?.superview === nativeTitlebarView)
        }
    }

    func testMiniWindowTrafficLightsContainerWindowWillCloseSuppressesTitlebarRestore() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )
        let nativeFrames = window.nativeWindowControlsMetrics(for: WindowChromeTestSupport.standardButtonTypes)?.buttonFrames

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        host.prepareForRemoval()

        XCTAssertTrue(window.isBrowserChromeNativeWindowControlsTeardownInProgress)
        assertButtonsHostedWithMiniWindowSpacing(
            in: host,
            window: window,
            nativeFrames: nativeFrames ?? [:]
        )
    }

    private func assertButtonsHostedWithMiniWindowSpacing(
        in host: MiniWindowTrafficLightsContainerView,
        window: NSWindow,
        nativeFrames: [NSWindow.ButtonType: NSRect],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var expectedMinX: CGFloat = 0

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let nativeFrame = nativeFrames[type]
            else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            XCTAssertTrue(button.superview === host, file: file, line: line)
            XCTAssertEqual(button.frame.minX, expectedMinX, file: file, line: line)
            XCTAssertEqual(
                button.frame.minY,
                floor((host.bounds.height - nativeFrame.height) / 2),
                file: file,
                line: line
            )
            XCTAssertEqual(button.frame.size, nativeFrame.size, file: file, line: line)
            expectedMinX += nativeFrame.width + 8
        }
    }

    private func runMainLoopBriefly() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func runMainLoopForSheetTransition() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
}
