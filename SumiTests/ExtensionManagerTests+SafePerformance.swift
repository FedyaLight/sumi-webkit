import AppKit
import Foundation
import WebKit
import XCTest
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerTests {
    func testReleaseExternallyConnectableRuntimeClearsWebViewState() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let webView = WKWebView(
            frame: .zero,
            configuration: harness.browserConfiguration.cacheOptimizedWebViewConfiguration()
        )
        let webViewID = ObjectIdentifier(webView)
        let pageURL = try XCTUnwrap(
            URL(string: "https://accounts.example.com/index.html")
        )
        let requestID = UUID()
        var resolvedReply: Any?
        var resolvedError: String?

        manager.updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: pageURL
        )
        manager.ecRegistry.addRequest(
            PendingExternallyConnectableNativeRequest(
                id: requestID,
                extensionId: "fixture.extension",
                webViewIdentifier: webViewID,
                pageURLString: pageURL.absoluteString
            ) { reply, errorMessage in
                resolvedReply = reply
                resolvedError = errorMessage
            }
        )

        manager.releaseExternallyConnectableRuntime(
            for: webView,
            reason: "WebView cleanup"
        )

        XCTAssertNil(resolvedReply)
        XCTAssertEqual(
            resolvedError,
            "Extension request canceled because WebView cleanup"
        )
        XCTAssertTrue(manager.ecRegistry.allRequestIDs.isEmpty)
        XCTAssertNil(manager.ecRegistry.trackedPageURL(for: webView))
        XCTAssertFalse(manager.ecRegistry.hasTrackedState(for: webView))
    }

    func testRequiredBackgroundWakeCoalescesInFlightRequestsAndSkipsLoadedContext()
        async throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 2,
                "name": "Wake Fixture",
                "version": "1.0",
                "background": [
                    "scripts": ["background.js"],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try "console.log('background');\n".write(
            to: extensionRoot.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.extensionContexts["wake.fixture"] = extensionContext

        var wakeCount = 0
        var firstWakeContinuation: CheckedContinuation<Void, Never>?
        var hooks = manager.testHooks
        hooks.backgroundContentWake = { extensionId, _ in
            XCTAssertEqual(extensionId, "wake.fixture")
            wakeCount += 1

            if wakeCount == 1 {
                await withCheckedContinuation { continuation in
                    firstWakeContinuation = continuation
                }
            }
        }
        manager.testHooks = hooks

        async let firstWake = manager.ensureBackgroundAvailableIfRequired(
            for: webExtension,
            context: extensionContext,
            reason: .startup
        )
        async let secondWake = manager.ensureBackgroundAvailableIfRequired(
            for: webExtension,
            context: extensionContext,
            reason: .reload
        )

        try await waitUntil(timeout: 1) {
            wakeCount == 1
                && manager.debugRuntimeStateSnapshot.backgroundWakeInFlightIDs
                    == ["wake.fixture"]
                && manager.debugRuntimeStateSnapshot.backgroundRuntimeStatesByExtensionID[
                    "wake.fixture"
                ] == .wakeInFlight
        }

        firstWakeContinuation?.resume()
        _ = try await firstWake
        _ = try await secondWake

        try await waitUntil(timeout: 1) {
            let snapshot = manager.debugRuntimeStateSnapshot
            return snapshot.backgroundWakeInFlightIDs.isEmpty
                && snapshot.backgroundContentLoadedIDs == ["wake.fixture"]
                && snapshot.backgroundRuntimeStatesByExtensionID["wake.fixture"] == .loaded
        }

        _ = try await manager.ensureBackgroundAvailableIfRequired(
            for: webExtension,
            context: extensionContext,
            reason: .externallyConnectable
        )

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(wakeCount, 1)
        XCTAssertEqual(
            manager.debugRuntimeStateSnapshot.runtimeMetricsByExtensionID[
                "wake.fixture"
            ]?.backgroundWakeCount,
            1
        )
    }

    func testRequiredBackgroundWakeStateClearsOnRuntimeTeardown()
        async throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 2,
                "name": "Wake Fixture",
                "version": "1.0",
                "background": [
                    "scripts": ["background.js"],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try "console.log('background');\n".write(
            to: extensionRoot.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.extensionContexts["wake.fixture"] = extensionContext

        var wakeCount = 0
        var hooks = manager.testHooks
        hooks.backgroundContentWake = { extensionId, _ in
            XCTAssertEqual(extensionId, "wake.fixture")
            wakeCount += 1
        }
        manager.testHooks = hooks

        _ = try await manager.ensureBackgroundAvailableIfRequired(
            for: webExtension,
            context: extensionContext,
            reason: .startup
        )

        try await waitUntil(timeout: 1) {
            wakeCount == 1
                && manager.debugRuntimeStateSnapshot.backgroundContentLoadedIDs
                    == ["wake.fixture"]
        }

        manager.tearDownExtensionRuntimeState(
            for: "wake.fixture",
            removeUIState: false
        )
        XCTAssertFalse(
            manager.debugRuntimeStateSnapshot.backgroundContentLoadedIDs
                .contains("wake.fixture")
        )

        manager.extensionContexts["wake.fixture"] = extensionContext
        _ = try await manager.ensureBackgroundAvailableIfRequired(
            for: webExtension,
            context: extensionContext,
            reason: .reload
        )

        try await waitUntil(timeout: 1) {
            wakeCount == 2
        }
    }

    func testRequiredBackgroundWakeTracksLoadFailureState()
        async throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 2,
                "name": "Wake Failure Fixture",
                "version": "1.0",
                "background": [
                    "scripts": ["background.js"],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try "console.log('background');\n".write(
            to: extensionRoot.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.extensionContexts["wake.fixture"] = extensionContext

        enum WakeFailure: Error {
            case failed
        }

        var hooks = manager.testHooks
        hooks.backgroundContentWake = { _, _ in
            throw WakeFailure.failed
        }
        manager.testHooks = hooks

        do {
            _ = try await manager.ensureBackgroundAvailableIfRequired(
                for: webExtension,
                context: extensionContext,
                reason: .startup
            )
            XCTFail("Required wake should surface load failures")
        } catch {
            XCTAssertTrue(error is WakeFailure)
        }

        let snapshot = manager.debugRuntimeStateSnapshot
        XCTAssertEqual(snapshot.backgroundWakeInFlightIDs, [])
        XCTAssertEqual(snapshot.backgroundContentFailedIDs, ["wake.fixture"])
        XCTAssertEqual(
            snapshot.backgroundRuntimeStatesByExtensionID["wake.fixture"],
            .loadFailed
        )
        XCTAssertEqual(
            snapshot.runtimeMetricsByExtensionID["wake.fixture"]?.lastBackgroundWakeFailed,
            true
        )
    }

    func testPopupAndToolbarActionPathsDoNotInvokeBackgroundWakeHelpers() throws {
        let workspaceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let popupDelegateSource = try String(
            contentsOf: workspaceRoot.appendingPathComponent(
                "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
            ),
            encoding: .utf8
        )
        let toolbarActionSource = try String(
            contentsOf: workspaceRoot.appendingPathComponent(
                "Sumi/Components/Extensions/ExtensionActionView.swift"
            ),
            encoding: .utf8
        )

        for source in [popupDelegateSource, toolbarActionSource] {
            XCTAssertFalse(source.contains("ensureBackgroundAvailableIfRequired("))
            XCTAssertFalse(source.contains("startBackgroundContentDefensively("))
        }
    }

    func testExtensionIconCacheReusesImageUntilModificationDateChanges() throws {
        let cache = ExtensionIconCache()
        let directoryURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let iconURL = directoryURL.appendingPathComponent("icon.png")
        try Data([0]).write(to: iconURL)

        var loadCount = 0
        cache.imageLoader = { _ in
            loadCount += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        }

        let firstImage = try XCTUnwrap(
            cache.image(extensionId: "icon.fixture", iconPath: iconURL.path)
        )
        let secondImage = try XCTUnwrap(
            cache.image(extensionId: "icon.fixture", iconPath: iconURL.path)
        )

        XCTAssertEqual(loadCount, 1)
        XCTAssertTrue(firstImage === secondImage)

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: iconURL.path
        )

        let thirdImage = try XCTUnwrap(
            cache.image(extensionId: "icon.fixture", iconPath: iconURL.path)
        )

        XCTAssertEqual(loadCount, 2)
        XCTAssertFalse(firstImage === thirdImage)
    }

    func testSetActionAnchorReusesObserverForSameViewAndPrunesStaleAnchors()
        throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "anchor.fixture"
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        let staleView = NSView(frame: NSRect(x: 20, y: 0, width: 16, height: 16))

        manager.setActionAnchor(for: extensionId, anchorView: view)
        let firstToken = try XCTUnwrap(
            manager.anchorObserverTokens[extensionId]?[ObjectIdentifier(view)]
        )

        manager.setActionAnchor(for: extensionId, anchorView: view)
        let secondToken = try XCTUnwrap(
            manager.anchorObserverTokens[extensionId]?[ObjectIdentifier(view)]
        )

        XCTAssertEqual(manager.anchorObserverTokens[extensionId]?.count, 1)
        XCTAssertEqual(
            ObjectIdentifier(firstToken as AnyObject),
            ObjectIdentifier(secondToken as AnyObject)
        )

        manager.setActionAnchor(for: extensionId, anchorView: staleView)
        XCTAssertEqual(manager.anchorObserverTokens[extensionId]?.count, 1)
        XCTAssertNil(manager.anchorObserverTokens[extensionId]?[ObjectIdentifier(view)])

        manager.setActionAnchor(for: extensionId, anchorView: view)

        XCTAssertEqual(manager.anchorObserverTokens[extensionId]?.count, 1)
        XCTAssertEqual(manager.actionAnchors[extensionId]?.count, 1)
        XCTAssertNil(
            manager.anchorObserverTokens[extensionId]?[ObjectIdentifier(staleView)]
        )
    }

    func testBrowserExtensionSurfaceStoreReceivesInstalledExtensionsAfterMutation()
        async throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let store = BrowserExtensionSurfaceStore(extensionManager: manager)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Projection Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json")
        )
        let record = makeInstalledExtensionRecord(
            id: "projection.fixture",
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )

        manager.debugReplaceInstalledExtensions([record])

        XCTAssertTrue(store.installedExtensions.isEmpty)
        try await waitUntil(timeout: 1.0) {
            store.installedExtensions.map(\.id) == ["projection.fixture"]
        }
        XCTAssertEqual(store.installedExtensions.map(\.id), ["projection.fixture"])
    }

    func testSettingsViewStateDeferralSchedulesMutationAsynchronously() async throws {
        var events: [String] = []

        events.append("before")
        SettingsViewStateDeferral.schedule {
            events.append("scheduled")
        }
        events.append("after")

        XCTAssertEqual(events, ["before", "after"])
        try await waitUntil(timeout: 1.0) {
            events == ["before", "after", "scheduled"]
        }
    }

    func testBrowserExtensionSurfaceStoreReloadPublishesAsynchronously() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let store = BrowserExtensionSurfaceStore(extensionManager: manager)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Reload Projection Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json")
        )
        let record = makeInstalledExtensionRecord(
            id: "reload.projection.fixture",
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )

        manager.debugReplaceInstalledExtensions([record])
        XCTAssertTrue(store.installedExtensions.isEmpty)

        store.reload()
        XCTAssertTrue(store.installedExtensions.isEmpty)

        try await waitUntil(timeout: 1.0) {
            store.installedExtensions.map(\.id) == ["reload.projection.fixture"]
        }
    }
}
