import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3RuntimeListenerContractTests: XCTestCase {
    func testAllRequiredListenerSurfacesAreModeled() {
        let surfaces = ChromeMV3RuntimeListenerSurface.allModeledSurfaces(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertEqual(
            Set(surfaces.map(\.surface)),
            Set(ChromeMV3RuntimeListenerSurfaceKind.allCases)
        )
        XCTAssertTrue(surfaces.allSatisfy { $0.implementedNow == false })
    }

    func testRuntimeOnMessageServiceWorkerListenerIsModeledButUnavailable() {
        let surface = surface(.runtimeOnMessageServiceWorker)
        let contract =
            ChromeMV3RuntimeListenerRegistrationContract.make(
                surface: surface
            )

        XCTAssertEqual(surface.owningContext, .serviceWorker)
        XCTAssertTrue(surface.requiresServiceWorkerContext)
        XCTAssertFalse(surface.implementedNow)
        XCTAssertFalse(contract.registrationAllowedNow)
        XCTAssertFalse(contract.registersRealListenerNow)
        XCTAssertTrue(
            surface.blockers.contains(
                "Service-worker context and wake are not implemented."
            )
        )
    }

    func testRuntimeOnConnectServiceWorkerListenerIsModeledButUnavailable() {
        let surface = surface(.runtimeOnConnectServiceWorker)
        let contract =
            ChromeMV3RuntimeListenerRegistrationContract.make(
                surface: surface
            )

        XCTAssertEqual(surface.eventName, "chrome.runtime.onConnect")
        XCTAssertEqual(surface.owningContext, .serviceWorker)
        XCTAssertTrue(surface.requiresServiceWorkerContext)
        XCTAssertFalse(contract.registrationAllowedNow)
        XCTAssertEqual(
            contract.serviceWorkerIdleUnloadRelationship,
            .serviceWorkerCanUnloadAndMustReregisterOnFutureWake
        )
    }

    func testContentScriptListenerSurfacesAreBlockedByMissingInjection() {
        let surfaces = [
            surface(.runtimeOnMessageContentScript),
            surface(.runtimeOnConnectContentScript),
            surface(.tabsMessageContentScript),
            surface(.tabsConnectContentScript),
        ]

        for surface in surfaces {
            XCTAssertEqual(surface.owningContext, .contentScript)
            XCTAssertTrue(surface.requiresContentScriptInjection)
            XCTAssertTrue(surface.requiresTabFrameTargeting)
            XCTAssertTrue(surface.requiresPermissionActiveTabGate)
            XCTAssertFalse(surface.implementedNow)
            XCTAssertTrue(
                surface.blockers.contains(
                    "Content-script injection is not implemented."
                ),
                surface.surface.rawValue
            )
        }
    }

    func testPopupAndOptionsListenerSurfacesAreBlockedByMissingPageHost() {
        for kind in [
            ChromeMV3RuntimeListenerSurfaceKind.actionPopupListener,
            .optionsPageListener,
        ] {
            let surface = surface(kind)

            XCTAssertTrue(surface.requiresExtensionPageHost)
            XCTAssertFalse(surface.implementedNow)
            XCTAssertTrue(
                surface.blockers.contains(
                    "Extension page, popup, and options hosts are not implemented."
                ),
                kind.rawValue
            )
        }
    }

    func testNativeMessagingListenerSurfaceIsBlockedAndDeferred() {
        let surface = surface(.nativeMessagingPortListener)
        let matrix = ChromeMV3RuntimeEventSurfaceCapability.matrix(
            surfaces: [surface]
        )
        let capability = try! XCTUnwrap(matrix.first)

        XCTAssertTrue(surface.requiresNativeMessaging)
        XCTAssertFalse(surface.implementedNow)
        XCTAssertTrue(
            capability.statuses.contains(.blockedByNativeMessagingDeferred)
        )
        XCTAssertTrue(capability.statuses.contains(.deferred))
    }

    func testEventSurfaceMatrixClassifiesBlockersDeterministically() throws {
        let surfaces = ChromeMV3RuntimeListenerSurface.allModeledSurfaces(
            extensionID: "extension-a",
            profileID: "profile-a"
        )
        let first = ChromeMV3RuntimeEventSurfaceCapability.matrix(
            surfaces: surfaces
        )
        let second = ChromeMV3RuntimeEventSurfaceCapability.matrix(
            surfaces: surfaces.reversed()
        )
        let bySurface = Dictionary(uniqueKeysWithValues: first.map {
            ($0.surface, $0)
        })

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            bySurface[.runtimeOnMessageServiceWorker]?.statuses,
            [
                .blockedByNoContext,
                .blockedByNoServiceWorkerWake,
                .modeled,
            ].sorted()
        )
        XCTAssertTrue(
            try XCTUnwrap(bySurface[.tabsMessageContentScript])
                .statuses
                .contains(.blockedByNoContentScriptInjection)
        )
        XCTAssertTrue(
            try XCTUnwrap(bySurface[.actionPopupListener])
                .statuses
                .contains(.blockedByNoExtensionPageHost)
        )
    }

    func testListenerRegistrationContractsNeverRegisterListeners() {
        let registry = ChromeMV3RuntimeListenerRegistrySnapshot.modeled(
            extensionID: "extension-a",
            profileID: "profile-a"
        )

        XCTAssertFalse(registry.listenerRegistrationImplementedNow)
        XCTAssertFalse(registry.dispatchImplementedNow)
        XCTAssertEqual(
            Set(registry.registrations.map(\.listenerSurface.surface)),
            Set(ChromeMV3RuntimeListenerSurfaceKind.allCases)
        )
        XCTAssertTrue(
            registry.registrations.allSatisfy {
                $0.registrationAllowedNow == false
                    && $0.registersRealListenerNow == false
            }
        )
    }

    func testListenerResolutionReturnsNoReceivingEndWhenRegistryIsEmpty() {
        let route = messageRoute(.tabsSendMessage)
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            snapshot: permissionSnapshot(hostPermissions: [
                "https://example.com/*",
            ])
        )
        let result = ChromeMV3RuntimeListenerResolver.resolve(
            route: route,
            listenerRegistrySnapshot: .empty,
            permissionDecision: decision,
            serviceWorkerAvailability:
                .diagnosticFixture(),
            contentScriptAvailability:
                .diagnosticFixture(),
            extensionPageAvailability:
                .diagnosticFixture()
        )

        XCTAssertFalse(result.receivingListenerModeled)
        XCTAssertFalse(result.receivingListenerAvailableNow)
        XCTAssertEqual(result.errorContract?.error, .noReceivingEnd)
    }

    func testListenerResolutionReturnsRegistrationNotImplementedWhenModeled() {
        let route = messageRoute(.serviceWorkerToExtensionPage)
        let decision = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            snapshot: .empty
        )
        let result = ChromeMV3RuntimeListenerResolver.resolve(
            route: route,
            listenerRegistrySnapshot: .modeled(
                extensionID: "extension-a",
                profileID: "profile-a"
            ),
            permissionDecision: decision,
            serviceWorkerAvailability:
                .diagnosticFixture(),
            contentScriptAvailability:
                .diagnosticFixture(),
            extensionPageAvailability:
                .diagnosticFixture()
        )

        XCTAssertTrue(result.receivingListenerModeled)
        XCTAssertFalse(result.receivingListenerAvailableNow)
        XCTAssertTrue(result.wouldNeedExtensionPageHost)
        XCTAssertEqual(
            result.errorContract?.error,
            .listenerRegistrationNotImplemented
        )
    }

    func testServiceWorkerEventAvailabilityRemainsFalse() {
        let availability =
            ChromeMV3RuntimeServiceWorkerEventAvailabilityContract.make(
                serviceWorkerScriptDeclared: true,
                serviceWorkerObjectAcceptedByWebKit: true
            )

        XCTAssertTrue(availability.serviceWorkerScriptDeclared)
        XCTAssertTrue(availability.serviceWorkerObjectAcceptedByWebKit)
        XCTAssertTrue(availability.serviceWorkerListenersModeled)
        XCTAssertTrue(availability.permanentBackgroundForbidden)
        XCTAssertTrue(availability.requiredBeforeRuntimeDispatch)
        XCTAssertFalse(availability.serviceWorkerContextCreated)
        XCTAssertFalse(
            availability.serviceWorkerEventListenerRegistrationImplemented
        )
        XCTAssertFalse(availability.serviceWorkerWakeImplemented)
        XCTAssertFalse(availability.serviceWorkerIdleLifecycleImplemented)
        XCTAssertFalse(availability.serviceWorkerListenersAvailableNow)
        XCTAssertFalse(availability.serviceWorkerWakeAvailableNow)
    }

    func testPasswordManagerLikeFixtureReportsListenerBlockers() {
        let report = ChromeMV3RuntimeListenerContractReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let password = report.passwordManagerListenerSummary

        XCTAssertTrue(password.contentScriptListenerRequired)
        XCTAssertTrue(password.serviceWorkerOnMessageRequired)
        XCTAssertTrue(password.popupOnMessageOnConnectRequired)
        XCTAssertTrue(password.portListenerRequiredForUnlockFillFlow)
        XCTAssertTrue(password.nativeMessagingListenerRequiredButBlocked)
        XCTAssertFalse(password.contentScriptInjectionImplemented)
        XCTAssertFalse(password.serviceWorkerWakeImplemented)
        XCTAssertFalse(password.extensionPageHostImplemented)
        XCTAssertFalse(password.passwordManagerListenerReady)
        XCTAssertTrue(
            password.blockers.contains {
                $0.contains("content-script injection is not implemented")
            }
        )
    }

    func testListenerReadinessReportKeepsAllRuntimeFlagsFalse()
        throws
    {
        let report = ChromeMV3RuntimeListenerContractReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())
        let data = try ChromeMV3DeterministicJSON.encodedData(report)
        let decoded = try JSONDecoder().decode(
            ChromeMV3RuntimeListenerContractReport.self,
            from: data
        )

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(
            report.reportFileName,
            ChromeMV3RuntimeListenerContractReportWriter.reportFileName
        )
        XCTAssertFalse(report.canRegisterListenersNow)
        XCTAssertFalse(report.canResolveReceivingListenersNow)
        XCTAssertFalse(report.canDispatchMessagesNow)
        XCTAssertFalse(report.canWakeServiceWorkerNow)
        XCTAssertFalse(report.canCreateContextNow)
        XCTAssertFalse(report.canLoadContextNow)
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertFalse(
            report.passwordManagerListenerSummary
                .passwordManagerListenerReady
        )
    }

    func testListenerReadinessReportWriterWritesExpectedFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = ChromeMV3RuntimeListenerContractReportGenerator
            .makeReport(prerequisitesReport: makePrerequisitesReport())

        try ChromeMV3RuntimeListenerContractReportWriter.write(
            report,
            toRewrittenBundleRoot: root
        )

        let reportURL = root.appendingPathComponent(
            ChromeMV3RuntimeListenerContractReportWriter.reportFileName
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        let decoded = try JSONDecoder().decode(
            ChromeMV3RuntimeListenerContractReport.self,
            from: Data(contentsOf: reportURL)
        )
        XCTAssertEqual(decoded, report)
    }

    @MainActor
    func testSumiExtensionsModuleWritesListenerContractReportOnlyWhenEnabled()
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
            ChromeMV3RuntimeListenerContractReportWriter.reportFileName
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
            disabledModule.chromeMV3RuntimeListenerContractReportIfEnabled(
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
            enabledModule.chromeMV3RuntimeListenerContractReportIfEnabled(
                fromRewrittenBundleRoot: root,
                writeReport: true
            )
        )
        let diagnostics = enabledModule.chromeMV3InventoryDiagnosticsIfEnabled(
            rootURL: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
        XCTAssertEqual(
            diagnostics?.runtimeListenerContractReportSummary,
            enabledReport.summary
        )
        XCTAssertFalse(enabledModule.hasLoadedRuntime)
    }

    func testRuntimeMessagingAndBridgeReadinessReportsIncludeListenerSummary() {
        let prerequisites = makePrerequisitesReport()
        let messagingReport = ChromeMV3RuntimeMessagingContractReportGenerator
            .makeReport(prerequisitesReport: prerequisites)
        let readinessReport = ChromeMV3RuntimeBridgeReadinessReportGenerator
            .makeReport(
                prerequisitesReport: prerequisites,
                prerequisitesReportPath:
                    "/tmp/password-manager-fixture/runtime-bridge-prerequisites-report.json"
            )

        XCTAssertEqual(
            messagingReport.listenerContractReportSummary?
                .reportFileName,
            ChromeMV3RuntimeListenerContractReportWriter.reportFileName
        )
        XCTAssertEqual(
            readinessReport.runtimeListenerContractReportSummary?
                .reportFileName,
            ChromeMV3RuntimeListenerContractReportWriter.reportFileName
        )
        let listenerSummary = try! XCTUnwrap(
            readinessReport.runtimeListenerContractReportSummary
        )
        XCTAssertFalse(listenerSummary.canRegisterListenersNow)
    }

    func testSourceLevelGuardsForRuntimeListenerContractLayer()
        throws
    {
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
                    != "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3RuntimeJSMessagingMVPTests.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift"
                    && $0.relativePath
                        != "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift"
                    && $0.relativePath
                        != "SumiTests/ChromeMV3NativeMessagingInternalRuntimeTests.swift"
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
            "canRegister" + "ListenersNow\\s*[:=].*" + "tr" + "ue",
            "canWake" + "ServiceWorkerNow\\s*[:=].*" + "tr" + "ue",
            "password" + "ManagerListenerReady\\s*[:=].*" + "tr" + "ue",
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

    private func surface(
        _ kind: ChromeMV3RuntimeListenerSurfaceKind
    ) -> ChromeMV3RuntimeListenerSurface {
        ChromeMV3RuntimeListenerSurface.make(
            surface: kind,
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 42,
            frameID: 0
        )
    }

    private func messageRoute(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> ChromeMV3RuntimeMessagingRoute {
        ChromeMV3RuntimeMessagingRoute.make(
            kind: kind,
            extensionID: "extension-a",
            profileID: "profile-a",
            tabID: 42,
            frameID: 0,
            documentID: "document-0",
            sourceURL: "https://example.com/login",
            targetURL: "https://example.com/login"
        )
    }

    private func permissionSnapshot(
        hostPermissions: [String]
    ) -> ChromeMV3RuntimeMessagingPermissionSnapshot {
        ChromeMV3RuntimeMessagingPermissionSnapshot(
            grantedHostPermissions: hostPermissions,
            optionalPermissions: [],
            optionalHostPermissions: [],
            tabPermissionGranted: false,
            activeTabPermissionDeclared: false,
            activeTabGrants: [],
            deniedPermissions: [],
            userGestureAvailable: false
        )
    }

    private func makePrerequisitesReport()
        -> ChromeMV3RuntimeBridgePrerequisitesReport
    {
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
            manifestFacts: manifestFacts(),
            runtimeMessagingPrerequisites: runtimeMessagingPrerequisites(),
            nativeMessagingPrerequisites: nativeMessagingPrerequisites(),
            storagePrerequisites: storagePrerequisites(),
            permissionsActiveTabPrerequisites: permissionsPrerequisites(),
            serviceWorkerLifecyclePrerequisites: lifecyclePrerequisites(),
            passwordManagerPrerequisiteSummary: passwordSummary(),
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

    private func manifestFacts()
        -> ChromeMV3RuntimeBridgeManifestFacts
    {
        ChromeMV3RuntimeBridgeManifestFacts(
            manifestReadStatus: .loaded,
            manifestPath: "/tmp/password-manager-fixture/manifest.json",
            manifestSHA256: String(repeating: "b", count: 64),
            declaredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: [],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: [],
            contentScriptsPresent: true,
            contentScriptMatchPatterns: ["https://example.com/*"],
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
            status: .modeled,
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

    private func storagePrerequisites()
        -> ChromeMV3StoragePrerequisites
    {
        ChromeMV3StoragePrerequisites(
            status: .notImplemented,
            storagePermissionPresent: true,
            implementedNow: false,
            webKitBehaviorSufficientWithoutHostLayer: false,
            hostBackedLayerDecisionRequired: true,
            profileIsolationVerified: false,
            workerUnloadReloadStateVerified: false,
            passwordManagerStateRequirements: [
                "Password-manager state required.",
            ],
            areas: ChromeMV3StorageAreaName.allCases.map {
                ChromeMV3StorageAreaPrerequisite(
                    area: $0,
                    required: true,
                    implementedNow: false,
                    persistenceExpectation: "Future persistence.",
                    contentScriptExposureDefault: "Future exposure.",
                    decisionRequired: "Future decision.",
                    blockers: ["Storage area is not implemented."]
                )
            },
            blockers: ["Storage backend is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func permissionsPrerequisites()
        -> ChromeMV3PermissionsActiveTabPrerequisites
    {
        ChromeMV3PermissionsActiveTabPrerequisites(
            status: .notImplemented,
            requiredPermissions: ["nativeMessaging", "storage"],
            optionalPermissions: [],
            hostPermissions: ["https://example.com/*"],
            optionalHostPermissions: [],
            activeTabDeclared: false,
            permissionBrokerImplemented: true,
            activeTabImplemented: true,
            hostPermissionEvaluationImplemented: true,
            userGestureRequirementModeled: true,
            grantLifetimeRequirement: "Temporary grant.",
            tabNavigationInvalidationRequirement: "Invalidate on navigation.",
            permissionPromptUIFutureRequirement: true,
            contentScriptExecutionInteraction:
                "Content script execution remains blocked.",
            passwordManagerHostAccessRequirement:
                "Password-manager host access required.",
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
            requiredBeforeContextLoadReason:
                "Lifecycle required before context load.",
            requiredBeforeRuntimeLoadability: true,
            wakeReasonsRequired: ["runtime message"],
            eventDispatchPrerequisites: ["event queue"],
            idleReleasePolicy: "Release idle workers.",
            hardTimeoutPolicy: "Report long requests.",
            longLivedPortPolicy: "Model Port lifetime.",
            nativeMessagingPortPolicy: "Model native messaging lifetime.",
            alarmWakePolicy: "Model alarm wake.",
            statePersistenceRequirements: ["Persist state."],
            diagnosticsRequired: ["wake reason"],
            blockers: ["Service-worker wake is not implemented."],
            futureTestsNeeded: []
        )
    }

    private func passwordSummary()
        -> ChromeMV3PasswordManagerPrerequisiteSummary
    {
        ChromeMV3PasswordManagerPrerequisiteSummary(
            contentScriptsPresent: true,
            actionPopupPresent: true,
            hostPermissionsPresent: true,
            storagePermissionPresent: true,
            nativeMessagingPermissionPresent: true,
            runtimeMessagingMissing: true,
            permissionActiveTabMissing: true,
            storageBackendMissingOrDeferred: true,
            nativeMessagingMissing: true,
            controlledInputPageWorldBehaviorNotVerified: true,
            serviceWorkerLifecycleNotVerified: true,
            passwordManagerSupportReady: false,
            blockers: ["Password-manager support is not ready."],
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
        return files.sorted(by: { lhs, rhs in
            lhs.relativePath < rhs.relativePath
        })
    }

    private static func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
