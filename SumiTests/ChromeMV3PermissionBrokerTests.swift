import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3PermissionBrokerTests: XCTestCase {
    func testRequiredOptionalAndHostPermissionsAreModeled() {
        let broker = permissionBroker(
            required: ["tabs", "storage"],
            optional: ["bookmarks", "history"],
            grantedOptional: ["bookmarks"],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: ["https://optional.example/*"],
            grantedOptionalHostPermissions: ["https://granted.example/*"]
        )

        XCTAssertTrue(broker.hasAPIPermission("tabs"))
        XCTAssertTrue(broker.hasOptionalPermission("bookmarks"))
        XCTAssertFalse(broker.hasOptionalPermission("history"))
        XCTAssertTrue(broker.wouldNeedPrompt(permission: "history"))
        XCTAssertTrue(
            broker.hasHostPermission(url: "https://example.com/login")
        )
        XCTAssertTrue(
            broker.hasHostPermission(url: "https://granted.example/login")
        )
        XCTAssertTrue(
            broker.wouldNeedPrompt(host: "https://optional.example/login")
        )
    }

    func testUnsupportedAndDeferredPermissionsAreReported() {
        let broker = permissionBroker(
            required: ["nativeMessaging", "debugger"],
            unavailable: ["nativeMessaging"],
            unsupported: ["debugger"]
        )

        let native = broker.apiPermissionDecision("nativeMessaging")
        let debugger = broker.apiPermissionDecision("debugger")

        XCTAssertFalse(native.hasPermission)
        XCTAssertEqual(native.status, .deferred)
        XCTAssertTrue(broker.isPermissionDeferred("nativeMessaging"))
        XCTAssertFalse(debugger.hasPermission)
        XCTAssertEqual(debugger.status, .unsupported)
        XCTAssertTrue(broker.isPermissionUnsupported("debugger"))
    }

    func testAllURLsMatchesHTTPAndHTTPSOnlyForModeledHostAccess() {
        let pattern = ChromeMV3HostMatchPattern("<all_urls>")

        XCTAssertTrue(pattern.matches(url: "http://example.com/"))
        XCTAssertTrue(pattern.matches(url: "https://example.com/"))
        XCTAssertFalse(pattern.matches(url: "chrome://extensions/"))
        XCTAssertTrue(pattern.isValid)
    }

    func testSchemeSpecificHostPatternsMatchOnlyCorrectScheme() {
        let https = ChromeMV3HostMatchPattern("https://example.com/*")

        XCTAssertTrue(https.matches(url: "https://example.com/a"))
        XCTAssertFalse(https.matches(url: "http://example.com/a"))
        XCTAssertFalse(https.matches(url: "https://other.example/a"))
    }

    func testWildcardSubdomainPatternBehaviorIsDeterministic() {
        let pattern = ChromeMV3HostMatchPattern("*://*.example.com/*")

        XCTAssertTrue(pattern.matches(url: "https://example.com/login"))
        XCTAssertTrue(pattern.matches(url: "http://www.example.com/login"))
        XCTAssertTrue(pattern.matches(url: "https://a.b.example.com/login"))
        XCTAssertFalse(pattern.matches(url: "https://badexample.com/login"))
    }

    func testInvalidAndUnsupportedPatternsProduceDiagnostics() {
        let invalidWildcard =
            ChromeMV3HostMatchPattern("https://exa*mple.com/*")
        let missingPath = ChromeMV3HostMatchPattern("https://example.com")
        let unsupportedFile = ChromeMV3HostMatchPattern("file:///tmp/*")

        XCTAssertTrue(invalidWildcard.isInvalid)
        XCTAssertTrue(missingPath.isInvalid)
        XCTAssertTrue(unsupportedFile.isUnsupported)
        XCTAssertFalse(invalidWildcard.diagnostics.isEmpty)
        XCTAssertFalse(unsupportedFile.diagnostics.isEmpty)
    }

    func testHostPermissionAllowsSenderMetadataExposure() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://example.com/login"
        )
        let broker = permissionBroker(
            hostPermissions: ["https://example.com/*"]
        )
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionBroker: broker
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            permissionDecision: decision
        )

        XCTAssertTrue(decision.allowedForFutureDispatch)
        XCTAssertEqual(decision.senderMetadataRedaction, .preserveURLAndOrigin)
        XCTAssertEqual(envelope.senderMetadata.url, "https://example.com/login")
        XCTAssertEqual(envelope.senderMetadata.origin, "https://example.com")
        XCTAssertTrue(decision.hostAccessDecision?.hasHostAccess == true)
    }

    func testMissingHostPermissionRedactsSenderMetadata() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://secret.example/login"
        )
        let broker = permissionBroker()
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionBroker: broker
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            permissionDecision: decision
        )

        XCTAssertFalse(decision.allowedForFutureDispatch)
        XCTAssertEqual(decision.missingGrantReason, .missingHostPermission)
        XCTAssertEqual(decision.senderMetadataRedaction, .redactURLAndOrigin)
        XCTAssertNil(envelope.senderMetadata.url)
        XCTAssertNil(envelope.senderMetadata.origin)
    }

    func testModeledActiveTabGrantAllowsTabRouteButStillDoesNotDispatch() {
        let route = route(
            .serviceWorkerToTab,
            targetURL: "https://example.com/login"
        )
        let broker = permissionBroker(
            required: ["activeTab"],
            activeTabGrants: [
                activeTabGrant(
                    tabID: 42,
                    origin: "https://example.com"
                ),
            ]
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionBroker: broker,
            readiness: readiness(
                contextLoaded: true,
                receiverListenerRegistered: true,
                serviceWorkerLifecycleReady: true
            )
        )

        XCTAssertTrue(
            evaluation.permissionDecision.allowedForFutureDispatch
        )
        XCTAssertTrue(
            evaluation.permissionDecision.hostAccessDecision?
                .allowedByActiveTab == true
        )
        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertEqual(evaluation.errorContract?.error, .routeNotImplemented)
    }

    func testActiveTabExpiresOnNavigationAwayFromOrigin() {
        let broker = ChromeMV3ActiveTabGrantBroker(
            grants: [
                activeTabGrant(
                    tabID: 42,
                    origin: "https://example.com"
                ),
            ]
        )
        let sameOrigin = broker.applyingNavigation(
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 42,
            oldURL: "https://example.com/login",
            newURL: "https://example.com/settings",
            sequence: 2
        )
        let crossOrigin = broker.applyingNavigation(
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 42,
            oldURL: "https://example.com/login",
            newURL: "https://chromium.org/",
            sequence: 3
        )

        XCTAssertTrue(
            sameOrigin.hasActiveTabGrant(
                extensionID: "extension-a",
                profileID: "profile-a",
                tabID: 42,
                url: "https://example.com/settings"
            )
        )
        XCTAssertFalse(
            crossOrigin.hasActiveTabGrant(
                extensionID: "extension-a",
                profileID: "profile-a",
                tabID: 42,
                url: "https://example.com/login"
            )
        )
        XCTAssertEqual(crossOrigin.grants.first?.expiryRecord?.trigger, .tabNavigation)
    }

    func testActiveTabExpiresOnTabClose() {
        let broker = ChromeMV3ActiveTabGrantBroker(
            grants: [
                activeTabGrant(
                    tabID: 42,
                    origin: "https://example.com"
                ),
            ]
        )
        let expired = broker.applyingTabClose(
            profileID: "profile-a",
            tabID: 42,
            sequence: 4
        )

        XCTAssertFalse(
            expired.hasActiveTabGrant(
                extensionID: "extension-a",
                profileID: "profile-a",
                tabID: 42,
                url: "https://example.com/login"
            )
        )
        XCTAssertEqual(expired.grants.first?.expiryRecord?.trigger, .tabClose)
    }

    func testActiveTabExpiresOnExtensionDisable() {
        let broker = ChromeMV3ActiveTabGrantBroker(
            grants: [
                activeTabGrant(
                    tabID: 42,
                    origin: "https://example.com"
                ),
            ]
        )
        let expired = broker.applyingExtensionDisable(
            extensionID: "extension-a",
            profileID: "profile-a",
            sequence: 5
        )

        XCTAssertEqual(
            expired.grants.first?.expiryRecord?.trigger,
            .extensionDisable
        )
        XCTAssertFalse(expired.grants.first?.active ?? true)
    }

    func testPermissionDecisionStoreLoadsExportsAndMutatesDeterministically()
        throws
    {
        let snapshot = ChromeMV3PermissionDecisionStoreSnapshot(
            extensionID: "extension-a",
            profileID: "profile-a",
            declaredAPIPermissions: ["storage"],
            declaredHostPermissions: ["https://example.com/*"],
            optionalAPIPermissions: ["history"],
            optionalHostPermissions: ["https://optional.example/*"],
            deferredPermissions: ["storage"],
            unsupportedPermissions: ["debugger"]
        )
        let store = ChromeMV3PermissionDecisionStore(snapshot: snapshot)
        let granted = store
            .applyingModeledGrant("history", sequence: 10)
            .applyingModeledGrant(
                "https://optional.example/*",
                sequence: 11
            )
        let denied = granted.applyingModeledDenial("history", sequence: 12)
        let revoked = granted.applyingRevoke(
            "https://optional.example/*",
            sequence: 13
        )
        let first = try ChromeMV3DeterministicJSON.encodedData(
            granted.exportSnapshot()
        )
        let second = try ChromeMV3DeterministicJSON.encodedData(
            granted.exportSnapshot()
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            granted.apiPermissionDecision("history").status,
            .allowed
        )
        XCTAssertTrue(
            granted.hostAccessDecision(
                url: "https://optional.example/login"
            ).hasHostAccess
        )
        XCTAssertEqual(denied.apiPermissionDecision("history").status, .denied)
        XCTAssertEqual(
            revoked.hostAccessDecision(
                url: "https://optional.example/login"
            ).status,
            .revoked
        )
        XCTAssertTrue(store.isPermissionDeferred("storage"))
        XCTAssertTrue(store.isPermissionUnsupported("debugger"))
        XCTAssertFalse(granted.exportSnapshot().decisionRecords.isEmpty)
    }

    func testActiveTabGrantStoreQueriesAndExpiresForLifecycleBoundaries() {
        let store = ChromeMV3ActiveTabGrantStore
            .empty(extensionID: "extension-a", profileID: "profile-a")
            .addingModeledGrant(
                tabID: 42,
                url: "https://example.com/login",
                reason: .testFixture,
                sequence: 1
            )

        XCTAssertTrue(
            store.hasActiveTabGrant(
                tabID: 42,
                url: "https://example.com/settings"
            )
        )
        XCTAssertFalse(
            store.hasActiveTabGrant(
                tabID: 7,
                url: "https://example.com/settings"
            )
        )
        XCTAssertFalse(
            store.hasActiveTabGrant(
                tabID: 42,
                url: "https://other.example/settings"
            )
        )

        let sameOrigin = store.expiringForNavigation(
            tabID: 42,
            oldURL: "https://example.com/login",
            newURL: "https://example.com/settings",
            sequence: 2
        )
        let navigated = store.expiringForNavigation(
            tabID: 42,
            oldURL: "https://example.com/login",
            newURL: "https://chromium.org/",
            sequence: 3
        )
        let closed = store.expiringForTabClose(tabID: 42, sequence: 4)
        let profileClosed = store.expiringForProfileClose(
            profileID: "profile-a",
            sequence: 5
        )
        let disabled = store.expiringForExtensionDisable(
            extensionID: "extension-a",
            profileID: "profile-a",
            sequence: 6
        )
        let revoked = store.expiringForPermissionRevoke(
            extensionID: "extension-a",
            profileID: "profile-a",
            permission: "activeTab",
            sequence: 7
        )

        XCTAssertTrue(sameOrigin.expired.isEmpty)
        XCTAssertEqual(navigated.expired.first?.grant.expiryRecord?.trigger, .tabNavigation)
        XCTAssertEqual(closed.expired.first?.grant.expiryRecord?.trigger, .tabClose)
        XCTAssertEqual(profileClosed.expired.first?.grant.expiryRecord?.trigger, .profileClose)
        XCTAssertEqual(disabled.expired.first?.grant.expiryRecord?.trigger, .extensionDisable)
        XCTAssertEqual(revoked.expired.first?.grant.expiryRecord?.trigger, .permissionRevoke)
    }

    func testLifecycleAdapterReportsExpiredAndRetainedGrants() {
        let permissionStore = permissionDecisionStore(
            optional: ["history"],
            optionalHostPermissions: ["https://example.com/*"]
        )
        let activeTabStore = ChromeMV3ActiveTabGrantStore
            .empty(extensionID: "extension-a", profileID: "profile-a")
            .addingModeledGrant(
                tabID: 42,
                url: "https://example.com/login",
                reason: .testFixture,
                sequence: 1
            )
            .addingModeledGrant(
                tabID: 7,
                url: "https://retained.example/login",
                reason: .testFixture,
                sequence: 2
            )
        let adapter = ChromeMV3PermissionLifecycleAdapter(
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        .applying([
            ChromeMV3PermissionLifecycleEvent(
                kind: .tabNavigated,
                extensionID: "extension-a",
                profileID: "profile-a",
                tabID: 42,
                oldURL: "https://example.com/login",
                newURL: "https://chromium.org/",
                sequence: 3
            ),
            ChromeMV3PermissionLifecycleEvent(
                kind: .permissionRevoked,
                extensionID: "extension-a",
                profileID: "profile-a",
                permission: "history",
                sequence: 4
            ),
        ])

        XCTAssertEqual(adapter.eventResults.first?.grantsExpired.count, 1)
        XCTAssertEqual(adapter.eventResults.first?.grantsRetained.count, 1)
        XCTAssertEqual(
            adapter.permissionStore.apiPermissionDecision("history").status,
            .revoked
        )
        XCTAssertTrue(
            adapter.eventResults.last?.readinessImpact.contains {
                $0.contains("canDispatchMessagesNow remains false")
            } == true
        )
    }

    func testStoreBackedMessagingExposesAndRedactsSenderMetadata() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://example.com/login"
        )
        let permissionStore = permissionDecisionStore(
            hostPermissions: ["https://example.com/*"]
        )
        let activeTabStore = ChromeMV3ActiveTabGrantStore.empty(
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let allowed = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        let redacted = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionStore: permissionDecisionStore(),
            activeTabStore: activeTabStore
        )

        XCTAssertEqual(allowed.senderMetadataRedaction, .preserveURLAndOrigin)
        XCTAssertEqual(redacted.senderMetadataRedaction, .redactURLAndOrigin)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: ChromeMV3RuntimeMessageEnvelope.make(
                route: route,
                permissionDecision: allowed
            ),
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            readiness: readiness(
                contextLoaded: true,
                receiverListenerRegistered: true,
                serviceWorkerLifecycleReady: true
            )
        )
        XCTAssertFalse(evaluation.canDispatchNow)
        XCTAssertEqual(evaluation.errorContract?.error, .routeNotImplemented)
    }

    func testListenerDiagnosticsUseStoreBackedDecision() {
        let surfaces = ChromeMV3RuntimeListenerSurface.allModeledSurfaces(
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let missing = ChromeMV3RuntimeEventSurfaceCapability.matrix(
            surfaces: surfaces,
            permissionBroker: permissionDecisionStore()
                .permissionBroker(
                    activeTabStore:
                        ChromeMV3ActiveTabGrantStore.empty(
                            extensionID: "extension-a",
                            profileID: "profile-a"
                        )
                )
        )
        let grantedStore = permissionDecisionStore(
            optionalHostPermissions: ["https://example.com/*"]
        )
        .applyingModeledGrant("https://example.com/*", sequence: 1)
        let granted = ChromeMV3RuntimeEventSurfaceCapability.matrix(
            surfaces: surfaces,
            permissionBroker: grantedStore.permissionBroker(
                activeTabStore:
                    ChromeMV3ActiveTabGrantStore.empty(
                        extensionID: "extension-a",
                        profileID: "profile-a"
                    )
            )
        )

        XCTAssertTrue(
            missing.first { $0.surface == .tabsMessageContentScript }?
                .statuses.contains(.blockedByMissingHostAccess) == true
        )
        XCTAssertFalse(
            granted.first { $0.surface == .tabsMessageContentScript }?
                .statuses.contains(.blockedByMissingHostAccess) == true
        )
    }

    func testPermissionLifecycleReportIsDeterministicWritableAndBlocked()
        throws
    {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3PermissionLifecycleReportGenerator.makeReport(
            prerequisitesReport: makePrerequisitesReport(),
            modeledActiveTabGrants: [
                ChromeMV3ActiveTabGrant(
                    extensionID: "password-manager-fixture",
                    profileID: "diagnostic-profile",
                    tabID: 1,
                    scope: .origin("https://example.com"),
                    reason: .testFixture,
                    userGestureModeled: true,
                    createdSequence: 1
                ),
            ],
            lifecycleEvents: [
                ChromeMV3PermissionLifecycleEvent(
                    kind: .tabNavigated,
                    extensionID: "password-manager-fixture",
                    profileID: "diagnostic-profile",
                    tabID: 1,
                    oldURL: "https://example.com/login",
                    newURL: "https://chromium.org/",
                    sequence: 2
                ),
            ]
        )
        let first = try ChromeMV3DeterministicJSON.encodedData(report)
        let second = try ChromeMV3DeterministicJSON.encodedData(report)

        try ChromeMV3PermissionLifecycleReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        let decoded = try JSONDecoder().decode(
            ChromeMV3PermissionLifecycleReport.self,
            from: Data(
                contentsOf: root.appendingPathComponent(
                    ChromeMV3PermissionLifecycleReportWriter.reportFileName
                )
            )
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(decoded, report)
        XCTAssertEqual(report.summary.expiredGrantCount, 1)
        XCTAssertFalse(report.canPromptUserNow)
        XCTAssertFalse(report.canDispatchMessagesNow)
        XCTAssertFalse(report.canRegisterListenersNow)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(
            report.passwordManagerPermissionReadiness
                .passwordManagerPermissionReady
        )
        XCTAssertEqual(
            report.passwordManagerPermissionReadiness.loginPageURL,
            "https://example.com/login"
        )
        XCTAssertTrue(
            report.passwordManagerPermissionReadiness
                .nativeMessagingPermissionStillBlockedByNativeMessagingLayer
        )
        XCTAssertTrue(
            report.passwordManagerPermissionReadiness
                .storagePermissionStillBlockedByStorageRuntime
        )
    }

    @MainActor
    func testSumiExtensionsModuleWritesPermissionLifecycleReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            makePrerequisitesReport(),
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3PermissionLifecycleReportWriter.reportFileName
        )
        let disabledHarness = TestDefaultsHarness()
        defer { disabledHarness.reset() }
        let disabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: disabledHarness.defaults)
        )
        let disabledModule = SumiExtensionsModule(
            moduleRegistry: disabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let disabledReport =
            disabledModule.chromeMV3PermissionLifecycleReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabledHarness = TestDefaultsHarness()
        defer { enabledHarness.reset() }
        let enabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: enabledHarness.defaults)
        )
        enabledRegistry.enable(.extensions)
        let enabledModule = SumiExtensionsModule(
            moduleRegistry: enabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let enabledReport = try XCTUnwrap(
            enabledModule.chromeMV3PermissionLifecycleReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.permissionLifecycleReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    func testMissingActiveTabMapsToActiveTabMissing() {
        let route = route(
            .serviceWorkerToTab,
            targetURL: "https://example.com/login"
        )
        let broker = permissionBroker(required: ["activeTab"])
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(route: route)

        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionBroker: broker,
            readiness: readiness(contextLoaded: true)
        )

        XCTAssertFalse(
            evaluation.permissionDecision.allowedForFutureDispatch
        )
        XCTAssertEqual(evaluation.errorContract?.error, .activeTabMissing)
    }

    func testServiceWorkerToTabAndTabsSendMessageUseBrokerDecision() {
        let broker = permissionBroker(
            hostPermissions: ["https://example.com/*"]
        )

        for kind in [
            ChromeMV3RuntimeMessagingRouteKind.serviceWorkerToTab,
            .tabsSendMessage,
        ] {
            let route = route(kind, targetURL: "https://example.com/login")
            let decision = ChromeMV3RuntimeMessagingPermissionDecision
                .evaluate(route: route, permissionBroker: broker)

            XCTAssertTrue(decision.allowedForFutureDispatch, kind.rawValue)
            XCTAssertTrue(
                decision.hostAccessDecision?.allowedByHostPermission == true,
                kind.rawValue
            )
        }
    }

    func testContentScriptToServiceWorkerRecordsHostAccessRequirement() {
        let route = route(
            .contentScriptToServiceWorker,
            sourceURL: "https://example.com/login"
        )
        let broker = permissionBroker()
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionBroker: broker
        )

        XCTAssertFalse(decision.allowedForFutureDispatch)
        XCTAssertEqual(
            decision.hostAccessDecision?.missingReason,
            .hostPermissionMissing
        )
        XCTAssertTrue(
            decision.brokerDiagnostics.contains {
                $0.contains("Host access decision")
            }
        )
    }

    func testListenerDiagnosticsIncludePermissionBrokerBlockers() {
        let report = ChromeMV3RuntimeListenerContractReportGenerator
            .makeReport(
                prerequisitesReport:
                    makePrerequisitesReport(hostPermissions: [])
            )
        let statuses = report.eventSurfaceCapabilityMatrix
            .first { $0.surface == .tabsMessageContentScript }?
            .statuses ?? []
        let resolution = report.listenerResolutionContractCoverage
            .first { $0.routeKind == .tabsSendMessage }

        XCTAssertTrue(statuses.contains(.permissionBrokerModeled))
        XCTAssertTrue(statuses.contains(.blockedByMissingHostAccess))
        XCTAssertEqual(
            resolution?.errorContract?.error,
            .hostPermissionMissing
        )
        XCTAssertTrue(
            resolution?.diagnostics.contains {
                $0.contains("Host access decision")
            } == true
        )
    }

    func testPermissionReadinessReportIncludesPasswordManagerBlockers() {
        let report = ChromeMV3PermissionBrokerReadinessReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let password = report.passwordManagerPermissionReadiness

        XCTAssertTrue(password.hostPermissionsDetected)
        XCTAssertTrue(password.contentScriptHostAccessRequired)
        XCTAssertTrue(
            password
                .actionPopupUserGestureMayCreateActiveTabGrantInFuture
        )
        XCTAssertTrue(password.nativeMessagingPermissionDetectedButBlocked)
        XCTAssertTrue(password.storagePermissionDetectedButRuntimeMissing)
        XCTAssertTrue(password.runtimeMessagingBlocked)
        XCTAssertTrue(password.permissionBrokerSkeletonPresent)
        XCTAssertFalse(password.realPermissionPromptsImplemented)
        XCTAssertFalse(password.passwordManagerPermissionReady)
    }

    func testPermissionReadinessReportKeepsRuntimeFlagsFalse() {
        let report = ChromeMV3PermissionBrokerReadinessReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())

        XCTAssertFalse(report.canGrantPermissionsNow)
        XCTAssertFalse(report.canPromptUserNow)
        XCTAssertFalse(report.canDispatchMessagesNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(
            report.passwordManagerPermissionReadiness
                .passwordManagerPermissionReady
        )
        XCTAssertFalse(report.summary.canPromptUserNow)
        XCTAssertFalse(report.summary.canDispatchMessagesNow)
        XCTAssertFalse(report.summary.canLoadContextNow)
        XCTAssertFalse(report.summary.runtimeLoadable)
    }

    func testPermissionReadinessReportIsDeterministicAndWritable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3PermissionBrokerReadinessReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let first = try ChromeMV3DeterministicJSON.encodedData(report)
        let second = try ChromeMV3DeterministicJSON.encodedData(report)

        try ChromeMV3PermissionBrokerReadinessReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        let decoded = try JSONDecoder().decode(
            ChromeMV3PermissionBrokerReadinessReport.self,
            from: Data(
                contentsOf: root.appendingPathComponent(
                    ChromeMV3PermissionBrokerReadinessReportWriter
                        .reportFileName
                )
            )
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(decoded, report)
    }

    func testPermissionsAPIContainsReturnsTrueForDeclaredAPIPermission() {
        let store = permissionDecisionStore(required: ["tabs"])
        let result = ChromeMV3PermissionsAPIContractEvaluator.contains(
            input: permissionsAPIInput(permissions: ["tabs"]),
            permissionStore: store
        )

        XCTAssertTrue(result.wouldReturn)
        XCTAssertFalse(result.runtimeImplementedNow)
        XCTAssertEqual(
            result.permissionDecisions.first?.grantSource,
            .requiredPermission
        )
    }

    func testPermissionsAPIContainsReturnsTrueForDeclaredHostOrigin() {
        let store = permissionDecisionStore(
            hostPermissions: ["https://example.com/*"]
        )
        let result = ChromeMV3PermissionsAPIContractEvaluator.contains(
            input: permissionsAPIInput(origins: ["https://example.com/login"]),
            permissionStore: store
        )

        XCTAssertTrue(result.wouldReturn)
        XCTAssertTrue(result.originDecisions.first?.hasHostAccess == true)
    }

    func testPermissionsAPIContainsReturnsFalseForMissingOptionalPermission() {
        let store = permissionDecisionStore(optional: ["history"])
        let result = ChromeMV3PermissionsAPIContractEvaluator.contains(
            input: permissionsAPIInput(permissions: ["history"]),
            permissionStore: store
        )

        XCTAssertFalse(result.wouldReturn)
        XCTAssertEqual(result.permissionDecisions.first?.status, .promptRequired)
    }

    func testPermissionsAPIContainsReturnsFalseForRevokedOrigin() {
        let store = permissionDecisionStore(
            hostPermissions: ["https://example.com/*"],
            revoked: ["https://example.com/*"]
        )
        let result = ChromeMV3PermissionsAPIContractEvaluator.contains(
            input: permissionsAPIInput(origins: ["https://example.com/login"]),
            permissionStore: store
        )

        XCTAssertFalse(result.wouldReturn)
        XCTAssertEqual(result.originDecisions.first?.status, .revoked)
        XCTAssertTrue(
            result.blockedDiagnostics.contains {
                $0.contains("revoked")
            }
        )
    }

    func testPermissionsAPIGetAllReturnsDeterministicCurrentGrantList()
        throws
    {
        let store = permissionDecisionStore(
            required: ["tabs", "storage"],
            optional: ["history"],
            grantedOptional: ["history"],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: ["https://optional.example/*"],
            grantedOptionalHostPermissions: ["https://optional.example/*"],
            denied: ["tabs"],
            deferred: ["storage"],
            unsupported: ["debugger"]
        )
        let result = ChromeMV3PermissionsAPIContractEvaluator.getAll(
            permissionStore: store
        )
        let first = try ChromeMV3DeterministicJSON.encodedData(result)
        let second = try ChromeMV3DeterministicJSON.encodedData(result)

        XCTAssertEqual(first, second)
        XCTAssertEqual(result.permissions, ["history"])
        XCTAssertEqual(
            result.origins,
            ["https://example.com/*", "https://optional.example/*"]
        )
        XCTAssertEqual(result.excludedDeferredPermissions, ["storage"])
        XCTAssertFalse(result.runtimeImplementedNow)
    }

    func testPermissionsAPIRequestClassifiesAlreadyGrantedPermission() {
        let store = permissionDecisionStore(required: ["tabs"])
        let result = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: permissionsAPIInput(
                userGestureModeled: true,
                permissions: ["tabs"]
            ),
            permissionStore: store
        )

        XCTAssertEqual(
            result.itemDecisions.first?.classification,
            .alreadyGranted
        )
        XCTAssertTrue(result.wouldBeAllowedByModel)
        XCTAssertFalse(result.canPromptUserNow)
    }

    func testPermissionsAPIRequestClassifiesOptionalPermissionAsPromptRequired()
    {
        let store = permissionDecisionStore(optional: ["history"])
        let result = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: permissionsAPIInput(
                sourceContext: .actionPopup,
                userGestureModeled: true,
                permissions: ["history"]
            ),
            permissionStore: store
        )

        XCTAssertEqual(
            result.itemDecisions.first?.classification,
            .requestableOptionalPermission
        )
        XCTAssertTrue(result.wouldRequirePrompt)
        XCTAssertTrue(result.wouldGrantIfUserAccepted)
        XCTAssertFalse(result.canPromptUserNow)
    }

    func testPermissionsAPIRequestClassifiesOptionalOriginAsPromptRequired() {
        let store = permissionDecisionStore(
            optionalHostPermissions: ["https://*/*"]
        )
        let result = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: permissionsAPIInput(
                sourceContext: .actionPopup,
                userGestureModeled: true,
                origins: ["https://example.com/"]
            ),
            permissionStore: store
        )

        XCTAssertEqual(
            result.itemDecisions.first?.classification,
            .requestableOptionalOrigin
        )
        XCTAssertEqual(
            result.itemDecisions.first?.optionalDeclarationMatched,
            ["https://*/*"]
        )
        XCTAssertTrue(result.wouldRequirePrompt)
    }

    func testPermissionsAPIRequestRejectsNonOptionalUndeclaredPermission() {
        let result = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: permissionsAPIInput(
                userGestureModeled: true,
                permissions: ["bookmarks"]
            ),
            permissionStore: permissionDecisionStore()
        )

        XCTAssertEqual(
            result.itemDecisions.first?.classification,
            .notDeclaredOptional
        )
        XCTAssertTrue(result.wouldBeDeniedByModel)
    }

    func testPermissionsAPIRequestRejectsMissingUserGesture() {
        let store = permissionDecisionStore(optional: ["history"])
        let result = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: permissionsAPIInput(
                sourceContext: .actionPopup,
                userGestureModeled: false,
                permissions: ["history"]
            ),
            permissionStore: store
        )

        XCTAssertEqual(
            result.itemDecisions.first?.classification,
            .missingUserGesture
        )
        XCTAssertTrue(result.itemDecisions.first?.missingUserGesture == true)
        XCTAssertFalse(result.wouldRequirePrompt)
    }

    func testPermissionsAPIRequestClassifiesUnsupportedAndDeferredPermissions()
    {
        let store = permissionDecisionStore(
            deferred: ["storage"],
            unsupported: ["debugger"]
        )
        let result = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: permissionsAPIInput(
                userGestureModeled: true,
                permissions: ["debugger", "storage"]
            ),
            permissionStore: store
        )

        XCTAssertEqual(
            result.itemDecisions.map(\.classification),
            [.unsupportedPermission, .deferredPermission]
        )
        XCTAssertTrue(result.wouldBeDeniedByModel)
    }

    func testPermissionsAPIRemoveRejectsRequiredManifestPermission() {
        let store = permissionDecisionStore(required: ["tabs"])
        let result = ChromeMV3PermissionsAPIContractEvaluator.remove(
            input: permissionsAPIInput(permissions: ["tabs"]),
            permissionStore: store
        )

        XCTAssertFalse(result.wouldReturn)
        XCTAssertEqual(
            result.itemDecisions.first?.classification,
            .requiredManifestPermission
        )
    }

    func testPermissionsAPIRemoveAllowsOptionalPermissionAndExpiresActiveTab()
    {
        let store = permissionDecisionStore(
            optional: ["history"],
            grantedOptional: ["history"]
        )
        let activeTabStore = ChromeMV3ActiveTabGrantStore
            .empty(extensionID: "extension-a", profileID: "profile-a")
            .addingModeledGrant(
                tabID: 42,
                url: "https://example.com/login",
                reason: .testFixture,
                sequence: 1
            )
        let applied = ChromeMV3PermissionsAPIContractEvaluator
            .applyingRemove(
                input: permissionsAPIInput(permissions: ["history"]),
                permissionStore: store,
                activeTabStore: activeTabStore,
                sequence: 2
            )

        XCTAssertTrue(applied.result.wouldReturn)
        XCTAssertTrue(applied.result.wouldRevokeModeledPermissions)
        XCTAssertTrue(applied.result.wouldExpireActiveTabGrants)
        XCTAssertEqual(
            applied.permissionStore.apiPermissionDecision("history").status,
            .revoked
        )
        XCTAssertFalse(
            applied.activeTabStore.hasActiveTabGrant(
                tabID: 42,
                url: "https://example.com/login"
            )
        )
    }

    func testPermissionsAPIRemoveAllowsOptionalOriginRemoval() {
        let store = permissionDecisionStore(
            optionalHostPermissions: ["https://example.com/*"],
            grantedOptionalHostPermissions: ["https://example.com/*"]
        )
        let applied = ChromeMV3PermissionsAPIContractEvaluator
            .applyingRemove(
                input: permissionsAPIInput(
                    origins: ["https://example.com/*"]
                ),
                permissionStore: store,
                activeTabStore:
                    ChromeMV3ActiveTabGrantStore.empty(
                        extensionID: "extension-a",
                        profileID: "profile-a"
                    ),
                sequence: 1
            )

        XCTAssertTrue(applied.result.wouldReturn)
        XCTAssertEqual(
            applied.result.itemDecisions.first?.classification,
            .removedOptionalOrigin
        )
        XCTAssertEqual(
            applied.permissionStore.hostAccessDecision(
                url: "https://example.com/login"
            ).status,
            .revoked
        )
    }

    func testPermissionsAPIOnAddedPayloadIsDeterministicButNotDispatched()
        throws
    {
        let store = permissionDecisionStore(optional: ["history"])
        let request = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: permissionsAPIInput(
                sourceContext: .actionPopup,
                userGestureModeled: true,
                permissions: ["history"]
            ),
            permissionStore: store
        )
        let payload = try XCTUnwrap(request.eventPayloadIfAccepted)
        let first = try ChromeMV3DeterministicJSON.encodedData(payload)
        let second = try ChromeMV3DeterministicJSON.encodedData(payload)

        XCTAssertEqual(first, second)
        XCTAssertEqual(payload.eventKind, .onAdded)
        XCTAssertEqual(payload.permissions, ["history"])
        XCTAssertFalse(payload.wouldDispatchNow)
        XCTAssertTrue(payload.listenerRegistrationRequired)
        XCTAssertFalse(payload.serviceWorkerWakeRequired)
    }

    func testPermissionsAPIOnRemovedPayloadIsDeterministicButNotDispatched()
        throws
    {
        let store = permissionDecisionStore(
            optional: ["history"],
            grantedOptional: ["history"]
        )
        let applied = ChromeMV3PermissionsAPIContractEvaluator
            .applyingRemove(
                input: permissionsAPIInput(permissions: ["history"]),
                permissionStore: store,
                activeTabStore:
                    ChromeMV3ActiveTabGrantStore.empty(
                        extensionID: "extension-a",
                        profileID: "profile-a"
                    ),
                sequence: 1
            )
        let payload = try XCTUnwrap(applied.result.eventPayloadIfApplied)
        let first = try ChromeMV3DeterministicJSON.encodedData(payload)
        let second = try ChromeMV3DeterministicJSON.encodedData(payload)

        XCTAssertEqual(first, second)
        XCTAssertEqual(payload.eventKind, .onRemoved)
        XCTAssertEqual(payload.permissions, ["history"])
        XCTAssertFalse(payload.wouldDispatchNow)
        XCTAssertFalse(payload.canRegisterListenersNow)
        XCTAssertFalse(payload.canWakeServiceWorkerNow)
    }

    func testPermissionsAPIContractReportIsDeterministicAndBlocked()
        throws
    {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3PermissionsAPIContractReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let first = try ChromeMV3DeterministicJSON.encodedData(report)
        let second = try ChromeMV3DeterministicJSON.encodedData(report)

        try ChromeMV3PermissionsAPIContractReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )
        let decoded = try JSONDecoder().decode(
            ChromeMV3PermissionsAPIContractReport.self,
            from: Data(
                contentsOf: root.appendingPathComponent(
                    ChromeMV3PermissionsAPIContractReportWriter.reportFileName
                )
            )
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(decoded, report)
        XCTAssertTrue(report.contractSummary.containsModeled)
        XCTAssertTrue(report.contractSummary.requestModeled)
        XCTAssertTrue(report.contractSummary.onAddedModeled)
        XCTAssertTrue(report.contractSummary.onRemovedModeled)
        XCTAssertFalse(report.canPromptUserNow)
        XCTAssertFalse(report.canDispatchPermissionEventNow)
        XCTAssertFalse(report.canRegisterListenersNow)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canDispatchMessagesNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(
            report.passwordManagerPermissionAPIReadiness
                .passwordManagerPermissionAPIReady
        )
        XCTAssertTrue(
            report.passwordManagerPermissionAPIReadiness
                .runtimeMessagingBlockerRemains
        )
        XCTAssertTrue(
            report.passwordManagerPermissionAPIReadiness
                .nativeMessagingBlockerRemains
        )
    }

    @MainActor
    func testSumiExtensionsModuleWritesPermissionsAPIContractReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            makePrerequisitesReport(),
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3PermissionsAPIContractReportWriter.reportFileName
        )
        let disabledHarness = TestDefaultsHarness()
        defer { disabledHarness.reset() }
        let disabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: disabledHarness.defaults)
        )
        let disabledModule = SumiExtensionsModule(
            moduleRegistry: disabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let disabledReport =
            disabledModule.chromeMV3PermissionsAPIContractReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabledHarness = TestDefaultsHarness()
        defer { enabledHarness.reset() }
        let enabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: enabledHarness.defaults)
        )
        enabledRegistry.enable(.extensions)
        let enabledModule = SumiExtensionsModule(
            moduleRegistry: enabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let enabledReport = try XCTUnwrap(
            enabledModule.chromeMV3PermissionsAPIContractReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.permissionsAPIContractReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    @MainActor
    func testSumiExtensionsModuleWritesPermissionReportOnlyWhenEnabled()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 module diagnostics require macOS 15.5.")
        }

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
            makePrerequisitesReport(),
            toRewrittenBundleRoot: root
        )
        let reportURL = root.appendingPathComponent(
            ChromeMV3PermissionBrokerReadinessReportWriter.reportFileName
        )
        let disabledHarness = TestDefaultsHarness()
        defer { disabledHarness.reset() }
        let disabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: disabledHarness.defaults)
        )
        let disabledModule = SumiExtensionsModule(
            moduleRegistry: disabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let disabledReport =
            disabledModule.chromeMV3PermissionBrokerReadinessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )

        XCTAssertNil(disabledReport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let enabledHarness = TestDefaultsHarness()
        defer { enabledHarness.reset() }
        let enabledRegistry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: enabledHarness.defaults)
        )
        enabledRegistry.enable(.extensions)
        let enabledModule = SumiExtensionsModule(
            moduleRegistry: enabledRegistry,
            browserConfiguration: BrowserConfiguration()
        )

        let enabledReport = try XCTUnwrap(
            enabledModule.chromeMV3PermissionBrokerReadinessReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.permissionBrokerReadinessReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    func testSourceLevelGuardsForPermissionBrokerLayer() throws {
        let sources = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "SumiTests",
        ])
        .filter {
            $0.relativePath.hasPrefix("Sumi/Models/Extension/ChromeMV3/")
                || $0.relativePath.hasPrefix("SumiTests/ChromeMV3")
        }
        let joined = sources.map(\.contents).joined(separator: "\n")
        let boundaryGuardJoined = sources
            .filter {
                $0.relativePath
                    != "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
            }
            .map(\.contents)
            .joined(separator: "\n")

        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(boundaryGuardJoined.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canCreate" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canDispatch" + "MessagesNow\\s*[:=].*" + "tr" + "ue",
            "canPrompt" + "UserNow\\s*[:=].*" + "tr" + "ue",
            "canDispatch" + "PermissionEventNow\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerPermissionReady\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerPermissionAPIReady\\s*[:=].*" + "tr" + "ue",
        ] {
            XCTAssertNil(
                joined.range(
                    of: forbiddenRegex,
                    options: .regularExpression
                ),
                forbiddenRegex
            )
        }
    }

    private func route(
        _ kind: ChromeMV3RuntimeMessagingRouteKind,
        frameID: Int? = 0,
        documentID: String? = "document-0",
        sourceURL: String? = nil,
        targetURL: String? = nil
    ) -> ChromeMV3RuntimeMessagingRoute {
        ChromeMV3RuntimeMessagingRoute.make(
            kind: kind,
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 42,
            frameID: frameID,
            documentID: documentID,
            sourceURL: sourceURL,
            targetURL: targetURL
        )
    }

    private func permissionBroker(
        required: [String] = [],
        optional: [String] = [],
        grantedOptional: [String] = [],
        hostPermissions: [String] = [],
        optionalHostPermissions: [String] = [],
        grantedOptionalHostPermissions: [String] = [],
        denied: [String] = [],
        unavailable: [String] = [],
        unsupported: [String] = [],
        activeTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PermissionBroker {
        ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: "extension-a",
                profileID: "profile-a",
                requiredPermissions: required,
                optionalPermissions: optional,
                grantedOptionalPermissions: grantedOptional,
                hostPermissions: hostPermissions,
                optionalHostPermissions: optionalHostPermissions,
                grantedOptionalHostPermissions:
                    grantedOptionalHostPermissions,
                deniedPermissions: denied,
                unavailablePermissions: unavailable,
                unsupportedPermissions: unsupported,
                activeTabGrants: activeTabGrants
            )
        )
    }

    private func permissionDecisionStore(
        required: [String] = [],
        optional: [String] = [],
        grantedOptional: [String] = [],
        hostPermissions: [String] = [],
        optionalHostPermissions: [String] = [],
        grantedOptionalHostPermissions: [String] = [],
        denied: [String] = [],
        revoked: [String] = [],
        deferred: [String] = [],
        unsupported: [String] = []
    ) -> ChromeMV3PermissionDecisionStore {
        ChromeMV3PermissionDecisionStore(
            snapshot: ChromeMV3PermissionDecisionStoreSnapshot(
                extensionID: "extension-a",
                profileID: "profile-a",
                declaredAPIPermissions: required,
                declaredHostPermissions: hostPermissions,
                optionalAPIPermissions: optional,
                optionalHostPermissions: optionalHostPermissions,
                grantedOptionalAPIPermissions: grantedOptional,
                grantedOptionalHostPermissions:
                    grantedOptionalHostPermissions,
                deniedPermissions: denied,
                revokedPermissions: revoked,
                deferredPermissions: deferred,
                unsupportedPermissions: unsupported
            )
        )
    }

    private func permissionsAPIInput(
        sourceContext: ChromeMV3PermissionsAPIRequestSourceContext =
            .testFixture,
        userGestureModeled: Bool = false,
        extensionModuleEnabled: Bool = true,
        permissions: [String] = [],
        origins: [String] = []
    ) -> ChromeMV3PermissionsAPIRequestInput {
        ChromeMV3PermissionsAPIRequestInput(
            extensionID: "extension-a",
            profileID: "profile-a",
            sourceContext: sourceContext,
            userGestureModeled: userGestureModeled,
            extensionModuleEnabled: extensionModuleEnabled,
            permissions: permissions,
            origins: origins
        )
    }

    private func activeTabGrant(
        tabID: Int,
        origin: String
    ) -> ChromeMV3ActiveTabGrant {
        ChromeMV3ActiveTabGrant(
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: tabID,
            scope: .origin(origin),
            reason: .testFixture,
            userGestureModeled: true,
            createdSequence: 1
        )
    }

    private func readiness(
        contextLoaded: Bool = false,
        receiverListenerRegistered: Bool = false,
        serviceWorkerLifecycleReady: Bool = false,
        targetTabExists: Bool = true,
        targetFrameExists: Bool = true
    ) -> ChromeMV3RuntimeMessagingReadinessSnapshot {
        ChromeMV3RuntimeMessagingReadinessSnapshot(
            extensionModuleEnabled: true,
            contextLoaded: contextLoaded,
            targetTabExists: targetTabExists,
            targetFrameExists: targetFrameExists,
            receiverListenerRegistered: receiverListenerRegistered,
            serviceWorkerLifecycleReady: serviceWorkerLifecycleReady,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false
        )
    }

    private func makePrerequisitesReport(
        hostPermissions: [String] = ["https://example.com/*"]
    ) -> ChromeMV3RuntimeBridgePrerequisitesReport {
        ChromeMV3RuntimeBridgePrerequisitesReport(
            schemaVersion: 1,
            id: "runtime-prerequisites-test",
            reportFileName:
                ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName,
            candidateID: "password-manager-fixture",
            generatedRewrittenRootPath: "/tmp/password-manager-fixture",
            contextReadinessReportID: "context-readiness-test",
            contextReadinessReportPath:
                "/tmp/password-manager-fixture/context-readiness-report.json",
            contextReadinessReportHash: String(repeating: "a", count: 64),
            contextReadinessConsumerDiagnostic:
                ChromeMV3ContextReadinessReportConsumptionDiagnostic(
                    schemaVersion: 1,
                    reportFileName:
                        ChromeMV3ContextReadinessReportWriter.reportFileName,
                    reportPath:
                        "/tmp/password-manager-fixture/context-readiness-report.json",
                    state: .ready,
                    canImplementRecommendedBranch: true,
                    nextRequiredPromptCategory:
                        .addRuntimeBridgePrerequisites,
                    rawNextRequiredPromptCategory:
                        "addRuntimeBridgePrerequisites",
                    allowedNextRequiredPromptCategories: [
                        "addRuntimeBridgePrerequisites",
                    ],
                    blockingReasons: [],
                    warnings: [],
                    requiredActions: []
                ),
            manifestFacts: manifestFacts(hostPermissions: hostPermissions),
            runtimeMessagingPrerequisites: runtimeMessagingPrerequisites(),
            nativeMessagingPrerequisites: nativeMessagingPrerequisites(),
            storagePrerequisites: storagePrerequisites(),
            permissionsActiveTabPrerequisites:
                permissionsPrerequisites(hostPermissions: hostPermissions),
            serviceWorkerLifecyclePrerequisites: lifecyclePrerequisites(),
            passwordManagerPrerequisiteSummary:
                passwordSummary(hostPermissions: hostPermissions),
            unsupportedDeferredAPIs:
                ChromeMV3UnsupportedDeferredAPISummary(
                    unsupportedAPIs: [],
                    deferredAPIs: [.nativeMessaging],
                    unsupportedDeferredAPIsRemainRuntimeBlockers: true
                ),
            modeledOnlyComponents: ["runtime messaging routes"],
            blockedComponents: ["runtime message dispatch"],
            requiredFutureComponents: ["runtime messaging dispatcher"],
            unsupportedOrDeferredAPIs: [.nativeMessaging],
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            contextCreationBlockedReason:
                "Context creation remains blocked.",
            contextLoadingBlockedReason:
                "Context loading remains blocked.",
            runtimeLoadableFalseReason:
                "runtimeLoadable remains false.",
            nextRequiredCategoryAfterThisReport:
                .implementRuntimeBridgeComponents,
            documentationSources: [],
            warnings: []
        )
    }

    private func manifestFacts(hostPermissions: [String])
        -> ChromeMV3RuntimeBridgeManifestFacts
    {
        ChromeMV3RuntimeBridgeManifestFacts(
            manifestReadStatus: .loaded,
            manifestPath: "/tmp/password-manager-fixture/manifest.json",
            manifestSHA256: String(repeating: "b", count: 64),
            declaredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: [],
            hostPermissions: hostPermissions,
            optionalHostPermissions: [],
            contentScriptsPresent: true,
            contentScriptMatchPatterns:
                hostPermissions.isEmpty
                    ? ["https://example.com/*"]
                    : hostPermissions,
            actionPopupPresent: true,
            backgroundServiceWorkerPresent: true,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            activeTabPermissionPresent: false,
            permissionsAPIPresent: false,
            warnings: []
        )
    }

    private func runtimeMessagingPrerequisites()
        -> ChromeMV3RuntimeMessagingContract
    {
        ChromeMV3RuntimeMessagingContract(
            status: .notImplemented,
            implementedNow: false,
            dispatchImplemented: false,
            listenerDeliveryImplemented: false,
            callbackCompatibilityRequired: true,
            promiseCompatibilityRequired: true,
            lastErrorRequirement:
                "Chrome-style lastError contract required.",
            timeoutPolicyRequired: true,
            timeoutPolicy: "No runtime schedule in this layer.",
            routes: [
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "contentScriptToServiceWorker",
                    requiredAPI: "runtime.sendMessage",
                    requiresServiceWorkerWakePolicy: true,
                    requiresTabAddressing: true,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "serviceWorkerToTabContentScript",
                    requiredAPI: "tabs.sendMessage",
                    requiresServiceWorkerWakePolicy: false,
                    requiresTabAddressing: true,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
                ChromeMV3RuntimeMessagingRouteContract(
                    route: "contentScriptLongLivedPortToExtension",
                    requiredAPI: "runtime.connect",
                    requiresServiceWorkerWakePolicy: true,
                    requiresTabAddressing: true,
                    implementedNow: false,
                    blockedReason: "Modeled only."
                ),
            ],
            portLifecycleRequirements: ["Port model required."],
            disconnectReasons: ["tabClosed"],
            contentScriptMessagingRestrictions: [
                "Content scripts message extension contexts.",
            ],
            requiredBeforePasswordManagerSupport: true,
            requiredBeforeRuntimeLoadability: true,
            blockers: ["Runtime messaging is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func nativeMessagingPrerequisites()
        -> ChromeMV3NativeMessagingPrerequisites
    {
        ChromeMV3NativeMessagingPrerequisites(
            status: .blocked,
            nativeMessagingDetected: true,
            nativeMessagingBlocked: true,
            hostManifestLookupImplemented: true,
            hostValidationImplemented: true,
            userConsentImplemented: false,
            processLaunchImplemented: false,
            stdioFramingRequired: true,
            inboundHostMessageLimitBytes: 1_048_576,
            outboundHostMessageLimitBytes: 67_108_864,
            portLifecycleModeled: true,
            hostExitBehaviorModeled: true,
            disabledModuleBehavior: "No native messaging runtime.",
            noLaunchWhileExtensionsDisabled: true,
            noLaunchBeforeExplicitImplementation: true,
            requiredBeforePasswordManagerSupport: true,
            futureSecurityReviewRequired: true,
            blockers: ["Native messaging remains blocked."],
            hostManifestLookupRequirements: [],
            allowedHostValidationRequirements: [],
            futureTestsNeeded: []
        )
    }

    private func storagePrerequisites() -> ChromeMV3StoragePrerequisites {
        ChromeMV3StoragePrerequisites(
            status: .notImplemented,
            storagePermissionPresent: true,
            implementedNow: false,
            webKitBehaviorSufficientWithoutHostLayer: false,
            hostBackedLayerDecisionRequired: true,
            profileIsolationVerified: false,
            workerUnloadReloadStateVerified: false,
            passwordManagerStateRequirements: [],
            areas: ChromeMV3StorageAreaName.allCases.map {
                ChromeMV3StorageAreaPrerequisite(
                    area: $0,
                    required: true,
                    implementedNow: false,
                    persistenceExpectation: "Modeled.",
                    contentScriptExposureDefault: "Modeled.",
                    decisionRequired: "Future decision required.",
                    blockers: ["Storage is not implemented."]
                )
            },
            blockers: ["Storage is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func permissionsPrerequisites(hostPermissions: [String])
        -> ChromeMV3PermissionsActiveTabPrerequisites
    {
        ChromeMV3PermissionsActiveTabPrerequisites(
            status: .modeled,
            requiredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: [],
            hostPermissions: hostPermissions,
            optionalHostPermissions: [],
            activeTabDeclared: false,
            permissionBrokerImplemented: true,
            activeTabImplemented: true,
            hostPermissionEvaluationImplemented: true,
            userGestureRequirementModeled: true,
            grantLifetimeRequirement: "Modeled.",
            tabNavigationInvalidationRequirement: "Modeled.",
            permissionPromptUIFutureRequirement: true,
            contentScriptExecutionInteraction: "Blocked.",
            passwordManagerHostAccessRequirement: "Required.",
            requiredBeforeContentScriptExecution: true,
            requiredBeforePasswordManagerSupport: true,
            blockers: ["Real permission prompts are not implemented."],
            futureTestsNeeded: []
        )
    }

    private func lifecyclePrerequisites()
        -> ChromeMV3ServiceWorkerLifecycleReadiness
    {
        ChromeMV3ServiceWorkerLifecycleReadiness(
            status: .notImplemented,
            lifecycleCoordinatorImplemented: false,
            serviceWorkerWakeImplemented: false,
            idleUnloadPolicyModeled: true,
            permanentBackgroundForbidden: true,
            requiredBeforeContextLoad: true,
            requiredBeforeContextLoadReason: "Required.",
            requiredBeforeRuntimeLoadability: true,
            wakeReasonsRequired: ["runtime message"],
            eventDispatchPrerequisites: ["message dispatch"],
            idleReleasePolicy: "Modeled.",
            hardTimeoutPolicy: "Modeled.",
            longLivedPortPolicy: "Modeled.",
            nativeMessagingPortPolicy: "Blocked.",
            alarmWakePolicy: "Modeled.",
            statePersistenceRequirements: [],
            diagnosticsRequired: [],
            blockers: ["Service-worker wake is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func passwordSummary(hostPermissions: [String])
        -> ChromeMV3PasswordManagerPrerequisiteSummary
    {
        ChromeMV3PasswordManagerPrerequisiteSummary(
            contentScriptsPresent: true,
            actionPopupPresent: true,
            hostPermissionsPresent: hostPermissions.isEmpty == false,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            runtimeMessagingMissing: true,
            permissionActiveTabMissing: true,
            storageBackendMissingOrDeferred: true,
            nativeMessagingMissing: true,
            controlledInputPageWorldBehaviorNotVerified: true,
            serviceWorkerLifecycleNotVerified: true,
            passwordManagerSupportReady: false,
            blockers: ["Password-manager permissions are not ready."],
            deferredChecks: []
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static func sourceFiles(
        in relativeDirectories: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        let root = projectRoot()
        var files: [(relativePath: String, contents: String)] = []
        for relativeDirectory in relativeDirectories {
            let directory = root.appendingPathComponent(
                relativeDirectory,
                isDirectory: true
            )
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            else { continue }

            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey,
                ])
                guard values.isRegularFile == true,
                      url.pathExtension == "swift"
                else { continue }
                let relativePath = String(
                    url.standardizedFileURL.path.dropFirst(
                        root.standardizedFileURL.path.count + 1
                    )
                )
                files.append(
                    (
                        relativePath,
                        try String(contentsOf: url, encoding: .utf8)
                    )
                )
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
