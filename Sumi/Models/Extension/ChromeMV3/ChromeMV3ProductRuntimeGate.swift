//
//  ChromeMV3ProductRuntimeGate.swift
//  Sumi
//
//  Product-gated Chrome MV3 normal-tab bridge planning. This layer is
//  deterministic policy and diagnostics only: it does not create WebKit
//  extension objects, attach controllers, inject scripts, wake service
//  workers, launch native hosts, or enable product network enforcement.
//

import Foundation

enum ChromeMV3ProductRuntimeGateState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case allowed
    case blocked
    case disabled
    case notConfigured
    case internalOnly

    static func < (
        lhs: ChromeMV3ProductRuntimeGateState,
        rhs: ChromeMV3ProductRuntimeGateState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ProductRuntimeGateName:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case globalProductRuntimeGate
    case profileProductRuntimeGate
    case extensionProductRuntimeGate
    case tabProductRuntimeGate
    case diagnosticsGate
    case debugOverrideGate

    static func < (
        lhs: ChromeMV3ProductRuntimeGateName,
        rhs: ChromeMV3ProductRuntimeGateName
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ProductRuntimeGateSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case defaultOffPolicy
    case globalProductRuntimeGate
    case profileProductRuntimeGate
    case extensionProductRuntimeGate
    case tabProductRuntimeGate
    case diagnosticsGate
    case debugOverrideGate
    case compatibilityReport
    case generatedBundle
    case WebKitRuntime
    case contentScriptPolicy
    case permissionPolicy
    case serviceWorkerPolicy
    case nativeMessagingPolicy
    case networkPolicy
    case sidePanelOffscreenIdentityPolicy
    case disabledInvariant

    static func < (
        lhs: ChromeMV3ProductRuntimeGateSource,
        rhs: ChromeMV3ProductRuntimeGateSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ProductRuntimeFlagName:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case productRuntimeAvailable
    case normalTabRuntimeBridgeAvailable
    case runtimeLoadable
    case productExtensionUIAvailable
    case productNetworkEnforcementAvailable
    case productRuntimeExposed

    static func < (
        lhs: ChromeMV3ProductRuntimeFlagName,
        rhs: ChromeMV3ProductRuntimeFlagName
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ProductRuntimeFlagImpact:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case remainsFalse
    case noProductFlagChange
    case testOnlyPreflightNoProductFlagChange

    static func < (
        lhs: ChromeMV3ProductRuntimeFlagImpact,
        rhs: ChromeMV3ProductRuntimeFlagImpact
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ProductRuntimeFlagImpactRecord:
    Codable,
    Equatable,
    Sendable
{
    var flag: ChromeMV3ProductRuntimeFlagName
    var impact: ChromeMV3ProductRuntimeFlagImpact

    static func all(
        _ impact: ChromeMV3ProductRuntimeFlagImpact
    ) -> [ChromeMV3ProductRuntimeFlagImpactRecord] {
        ChromeMV3ProductRuntimeFlagName.allCases.sorted().map {
            ChromeMV3ProductRuntimeFlagImpactRecord(
                flag: $0,
                impact: impact
            )
        }
    }
}

struct ChromeMV3ProductRuntimeGateRecord:
    Codable,
    Equatable,
    Sendable
{
    var name: ChromeMV3ProductRuntimeGateName
    var state: ChromeMV3ProductRuntimeGateState
    var reason: String
    var blockerIDs: [String]
    var source: ChromeMV3ProductRuntimeGateSource
    var productFlagImpact: [ChromeMV3ProductRuntimeFlagImpactRecord]

    var allowsProductPreflight: Bool {
        state == .allowed
    }

    static func make(
        _ name: ChromeMV3ProductRuntimeGateName,
        state: ChromeMV3ProductRuntimeGateState,
        reason: String,
        blockerIDs: [String] = [],
        source: ChromeMV3ProductRuntimeGateSource,
        productFlagImpact:
            ChromeMV3ProductRuntimeFlagImpact =
                .noProductFlagChange
    ) -> ChromeMV3ProductRuntimeGateRecord {
        ChromeMV3ProductRuntimeGateRecord(
            name: name,
            state: state,
            reason: reason,
            blockerIDs: Array(Set(blockerIDs)).sorted(),
            source: source,
            productFlagImpact:
                ChromeMV3ProductRuntimeFlagImpactRecord.all(
                    productFlagImpact
                )
        )
    }
}

struct ChromeMV3ProductRuntimeGateSet:
    Codable,
    Equatable,
    Sendable
{
    var globalProductRuntimeGate: ChromeMV3ProductRuntimeGateRecord
    var profileProductRuntimeGate: ChromeMV3ProductRuntimeGateRecord
    var extensionProductRuntimeGate: ChromeMV3ProductRuntimeGateRecord
    var tabProductRuntimeGate: ChromeMV3ProductRuntimeGateRecord
    var diagnosticsGate: ChromeMV3ProductRuntimeGateRecord
    var debugOverrideGate: ChromeMV3ProductRuntimeGateRecord

    var records: [ChromeMV3ProductRuntimeGateRecord] {
        [
            globalProductRuntimeGate,
            profileProductRuntimeGate,
            extensionProductRuntimeGate,
            tabProductRuntimeGate,
            diagnosticsGate,
            debugOverrideGate,
        ].sorted { $0.name < $1.name }
    }

    var blockingRecords: [ChromeMV3ProductRuntimeGateRecord] {
        records.filter { $0.allowsProductPreflight == false }
    }

    var allExplicitGatesAllowPreflight: Bool {
        blockingRecords.isEmpty
    }

    static func defaultBlocked(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        tabID: String = "normal-tab-preflight"
    ) -> ChromeMV3ProductRuntimeGateSet {
        let blockerIDs = productBlockerIDs(report)
        let profileID = lifecycleRecord?.profileID
            ?? "unresolved-product-profile"
        let extensionID = lifecycleRecord?.extensionID
            ?? "unresolved-product-extension"
        return ChromeMV3ProductRuntimeGateSet(
            globalProductRuntimeGate: .make(
                .globalProductRuntimeGate,
                state: .blocked,
                reason: "Product MV3 runtime is globally blocked by default.",
                blockerIDs: blockerIDs,
                source: .defaultOffPolicy,
                productFlagImpact: .remainsFalse
            ),
            profileProductRuntimeGate: .make(
                .profileProductRuntimeGate,
                state: .notConfigured,
                reason: "Profile \(profileID) has no product MV3 runtime enablement record.",
                blockerIDs: blockerIDs,
                source: .profileProductRuntimeGate,
                productFlagImpact: .remainsFalse
            ),
            extensionProductRuntimeGate: .make(
                .extensionProductRuntimeGate,
                state: .internalOnly,
                reason: "Extension \(extensionID) is limited to internal diagnostics.",
                blockerIDs: blockerIDs,
                source: .extensionProductRuntimeGate,
                productFlagImpact: .remainsFalse
            ),
            tabProductRuntimeGate: .make(
                .tabProductRuntimeGate,
                state: .notConfigured,
                reason: "Tab \(tabID) has not been explicitly marked eligible for product MV3 runtime preflight.",
                blockerIDs: [],
                source: .tabProductRuntimeGate,
                productFlagImpact: .remainsFalse
            ),
            diagnosticsGate: .make(
                .diagnosticsGate,
                state: .internalOnly,
                reason: "Compatibility diagnostics are report-only and do not enable product runtime.",
                blockerIDs: blockerIDs,
                source: .diagnosticsGate,
                productFlagImpact: .remainsFalse
            ),
            debugOverrideGate: .make(
                .debugOverrideGate,
                state: .disabled,
                reason: "No explicit DEBUG/internal product-gate fixture override is active.",
                blockerIDs: [],
                source: .debugOverrideGate,
                productFlagImpact: .remainsFalse
            )
        )
    }

    static func explicitInternalTestAllowed(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        tabID: String = "normal-tab-product-gate-fixture"
    ) -> ChromeMV3ProductRuntimeGateSet {
        let profileID = lifecycleRecord?.profileID
            ?? "internal-product-gate-profile"
        let extensionID = lifecycleRecord?.extensionID
            ?? "internal-product-gate-extension"
        #if DEBUG
            let debugState: ChromeMV3ProductRuntimeGateState = .allowed
            let debugReason =
                "Explicit DEBUG/internal product-gate fixture override is active for preflight only."
            let debugImpact: ChromeMV3ProductRuntimeFlagImpact =
                .testOnlyPreflightNoProductFlagChange
        #else
            let debugState: ChromeMV3ProductRuntimeGateState = .disabled
            let debugReason =
                "DEBUG/internal product-gate fixture override is unavailable in this build."
            let debugImpact: ChromeMV3ProductRuntimeFlagImpact = .remainsFalse
        #endif
        return ChromeMV3ProductRuntimeGateSet(
            globalProductRuntimeGate: .make(
                .globalProductRuntimeGate,
                state: .allowed,
                reason: "Explicit internal test gate allowed global product runtime preflight.",
                source: .globalProductRuntimeGate,
                productFlagImpact: .testOnlyPreflightNoProductFlagChange
            ),
            profileProductRuntimeGate: .make(
                .profileProductRuntimeGate,
                state: .allowed,
                reason: "Profile \(profileID) is allowed by an explicit internal test gate.",
                source: .profileProductRuntimeGate,
                productFlagImpact: .testOnlyPreflightNoProductFlagChange
            ),
            extensionProductRuntimeGate: .make(
                .extensionProductRuntimeGate,
                state: .allowed,
                reason: "Extension \(extensionID) is allowed by an explicit internal test gate.",
                source: .extensionProductRuntimeGate,
                productFlagImpact: .testOnlyPreflightNoProductFlagChange
            ),
            tabProductRuntimeGate: .make(
                .tabProductRuntimeGate,
                state: .allowed,
                reason: "Tab \(tabID) is allowed by an explicit internal test gate.",
                source: .tabProductRuntimeGate,
                productFlagImpact: .testOnlyPreflightNoProductFlagChange
            ),
            diagnosticsGate: .make(
                .diagnosticsGate,
                state: .allowed,
                reason: "Required internal diagnostics may be consumed by the product-gate fixture.",
                blockerIDs: productBlockerIDs(report),
                source: .diagnosticsGate,
                productFlagImpact: .testOnlyPreflightNoProductFlagChange
            ),
            debugOverrideGate: .make(
                .debugOverrideGate,
                state: debugState,
                reason: debugReason,
                source: .debugOverrideGate,
                productFlagImpact: debugImpact
            )
        )
    }

    private static func productBlockerIDs(
        _ report: ChromeMV3EndToEndInstallDiagnosticsReport?
    ) -> [String] {
        report?.blockerTaxonomy.filter {
            $0.severity == .productBlocked
        }.map(\.id).sorted() ?? []
    }
}

enum ChromeMV3ExtensionProductEnablementState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case internalOnly
    case productEligible
    case productBlocked
    case productDisabled
    case productTestEnabled
    case productEnablementFailed

    static func < (
        lhs: ChromeMV3ExtensionProductEnablementState,
        rhs: ChromeMV3ExtensionProductEnablementState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ExtensionProductEnablement:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String
    var state: ChromeMV3ExtensionProductEnablementState
    var canEverAttachToProductNormalTab: Bool
    var requiresProductAPIsStillBlocked: Bool
    var productBlockedAPIs: [ChromeMV3API]
    var productBlockerIDs: [String]
    var fatalBlockerIDs: [String]
    var unsupportedBlockerIDs: [String]
    var diagnostics: [String]
}

enum ChromeMV3ExtensionProductEnablementEvaluator {
    static func evaluate(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        gateSet: ChromeMV3ProductRuntimeGateSet
    ) -> ChromeMV3ExtensionProductEnablement {
        let profileID = lifecycleRecord?.profileID
            ?? "unresolved-product-profile"
        let extensionID = lifecycleRecord?.extensionID
            ?? "unresolved-product-extension"
        let blockers = report?.blockerTaxonomy ?? []
        let fatalBlockers = blockers.filter {
            $0.severity == .fatalInstall || $0.severity == .fatalRuntime
        }
        let unsupportedBlockers = blockers.filter {
            $0.severity == .unsupported
        }
        let productBlockers = blockers.filter {
            $0.severity == .productBlocked
        }
        let productAPIBlockers = forbiddenProductAPIBlockers(in: report)
        let extensionGate = gateSet.extensionProductRuntimeGate
        let debugOverride = gateSet.debugOverrideGate
        let state: ChromeMV3ExtensionProductEnablementState

        if extensionGate.state == .disabled {
            state = .productDisabled
        } else if fatalBlockers.isEmpty == false {
            state = .productEnablementFailed
        } else if extensionGate.state == .allowed,
                  debugOverride.state == .allowed,
                  productAPIBlockers.isEmpty,
                  unsupportedBlockers.isEmpty
        {
            state = .productTestEnabled
        } else if extensionGate.state == .allowed,
                  productBlockers.isEmpty,
                  unsupportedBlockers.isEmpty
        {
            state = .productEligible
        } else if extensionGate.state == .allowed {
            state = .productBlocked
        } else {
            state = .internalOnly
        }

        let canEverAttach =
            (state == .productEligible || state == .productTestEnabled)
                && productAPIBlockers.isEmpty
                && fatalBlockers.isEmpty
                && unsupportedBlockers.isEmpty
        return ChromeMV3ExtensionProductEnablement(
            profileID: profileID,
            extensionID: extensionID,
            state: state,
            canEverAttachToProductNormalTab: canEverAttach,
            requiresProductAPIsStillBlocked: productAPIBlockers.isEmpty == false,
            productBlockedAPIs:
                uniqueAPIs(
                    productAPIBlockers.compactMap {
                        $0.apiNamespace.flatMap(ChromeMV3API.init(rawValue:))
                    }
                ),
            productBlockerIDs: productBlockers.map(\.id).sorted(),
            fatalBlockerIDs: fatalBlockers.map(\.id).sorted(),
            unsupportedBlockerIDs: unsupportedBlockers.map(\.id).sorted(),
            diagnostics: diagnostics(
                state: state,
                extensionGate: extensionGate,
                productAPIBlockerCount: productAPIBlockers.count,
                fatalBlockerCount: fatalBlockers.count,
                unsupportedBlockerCount: unsupportedBlockers.count
            )
        )
    }

    private static func diagnostics(
        state: ChromeMV3ExtensionProductEnablementState,
        extensionGate: ChromeMV3ProductRuntimeGateRecord,
        productAPIBlockerCount: Int,
        fatalBlockerCount: Int,
        unsupportedBlockerCount: Int
    ) -> [String] {
        var values = [
            "Extension product enablement state is \(state.rawValue).",
            extensionGate.reason,
        ]
        if productAPIBlockerCount > 0 {
            values.append("The extension requires product APIs that are still blocked.")
        }
        if fatalBlockerCount > 0 {
            values.append("Fatal install/runtime blockers prevent product enablement.")
        }
        if unsupportedBlockerCount > 0 {
            values.append("Unsupported API blockers prevent product enablement.")
        }
        if state == .productTestEnabled {
            values.append("The allowed state is scoped to explicit internal product-gate preflight tests.")
        }
        return uniqueSortedProduct(values)
    }
}

enum ChromeMV3ProductRuntimePreflightBlockerKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case moduleDisabled
    case gateBlocked
    case extensionProductStateBlocked
    case tabIneligible
    case generatedBundleMissing
    case webKitDiagnosticsMissing
    case sameControllerRequirementUnsatisfied
    case contentScriptProductPolicyBlocked
    case permissionProductPolicyBlocked
    case serviceWorkerProductPolicyBlocked
    case nativeMessagingProductPolicyBlocked
    case productNetworkEnforcementBlocked
    case sidePanelOffscreenIdentityProductPolicyBlocked
    case disabledInvariantViolation
    case runtimeGateBlocked
    case fatalCompatibilityBlocker
    case unsupportedAPIBlocker

    static func < (
        lhs: ChromeMV3ProductRuntimePreflightBlockerKind,
        rhs: ChromeMV3ProductRuntimePreflightBlockerKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ProductRuntimePreflightBlocker:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var kind: ChromeMV3ProductRuntimePreflightBlockerKind
    var source: ChromeMV3ProductRuntimeGateSource
    var reason: String
    var relatedCompatibilityBlockerIDs: [String]
}

struct ChromeMV3ProductNormalTabRuntimePreflightInput:
    Codable,
    Equatable,
    Sendable
{
    var moduleEnabled: Bool
    var profileID: String
    var extensionID: String
    var tabID: String
    var tabSurface: ChromeMV3WebViewSurface
    var gateSet: ChromeMV3ProductRuntimeGateSet
    var generatedBundleActive: Bool
    var generatedBundleExists: Bool
    var WebKitObjectDiagnosticsReady: Bool
    var contextReadinessDiagnosticsReady: Bool
    var controllerLoadDiagnosticsReady: Bool
    var runtimeBridgeDiagnosticsReady: Bool
    var sameControllerRequirementSatisfied: Bool
    var contentScriptEligibilitySatisfied: Bool
    var permissionStateSatisfied: Bool
    var nativeMessagingProductPolicyAllows: Bool
    var productNetworkEnforcementPolicyAllows: Bool
    var sidePanelOffscreenIdentityProductPolicyAllows: Bool
    var disabledRuntimeInvariantsSatisfied: Bool
    var report: ChromeMV3EndToEndInstallDiagnosticsReport?
    var lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?

    static func make(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        gateSet: ChromeMV3ProductRuntimeGateSet,
        moduleEnabled: Bool? = nil,
        tabID: String = "normal-tab-preflight",
        tabSurface: ChromeMV3WebViewSurface = .normalTab,
        generatedBundleActive: Bool? = nil,
        generatedBundleExists: Bool? = nil,
        WebKitObjectDiagnosticsReady: Bool? = nil,
        contextReadinessDiagnosticsReady: Bool? = nil,
        controllerLoadDiagnosticsReady: Bool? = nil,
        runtimeBridgeDiagnosticsReady: Bool? = nil,
        sameControllerRequirementSatisfied: Bool = false,
        contentScriptEligibilitySatisfied: Bool? = nil,
        permissionStateSatisfied: Bool? = nil,
        nativeMessagingProductPolicyAllows: Bool = false,
        productNetworkEnforcementPolicyAllows: Bool = false,
        sidePanelOffscreenIdentityProductPolicyAllows: Bool = false,
        disabledRuntimeInvariantsSatisfied: Bool = true
    ) -> ChromeMV3ProductNormalTabRuntimePreflightInput {
        let summary = report?.chromeMV3ProductActiveManifestSummary
        let reportNames = Set(
            report?.internalSyntheticReadinessSummary
                .syntheticAPIReportsAvailable ?? []
        )
        let activeVersion = report?.chromeMV3ProductActiveGeneratedVersion
        let bundleActive = activeVersion != nil
            && report?.lifecycleAvailability.generatedBundleAvailable == true
        let bundleExists = activeVersion?.rewrittenVariantRootPath?.isEmpty == false
            || activeVersion?.generatedBundleRootPath.isEmpty == false
        return ChromeMV3ProductNormalTabRuntimePreflightInput(
            moduleEnabled: moduleEnabled
                ?? (report?.lifecycleAvailability.extensionInstalledInInternalRegistry
                    ?? false),
            profileID: lifecycleRecord?.profileID
                ?? "unresolved-product-profile",
            extensionID: lifecycleRecord?.extensionID
                ?? "unresolved-product-extension",
            tabID: tabID,
            tabSurface: tabSurface,
            gateSet: gateSet,
            generatedBundleActive: generatedBundleActive ?? bundleActive,
            generatedBundleExists: generatedBundleExists ?? bundleExists,
            WebKitObjectDiagnosticsReady:
                WebKitObjectDiagnosticsReady
                    ?? reportNames.contains("WebKitObject"),
            contextReadinessDiagnosticsReady:
                contextReadinessDiagnosticsReady
                    ?? reportNames.contains("contextCreationGate"),
            controllerLoadDiagnosticsReady:
                controllerLoadDiagnosticsReady
                    ?? reportNames.contains("controllerLoadGate"),
            runtimeBridgeDiagnosticsReady:
                runtimeBridgeDiagnosticsReady
                    ?? reportNames.contains("runtimeBridgeReadiness"),
            sameControllerRequirementSatisfied:
                sameControllerRequirementSatisfied,
            contentScriptEligibilitySatisfied:
                contentScriptEligibilitySatisfied
                    ?? ((summary?.contentScriptCount ?? 0) == 0),
            permissionStateSatisfied:
                permissionStateSatisfied
                    ?? (summary?.chromeMV3ProductRequiresPermissionPolicy
                        == false),
            nativeMessagingProductPolicyAllows:
                nativeMessagingProductPolicyAllows,
            productNetworkEnforcementPolicyAllows:
                productNetworkEnforcementPolicyAllows,
            sidePanelOffscreenIdentityProductPolicyAllows:
                sidePanelOffscreenIdentityProductPolicyAllows,
            disabledRuntimeInvariantsSatisfied:
                disabledRuntimeInvariantsSatisfied,
            report: report,
            lifecycleRecord: lifecycleRecord
        )
    }
}

struct ChromeMV3ProductNormalTabRuntimePreflight:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String
    var tabID: String
    var tabSurface: ChromeMV3WebViewSurface
    var gateSet: ChromeMV3ProductRuntimeGateSet
    var extensionEnablement:
        ChromeMV3ExtensionProductEnablement
    var generatedBundleActive: Bool
    var generatedBundleExists: Bool
    var sameControllerRequirementSatisfied: Bool
    var canAttachToNormalTabNow: Bool
    var canExposeRuntimeBridgeNow: Bool
    var canInjectContentScriptsNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canUseNativeMessagingNow: Bool
    var canUseProductNetworkEnforcementNow: Bool
    var blockers: [ChromeMV3ProductRuntimePreflightBlocker]
    var waivedCompatibilityBlockerIDs: [String]
    var diagnostics: [String]
}

enum ChromeMV3ProductNormalTabRuntimePreflightEvaluator {
    static func evaluate(
        input: ChromeMV3ProductNormalTabRuntimePreflightInput
    ) -> ChromeMV3ProductNormalTabRuntimePreflight {
        let summary = input.report?.chromeMV3ProductActiveManifestSummary
        let extensionEnablement =
            ChromeMV3ExtensionProductEnablementEvaluator.evaluate(
                report: input.report,
                lifecycleRecord: input.lifecycleRecord,
                gateSet: input.gateSet
            )
        var blockers: [ChromeMV3ProductRuntimePreflightBlocker] = []
        var waivedCompatibilityBlockerIDs: [String] = []

        if input.moduleEnabled == false {
            blockers.append(
                blocker(
                    kind: .moduleDisabled,
                    source: .defaultOffPolicy,
                    reason: "The extensions module is disabled; no product gate or runtime state should be created."
                )
            )
        }

        for gate in input.gateSet.blockingRecords {
            blockers.append(
                blocker(
                    kind: .gateBlocked,
                    source: gate.source,
                    reason: gate.reason,
                    relatedIDs: gate.blockerIDs
                )
            )
        }

        if extensionEnablement.canEverAttachToProductNormalTab == false {
            blockers.append(
                blocker(
                    kind: .extensionProductStateBlocked,
                    source: .extensionProductRuntimeGate,
                    reason: "Extension product state is \(extensionEnablement.state.rawValue).",
                    relatedIDs: extensionEnablement.productBlockerIDs
                        + extensionEnablement.fatalBlockerIDs
                        + extensionEnablement.unsupportedBlockerIDs
                )
            )
        }

        if input.tabSurface.isRealNormalBrowsingSurfaceForChromeMV3Attachment
            == false
        {
            blockers.append(
                blocker(
                    kind: .tabIneligible,
                    source: .tabProductRuntimeGate,
                    reason: "Tab surface \(input.tabSurface.rawValue) is not eligible for product normal-tab runtime preflight."
                )
            )
        }

        if input.generatedBundleActive == false || input.generatedBundleExists == false {
            blockers.append(
                blocker(
                    kind: .generatedBundleMissing,
                    source: .generatedBundle,
                    reason: "An active generated rewritten bundle is required before normal-tab product preflight can pass."
                )
            )
        }

        appendWebKitDiagnosticsBlockers(input: input, blockers: &blockers)

        if input.sameControllerRequirementSatisfied == false {
            blockers.append(
                blocker(
                    kind: .sameControllerRequirementUnsatisfied,
                    source: .WebKitRuntime,
                    reason: "Normal tabs must use the same WKWebExtensionController/context boundary as the extension runtime."
                )
            )
        }

        if (summary?.contentScriptCount ?? 0) > 0,
           input.contentScriptEligibilitySatisfied == false
        {
            blockers.append(
                blocker(
                    kind: .contentScriptProductPolicyBlocked,
                    source: .contentScriptPolicy,
                    reason: "Content scripts are present, but product normal-tab content-script eligibility is blocked."
                )
            )
        }

        if summary?.chromeMV3ProductRequiresPermissionPolicy == true,
           input.permissionStateSatisfied == false
        {
            blockers.append(
                blocker(
                    kind: .permissionProductPolicyBlocked,
                    source: .permissionPolicy,
                    reason: "The extension requires product permission state, but product permission prompts are not enabled."
                )
            )
        }

        if summary?.backgroundServiceWorker != nil {
            blockers.append(
                blocker(
                    kind: .serviceWorkerProductPolicyBlocked,
                    source: .serviceWorkerPolicy,
                    reason: "Product service-worker wake remains blocked for normal-tab runtime preflight.",
                    relatedIDs:
                        relatedProductBlockerIDs(input.report, sources: [.serviceWorker])
                )
            )
        }

        if summary?.chromeMV3ProductRequiresNativeMessaging == true,
           input.nativeMessagingProductPolicyAllows == false
        {
            blockers.append(
                blocker(
                    kind: .nativeMessagingProductPolicyBlocked,
                    source: .nativeMessagingPolicy,
                    reason: "Native messaging product policy blocks arbitrary native host launch.",
                    relatedIDs:
                        relatedProductBlockerIDs(input.report, sources: [.nativeMessaging])
                )
            )
        }

        if summary?.chromeMV3ProductRequiresNetworkEnforcement == true,
           input.productNetworkEnforcementPolicyAllows == false
        {
            blockers.append(
                blocker(
                    kind: .productNetworkEnforcementBlocked,
                    source: .networkPolicy,
                    reason: "Product DNR/webRequest network enforcement remains unavailable.",
                    relatedIDs:
                        relatedProductBlockerIDs(input.report, sources: [.network])
                )
            )
        }

        if summary?.chromeMV3ProductRequiresSidePanelOffscreenIdentity == true,
           input.sidePanelOffscreenIdentityProductPolicyAllows == false
        {
            blockers.append(
                blocker(
                    kind: .sidePanelOffscreenIdentityProductPolicyBlocked,
                    source: .sidePanelOffscreenIdentityPolicy,
                    reason: "Product sidePanel, offscreen, and identity runtime paths remain blocked.",
                    relatedIDs:
                        relatedProductBlockerIDs(
                            input.report,
                            sources: [.sidePanel, .offscreen, .identity, .productUI]
                        )
                )
            )
        }

        if input.disabledRuntimeInvariantsSatisfied == false {
            blockers.append(
                blocker(
                    kind: .disabledInvariantViolation,
                    source: .disabledInvariant,
                    reason: "Disabled/off zero-cost invariants were not satisfied."
                )
            )
        }

        let runtimeGateBlockers = relatedProductBlockerIDs(
            input.report,
            sources: [.runtimeGate]
        )
        if runtimeGateBlockers.isEmpty == false {
            if input.gateSet.debugOverrideGate.state == .allowed {
                waivedCompatibilityBlockerIDs.append(contentsOf: runtimeGateBlockers)
            } else {
                blockers.append(
                    blocker(
                        kind: .runtimeGateBlocked,
                        source: .compatibilityReport,
                        reason: "Compatibility report keeps runtimeLoadable false for product runtime.",
                        relatedIDs: runtimeGateBlockers
                    )
                )
            }
        }

        let fatalIDs = input.report?.blockerTaxonomy.filter {
            $0.severity == .fatalInstall || $0.severity == .fatalRuntime
        }.map(\.id) ?? []
        if fatalIDs.isEmpty == false {
            blockers.append(
                blocker(
                    kind: .fatalCompatibilityBlocker,
                    source: .compatibilityReport,
                    reason: "Fatal compatibility blockers prevent product runtime preflight.",
                    relatedIDs: fatalIDs
                )
            )
        }

        let unsupportedIDs = input.report?.blockerTaxonomy.filter {
            $0.severity == .unsupported
        }.map(\.id) ?? []
        if unsupportedIDs.isEmpty == false {
            blockers.append(
                blocker(
                    kind: .unsupportedAPIBlocker,
                    source: .compatibilityReport,
                    reason: "Unsupported API blockers prevent product runtime preflight.",
                    relatedIDs: unsupportedIDs
                )
            )
        }

        blockers = uniqueBlockers(blockers)
        let canAttach = blockers.isEmpty
            && input.gateSet.allExplicitGatesAllowPreflight
            && extensionEnablement.canEverAttachToProductNormalTab
        let contentScriptsPresent = (summary?.contentScriptCount ?? 0) > 0
        return ChromeMV3ProductNormalTabRuntimePreflight(
            profileID: input.profileID,
            extensionID: input.extensionID,
            tabID: input.tabID,
            tabSurface: input.tabSurface,
            gateSet: input.gateSet,
            extensionEnablement: extensionEnablement,
            generatedBundleActive: input.generatedBundleActive,
            generatedBundleExists: input.generatedBundleExists,
            sameControllerRequirementSatisfied:
                input.sameControllerRequirementSatisfied,
            canAttachToNormalTabNow: canAttach,
            canExposeRuntimeBridgeNow: canAttach,
            canInjectContentScriptsNow:
                canAttach && contentScriptsPresent
                    && input.contentScriptEligibilitySatisfied,
            canWakeServiceWorkerNow: false,
            canUseNativeMessagingNow: false,
            canUseProductNetworkEnforcementNow: false,
            blockers: blockers,
            waivedCompatibilityBlockerIDs:
                Array(Set(waivedCompatibilityBlockerIDs)).sorted(),
            diagnostics: diagnostics(
                canAttach: canAttach,
                blockers: blockers,
                waivedCompatibilityBlockerIDs:
                    waivedCompatibilityBlockerIDs
            )
        )
    }

    private static func appendWebKitDiagnosticsBlockers(
        input: ChromeMV3ProductNormalTabRuntimePreflightInput,
        blockers: inout [ChromeMV3ProductRuntimePreflightBlocker]
    ) {
        let checks: [(Bool, String)] = [
            (
                input.WebKitObjectDiagnosticsReady,
                "WebKit object diagnostics are required before product normal-tab preflight."
            ),
            (
                input.contextReadinessDiagnosticsReady,
                "Context readiness diagnostics are required before product normal-tab preflight."
            ),
            (
                input.controllerLoadDiagnosticsReady,
                "Controller load diagnostics are required before product normal-tab preflight."
            ),
            (
                input.runtimeBridgeDiagnosticsReady,
                "Runtime bridge readiness diagnostics are required before product normal-tab preflight."
            ),
        ]
        for check in checks where check.0 == false {
            blockers.append(
                blocker(
                    kind: .webKitDiagnosticsMissing,
                    source: .WebKitRuntime,
                    reason: check.1
                )
            )
        }
    }

    private static func diagnostics(
        canAttach: Bool,
        blockers: [ChromeMV3ProductRuntimePreflightBlocker],
        waivedCompatibilityBlockerIDs: [String]
    ) -> [String] {
        var values = [
            canAttach
                ? "All explicit internal product gates passed for preflight; no runtime was attached."
                : "Product normal-tab runtime preflight is blocked.",
            "Service-worker wake, native messaging, product network enforcement, and product UI remain blocked.",
            "This preflight does not mutate WKWebViewConfiguration or register JavaScript.",
        ]
        if blockers.isEmpty == false {
            values.append(
                "Blocked by: \(blockers.map(\.kind.rawValue).sorted().joined(separator: ", "))."
            )
        }
        if waivedCompatibilityBlockerIDs.isEmpty == false {
            values.append(
                "Runtime-gate compatibility blockers were waived only for explicit internal product-gate preflight."
            )
        }
        return uniqueSortedProduct(values)
    }

    private static func blocker(
        kind: ChromeMV3ProductRuntimePreflightBlockerKind,
        source: ChromeMV3ProductRuntimeGateSource,
        reason: String,
        relatedIDs: [String] = []
    ) -> ChromeMV3ProductRuntimePreflightBlocker {
        ChromeMV3ProductRuntimePreflightBlocker(
            id: "product-preflight-\(kind.rawValue)-\(source.rawValue)",
            kind: kind,
            source: source,
            reason: reason,
            relatedCompatibilityBlockerIDs: Array(Set(relatedIDs)).sorted()
        )
    }

    private static func uniqueBlockers(
        _ blockers: [ChromeMV3ProductRuntimePreflightBlocker]
    ) -> [ChromeMV3ProductRuntimePreflightBlocker] {
        var seen: Set<String> = []
        return blockers.filter {
            if seen.contains($0.id) { return false }
            seen.insert($0.id)
            return true
        }
        .sorted {
            if $0.kind != $1.kind {
                return $0.kind < $1.kind
            }
            return $0.id < $1.id
        }
    }
}

enum ChromeMV3ProductBridgeAttachmentPlanItemKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case webViewConfigurationControllerAttachment
    case extensionContext
    case jsBridgeNamespace
    case contentScriptBehavior
    case permissionRequirement
    case serviceWorkerLifecycleSession
    case nativeMessagingPolicy
    case networkEnforcementPolicy
    case teardownPolicy

    static func < (
        lhs: ChromeMV3ProductBridgeAttachmentPlanItemKind,
        rhs: ChromeMV3ProductBridgeAttachmentPlanItemKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ProductBridgeAttachmentPlanItem:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3ProductBridgeAttachmentPlanItemKind
    var title: String
    var planned: Bool
    var activeNow: Bool
    var details: [String]
}

struct ChromeMV3ProductBridgeAttachmentPlan:
    Codable,
    Equatable,
    Sendable
{
    var planID: String
    var profileID: String
    var extensionID: String
    var tabID: String
    var planOnly: Bool
    var performsAttachmentNow: Bool
    var canPrepareAttachmentNow: Bool
    var wouldAttachWKWebViewConfigurationWebExtensionController: Bool
    var requiresSameControllerAsExtensionRuntime: Bool
    var wouldCreateExtensionContexts: Bool
    var wouldUseExistingExtensionContexts: Bool
    var plannedJSBridgeNamespaces: [String]
    var exposedJSBridgeNamespacesNow: [String]
    var wouldInjectContentScriptsNow: Bool
    var wouldWakeServiceWorkerNow: Bool
    var wouldUseNativeMessagingNow: Bool
    var wouldUseProductNetworkEnforcementNow: Bool
    var teardownPolicy: [String]
    var items: [ChromeMV3ProductBridgeAttachmentPlanItem]
    var blockers: [ChromeMV3ProductRuntimePreflightBlocker]

    static func make(
        preflight: ChromeMV3ProductNormalTabRuntimePreflight,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?
    ) -> ChromeMV3ProductBridgeAttachmentPlan {
        let namespaces = plannedNamespaces(
            manifestSummary: report?.chromeMV3ProductActiveManifestSummary
        )
        let teardown = [
            "Detach controller association before profile/module disable if a future product attachment exists.",
            "Do not retain hidden WebViews or fallback runtimes.",
            "Cancel service-worker, native messaging, and JS bridge sessions before clearing product gates.",
            "Remove per-tab product eligibility when the normal tab is closed or reclassified.",
        ]
        let canPrepare = preflight.canAttachToNormalTabNow
            && preflight.canExposeRuntimeBridgeNow
        let items = [
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .webViewConfigurationControllerAttachment,
                title: "WKWebViewConfiguration.webExtensionController",
                planned: canPrepare,
                activeNow: false,
                details: [
                    "Would attach the profile-scoped WKWebExtensionController only after all explicit product gates pass.",
                    "No BrowserConfiguration mutation occurs from this plan.",
                ]
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .extensionContext,
                title: "Extension contexts",
                planned: canPrepare,
                activeNow: false,
                details: [
                    "Requires a future loaded WKWebExtensionContext that shares the same controller as the normal tab.",
                    "This phase does not create or load contexts.",
                ]
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .jsBridgeNamespace,
                title: "JS bridge namespaces",
                planned: canPrepare,
                activeNow: false,
                details: namespaces
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .contentScriptBehavior,
                title: "Content scripts",
                planned: preflight.canInjectContentScriptsNow,
                activeNow: false,
                details: [
                    "No product normal-tab JS shim or content script is installed by default.",
                ]
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .permissionRequirement,
                title: "Permission requirements",
                planned: canPrepare,
                activeNow: false,
                details: [
                    "Product permission prompt UI remains unavailable.",
                ]
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .serviceWorkerLifecycleSession,
                title: "Service-worker lifecycle",
                planned: false,
                activeNow: false,
                details: [
                    "Product service-worker wake remains blocked.",
                ]
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .nativeMessagingPolicy,
                title: "Native messaging policy",
                planned: false,
                activeNow: false,
                details: [
                    "Arbitrary native host launch remains blocked.",
                ]
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .networkEnforcementPolicy,
                title: "Product network enforcement",
                planned: false,
                activeNow: false,
                details: [
                    "DNR/webRequest product enforcement remains blocked.",
                ]
            ),
            ChromeMV3ProductBridgeAttachmentPlanItem(
                kind: .teardownPolicy,
                title: "Teardown policy",
                planned: canPrepare,
                activeNow: false,
                details: teardown
            ),
        ].sorted {
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            return $0.title < $1.title
        }
        return ChromeMV3ProductBridgeAttachmentPlan(
            planID: [
                "product-bridge-plan",
                preflight.profileID,
                preflight.extensionID,
                preflight.tabID,
            ].joined(separator: "-"),
            profileID: preflight.profileID,
            extensionID: preflight.extensionID,
            tabID: preflight.tabID,
            planOnly: true,
            performsAttachmentNow: false,
            canPrepareAttachmentNow: canPrepare,
            wouldAttachWKWebViewConfigurationWebExtensionController:
                canPrepare,
            requiresSameControllerAsExtensionRuntime: true,
            wouldCreateExtensionContexts: false,
            wouldUseExistingExtensionContexts: canPrepare,
            plannedJSBridgeNamespaces: namespaces,
            exposedJSBridgeNamespacesNow:
                preflight.canExposeRuntimeBridgeNow ? namespaces : [],
            wouldInjectContentScriptsNow:
                preflight.canInjectContentScriptsNow,
            wouldWakeServiceWorkerNow: false,
            wouldUseNativeMessagingNow: false,
            wouldUseProductNetworkEnforcementNow: false,
            teardownPolicy: teardown,
            items: items,
            blockers: preflight.blockers
        )
    }

    private static func plannedNamespaces(
        manifestSummary: ChromeMV3ManifestSummary?
    ) -> [String] {
        guard let manifestSummary else { return ["chrome.runtime"] }
        var namespaces = ["chrome.runtime"]
        if manifestSummary.permissions.contains("storage") {
            namespaces.append("chrome.storage")
        }
        if manifestSummary.permissions.contains("tabs") {
            namespaces.append("chrome.tabs")
        }
        if manifestSummary.permissions.contains("scripting")
            || manifestSummary.contentScriptCount > 0
        {
            namespaces.append("chrome.scripting")
        }
        if manifestSummary.chromeMV3ProductRequiresPermissionPolicy {
            namespaces.append("chrome.permissions")
        }
        if manifestSummary.chromeMV3ProductRequiresNativeMessaging {
            namespaces.append("chrome.runtime.nativeMessaging")
        }
        if manifestSummary.hasDeclarativeNetRequest
            || manifestSummary.permissions.contains("declarativeNetRequest")
        {
            namespaces.append("chrome.declarativeNetRequest")
        }
        if manifestSummary.permissions.contains("webRequest")
            || manifestSummary.permissions.contains("webRequestBlocking")
        {
            namespaces.append("chrome.webRequest")
        }
        if manifestSummary.hasSidePanel
            || manifestSummary.permissions.contains("sidePanel")
        {
            namespaces.append("chrome.sidePanel")
        }
        if manifestSummary.permissions.contains("offscreen") {
            namespaces.append("chrome.offscreen")
        }
        if manifestSummary.permissions.contains("identity")
            || manifestSummary.permissions.contains("identity.email")
        {
            namespaces.append("chrome.identity")
        }
        return Array(Set(namespaces)).sorted()
    }
}

struct ChromeMV3ProductEnablementPreflightSection:
    Codable,
    Equatable,
    Sendable
{
    var gateSummary: ChromeMV3ProductRuntimeGateSet
    var extensionProductEnablement:
        ChromeMV3ExtensionProductEnablement
    var normalTabPreflight: ChromeMV3ProductNormalTabRuntimePreflight
    var bridgeAttachmentPlan: ChromeMV3ProductBridgeAttachmentPlan
    var productBlockerIDs: [String]
    var nextPhaseBlockers: [String]

    static func make(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        gateSet: ChromeMV3ProductRuntimeGateSet? = nil
    ) -> ChromeMV3ProductEnablementPreflightSection {
        let resolvedGateSet = gateSet ?? .defaultBlocked(
            report: report,
            lifecycleRecord: lifecycleRecord
        )
        let input = ChromeMV3ProductNormalTabRuntimePreflightInput.make(
            report: report,
            lifecycleRecord: lifecycleRecord,
            gateSet: resolvedGateSet
        )
        let preflight =
            ChromeMV3ProductNormalTabRuntimePreflightEvaluator.evaluate(
                input: input
            )
        let plan = ChromeMV3ProductBridgeAttachmentPlan.make(
            preflight: preflight,
            report: report
        )
        let productBlockerIDs = report?.blockerTaxonomy.filter {
            $0.severity == .productBlocked
        }.map(\.id).sorted() ?? []
        return ChromeMV3ProductEnablementPreflightSection(
            gateSummary: resolvedGateSet,
            extensionProductEnablement:
                preflight.extensionEnablement,
            normalTabPreflight: preflight,
            bridgeAttachmentPlan: plan,
            productBlockerIDs: productBlockerIDs,
            nextPhaseBlockers: nextPhaseBlockers(
                report: report,
                preflight: preflight
            )
        )
    }

    private static func nextPhaseBlockers(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        preflight: ChromeMV3ProductNormalTabRuntimePreflight
    ) -> [String] {
        var blockers = preflight.blockers.map(\.reason)
        let productSources = Set(
            report?.blockerTaxonomy.filter {
                $0.severity == .productBlocked
            }.map(\.source) ?? []
        )
        if productSources.contains(.network) {
            blockers.append("Product DNR/network enforcement policy is still required.")
        }
        if productSources.contains(.nativeMessaging) {
            blockers.append("Product native messaging host policy is still required.")
        }
        if productSources.contains(.serviceWorker) {
            blockers.append("Product service-worker wake policy is still required.")
        }
        if productSources.contains(.sidePanel)
            || productSources.contains(.offscreen)
            || productSources.contains(.identity)
        {
            blockers.append("Product sidePanel/offscreen/identity design is still required.")
        }
        blockers.append("Product permission prompt UI remains a separate blocked phase.")
        return uniqueSortedProduct(blockers)
    }
}

private extension ChromeMV3EndToEndInstallDiagnosticsReport {
    var chromeMV3ProductActiveGeneratedVersion:
        ChromeMV3GeneratedBundleVersionRecord?
    {
        generatedBundleVersionState.last {
            $0.state == .active || $0.state == .rollbackActive
        } ?? generatedBundleVersionState.last
    }

    var chromeMV3ProductActiveManifestSummary: ChromeMV3ManifestSummary? {
        chromeMV3ProductActiveGeneratedVersion?
            .generatedBundleRecord
            .installReportSummary
            .manifestSummary
    }
}

private extension ChromeMV3ManifestSummary {
    var chromeMV3ProductRequiresPermissionPolicy: Bool {
        permissions.isEmpty == false
            || optionalPermissions.isEmpty == false
            || hostPermissions.isEmpty == false
    }

    var chromeMV3ProductRequiresNativeMessaging: Bool {
        permissions.contains("nativeMessaging")
    }

    var chromeMV3ProductRequiresNetworkEnforcement: Bool {
        hasDeclarativeNetRequest
            || permissions.contains("declarativeNetRequest")
            || permissions.contains("webRequest")
            || permissions.contains("webRequestBlocking")
            || permissions.contains("webRequestAuthProvider")
    }

    var chromeMV3ProductRequiresSidePanelOffscreenIdentity: Bool {
        hasSidePanel
            || permissions.contains("sidePanel")
            || permissions.contains("offscreen")
            || permissions.contains("identity")
            || permissions.contains("identity.email")
    }
}

private func relatedProductBlockerIDs(
    _ report: ChromeMV3EndToEndInstallDiagnosticsReport?,
    sources: Set<ChromeMV3APIBlockerSource>
) -> [String] {
    report?.blockerTaxonomy.filter {
        $0.severity == .productBlocked && sources.contains($0.source)
    }.map(\.id).sorted() ?? []
}

private func forbiddenProductAPIBlockers(
    in report: ChromeMV3EndToEndInstallDiagnosticsReport?
) -> [ChromeMV3APIBlockerRecord] {
    let forbiddenSources: Set<ChromeMV3APIBlockerSource> = [
        .nativeMessaging,
        .network,
        .offscreen,
        .identity,
        .productUI,
        .securityPolicy,
        .serviceWorker,
        .sidePanel,
    ]
    return report?.blockerTaxonomy.filter {
        $0.severity == .productBlocked
            && forbiddenSources.contains($0.source)
    }.sorted {
        if $0.source != $1.source { return $0.source < $1.source }
        return $0.id < $1.id
    } ?? []
}

private func uniqueAPIs(_ apis: [ChromeMV3API]) -> [ChromeMV3API] {
    Array(Set(apis)).sorted()
}

private func uniqueSortedProduct(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
