import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionSiteAccessPolicyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(
            forKey: ExtensionManager.extensionSiteAccessStorageKey
        )
        UserDefaults.standard.removeObject(
            forKey: ExtensionManager.extensionPermissionDecisionsStorageKey
        )
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(
            forKey: ExtensionManager.extensionSiteAccessStorageKey
        )
        UserDefaults.standard.removeObject(
            forKey: ExtensionManager.extensionPermissionDecisionsStorageKey
        )
        super.tearDown()
    }

    func testDefaultAllowGrantsOptionalHostPatterns() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Site Access")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "OptionalHostAccess"
        )
        _ = try await manager.enableExtension(installed.id)

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        XCTAssertTrue(context.webExtension.optionalPermissionMatchPatterns.contains(matchPattern))
        XCTAssertEqual(
            context.permissionStatus(for: matchPattern),
            .grantedExplicitly
        )
        XCTAssertTrue(
            context.hasAccess(to: URL(string: "https://account.proton.me/u/0")!)
        )
    }

    func testDefaultDenyDeniesDeclaredHostPatterns() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Default Deny Site Access")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "DefaultDenyHostAccess"
        )
        _ = try await manager.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .deny,
            extensionId: installed.id,
            profileId: profile.id
        )

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        XCTAssertEqual(context.permissionStatus(for: matchPattern), .deniedExplicitly)
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://account.proton.me/u/0")!))
    }

    func testSiteAccessPersistsAcrossManagerReloadForProfile() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Persistent Site Access")
        let firstManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: firstManager,
            name: "PersistentOptionalHostAccess"
        )
        _ = try await firstManager.enableExtension(installed.id)
        firstManager.setDefaultSiteAccess(
            .ask,
            extensionId: installed.id,
            profileId: profile.id
        )

        let reloadedManager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        _ = try await reloadedManager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )

        let reloadedContext = try XCTUnwrap(
            reloadedManager.getExtensionContext(
                for: installed.id,
                profileId: profile.id
            )
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        XCTAssertEqual(
            reloadedManager.siteAccessPolicy(
                extensionId: installed.id,
                profileId: profile.id
            ).defaultAccess,
            .ask
        )
        XCTAssertFalse(
            reloadedManager.isGrantedPermissionStatus(
                reloadedContext.permissionStatus(for: matchPattern)
            )
        )
    }

    func testSiteAccessIsProfileScoped() async throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        let installed = try await installExtension(
            manager: manager,
            name: "ProfileScopedSiteAccess"
        )
        _ = try await manager.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .ask,
            extensionId: installed.id,
            profileId: profileA.id
        )

        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profileB.id
        )

        let contextA = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profileA.id)
        )
        let contextB = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profileB.id)
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        XCTAssertFalse(
            manager.isGrantedPermissionStatus(contextA.permissionStatus(for: matchPattern))
        )
        XCTAssertEqual(contextB.permissionStatus(for: matchPattern), .grantedExplicitly)
    }

    func testNativeMessagingPermissionGrantIsProfileScopedAndUsesSDKPermission()
        async throws
    {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        let installed = try await installExtension(
            manager: manager,
            name: "NativeMessagingPermission",
            permissions: ["nativeMessaging"]
        )
        _ = try await manager.enableExtension(installed.id)
        _ = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profileB.id
        )

        let contextA = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profileA.id)
        )
        let contextB = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profileB.id)
        )

        XCTAssertEqual(
            contextA.permissionStatus(for: .nativeMessaging),
            .grantedExplicitly
        )
        XCTAssertEqual(
            contextB.permissionStatus(for: .nativeMessaging),
            .grantedExplicitly
        )
        XCTAssertFalse(
            contextA.unsupportedAPIs.contains {
                $0.localizedCaseInsensitiveContains("nativeMessaging")
            }
        )
    }

    func testConfiguredAskOverridesDefaultAllow() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Configured Ask")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "ConfiguredAsk"
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        XCTAssertEqual(context.permissionStatus(for: matchPattern), .grantedExplicitly)

        manager.setConfiguredSiteAccess(
            .ask,
            extensionId: installed.id,
            profileId: profile.id,
            matchPatternString: matchPattern.string
        )

        XCTAssertEqual(
            manager.configuredSiteAccessLevel(
                for: matchPattern,
                extensionId: installed.id,
                profileId: profile.id
            ),
            .ask
        )
        XCTAssertFalse(
            manager.isGrantedPermissionStatus(context.permissionStatus(for: matchPattern))
        )
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://account.proton.me/u/0")!))
    }

    func testPolicyDrivenCurrentSiteGrantDoesNotCreateConfiguredRule()
        async throws
    {
        let container = try makeTestContainer()
        let profile = Profile(name: "Default Current Site Access")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "DefaultCurrentSiteAccess"
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let accountURL = try XCTUnwrap(
            URL(string: "https://account.proton.me/u/0")
        )

        manager.grantSiteAccess(
            to: accountURL,
            in: context,
            extensionId: installed.id,
            profileId: profile.id,
            persistPolicy: false
        )

        XCTAssertTrue(context.hasAccess(to: accountURL))
        XCTAssertTrue(
            manager.siteAccessPolicy(
                extensionId: installed.id,
                profileId: profile.id
            ).siteRules.isEmpty
        )
    }

    func testSpecificConfiguredRuleOverridesBroadConfiguredRule() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Specific Site Access")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "SpecificSiteAccess",
            optionalHostPermissions: [
                "*://*/*",
                "https://accounts.example.com/*",
            ]
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let broadPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "*://*/*")
        )
        let specificPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://accounts.example.com/*")
        )
        let specificURL = try XCTUnwrap(
            URL(string: "https://accounts.example.com/settings")
        )
        let otherURL = try XCTUnwrap(URL(string: "https://example.net/"))

        manager.setConfiguredSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id,
            matchPatternString: broadPattern.string
        )
        manager.setConfiguredSiteAccess(
            .deny,
            extensionId: installed.id,
            profileId: profile.id,
            matchPatternString: specificPattern.string
        )

        XCTAssertEqual(
            manager.configuredSiteAccessLevel(
                for: specificURL,
                extensionId: installed.id,
                profileId: profile.id
            ),
            .deny
        )
        XCTAssertEqual(
            manager.configuredSiteAccessLevel(
                for: specificPattern,
                extensionId: installed.id,
                profileId: profile.id
            ),
            .deny
        )
        XCTAssertEqual(
            manager.configuredSiteAccessLevel(
                for: broadPattern,
                extensionId: installed.id,
                profileId: profile.id
            ),
            .allow
        )
        XCTAssertFalse(context.hasAccess(to: specificURL))
        XCTAssertTrue(context.hasAccess(to: otherURL))
    }

    func testPrivateAccessRemainsExplicitAndHonorsManifest() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Private Access")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "PrivateCapable",
            incognitoMode: "split"
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )

        XCTAssertFalse(context.hasAccessToPrivateData)

        manager.setPrivateBrowsingAccess(
            true,
            extensionId: installed.id,
            profileId: profile.id
        )
        XCTAssertTrue(context.hasAccessToPrivateData)

        let blocked = try await installExtension(
            manager: manager,
            name: "PrivateBlocked",
            incognitoMode: "not_allowed"
        )
        _ = try await manager.enableExtension(blocked.id)
        manager.setPrivateBrowsingAccess(
            true,
            extensionId: blocked.id,
            profileId: profile.id
        )

        let blockedContext = try XCTUnwrap(
            manager.getExtensionContext(for: blocked.id, profileId: profile.id)
        )
        XCTAssertFalse(blockedContext.hasAccessToPrivateData)
    }

    func testConfiguredPolicyOverridesLegacyPromptDecisionStore() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Legacy Prompt Override")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "LegacyPromptOverride"
        )
        _ = try await manager.enableExtension(installed.id)

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        manager.persistExtensionPermissionDecision(
            extensionId: installed.id,
            profileId: profile.id,
            targetKind: .matchPattern,
            target: matchPattern.string,
            state: .denied,
            expiresAt: nil
        )
        manager.setConfiguredSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id,
            matchPatternString: matchPattern.string
        )
        context.setPermissionStatus(.unknown, for: matchPattern)

        let controller = manager.ensureExtensionController(for: profile.id)
        let grantedPatterns = await withCheckedContinuation { continuation in
            manager.webExtensionController(
                controller,
                promptForPermissionMatchPatterns: [matchPattern],
                in: nil,
                for: context
            ) { granted, _ in
                continuation.resume(returning: granted)
            }
        }

        XCTAssertTrue(grantedPatterns.contains(matchPattern))
        XCTAssertEqual(context.permissionStatus(for: matchPattern), .grantedExplicitly)
    }

    func testDefaultAllowMakesBroadHostGrantVisibleToPermissionsContains()
        async throws
    {
        let container = try makeTestContainer()
        let profile = Profile(name: "Broad Host API Visibility")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installBroadHostProbeExtension(
            manager: manager,
            name: "BroadHostProbe"
        )
        _ = try await manager.enableExtension(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )

        XCTAssertTrue(context.hasRequestedOptionalAccessToAllHosts)

        let results = try await permissionsContainsResults(in: context)
        XCTAssertEqual(results["allHosts"], true)
        XCTAssertEqual(results["account"], true)
        XCTAssertEqual(results["pass"], true)
    }

    func testConfiguredAllSitesAllowMakesBroadHostGrantVisibleToPermissionsContains()
        async throws
    {
        let container = try makeTestContainer()
        let profile = Profile(name: "Configured Broad Host API Visibility")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installBroadHostProbeExtension(
            manager: manager,
            name: "ConfiguredBroadHostProbe"
        )
        _ = try await manager.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .ask,
            extensionId: installed.id,
            profileId: profile.id
        )
        manager.setConfiguredSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id,
            matchPatternString: "*://*/*"
        )

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        XCTAssertTrue(context.hasRequestedOptionalAccessToAllHosts)

        let results = try await permissionsContainsResults(in: context)
        XCTAssertEqual(results["allHosts"], true)
        XCTAssertEqual(results["account"], true)
        XCTAssertEqual(results["pass"], true)
    }

    func testExternallyConnectableMatchesAreNotDeclaredSiteAccess() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "External Connectable Messaging Only")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "ExternalConnectableOnly",
            optionalHostPermissions: [],
            externallyConnectableMatches: [
                "https://account.example.test/*",
                "https://pass.example.test/*",
            ]
        )
        _ = try await manager.enableExtension(installed.id)

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let accountPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.example.test/*")
        )
        let passPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://pass.example.test/*")
        )
        let declaredPatterns = manager.declaredSiteAccessMatchPatterns(
            for: context.webExtension,
            manifest: installed.manifest
        )

        XCTAssertFalse(declaredPatterns.contains(accountPattern))
        XCTAssertFalse(declaredPatterns.contains(passPattern))
        XCTAssertFalse(
            manager.isGrantedPermissionStatus(context.permissionStatus(for: accountPattern))
        )
        XCTAssertFalse(
            manager.isGrantedPermissionStatus(context.permissionStatus(for: passPattern))
        )
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://account.example.test/login")!))
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://pass.example.test/")!))

        let surfaces = SafariExtensionManifestAccessSurfaces.from(manifest: installed.manifest)
        XCTAssertEqual(surfaces.surfaces(forHost: "account.example.test"), [.externallyConnectable])
        XCTAssertEqual(surfaces.surfaces(forHost: "pass.example.test"), [.externallyConnectable])
    }

    func testInstalledProtonPassDeclaredSitesAreGrantedWhenPresent() async throws {
        let appexURL = URL(
            fileURLWithPath:
                "/Applications/Proton Pass for Safari.app/Contents/PlugIns/Safari Extension.appex"
        )
        guard FileManager.default.fileExists(atPath: appexURL.path) else {
            throw XCTSkip("Proton Pass for Safari is not installed on this machine.")
        }
        let bundle = try XCTUnwrap(Bundle(url: appexURL))
        let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let manifest = try manifest(in: appexURL)

        let container = try makeTestContainer()
        let profile = Profile(name: "Installed Proton Site Access")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let extensionId = "live-proton-pass-site-access"

        manager.applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            extensionId: extensionId,
            profileId: profile.id,
            webExtension: webExtension,
            manifest: manifest
        )

        let allHosts = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "*://*/*")
        )
        let accountPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )
        let passPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://pass.proton.me/*")
        )
        let declaredPatterns = manager.declaredSiteAccessMatchPatterns(
            for: webExtension,
            manifest: manifest
        )
        XCTAssertTrue(declaredPatterns.contains(allHosts))
        XCTAssertTrue(declaredPatterns.contains(accountPattern))
        XCTAssertFalse(
            declaredPatterns.contains(passPattern),
            "Exact externally_connectable-only page messaging patterns must not be promoted to declared site access when broad host access already covers the page"
        )
        XCTAssertTrue(
            manager.isGrantedPermissionStatus(extensionContext.permissionStatus(for: allHosts))
        )
        XCTAssertTrue(
            extensionContext.hasAccess(to: URL(string: "https://account.proton.me/")!)
        )
        XCTAssertTrue(
            extensionContext.hasAccess(to: URL(string: "https://pass.proton.me/")!)
        )
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func installExtension(
        manager: ExtensionManager,
        name: String,
        incognitoMode: String = "spanning",
        permissions: [String] = ["storage"],
        optionalHostPermissions: [String] = [
            "https://account.proton.me/*",
            "https://pass.proton.me/*",
        ],
        externallyConnectableMatches: [String] = []
    ) async throws -> InstalledExtension {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: directory.deletingLastPathComponent()
            )
        }

        var manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "incognito": incognitoMode,
            "permissions": permissions,
            "optional_host_permissions": optionalHostPermissions,
            "action": ["default_popup": "popup.html"],
        ]
        if externallyConnectableMatches.isEmpty == false {
            manifest["externally_connectable"] = [
                "matches": externallyConnectableMatches,
            ]
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directory.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        try Data("<!doctype html><title>popup</title>".utf8)
            .write(
                to: directory.appendingPathComponent("popup.html"),
                options: [.atomic]
            )

        return try await manager.performInstallation(
            from: directory,
            enableOnInstall: false
        )
    }

    private func installBroadHostProbeExtension(
        manager: ExtensionManager,
        name: String
    ) async throws -> InstalledExtension {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(
                at: directory.deletingLastPathComponent()
            )
        }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            "permissions": ["scripting"],
            "host_permissions": ["*://*/*"],
            "action": ["default_popup": "probe.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directory.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        let probeHTML = """
        <!doctype html>
        <meta charset="utf-8">
        <title>probe</title>
        <body></body>
        <script src="probe.js"></script>
        """
        try Data(probeHTML.utf8)
            .write(
                to: directory.appendingPathComponent("probe.html"),
                options: [.atomic]
            )

        let probeScript = """
        (async () => {
          try {
            const api = globalThis.browser || globalThis.chrome;
            if (!api || !api.permissions || typeof api.permissions.contains !== "function") {
              throw new Error("permissions.contains unavailable");
            }
            const allHosts = await api.permissions.contains({ origins: ["*://*/*"] });
            const account = await api.permissions.contains({ origins: ["https://account.proton.me/*"] });
            const pass = await api.permissions.contains({ origins: ["https://pass.proton.me/*"] });
            document.body.dataset.result = JSON.stringify({ allHosts, account, pass });
          } catch (error) {
            document.body.dataset.error = String(error && (error.message || error));
          }
        })();
        """
        try Data(probeScript.utf8)
            .write(
                to: directory.appendingPathComponent("probe.js"),
                options: [.atomic]
            )

        return try await manager.performInstallation(
            from: directory,
            enableOnInstall: false
        )
    }

    private func permissionsContainsResults(
        in extensionContext: WKWebExtensionContext
    ) async throws -> [String: Bool] {
        let configuration = try XCTUnwrap(extensionContext.webViewConfiguration)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        let pageURL = extensionContext.baseURL
            .appendingPathComponent("probe.html")
        webView.load(URLRequest(url: pageURL))
        let rawValue = try await waitForPermissionsContainsResult(in: webView)
        let data = try XCTUnwrap(rawValue?.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        if let result = object as? [String: String],
           let error = result["error"]
        {
            XCTFail("permissions.contains failed in extension page: \(error)")
            return [:]
        }
        return try XCTUnwrap(object as? [String: Bool])
    }

    private func waitForPermissionsContainsResult(
        in webView: WKWebView
    ) async throws -> String? {
        let script = """
        (() => {
          if (!document.body) {
            return null;
          }
          if (document.body.dataset.error) {
            return JSON.stringify({ error: document.body.dataset.error });
          }
          return document.body.dataset.result || null;
        })();
        """

        for _ in 0..<50 {
            if let result = try? await webView.evaluateJavaScript(script) as? String {
                return result
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for permissions.contains result")
        return nil
    }

    private func manifest(in appexURL: URL) throws -> [String: Any] {
        let manifestURL = appexURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}
