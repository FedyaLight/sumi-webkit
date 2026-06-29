import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionActionPopupRuntimeTests: XCTestCase {
    func testRequestExtensionRuntimeAndWaitHonorsProfileReadinessWithoutForceReload() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Popup Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )

        manager.runtimeState = .idle
        manager.markExtensionRuntimeReadyIfProfileContextsLoaded(for: profile.id)

        let runtimeReady = await manager.requestExtensionRuntimeAndWait(
            reason: .extensionAction,
            profileId: profile.id
        )
        XCTAssertTrue(
            runtimeReady,
            "Profile-scoped readiness should satisfy the action-popup runtime gate without a destructive reload"
        )
        XCTAssertEqual(manager.runtimeState, .ready)
    }

    func testProfileExtensionRuntimeReadinessTracksMissingContextsPerProfile() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ProfileIsolationExtension"
        )
        _ = try await manager.enableExtension(installed.id)

        XCTAssertTrue(
            manager.isProfileExtensionRuntimeReady(for: profileA.id),
            "Enabled extension should be ready in the profile where it was enabled"
        )
        let profileAContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profileA.id)
        )
        XCTAssertFalse(
            manager.isProfileExtensionRuntimeReady(for: profileB.id),
            "A different profile must not inherit another profile's loaded context"
        )

        await manager.ensureEnabledExtensionsLoaded(for: profileB.id)
        XCTAssertTrue(
            manager.isProfileExtensionRuntimeReady(for: profileB.id),
            "Profile B should load its own isolated context on demand"
        )
        XCTAssertIdentical(
            manager.getExtensionContext(for: installed.id, profileId: profileA.id),
            profileAContext,
            "Loading another profile must not reset an already loaded profile context"
        )
        XCTAssertNotIdentical(
            manager.getExtensionContext(for: installed.id, profileId: profileA.id),
            manager.getExtensionContext(for: installed.id, profileId: profileB.id),
            "Profile A and Profile B must not share the same WKWebExtensionContext instance"
        )
    }

    func testImportedSafariAppexCanOpenActionPopupAfterEnable() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Raindrop Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Raindrop",
            manifestVersion: 3
        )
        _ = try await manager.enableExtension(installed.id)

        let tab = Tab(url: URL(string: "https://example.com/")!)
        tab.profileId = profile.id

        let result = await manager.openActionPopupFromURLHub(
            extensionId: installed.id,
            currentTab: tab
        )

        let blocker = result.blocker
        XCTAssertTrue(
            result.opened
                || blocker == BrowserExtensionActionPopupBlocker.actionDisabled
                || blocker == BrowserExtensionActionPopupBlocker.noActionPopup,
            "Unexpected popup blocker: \(blocker?.rawValue ?? "nil") message=\(result.message) diagnostics=\(result.diagnostics)"
        )
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.runtimeUnavailable)
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.runtimeLoadFailed)
    }

    func testRaindropStyleIframePopupPackageReachesWebKitPopupGate() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Raindrop Iframe Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Raindrop Iframe",
            packageStyle: .raindropIframePopup
        )
        _ = try await manager.enableExtension(installed.id)

        XCTAssertEqual(installed.defaultPopupPath, "assets/action_in_iframe.html")
        XCTAssertTrue(installed.hasAction)
        XCTAssertFalse(installed.hasContentScripts)

        let tab = Tab(url: URL(string: "https://example.com/")!)
        tab.profileId = profile.id

        let result = await manager.openActionPopupFromURLHub(
            extensionId: installed.id,
            currentTab: tab
        )

        let blocker = result.blocker
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.currentPagePermissionMissing)
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.moduleWorkerUnsupported)
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.runtimeUnavailable)
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.runtimeLoadFailed)
        XCTAssertNotEqual(blocker, BrowserExtensionActionPopupBlocker.contextUnavailable)
    }

    func testURLHubActiveTabGrantUsesClickedTabBeforePopupDispatch() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "ActiveTab Popup Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ActiveTab Popup",
            packageStyle: .raindropIframePopup
        )
        _ = try await manager.enableExtension(installed.id)

        let clickedTab = Tab(url: URL(string: "https://clicked.example/path")!)
        clickedTab.profileId = profile.id
        let laterActiveURL = URL(string: "https://later.example/")!

        let result = await manager.openActionPopupFromURLHub(
            extensionId: installed.id,
            currentTab: clickedTab
        )

        let extensionContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        XCTAssertEqual(
            extensionContext.permissionStatus(for: clickedTab.url),
            .grantedExplicitly,
            "The URL-hub click must grant activeTab access to the concrete clicked tab URL"
        )
        XCTAssertNotEqual(
            extensionContext.permissionStatus(for: laterActiveURL),
            .grantedExplicitly,
            "A later active tab URL must not receive activeTab access from popup presentation"
        )
        XCTAssertNotEqual(
            result.blocker,
            BrowserExtensionActionPopupBlocker.currentPagePermissionMissing
        )
    }

    func testRaindropStyleIframePopupResourcesRenderInExtensionPageConfiguration() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Raindrop Iframe Resource Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Raindrop Iframe Resource",
            packageStyle: .raindropIframePopup
        )
        _ = try await manager.enableExtension(installed.id)

        guard let extensionContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        ) else {
            return XCTFail("Expected a loaded WebKit extension context")
        }
        guard let configuration = extensionContext.webViewConfiguration else {
            return XCTFail("Expected extension-origin web view configuration")
        }

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 480),
            configuration: configuration
        )
        let popupURL = extensionContext.baseURL
            .appendingPathComponent("assets/action_in_iframe.html")
        webView.load(URLRequest(url: popupURL))

        let stateScript = """
            (() => {
              const frame = document.getElementById("app");
              let innerText = "";
              let innerLoaded = "";
              let error = "";
              try {
                const innerBody = frame && frame.contentWindow && frame.contentWindow.document.body;
                innerText = innerBody ? innerBody.innerText.trim() : "";
                innerLoaded = innerBody ? (innerBody.dataset.loaded || "") : "";
              } catch (exception) {
                error = String(exception && (exception.name || exception.message) || exception);
              }
              return [
                document.readyState,
                frame ? getComputedStyle(frame).opacity : "",
                document.body.dataset.innerText || "",
                document.body.dataset.innerLoaded || "",
                innerText,
                innerLoaded,
                error
              ].join("|");
            })();
            """

        var lastState = ""
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if let state = try? await webView.evaluateJavaScript(stateScript) as? String {
                lastState = state
                if state.contains("|1|popup|true|popup|true|") {
                    return
                }
            }
        }

        XCTFail(
            "Expected nested extension iframe resource to become visible; last state=\(lastState)"
        )
    }

    func testReimportAfterDeleteCanReachPopupRuntimeGate() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Reimport Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Reimport Extension"
        )
        _ = try await manager.enableExtension(installed.id)
        try await manager.uninstallExtension(installed.id)

        let reinstalled = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Reimport Extension",
            extensionId: installed.id
        )
        _ = try await manager.enableExtension(reinstalled.id)

        _ = try await manager.ensureExtensionLoaded(
            extensionId: reinstalled.id,
            profileId: profile.id
        )
        XCTAssertNotNil(
            manager.getExtensionContext(for: reinstalled.id, profileId: profile.id)
        )
    }

    func testMV2SafariAppexStillLoadsThroughRuntimeGate() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "MV2 Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installSafariStyleCopiedPackage(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "Bitwarden",
            manifestVersion: 2
        )
        _ = try await manager.enableExtension(installed.id)

        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        XCTAssertTrue(
            manager.isExtensionRuntimeReady(
                extensionId: installed.id,
                profileId: profile.id
            )
        )
    }

    func testRaindropManualE2EPathRepresentedInAcceptanceMatrix() {
        let raindrop = SafariExtensionCompatibilityTargets.all.first {
            $0.key == "raindrop"
        }
        XCTAssertNotNil(raindrop)
        XCTAssertEqual(raindrop?.displayName, "Raindrop")
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func installUnpackedExtension(
        manager: ExtensionManager,
        scratchDirectory: URL,
        name: String,
        manifestVersion: Int = 3,
        packageStyle: TestPackageStyle = .simplePopup
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(name, isDirectory: true)
        try writeTestPackage(
            at: directoryURL,
            name: name,
            manifestVersion: manifestVersion,
            packageStyle: packageStyle
        )
        return try await manager.performInstallation(
            from: directoryURL,
            enableOnInstall: false
        )
    }

    private func installSafariStyleCopiedPackage(
        manager: ExtensionManager,
        scratchDirectory: URL,
        name: String,
        manifestVersion: Int = 3,
        extensionId: String? = nil,
        packageStyle: TestPackageStyle = .simplePopup
    ) async throws -> InstalledExtension {
        let packageRoot = scratchDirectory.appendingPathComponent(
            "\(name)-package",
            isDirectory: true
        )
        try writeTestPackage(
            at: packageRoot,
            name: name,
            manifestVersion: manifestVersion,
            packageStyle: packageStyle
        )

        let resolvedExtensionId = extensionId ?? UUID().uuidString
        let extensionsDirectory = ExtensionUtils.extensionsDirectory()
        let destinationDirectory = extensionsDirectory.appendingPathComponent(
            resolvedExtensionId,
            isDirectory: true
        )
        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.copyItem(at: packageRoot, to: destinationDirectory)

        let manifestURL = destinationDirectory.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(
            at: manifestURL,
            policy: .safariWebExtension
        )
        let record = try manager.makeInstalledRecord(
            extensionId: resolvedExtensionId,
            manifest: manifest,
            extensionRoot: destinationDirectory,
            isEnabled: false,
            sourceKind: .safariAppExtension,
            sourceBundlePath: "/tmp/missing-\(resolvedExtensionId).appex",
            sourceFingerprintURL: destinationDirectory,
            existingEntity: nil
        )
        try manager.persist(record: record)
        _ = manager.loadInstalledExtensionMetadata()
        return record
    }

    private func writeTestPackage(
        at directoryURL: URL,
        name: String,
        manifestVersion: Int,
        packageStyle: TestPackageStyle = .simplePopup
    ) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest = packageStyle.manifest(
            name: name,
            manifestVersion: manifestVersion
        )
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(to: manifestURL, options: [.atomic])
        try packageStyle.writeFiles(at: directoryURL)
    }

    private enum TestPackageStyle {
        case simplePopup
        case raindropIframePopup

        func manifest(name: String, manifestVersion: Int) -> [String: Any] {
            switch self {
            case .simplePopup:
                return [
                    "manifest_version": manifestVersion,
                    "name": name,
                    "version": "1.0",
                    "host_permissions": ["<all_urls>"],
                    "action": ["default_popup": "popup.html"],
                ]
            case .raindropIframePopup:
                return [
                    "manifest_version": 3,
                    "name": name,
                    "version": "1.0",
                    "background": [
                        "scripts": ["background.js"],
                        "persistent": false,
                    ],
                    "action": ["default_popup": "assets/action_in_iframe.html"],
                    "permissions": [
                        "activeTab",
                        "contextMenus",
                        "scripting",
                        "storage",
                    ],
                    "host_permissions": [],
                ]
            }
        }

        func writeFiles(at directoryURL: URL) throws {
            switch self {
            case .simplePopup:
                try Data("<!doctype html><title>popup</title>".utf8)
                    .write(to: directoryURL.appendingPathComponent("popup.html"), options: [.atomic])
            case .raindropIframePopup:
                let assets = directoryURL.appendingPathComponent("assets", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: assets,
                    withIntermediateDirectories: true
                )
                try Data("""
                    <!doctype html>
                    <html>
                    <head>
                    <link rel="preload" href="../index.html?action" as="document">
                    <style>
                    html, body { margin: 0; background: transparent; }
                    iframe { width: 100%; height: 100%; background: transparent; opacity: 0; }
                    </style>
                    </head>
                    <body>
                    <script src="action_in_iframe.js"></script>
                    <iframe id="app" src="../index.html?action" loading="eager" allowtransparency="true" frameborder="0" tabindex="-1"></iframe>
                    </body>
                    </html>
                    """.utf8)
                    .write(
                        to: assets.appendingPathComponent("action_in_iframe.html"),
                        options: [.atomic]
                    )
                try Data("""
                    document.addEventListener("DOMContentLoaded", () => {
                      const frame = document.getElementById("app");
                      frame.addEventListener("load", () => {
                        const innerBody = frame.contentWindow.document.body;
                        document.body.dataset.innerText = innerBody.innerText.trim();
                        document.body.dataset.innerLoaded = innerBody.dataset.loaded || "";
                        frame.style.opacity = "1";
                      });
                    });
                    """.utf8)
                    .write(
                        to: assets.appendingPathComponent("action_in_iframe.js"),
                        options: [.atomic]
                    )
                try Data("""
                    <!doctype html>
                    <html>
                    <head>
                    <link rel="stylesheet" href="assets/app.css">
                    </head>
                    <body>
                    <div id="react">popup</div>
                    <script src="assets/app.js"></script>
                    </body>
                    </html>
                    """.utf8)
                    .write(to: directoryURL.appendingPathComponent("index.html"), options: [.atomic])
                try Data("document.body.dataset.loaded = 'true';".utf8)
                    .write(to: assets.appendingPathComponent("app.js"), options: [.atomic])
                try Data("body { margin: 0; } iframe { border: 0; }".utf8)
                    .write(to: assets.appendingPathComponent("app.css"), options: [.atomic])
                try Data("browser.runtime.onInstalled.addListener(() => {});".utf8)
                    .write(to: directoryURL.appendingPathComponent("background.js"), options: [.atomic])
            }
        }
    }
}
