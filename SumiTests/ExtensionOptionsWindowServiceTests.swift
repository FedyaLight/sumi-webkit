import AppKit
@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowServiceTests: XCTestCase {
    func testTrackingWindowExposesWindowAndExtensionIDs() {
        let service = ExtensionOptionsWindowService()
        let window = NSWindow()

        let receipt = service.trackPresentedWindow(
            window,
            delegate: nil,
            for: "extension-a"
        )

        XCTAssertIdentical(service.windows["extension-a"], window)
        XCTAssertEqual(service.extensionIDs, ["extension-a"])
        XCTAssertEqual(receipt.extensionID, "extension-a")
    }

    func testCleanupWindowRemovesTrackedWindow() {
        let service = ExtensionOptionsWindowService()
        let window = NSWindow()
        let receipt = service.trackPresentedWindow(
            window,
            delegate: nil,
            for: "extension-a"
        )

        service.retire(receipt, shouldOrderOut: true)

        XCTAssertTrue(service.windows.isEmpty)
        XCTAssertTrue(service.extensionIDs.isEmpty)
    }

    func testCleanupOfStaleWindowPreservesRegisteredReplacementForSameExtension() {
        let service = ExtensionOptionsWindowService()
        let staleWindow = NSWindow()
        let replacementWindow = NSWindow()

        let staleReceipt = service.trackPresentedWindow(
            staleWindow,
            delegate: nil,
            for: "extension-a"
        )
        service.trackPresentedWindow(
            replacementWindow,
            delegate: nil,
            for: "extension-a"
        )

        service.retire(
            staleReceipt,
            window: staleWindow,
            shouldOrderOut: true
        )

        XCTAssertIdentical(service.windows["extension-a"], replacementWindow)
        XCTAssertEqual(service.extensionIDs, ["extension-a"])
    }

    func testSupersededReceiptCannotRetireReregisteredSameWindowIdentity() {
        let service = ExtensionOptionsWindowService()
        let window = NSWindow()
        let webView = WKWebView()
        window.contentView = webView
        let firstDelegate = ExtensionOptionsWindowDelegate(
            service: service,
            webView: webView,
            window: window
        )
        let first = service.trackPresentedWindow(
            window,
            webView: webView,
            delegate: firstDelegate,
            for: "extension-a"
        )
        firstDelegate.bind(first)
        let secondDelegate = ExtensionOptionsWindowDelegate(
            service: service,
            webView: webView,
            window: window
        )
        webView.uiDelegate = secondDelegate
        window.delegate = secondDelegate
        let second = service.trackPresentedWindow(
            window,
            webView: webView,
            delegate: secondDelegate,
            for: "extension-a"
        )
        secondDelegate.bind(second)

        XCTAssertNotEqual(first.registrationID, second.registrationID)

        service.retire(
            first,
            window: window,
            webView: webView,
            shouldOrderOut: true
        )

        XCTAssertIdentical(service.windows["extension-a"], window)
        XCTAssertEqual(service.extensionIDs, ["extension-a"])
        XCTAssertIdentical(window.contentView, webView)
        XCTAssertIdentical(window.delegate as AnyObject?, secondDelegate)
        XCTAssertIdentical(webView.uiDelegate as AnyObject?, secondDelegate)
    }

    func testExactReceiptRetiresOnlyItsRegistration() {
        let service = ExtensionOptionsWindowService()
        let firstWindow = NSWindow()
        let secondWindow = NSWindow()
        let first = service.trackPresentedWindow(
            firstWindow,
            delegate: nil,
            for: "extension-a"
        )
        let second = service.trackPresentedWindow(
            secondWindow,
            delegate: nil,
            for: "extension-b"
        )

        service.retire(first, shouldOrderOut: true)

        XCTAssertNil(service.windows["extension-a"])
        XCTAssertIdentical(service.windows["extension-b"], secondWindow)
        XCTAssertEqual(service.extensionIDs, [second.extensionID])
    }

    func testStaleWebViewCloseWithoutWindowPreservesRegisteredReplacement() {
        let service = ExtensionOptionsWindowService()
        let staleWebView = WKWebView()
        var staleWindow: NSWindow? = NSWindow()
        staleWindow?.contentView = staleWebView
        let delegate = ExtensionOptionsWindowDelegate(
            service: service,
            webView: staleWebView,
            window: staleWindow!
        )
        let staleReceipt = service.trackPresentedWindow(
            staleWindow!,
            webView: staleWebView,
            delegate: delegate,
            for: "extension-a"
        )
        delegate.bind(staleReceipt)

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

    func testOptionsPageResolutionRequiresExactSDKContextAndPackageFile()
        async throws {
        let extensionRoot = try makeExtensionRoot()
        let optionsURL = try writeOptionsPage("options.html", in: extensionRoot)
        try writeManifest(optionsPage: "options.html", in: extensionRoot)
        let webExtension = try await WKWebExtension(
            resourceBaseURL: extensionRoot
        )
        let context = WKWebExtensionContext(for: webExtension)
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        try controller.load(context)
        defer { try? controller.unload(context) }

        let resolution = ExtensionOptionsPageResolver.resolve(
            context: context,
            controller: controller,
            installedExtension: installedExtension(
                packageRoot: extensionRoot,
                optionsPagePath: "options.html"
            )
        )

        XCTAssertEqual(resolution?.presentationURL, context.optionsPageURL)
        XCTAssertEqual(resolution?.packageURL, optionsURL)
        XCTAssertEqual(resolution?.extensionRoot, extensionRoot)
    }

    func testOptionsPageResolutionDoesNotFallbackWhenControllerRejectsSDKURL()
        async throws {
        let extensionRoot = try makeExtensionRoot()
        _ = try writeOptionsPage("options.html", in: extensionRoot)
        try writeManifest(optionsPage: "options.html", in: extensionRoot)
        let webExtension = try await WKWebExtension(
            resourceBaseURL: extensionRoot
        )
        let context = WKWebExtensionContext(for: webExtension)
        let rejectingController = WKWebExtensionController(
            configuration: .nonPersistent()
        )

        let resolution = ExtensionOptionsPageResolver.resolve(
            context: context,
            controller: rejectingController,
            installedExtension: installedExtension(
                packageRoot: extensionRoot,
                optionsPagePath: "options.html"
            )
        )

        XCTAssertNil(resolution)
    }

    private func writeManifest(optionsPage: String, in root: URL) throws {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Options Test",
            "version": "1.0",
            "options_page": optionsPage,
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: root.appending(path: "manifest.json")
        )
    }

    private func installedExtension(
        packageRoot: URL,
        optionsPagePath: String
    ) -> InstalledExtension {
        InstalledExtension(
            id: "extension-a",
            name: "Options Test",
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: .distantPast,
            lastUpdateDate: .distantPast,
            packagePath: packageRoot.path,
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: "source",
            manifestRootFingerprint: "manifest",
            sourceBundlePath: packageRoot.path,
            optionsPagePath: optionsPagePath,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: true,
            hasContentScripts: false,
            hasExtensionPages: true,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: true,
                hasExtensionPages: true
            ),
            manifest: ["options_page": optionsPagePath]
        )
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
