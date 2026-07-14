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
            forKey: SafariExtensionSiteAccessPolicyStore.siteAccessStorageKey
        )
        UserDefaults.standard.removeObject(
            forKey: SafariExtensionSiteAccessPolicyStore.legacyPermissionDecisionsStorageKey
        )
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(
            forKey: SafariExtensionSiteAccessPolicyStore.siteAccessStorageKey
        )
        UserDefaults.standard.removeObject(
            forKey: SafariExtensionSiteAccessPolicyStore.legacyPermissionDecisionsStorageKey
        )
        super.tearDown()
    }

    func testDefaultAskDoesNotGrantOptionalHostPatterns() async throws {
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        XCTAssertTrue(context.webExtension.optionalPermissionMatchPatterns.contains(matchPattern))
        XCTAssertEqual(
            context.permissionStatus(for: matchPattern),
            .unknown
        )
        XCTAssertFalse(
            context.hasAccess(to: URL(string: "https://account.proton.me/u/0")!)
        )
    }

    func testExplicitDefaultAllowGrantsDeclaredHostPatterns() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Explicit Default Allow Site Access")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "ExplicitAllowHostAccess"
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let matchPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.proton.me/*")
        )

        XCTAssertEqual(context.permissionStatus(for: matchPattern), .grantedExplicitly)
        XCTAssertTrue(context.hasAccess(to: URL(string: "https://account.proton.me/u/0")!))
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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
        _ = try await firstManager.installedExtensionLifecycle.enable(installed.id)
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
            ExtensionPermissionStatusResolver.isGranted(
                reloadedContext.permissionStatus(for: matchPattern)
            )
        )
    }

    func testSurfaceStorePublishesSiteAccessPolicySnapshotForActiveProfile()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Surface Snapshot")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installExtension(
            manager: manager,
            name: "SurfaceSnapshotHostAccess"
        )
        let surfaceStore = BrowserExtensionSurfaceStore(extensionManager: manager)

        surfaceStore.refreshSiteAccessPolicies(profileId: profile.id)
        await waitForSurfaceStoreDefaultAccess(
            .ask,
            extensionId: installed.id,
            surfaceStore: surfaceStore
        )

        XCTAssertEqual(
            surfaceStore.siteAccessPoliciesByExtensionID[installed.id]?.defaultAccess,
            .ask
        )

        manager.setDefaultSiteAccess(
            .ask,
            extensionId: installed.id,
            profileId: profile.id
        )
        await waitForSurfaceStoreDefaultAccess(
            .ask,
            extensionId: installed.id,
            surfaceStore: surfaceStore
        )

        XCTAssertEqual(
            surfaceStore.siteAccessPoliciesByExtensionID[installed.id]?.defaultAccess,
            .ask
        )
    }

    func testSafariAppExtensionDefaultAccessSeedCreatesDefaultAllowPolicy() {
        let profile = Profile(name: "Safari App Extension Seed")
        let store = SafariExtensionSiteAccessPolicyStore(preferences: .standard)
        let extensionId = "safari-app-extension-seed"

        let result = store.seedSafariAppExtensionDefaultAccessIfNeeded(
            extensionId: extensionId,
            profileId: profile.id
        )

        XCTAssertTrue(result.didPersistChanges)
        XCTAssertEqual(result.policy.defaultAccess, .allow)
        XCTAssertEqual(
            store.policy(extensionId: extensionId, profileId: profile.id)
                .policy
                .defaultAccess,
            .allow
        )
    }

    func testSafariAppExtensionDefaultAccessSeedMigratesEmptyAskPolicy() {
        let profile = Profile(name: "Safari App Extension Ask Migration")
        let store = SafariExtensionSiteAccessPolicyStore(preferences: .standard)
        let extensionId = "safari-app-extension-ask-migration"

        XCTAssertEqual(
            store.policy(extensionId: extensionId, profileId: profile.id)
                .policy
                .defaultAccess,
            .ask
        )

        let result = store.seedSafariAppExtensionDefaultAccessIfNeeded(
            extensionId: extensionId,
            profileId: profile.id
        )

        XCTAssertTrue(result.didPersistChanges)
        XCTAssertEqual(result.policy.defaultAccess, .allow)
    }

    func testSafariAppExtensionDefaultAccessSeedAppliesAllowAndPreservesConfiguredRules() {
        let profile = Profile(name: "Safari App Extension Configured Rule")
        let store = SafariExtensionSiteAccessPolicyStore(preferences: .standard)
        let extensionId = "safari-app-extension-configured-rule"
        let pattern = "https://account.example.test/*"

        store.updatePolicy(
            extensionId: extensionId,
            profileId: profile.id
        ) { policy in
            policy.siteRules = [
                SafariExtensionSiteAccessRule(
                    matchPattern: pattern,
                    access: .deny,
                    expiresAt: nil,
                    updatedAt: Date()
                ),
            ]
        }

        let result = store.seedSafariAppExtensionDefaultAccessIfNeeded(
            extensionId: extensionId,
            profileId: profile.id
        )

        XCTAssertTrue(result.didPersistChanges)
        XCTAssertEqual(result.policy.defaultAccess, .allow)
        XCTAssertEqual(result.policy.siteRules.map(\.matchPattern), [pattern])
        XCTAssertEqual(result.policy.siteRules.map(\.access), [.deny])
    }

    /// Reproduces the field state that broke Proton Pass: a login prompt had
    /// persisted an allow rule and the private-browsing toggle was on before
    /// seeding ever ran, leaving `defaultAccess == .ask` and
    /// `permissions.contains({origins:["*://*/*"]})` false in the extension.
    func testSafariAppExtensionDefaultAccessSeedRepairsPromptDirtiedAskPolicy() {
        let profile = Profile(name: "Safari App Extension Dirty Ask Repair")
        let store = SafariExtensionSiteAccessPolicyStore(preferences: .standard)
        let extensionId = "safari-app-extension-dirty-ask-repair"
        let pattern = "https://*.proton.me/*"

        store.updatePolicy(
            extensionId: extensionId,
            profileId: profile.id
        ) { policy in
            policy.siteRules = [
                SafariExtensionSiteAccessRule(
                    matchPattern: pattern,
                    access: .allow,
                    expiresAt: nil,
                    updatedAt: Date()
                ),
            ]
            policy.privateAccessAllowed = true
        }

        let result = store.seedSafariAppExtensionDefaultAccessIfNeeded(
            extensionId: extensionId,
            profileId: profile.id
        )

        XCTAssertTrue(result.didPersistChanges)
        XCTAssertEqual(result.policy.defaultAccess, .allow)
        XCTAssertTrue(result.policy.privateAccessAllowed)
        XCTAssertEqual(result.policy.siteRules.map(\.matchPattern), [pattern])
    }

    func testSafariAppExtensionDefaultAccessSeedKeepsUserConfiguredAskDefault() {
        let profile = Profile(name: "Safari App Extension User Ask")
        let store = SafariExtensionSiteAccessPolicyStore(preferences: .standard)
        let extensionId = "safari-app-extension-user-ask"

        store.updatePolicy(
            extensionId: extensionId,
            profileId: profile.id
        ) { policy in
            policy.defaultAccess = .ask
            policy.defaultAccessConfiguredByUser = true
        }

        let result = store.seedSafariAppExtensionDefaultAccessIfNeeded(
            extensionId: extensionId,
            profileId: profile.id
        )

        XCTAssertFalse(result.didPersistChanges)
        XCTAssertEqual(result.policy.defaultAccess, .ask)
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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
            ExtensionPermissionStatusResolver.isGranted(contextA.permissionStatus(for: matchPattern))
        )
        XCTAssertFalse(
            ExtensionPermissionStatusResolver.isGranted(contextB.permissionStatus(for: matchPattern))
        )
    }

    func testNativeMessagingPermissionGrantIsProfileScopedAndUsesSDKPermission()
        async throws {
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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

    func testConfiguredAskOverridesExplicitDefaultAllow() async throws {
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
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
            ExtensionPermissionStatusResolver.isGranted(context.permissionStatus(for: matchPattern))
        )
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://account.proton.me/u/0")!))
    }

    func testPolicyDrivenCurrentSiteGrantDoesNotCreateConfiguredRule()
        async throws {
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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
        _ = try await manager.installedExtensionLifecycle.enable(blocked.id)
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)

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
        manager.testHooks.permissionPromptDecision = { _, _, _ in
            .allow(expirationDate: nil)
        }
        defer {
            manager.testHooks.permissionPromptDecision = nil
        }

        let controller = manager.ensureExtensionController(for: profile.id)
        let grantedPatterns = await withCheckedContinuation { continuation in
            manager.controllerDelegateBridge.webExtensionController(
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

    func testDefaultAskKeepsBroadHostGrantHiddenFromPermissionsContains()
        async throws {
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )

        XCTAssertFalse(context.hasRequestedOptionalAccessToAllHosts)

        let results = try await permissionsContainsResults(in: context)
        XCTAssertFalse(try XCTUnwrap(results["allHosts"]))
        XCTAssertFalse(try XCTUnwrap(results["account"]))
        XCTAssertFalse(try XCTUnwrap(results["pass"]))
        XCTAssertFalse(try XCTUnwrap(results["protonWildcard"]))
    }

    func testConfiguredAllSitesAllowMakesBroadHostGrantVisibleToPermissionsContains()
        async throws {
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
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
        XCTAssertTrue(try XCTUnwrap(results["allHosts"]))
        XCTAssertTrue(try XCTUnwrap(results["account"]))
        XCTAssertTrue(try XCTUnwrap(results["pass"]))
        XCTAssertTrue(try XCTUnwrap(results["protonWildcard"]))
    }

    /// Safari parity: permission state changes only when configuration
    /// changes. Re-applying an unchanged policy during context load or live
    /// policy reconciliation must be
    /// a no-op — the previous remove-then-regrant sweep fired
    /// `permissions.onRemoved`/`onAdded` storms into extension workers, which
    /// Proton Pass caches as "permissions missing" for its popup spotlight.
    func testUnchangedPolicyReapplicationEmitsNoPermissionEvents() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Idempotent Policy Application")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installBroadHostProbeExtension(
            manager: manager,
            name: "IdempotentPolicyProbe"
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let initialGrant = expectation(
            forNotification: WKWebExtensionContext
                .permissionMatchPatternsWereGrantedNotification,
            object: context
        )
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        await fulfillment(of: [initialGrant], timeout: 5)

        let allHosts = try XCTUnwrap(WKWebExtension.MatchPattern(string: "*://*/*"))
        XCTAssertNotNil(context.grantedPermissionMatchPatterns[allHosts])
        let grantedBefore = context.grantedPermissionMatchPatterns

        let permissionEventNames: [Notification.Name] = [
            WKWebExtensionContext.permissionMatchPatternsWereGrantedNotification,
            WKWebExtensionContext.permissionMatchPatternsWereDeniedNotification,
            WKWebExtensionContext.grantedPermissionMatchPatternsWereRemovedNotification,
            WKWebExtensionContext.deniedPermissionMatchPatternsWereRemovedNotification,
        ]
        let eventLog = PermissionEventLog()
        var observers: [NSObjectProtocol] = []
        for name in permissionEventNames {
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: context,
                    queue: nil
                ) { notification in
                    eventLog.append(notification.name.rawValue)
                }
            )
        }
        defer {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        let configuredDeny = expectation(
            forNotification: WKWebExtensionContext
                .permissionMatchPatternsWereDeniedNotification,
            object: context
        )

        // Context reconciliation may re-apply an unchanged policy repeatedly.
        for _ in 0..<3 {
            manager.siteAccessPolicyCoordinator.applyConfiguredSiteAccessPolicy(
                to: context,
                extensionId: installed.id,
                profileId: profile.id,
                webExtension: context.webExtension,
                manifest: installed.manifest
            )
        }
        XCTAssertEqual(context.grantedPermissionMatchPatterns, grantedBefore)

        // A real configuration change must still write through.
        manager.setConfiguredSiteAccess(
            .deny,
            extensionId: installed.id,
            profileId: profile.id,
            matchPatternString: "https://denied.example.test/*"
        )
        let deniedPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://denied.example.test/*")
        )
        XCTAssertNotNil(context.deniedPermissionMatchPatterns[deniedPattern])
        await fulfillment(of: [configuredDeny], timeout: 5)
        XCTAssertEqual(
            eventLog.names,
            [WKWebExtensionContext.permissionMatchPatternsWereDeniedNotification.rawValue],
            "Only the real configuration change may fire a permission event"
        )
    }

    /// Mirrors Proton Pass's popup "Grant permissions" flow:
    /// `browser.permissions.request({origins:["*://*/*"]})` followed by a
    /// `permissions.contains` re-verification (Proton treats Safari request
    /// results as untrusted and re-checks). The request must route through
    /// the WebKit delegate prompt, and an Allow decision must both resolve
    /// the request true and persist as Sumi site-access policy.
    func testPermissionsRequestAllHostsPromptAllowGrantsAndPersists()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Broad Host Request Grant")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installBroadHostProbeExtension(
            manager: manager,
            name: "BroadHostRequestProbe"
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )

        var promptedTargets: [[String]] = []
        manager.testHooks.permissionPromptDecision = { _, targets, _ in
            promptedTargets.append(targets)
            return .allow(expirationDate: nil)
        }
        defer {
            manager.testHooks.permissionPromptDecision = nil
        }

        let results = try await permissionsRequestResults(
            in: context,
            origins: ["*://*/*"]
        )
        XCTAssertTrue(
            try XCTUnwrap(results["granted"]),
            "permissions.request must resolve true after the prompt allows"
        )
        XCTAssertTrue(
            try XCTUnwrap(results["contains"]),
            "permissions.contains re-verification must see the grant"
        )
        XCTAssertEqual(promptedTargets.count, 1)

        let policy = manager.siteAccessPolicy(
            extensionId: installed.id,
            profileId: profile.id
        )
        XCTAssertTrue(
            policy.siteRules.contains {
                $0.matchPattern == "*://*/*" && $0.access == .allow
            },
            "Prompt allow must persist as a configured site-access rule"
        )
        XCTAssertTrue(context.hasRequestedOptionalAccessToAllHosts)
    }

    /// The same request with a Deny decision must resolve false, persist the
    /// deny, and not prompt again for the identical request.
    func testPermissionsRequestAllHostsPromptDenyResolvesFalseAndPersists()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Broad Host Request Deny")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        let installed = try await installBroadHostProbeExtension(
            manager: manager,
            name: "BroadHostRequestDenyProbe"
        )
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)
        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )

        var promptCount = 0
        manager.testHooks.permissionPromptDecision = { _, _, _ in
            promptCount += 1
            return .deny
        }
        defer {
            manager.testHooks.permissionPromptDecision = nil
        }

        let firstResults = try await permissionsRequestResults(
            in: context,
            origins: ["*://*/*"]
        )
        XCTAssertFalse(try XCTUnwrap(firstResults["granted"]))
        XCTAssertFalse(try XCTUnwrap(firstResults["contains"]))
        XCTAssertEqual(promptCount, 1)

        let policy = manager.siteAccessPolicy(
            extensionId: installed.id,
            profileId: profile.id
        )
        XCTAssertTrue(
            policy.siteRules.contains {
                $0.matchPattern == "*://*/*" && $0.access == .deny
            },
            "Prompt deny must persist as a configured site-access rule"
        )

        let secondResults = try await permissionsRequestResults(
            in: context,
            origins: ["*://*/*"]
        )
        // WebKit contract (WebExtensionContext::needsPermission): explicitly
        // denied patterns are excluded from the prompt set, and a request
        // with nothing left to prompt resolves true — the Safari
        // "false positive" Proton Pass works around by re-checking
        // permissions.contains after every request.
        XCTAssertTrue(try XCTUnwrap(secondResults["granted"]))
        XCTAssertFalse(
            try XCTUnwrap(secondResults["contains"]),
            "The false-positive request result must not grant access"
        )
        XCTAssertEqual(
            promptCount,
            1,
            "A persisted deny must resolve later requests without re-prompting"
        )
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
        _ = try await manager.installedExtensionLifecycle.enable(installed.id)

        let context = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        let accountPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://account.example.test/*")
        )
        let passPattern = try XCTUnwrap(
            WKWebExtension.MatchPattern(string: "https://pass.example.test/*")
        )
        let declaredPatterns = manager.siteAccessPolicyCoordinator
            .declaredSiteAccessMatchPatterns(
            for: context.webExtension,
            manifest: installed.manifest
        )

        XCTAssertFalse(declaredPatterns.contains(accountPattern))
        XCTAssertFalse(declaredPatterns.contains(passPattern))
        XCTAssertFalse(
            ExtensionPermissionStatusResolver.isGranted(context.permissionStatus(for: accountPattern))
        )
        XCTAssertFalse(
            ExtensionPermissionStatusResolver.isGranted(context.permissionStatus(for: passPattern))
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

        manager.setDefaultSiteAccess(
            .allow,
            extensionId: extensionId,
            profileId: profile.id
        )
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
        let declaredPatterns = manager.siteAccessPolicyCoordinator
            .declaredSiteAccessMatchPatterns(
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
            ExtensionPermissionStatusResolver.isGranted(extensionContext.permissionStatus(for: allHosts))
        )
        XCTAssertTrue(
            extensionContext.hasAccess(to: URL(string: "https://account.proton.me/")!)
        )
        XCTAssertTrue(
            extensionContext.hasAccess(to: URL(string: "https://pass.proton.me/")!)
        )
    }

    private final class PermissionEventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        var names: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ name: String) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(name)
        }
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func waitForSurfaceStoreDefaultAccess(
        _ expected: SafariExtensionSiteAccessLevel,
        extensionId: String,
        surfaceStore: BrowserExtensionSurfaceStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if surfaceStore.siteAccessPoliciesByExtensionID[extensionId]?.defaultAccess == expected {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for site-access surface snapshot", file: file, line: line)
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

        return try await manager.extensionInstaller.install(
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
            const protonWildcard = await api.permissions.contains({ origins: ["https://*.proton.me/*"] });
            document.body.dataset.result = JSON.stringify({ allHosts, account, pass, protonWildcard });
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

        return try await manager.extensionInstaller.install(
            from: directory,
            enableOnInstall: false
        )
    }

    private func permissionsContainsResults(
        in extensionContext: WKWebExtensionContext
    ) async throws -> [String: Bool] {
        let webView = try await loadPermissionsProbePage(in: extensionContext)
        let rawValue = try await waitForBodyDatasetResult(
            in: webView,
            resultKey: "result",
            errorKey: "error"
        )
        let data = try XCTUnwrap(rawValue?.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        if let result = object as? [String: String],
           let error = result["error"] {
            XCTFail("permissions.contains failed in extension page: \(error)")
            return [:]
        }
        return try XCTUnwrap(object as? [String: Bool])
    }

    /// Loads the probe extension page and runs `permissions.request` for the
    /// given origins via `evaluateJavaScript`, which WebKit executes as a
    /// user gesture — matching the click-driven request Proton Pass issues
    /// from its popup. Returns the request result and a follow-up
    /// `permissions.contains` re-verification.
    private func permissionsRequestResults(
        in extensionContext: WKWebExtensionContext,
        origins: [String]
    ) async throws -> [String: Bool] {
        let webView = try await loadPermissionsProbePage(in: extensionContext)
        _ = try await waitForBodyDatasetResult(
            in: webView,
            resultKey: "result",
            errorKey: "error"
        )

        let originsJSON = try XCTUnwrap(
            String(
                data: JSONSerialization.data(withJSONObject: origins),
                encoding: .utf8
            )
        )
        let requestScript = """
        (async () => {
          try {
            delete document.body.dataset.requestResult;
            delete document.body.dataset.requestError;
            const api = globalThis.browser || globalThis.chrome;
            if (!api || !api.permissions || typeof api.permissions.request !== "function") {
              throw new Error("permissions.request unavailable");
            }
            const origins = \(originsJSON);
            const granted = await api.permissions.request({ origins });
            const contains = await api.permissions.contains({ origins });
            document.body.dataset.requestResult = JSON.stringify({ granted, contains });
          } catch (error) {
            document.body.dataset.requestError = String(error && (error.message || error));
          }
        })();
        null;
        """
        _ = try? await webView.evaluateJavaScript(requestScript)

        let settledRequest = try await waitForBodyDatasetResult(
            in: webView,
            resultKey: "requestResult",
            errorKey: "requestError"
        )
        let rawValue = try XCTUnwrap(settledRequest)
        let data = try XCTUnwrap(rawValue.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        if let result = object as? [String: String],
           let error = result["error"] {
            XCTFail("permissions.request failed in extension page: \(error)")
            return [:]
        }
        return try XCTUnwrap(object as? [String: Bool])
    }

    private func loadPermissionsProbePage(
        in extensionContext: WKWebExtensionContext
    ) async throws -> WKWebView {
        let configuration = try XCTUnwrap(extensionContext.webViewConfiguration)
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 240),
            configuration: configuration
        )
        let didFinish = expectation(description: "permissions probe page loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.load(
            URLRequest(
                url: extensionContext.baseURL.appendingPathComponent("probe.html")
            )
        )
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil
        return webView
    }

    private func waitForBodyDatasetResult(
        in webView: WKWebView,
        resultKey: String,
        errorKey: String
    ) async throws -> String? {
        try await webView.callAsyncJavaScript(
            """
            const readResult = () => {
                if (!document.body) {
                    return null;
                }
                const error = document.body.dataset[errorKey];
                if (error) {
                    return JSON.stringify({ error });
                }
                return document.body.dataset[resultKey] || null;
            };
            const existingResult = readResult();
            if (existingResult !== null) {
                return existingResult;
            }
            return await new Promise(resolve => {
                let timeoutID = null;
                const observer = new MutationObserver(() => {
                    const observedResult = readResult();
                    if (observedResult !== null) {
                        finish(observedResult);
                    }
                });
                const finish = value => {
                    observer.disconnect();
                    if (timeoutID !== null) {
                        clearTimeout(timeoutID);
                    }
                    resolve(value);
                };
                observer.observe(document.body, { attributes: true });
                timeoutID = setTimeout(() => finish(null), 5000);
            });
            """,
            arguments: [
                "resultKey": resultKey,
                "errorKey": errorKey,
            ],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            onFinish()
        }
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
