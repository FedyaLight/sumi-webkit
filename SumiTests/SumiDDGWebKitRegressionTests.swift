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
            "makeTouchBar()",
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

    func testWebViewContainerLayoutDoesNotReparentDisplayedContent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift"
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
        let end = try XCTUnwrap(source.range(of: "// Removed SwiftUI contextMenu", range: start..<source.endIndex))
            .lowerBound
        let liveWebViewPath = String(source[start..<end])

        XCTAssertFalse(liveWebViewPath.contains(".browserContentSurface("))
        XCTAssertFalse(liveWebViewPath.contains(".clipShape("))
        XCTAssertFalse(liveWebViewPath.contains(".shadow("))
        XCTAssertTrue(liveWebViewPath.contains(".background(contentSurfaceBackground)"))
    }

    func testWebsiteCompositorPaneContainersStayPlainNSViews() throws {
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

        XCTAssertFalse(containerSource.contains("wantsLayer = true"))
        XCTAssertFalse(containerSource.contains("masksToBounds"))
        XCTAssertFalse(containerSource.contains("cornerRadius"))
        XCTAssertFalse(containerSource.contains("override var isOpaque"))
    }
}
