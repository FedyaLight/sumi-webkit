import AppKit
@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowOwnerTests: XCTestCase {
    func testTrackingWindowExposesWindowAndExtensionIDs() {
        let owner = ExtensionOptionsWindowOwner()
        let window = NSWindow()

        owner.trackPresentedWindow(window, delegate: nil, for: "extension-a")

        XCTAssertIdentical(owner.windows["extension-a"], window)
        XCTAssertEqual(owner.extensionIDs, ["extension-a"])
    }

    func testCleanupWindowRemovesTrackedWindow() {
        let owner = ExtensionOptionsWindowOwner()
        let window = NSWindow()
        owner.trackPresentedWindow(window, delegate: nil, for: "extension-a")

        owner.cleanupWindow(for: "extension-a", shouldOrderOut: true)

        XCTAssertTrue(owner.windows.isEmpty)
        XCTAssertTrue(owner.extensionIDs.isEmpty)
    }

    func testCloseAllWindowsRemovesAllTrackedWindows() {
        let owner = ExtensionOptionsWindowOwner()
        owner.trackPresentedWindow(NSWindow(), delegate: nil, for: "extension-a")
        owner.trackPresentedWindow(NSWindow(), delegate: nil, for: "extension-b")

        owner.closeAllWindows()

        XCTAssertTrue(owner.windows.isEmpty)
        XCTAssertTrue(owner.extensionIDs.isEmpty)
    }

    func testPreferredOptionsPageURLKeepsManifestFileAheadOfComputedManifestURL() throws {
        let extensionRoot = try makeExtensionRoot()
        let optionsURL = try writeOptionsPage("options.html", in: extensionRoot)
        let computedManifestURL = try XCTUnwrap(
            URL(string: "webkit-extension://extension-a/options.html")
        )

        let resolvedURL = ExtensionOptionsWindowOwner.preferredOptionsPageURL(
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

        let resolvedURL = ExtensionOptionsWindowOwner.preferredOptionsPageURL(
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

        let resolvedURL = ExtensionOptionsWindowOwner.preferredOptionsPageURL(
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
            .appending(path: "ExtensionOptionsWindowOwnerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
