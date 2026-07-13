import AppKit
@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowServiceTests: XCTestCase {
    func testTrackingWindowExposesWindowAndExtensionIDs() {
        let service = ExtensionOptionsWindowService()
        let window = NSWindow()

        service.trackPresentedWindow(window, delegate: nil, for: "extension-a")

        XCTAssertIdentical(service.windows["extension-a"], window)
        XCTAssertEqual(service.extensionIDs, ["extension-a"])
    }

    func testCleanupWindowRemovesTrackedWindow() {
        let service = ExtensionOptionsWindowService()
        let window = NSWindow()
        service.trackPresentedWindow(window, delegate: nil, for: "extension-a")

        service.cleanupWindow(for: "extension-a", shouldOrderOut: true)

        XCTAssertTrue(service.windows.isEmpty)
        XCTAssertTrue(service.extensionIDs.isEmpty)
    }

    func testCleanupOfStaleWindowPreservesRegisteredReplacementForSameExtension() {
        let service = ExtensionOptionsWindowService()
        let staleWindow = NSWindow()
        let replacementWindow = NSWindow()

        service.trackPresentedWindow(
            staleWindow,
            delegate: nil,
            for: "extension-a"
        )
        service.trackPresentedWindow(
            replacementWindow,
            delegate: nil,
            for: "extension-a"
        )

        service.cleanupWindow(
            for: "extension-a",
            window: staleWindow,
            shouldOrderOut: true
        )

        XCTAssertIdentical(service.windows["extension-a"], replacementWindow)
        XCTAssertEqual(service.extensionIDs, ["extension-a"])
    }

    func testStaleWebViewCloseWithoutWindowPreservesRegisteredReplacement() {
        let service = ExtensionOptionsWindowService()
        let staleWebView = WKWebView()
        var staleWindow: NSWindow? = NSWindow()
        staleWindow?.contentView = staleWebView
        let delegate = ExtensionOptionsWindowDelegate(
            extensionId: "extension-a",
            service: service,
            webView: staleWebView,
            window: staleWindow!
        )
        service.trackPresentedWindow(
            staleWindow!,
            delegate: delegate,
            for: "extension-a"
        )

        let replacementWindow = NSWindow()
        service.trackPresentedWindow(
            replacementWindow,
            delegate: nil,
            for: "extension-a"
        )
        staleWindow?.contentView = nil
        staleWindow = nil
        XCTAssertNil(staleWebView.window)

        delegate.webViewDidClose(staleWebView)

        XCTAssertIdentical(service.windows["extension-a"], replacementWindow)
        XCTAssertEqual(service.extensionIDs, ["extension-a"])
    }

    func testCloseAllWindowsRemovesAllTrackedWindows() {
        let service = ExtensionOptionsWindowService()
        service.trackPresentedWindow(NSWindow(), delegate: nil, for: "extension-a")
        service.trackPresentedWindow(NSWindow(), delegate: nil, for: "extension-b")

        service.closeAllWindows()

        XCTAssertTrue(service.windows.isEmpty)
        XCTAssertTrue(service.extensionIDs.isEmpty)
    }

    func testPreferredOptionsPageURLKeepsManifestFileAheadOfComputedManifestURL() throws {
        let extensionRoot = try makeExtensionRoot()
        let optionsURL = try writeOptionsPage("options.html", in: extensionRoot)
        let computedManifestURL = try XCTUnwrap(
            URL(string: "webkit-extension://extension-a/options.html")
        )

        let resolvedURL = ExtensionOptionsWindowService.preferredOptionsPageURL(
            sdkURL: nil,
            manifestURL: computedManifestURL,
            persistedPath: nil,
            manifest: ["options_ui": ["page": "options.html"]],
            extensionRoot: extensionRoot,
            extensionId: "extension-a"
        )

        XCTAssertEqual(resolvedURL, optionsURL)
    }

    func testPreferredOptionsPageURLFallsBackToComputedManifestURLAfterInvalidSDKURL() throws {
        let extensionRoot = try makeExtensionRoot()
        _ = try writeOptionsPage("persisted.html", in: extensionRoot)
        let invalidSDKURL = FileManager.default.temporaryDirectory
            .appending(path: "outside-\(UUID().uuidString)")
            .appending(path: "options.html")
        let computedManifestURL = try XCTUnwrap(
            URL(string: "webkit-extension://extension-a/options.html")
        )

        let resolvedURL = ExtensionOptionsWindowService.preferredOptionsPageURL(
            sdkURL: invalidSDKURL,
            manifestURL: computedManifestURL,
            persistedPath: "persisted.html",
            manifest: [:],
            extensionRoot: extensionRoot,
            extensionId: "extension-a"
        )

        XCTAssertEqual(resolvedURL, computedManifestURL)
    }

    func testPreferredOptionsPageURLFallsBackToPersistedPathAfterInvalidSDKURL() throws {
        let extensionRoot = try makeExtensionRoot()
        let persistedURL = try writeOptionsPage("persisted.html", in: extensionRoot)
        let invalidSDKURL = FileManager.default.temporaryDirectory
            .appending(path: "outside-\(UUID().uuidString)")
            .appending(path: "options.html")

        let resolvedURL = ExtensionOptionsWindowService.preferredOptionsPageURL(
            sdkURL: invalidSDKURL,
            manifestURL: nil,
            persistedPath: "persisted.html",
            manifest: [:],
            extensionRoot: extensionRoot,
            extensionId: "extension-a"
        )

        XCTAssertEqual(resolvedURL, persistedURL)
    }

    private func makeExtensionRoot() throws -> URL {
        let extensionRoot = FileManager.default.temporaryDirectory
            .appending(path: "ExtensionOptionsWindowServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: extensionRoot,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            guard FileManager.default.fileExists(atPath: extensionRoot.path) else {
                return
            }
            do {
                try FileManager.default.removeItem(at: extensionRoot)
            } catch {
                XCTFail("Failed to remove temporary extension root: \(error)")
            }
        }
        return extensionRoot.resolvingSymlinksInPath().standardizedFileURL
    }

    private func writeOptionsPage(
        _ relativePath: String,
        in extensionRoot: URL
    ) throws -> URL {
        let optionsURL = extensionRoot.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: optionsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("<html></html>".utf8).write(to: optionsURL)
        return optionsURL.resolvingSymlinksInPath().standardizedFileURL
    }
}
