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

        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "Pro" + "cess(",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(joined.contains(forbidden), forbidden)
        }

        for forbiddenRegex in [
            "runtime" + "Loadable\\s*[:=].*" + "tr" + "ue",
            "canCreate" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canLoad" + "ContextNow\\s*[:=].*" + "tr" + "ue",
            "canDispatch" + "MessagesNow\\s*[:=].*" + "tr" + "ue",
            "canPrompt" + "UserNow\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerPermissionReady\\s*[:=].*" + "tr" + "ue",
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
            hostManifestLookupImplemented: false,
            hostValidationImplemented: false,
            userConsentImplemented: false,
            processLaunchImplemented: false,
            stdioFramingRequired: true,
            inboundHostMessageLimitBytes: 1_048_576,
            outboundHostMessageLimitBytes: 4_294_967_296,
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
