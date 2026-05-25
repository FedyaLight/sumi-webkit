//
//  ChromeMV3ProfileHost.swift
//  Sumi
//
//  Profile-scoped Chrome MV3 host skeleton. It evaluates policy and preflight
//  only; it does not create, load, attach, register, repeat, or execute runtime
//  resources.
//

import Foundation

enum ChromeMV3ProfileHostModuleState: String, Codable, Sendable {
    case enabled
    case disabled
}

enum ChromeMV3ProfileHostControllerState: String, Codable, Sendable {
    case absentNotCreated
}

enum ChromeMV3ProfileDataStoreIdentity: Codable, Equatable, Sendable {
    case profileIdentifier(String)
    case ephemeralProfileIdentifier(String)
    case placeholder(String)
    case unresolved
}

struct ChromeMV3RewrittenVariantCandidate: Codable, Equatable, Sendable {
    var id: String
    var generatedVariantRootPath: String?
    var rewrittenVariantRootPath: String
    var runtimeLoadabilityReportPath: String?
    var rewrittenManifestSHA256: String? = nil
    var runtimeLoadabilityReportSHA256: String? = nil
    var manifestVersion: Int?
    var rewrittenVariantExists: Bool
}

struct ChromeMV3ProfileRuntimeAllowance: Codable, Equatable, Sendable {
    var allowedForProfilePreflight: Bool
    var reason: String
    var requiredFuturePreconditions: [String]
    var canCreateControllerNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
}

struct ChromeMV3ProfileHostDiagnosticsSummary: Codable, Equatable, Sendable {
    var profileIdentifier: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var controllerState: ChromeMV3ProfileHostControllerState
    var candidateVariantCount: Int
    var allowedForProfilePreflight: Bool
    var canCreateControllerNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
    var registersUserScriptsNow: Bool
    var launchesNativeMessagingNow: Bool
    var startsBackgroundWorkNow: Bool
    var blockingReasons: [String]
    var futureRequirements: [String]
}

struct ChromeMV3DisabledRuntimeInvariantStatus: Codable, Equatable, Sendable {
    var noWebKitExtensionObjectCreated: Bool
    var noControllerObjectCreated: Bool
    var noContextObjectCreated: Bool
    var noControllerAttachedToConfigurations: Bool
    var noExtensionJavaScriptRegistered: Bool
    var noServiceWorkerWakeups: Bool
    var noNativeMessagingRuntime: Bool
    var noHiddenRuntimeCost: Bool
    var accidentalAttachmentWhileDisabledDetected: Bool
}

struct ChromeMV3ProfileHostDiagnostics: Codable, Equatable, Sendable {
    var profileIdentifier: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var controllerState: ChromeMV3ProfileHostControllerState
    var candidateInventory: ChromeMV3CandidateInventory?
    var extensionObjectProbeDiagnostics:
        ChromeMV3ExtensionObjectProbeDiagnostics?
    var extensionObjectAcceptanceReport:
        ChromeMV3WebKitObjectAcceptanceReport?
    var contextReadinessReport:
        ChromeMV3ContextReadinessReport?
    var runtimeBridgePrerequisitesReport:
        ChromeMV3RuntimeBridgePrerequisitesReport?
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var runtimeMessagingContractReportSummary:
        ChromeMV3RuntimeMessagingContractReportSummary?
    var runtimeListenerContractReportSummary:
        ChromeMV3RuntimeListenerContractReportSummary? = nil
    var permissionBrokerReadinessReportSummary:
        ChromeMV3PermissionBrokerReadinessReportSummary? = nil
    var permissionLifecycleReportSummary:
        ChromeMV3PermissionLifecycleReportSummary? = nil
    var permissionsAPIContractReportSummary:
        ChromeMV3PermissionsAPIContractReportSummary? = nil
    var preflightResults: [ChromeMV3RuntimePreflightResult]
    var webViewSurfaceMappings: [ChromeMV3WebViewSurfaceMappingDiagnostic]
    var disabledRuntimeInvariantStatus: ChromeMV3DisabledRuntimeInvariantStatus
    var canCreateControllerNow: Bool
    var canLoadContextNow: Bool
    var canAttachToNormalTabsNow: Bool
    var attachableSurfacesNow: Array<ChromeMV3WebViewSurface>
    var futureEligibleSurfaces: [ChromeMV3WebViewSurface]
    var futureExtensionUIHostOnlySurfaces: [ChromeMV3WebViewSurface]
    var requiresPromotionOrReclassificationSurfaces: [ChromeMV3WebViewSurface]
    var ineligibleSurfaces: [ChromeMV3WebViewSurface]
    var blockingReasons: [String]
    var diagnosticsWarnings: [String]
}

struct ChromeMV3ProfileHost: Codable, Equatable, Sendable {
    static let unresolvedProfileIdentifier = "unresolved-profile"

    var profileIdentifier: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
    var controllerState: ChromeMV3ProfileHostControllerState
    var candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate]

    init(
        profileIdentifier: String,
        extensionsEnabled: Bool,
        profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity = .unresolved,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) {
        self.profileIdentifier = profileIdentifier.isEmpty
            ? Self.unresolvedProfileIdentifier
            : profileIdentifier
        self.moduleState = extensionsEnabled ? .enabled : .disabled
        self.profileDataStoreIdentity = profileDataStoreIdentity
        self.controllerState = .absentNotCreated
        self.candidateRewrittenVariants = candidateRewrittenVariants.sorted {
            $0.id < $1.id
        }
    }

    var isActive: Bool {
        moduleState == .enabled
    }

    var canCreateControllerNow: Bool {
        false
    }

    var canLoadContextNow: Bool {
        false
    }

    var canAttachToNormalTabsNow: Bool {
        false
    }

    func profileRuntimeAllowance() -> ChromeMV3ProfileRuntimeAllowance {
        if isActive == false {
            return ChromeMV3ProfileRuntimeAllowance(
                allowedForProfilePreflight: false,
                reason: "The extensions module is disabled for this profile.",
                requiredFuturePreconditions: [
                    "Enable the extensions module before Chrome MV3 runtime preflight.",
                ],
                canCreateControllerNow: false,
                canLoadContextNow: false,
                canAttachToNormalTabsNow: false
            )
        }

        return ChromeMV3ProfileRuntimeAllowance(
            allowedForProfilePreflight: true,
            reason: "The profile may evaluate Chrome MV3 preflight, but WebKit runtime loading remains blocked.",
            requiredFuturePreconditions: [
                "Clear generated-rewritten runtime blockers.",
                "Add explicit future WebKit controller creation.",
                "Add explicit future context loading.",
                "Re-evaluate normal-tab WebView eligibility before any future attachment.",
            ],
            canCreateControllerNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false
        )
    }

    func candidate(
        withID candidateID: String
    ) -> ChromeMV3RewrittenVariantCandidate? {
        candidateRewrittenVariants.first { $0.id == candidateID }
    }

    func evaluatePreflight(
        candidateID: String,
        report: ChromeMV3RuntimeLoadabilityReport?,
        surface: ChromeMV3WebViewSurface = .normalTab
    ) -> ChromeMV3RuntimePreflightResult {
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: surface,
            extensionModuleEnabled: isActive,
            profileHostActive: isActive
        )
        return ChromeMV3RuntimePreflight.evaluate(
            profileHost: self,
            candidate: candidate(withID: candidateID),
            report: report,
            webViewEligibility: eligibility
        )
    }

    func diagnosticsSummary(
        preflightResults: [ChromeMV3RuntimePreflightResult] = []
    ) -> ChromeMV3ProfileHostDiagnosticsSummary {
        let allowance = profileRuntimeAllowance()
        let preflightBlockingReasons = preflightResults
            .flatMap(\.blockingReasons)
        let preflightFutureRequirements = preflightResults
            .flatMap(\.futureRequirements)

        return ChromeMV3ProfileHostDiagnosticsSummary(
            profileIdentifier: profileIdentifier,
            moduleState: moduleState,
            profileDataStoreIdentity: profileDataStoreIdentity,
            controllerState: controllerState,
            candidateVariantCount: candidateRewrittenVariants.count,
            allowedForProfilePreflight: allowance.allowedForProfilePreflight,
            canCreateControllerNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            registersUserScriptsNow: false,
            launchesNativeMessagingNow: false,
            startsBackgroundWorkNow: false,
            blockingReasons: uniqueSorted(
                [allowance.reason] + preflightBlockingReasons
            ),
            futureRequirements: uniqueSorted(
                allowance.requiredFuturePreconditions
                    + preflightFutureRequirements
            )
        )
    }

    func diagnostics(
        candidateInventory: ChromeMV3CandidateInventory? = nil,
        extensionObjectProbeDiagnostics:
            ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
        extensionObjectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport? = nil,
        contextReadinessReport:
            ChromeMV3ContextReadinessReport? = nil,
        runtimeBridgePrerequisitesReport:
            ChromeMV3RuntimeBridgePrerequisitesReport? = nil,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport? = nil,
        runtimeMessagingContractReportSummary:
            ChromeMV3RuntimeMessagingContractReportSummary? = nil,
        runtimeListenerContractReportSummary:
            ChromeMV3RuntimeListenerContractReportSummary? = nil,
        permissionBrokerReadinessReportSummary:
            ChromeMV3PermissionBrokerReadinessReportSummary? = nil,
        permissionLifecycleReportSummary:
            ChromeMV3PermissionLifecycleReportSummary? = nil,
        permissionsAPIContractReportSummary:
            ChromeMV3PermissionsAPIContractReportSummary? = nil,
        surfaceMappings: [ChromeMV3WebViewSurfaceMapping] =
            ChromeMV3WebViewSurfaceInventory.currentSumiMappings
    ) -> ChromeMV3ProfileHostDiagnostics {
        let inventoryCandidates = candidateInventory?.candidates ?? []
        let candidatesForPreflight = inventoryCandidates.isEmpty
            ? candidateRewrittenVariants.map {
                ChromeMV3InventoryPreflightCandidate(
                    candidate: $0,
                    report: nil
                )
            }
            : inventoryCandidates.map {
                ChromeMV3InventoryPreflightCandidate(
                    candidate: $0.profileHostCandidate,
                    report: $0.runtimeLoadabilityReport
                )
            }

        let surfaceDiagnostics = ChromeMV3WebViewSurfaceInventory
            .diagnostics(
                extensionModuleEnabled: isActive,
                profileHostActive: isActive,
                mappings: surfaceMappings
            )

        let normalTabEligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: .normalTab,
            extensionModuleEnabled: isActive,
            profileHostActive: isActive
        )
        let preflightResults = candidatesForPreflight.map {
            ChromeMV3RuntimePreflight.evaluate(
                profileHost: self,
                candidate: $0.candidate,
                report: $0.report,
                webViewEligibility: normalTabEligibility
            )
        }

        let mappingWarnings = surfaceDiagnostics.flatMap(\.warnings)
        let inventoryWarnings = candidateInventory?.warnings ?? []
        let missingArtifactWarnings = inventoryCandidates
            .flatMap(\.missingArtifactWarnings)
        let preflightBlockingReasons = preflightResults.flatMap(\.blockingReasons)
        let inventoryBlockingReasons = inventoryCandidates.flatMap(\.blockers)
        let surfaceBlockingReasons = surfaceDiagnostics
            .filter { $0.currentEligibility.canAttachControllerNow == false }
            .map { "\($0.siteID): controller attachment is not allowed now." }

        return ChromeMV3ProfileHostDiagnostics(
            profileIdentifier: profileIdentifier,
            moduleState: moduleState,
            profileDataStoreIdentity: profileDataStoreIdentity,
            controllerState: controllerState,
            candidateInventory: candidateInventory,
            extensionObjectProbeDiagnostics: extensionObjectProbeDiagnostics,
            extensionObjectAcceptanceReport: extensionObjectAcceptanceReport,
            contextReadinessReport: contextReadinessReport,
            runtimeBridgePrerequisitesReport:
                runtimeBridgePrerequisitesReport,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            runtimeMessagingContractReportSummary:
                runtimeMessagingContractReportSummary,
            runtimeListenerContractReportSummary:
                runtimeListenerContractReportSummary,
            permissionBrokerReadinessReportSummary:
                permissionBrokerReadinessReportSummary,
            permissionLifecycleReportSummary:
                permissionLifecycleReportSummary,
            permissionsAPIContractReportSummary:
                permissionsAPIContractReportSummary,
            preflightResults: preflightResults.sorted {
                ($0.candidateID ?? "") < ($1.candidateID ?? "")
            },
            webViewSurfaceMappings: surfaceDiagnostics.sorted {
                $0.siteID < $1.siteID
            },
            disabledRuntimeInvariantStatus: disabledRuntimeInvariantStatus(
                surfaceDiagnostics: surfaceDiagnostics
            ),
            canCreateControllerNow: false,
            canLoadContextNow: false,
            canAttachToNormalTabsNow: false,
            attachableSurfacesNow: Array<ChromeMV3WebViewSurface>(),
            futureEligibleSurfaces: uniqueSortedSurfaces(
                surfaceMappings
                    .filter { $0.futureEligibility == .futureEligible }
                    .map(\.surface)
            ),
            futureExtensionUIHostOnlySurfaces: uniqueSortedSurfaces(
                surfaceMappings
                    .filter {
                        $0.futureEligibility ==
                            .futureEligibleThroughExtensionUIHostOnly
                    }
                    .map(\.surface)
            ),
            requiresPromotionOrReclassificationSurfaces: uniqueSortedSurfaces(
                surfaceMappings
                    .filter {
                        $0.futureEligibility ==
                            .eligibleAfterPromotionAndReevaluation
                            || $0.futureAttachmentRequiresNormalBrowsingPromotion
                    }
                    .map(\.surface)
            ),
            ineligibleSurfaces: uniqueSortedSurfaces(
                surfaceMappings
                    .filter {
                        $0.futureEligibility == .notEligible
                            || $0.futureEligibility == .neverEligible
                    }
                    .map(\.surface)
            ),
            blockingReasons: uniqueSorted(
                [profileRuntimeAllowance().reason]
                    + preflightBlockingReasons
                    + inventoryBlockingReasons
                    + surfaceBlockingReasons
            ),
            diagnosticsWarnings: uniqueSorted(
                inventoryWarnings + missingArtifactWarnings + mappingWarnings
            )
        )
    }

    private func disabledRuntimeInvariantStatus(
        surfaceDiagnostics: [ChromeMV3WebViewSurfaceMappingDiagnostic]
    )
        -> ChromeMV3DisabledRuntimeInvariantStatus
    {
        let accidentalAttachmentDetected = surfaceDiagnostics.contains {
            $0.controllerAttachmentAllowedNow
                || $0.currentEligibility.canAttachControllerNow
        }
        return ChromeMV3DisabledRuntimeInvariantStatus(
            noWebKitExtensionObjectCreated: true,
            noControllerObjectCreated: true,
            noContextObjectCreated: true,
            noControllerAttachedToConfigurations: accidentalAttachmentDetected == false,
            noExtensionJavaScriptRegistered: true,
            noServiceWorkerWakeups: true,
            noNativeMessagingRuntime: true,
            noHiddenRuntimeCost: true,
            accidentalAttachmentWhileDisabledDetected: accidentalAttachmentDetected
        )
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }

    private func uniqueSortedSurfaces(
        _ values: [ChromeMV3WebViewSurface]
    ) -> [ChromeMV3WebViewSurface] {
        Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
    }
}

private struct ChromeMV3InventoryPreflightCandidate {
    var candidate: ChromeMV3RewrittenVariantCandidate
    var report: ChromeMV3RuntimeLoadabilityReport?
}
