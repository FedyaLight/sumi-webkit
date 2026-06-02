//
//  ChromeMV3ProductRuntimeGate.swift
//  Sumi
//
//  Product-gated Chrome MV3 normal-tab bridge planning. This layer is
//  deterministic policy and diagnostics only: it does not create WebKit
//  extension objects, attach controllers, inject scripts, wake service
//  workers, launch native hosts, or enable product network enforcement.
//

import CryptoKit
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

struct ChromeMV3ProductNormalTabReadinessPolicy:
    Codable,
    Equatable,
    Sendable
{
    var productNormalTabMV3ReadinessAvailableInLocalExperimentalGate: Bool
    var productNormalTabMV3ReadinessAvailableByDefault: Bool
    var manualNormalTabSmokeAvailableInLocalExperimentalGate: Bool
    var manualNormalTabSmokeAvailableByDefault: Bool
    var productDefaultRuntimeAvailable: Bool
    var defaultOffRuntime: Bool
    var reviewedFileOnly: Bool
    var syntheticHTTPSOriginOnly: Bool
    var reviewedGeneratedBundleFileOnly: Bool
    var isolatedWorldOnly: Bool
    var topFrameOnly: Bool
    var mainWorldAllowed: Bool
    var multiFrameAllowed: Bool
    var fileSchemeAllowed: Bool
    var auxiliarySurfaceAllowed: Bool
    var requiresHostPermissionOrActiveTab: Bool
    var teardownRequired: Bool
    var diagnostics: [String]
    var sourceGaps: [String]

    static let localExperimentalDefaultOff =
        ChromeMV3ProductNormalTabReadinessPolicy(
            productNormalTabMV3ReadinessAvailableInLocalExperimentalGate: true,
            productNormalTabMV3ReadinessAvailableByDefault: false,
            manualNormalTabSmokeAvailableInLocalExperimentalGate: true,
            manualNormalTabSmokeAvailableByDefault: false,
            productDefaultRuntimeAvailable: false,
            defaultOffRuntime: true,
            reviewedFileOnly: true,
            syntheticHTTPSOriginOnly: true,
            reviewedGeneratedBundleFileOnly: true,
            isolatedWorldOnly: true,
            topFrameOnly: true,
            mainWorldAllowed: false,
            multiFrameAllowed: false,
            fileSchemeAllowed: false,
            auxiliarySurfaceAllowed: false,
            requiresHostPermissionOrActiveTab: true,
            teardownRequired: true,
            diagnostics: [
                "Product normal-tab MV3 readiness is local experimental and default-off.",
                "Manual normal-tab smoke is local experimental, explicit, and unavailable by default.",
                "The readiness slice is plan-only until an explicit local gate and all normal-tab smoke preflights pass.",
                "Only reviewed generated-bundle file planning is modeled; arbitrary code, functions, strings, and remote scripts remain blocked.",
                "No normal-tab attachment, WebKit controller/context creation, script registration, service-worker wake, native host launch, or network enforcement is performed by this policy.",
            ],
            sourceGaps: [
                "Apple public docs and local SDK headers expose WKUserContentController.removeAllUserScripts and content-world script-message-handler removal, but no public per-WKUserScript removal API. A future execution path must own a scoped teardown handle and remain blocked if that handle cannot prove removal.",
            ]
        )
}

enum ChromeMV3ProductNormalTabReadinessBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blockedByModule
    case blockedByExtension
    case blockedByProfile
    case blockedByLocalExperimentalGate
    case blockedBySurface
    case blockedByAuxiliarySurface
    case blockedByScheme
    case blockedByPermission
    case blockedByMissingReviewedResource
    case blockedByWorld
    case blockedByFrame
    case blockedByRuntimeGate
    case blockedByNonSyntheticOrigin

    static func < (
        lhs: ChromeMV3ProductNormalTabReadinessBlocker,
        rhs: ChromeMV3ProductNormalTabReadinessBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ProductNormalTabReadinessTeardownTrigger:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case navigation
    case tabClose
    case extensionDisable
    case moduleDisable
    case profileClose
    case permissionRevoke
    case resetOrUninstall
    case smokeCompletion

    static func < (
        lhs: ChromeMV3ProductNormalTabReadinessTeardownTrigger,
        rhs: ChromeMV3ProductNormalTabReadinessTeardownTrigger
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ProductNormalTabReadinessLifetimeReport:
    Codable,
    Equatable,
    Sendable
{
    var disabledModuleObjectsCreated: [String]
    var managerReadoutObjectsCreated: [String]
    var runtimeObjectsCreatedNow: [String]
    var objectsRetainedAfterReadiness: [String]
    var objectsRemovedOnTeardown: [String]
    var backgroundWorkScheduled: Bool
    var permanentRuntimeRetained: Bool
    var teardownTriggers: [ChromeMV3ProductNormalTabReadinessTeardownTrigger]
    var diagnostics: [String]

    static let planOnly =
        ChromeMV3ProductNormalTabReadinessLifetimeReport(
            disabledModuleObjectsCreated: [],
            managerReadoutObjectsCreated: [
                "Codable readiness policy record",
                "Codable normal-tab preflight record",
                "Codable reviewed-file injection plan record",
                "Codable lifecycle and manual-smoke readiness records",
            ],
            runtimeObjectsCreatedNow: [],
            objectsRetainedAfterReadiness: [],
            objectsRemovedOnTeardown: [
                "Future scoped content-world user scripts, if execution is explicitly enabled by a local smoke gate.",
                "Future scoped script-message handlers, if execution is explicitly enabled by a local smoke gate.",
                "Future content-script endpoint registrations for the tab/document/navigation sequence.",
                "Future activeTab grant references tied to the tab origin.",
            ],
            backgroundWorkScheduled: false,
            permanentRuntimeRetained: false,
            teardownTriggers:
                ChromeMV3ProductNormalTabReadinessTeardownTrigger
                .allCases
                .sorted(),
            diagnostics: [
                "Disabled extensions remain zero-cost: no ExtensionManager, runtime bridge, service-worker, content-script, or native-host objects are created by this readiness model.",
                "Manager readout creates only transient value records and performs no attachment or JavaScript registration.",
                "A future smoke attachment must be lazy, scoped to one tab/document/navigation sequence, and removed on every listed teardown trigger.",
            ]
        )
}

struct ChromeMV3ProductNormalTabReviewedResource:
    Codable,
    Equatable,
    Sendable
{
    var reviewedScriptPath: String
    var generatedResourceHash: String?
    var generatedResourceFileSystemPath: String?
    var present: Bool
    var packageOwned: Bool
    var diagnostics: [String]

    static func bootstrapAutofill(
        generatedBundleRootPath: String?,
        copiedResourcePaths: [String],
        hash: String?
    ) -> ChromeMV3ProductNormalTabReviewedResource {
        let reviewedPath =
            ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
            .bitwardenDetectFillBootstrapFile
        return reviewedGeneratedBundleFile(
            path: reviewedPath,
            generatedBundleRootPath: generatedBundleRootPath,
            copiedResourcePaths: copiedResourcePaths,
            hash: hash
        )
    }

    static func reviewedGeneratedBundleFile(
        path reviewedPath: String,
        generatedBundleRootPath: String?,
        copiedResourcePaths: [String],
        hash: String?
    ) -> ChromeMV3ProductNormalTabReviewedResource {
        let copied = copiedResourcePaths.contains(reviewedPath)
        let fileSystemPath = generatedBundleRootPath.map {
            URL(fileURLWithPath: $0)
                .appendingPathComponent(reviewedPath)
                .standardizedFileURL
                .path
        }
        return ChromeMV3ProductNormalTabReviewedResource(
            reviewedScriptPath: reviewedPath,
            generatedResourceHash: hash,
            generatedResourceFileSystemPath: fileSystemPath,
            present: copied && hash != nil,
            packageOwned: copied,
            diagnostics: [
                copied
                    ? "Reviewed generated-bundle file is listed in copied resources."
                    : "Reviewed generated-bundle file is not listed in copied resources.",
                hash == nil
                    ? "Reviewed generated-bundle file hash is unavailable."
                    : "Reviewed generated-bundle file hash is recorded.",
            ]
        )
    }

    static func unregistered() -> ChromeMV3ProductNormalTabReviewedResource {
        ChromeMV3ProductNormalTabReviewedResource(
            reviewedScriptPath: "",
            generatedResourceHash: nil,
            generatedResourceFileSystemPath: nil,
            present: false,
            packageOwned: false,
            diagnostics: [
                "No reviewed generated-bundle resource capability is registered.",
            ]
        )
    }
}

struct ChromeMV3ProductNormalTabReadinessPreflightInput:
    Sendable
{
    var policy: ChromeMV3ProductNormalTabReadinessPolicy =
        .localExperimentalDefaultOff
    var profileID: String
    var extensionID: String
    var tabID: String
    var documentID: String
    var urlString: String
    var moduleEnabled: Bool
    var extensionEnabled: Bool
    var profileEnabled: Bool
    var localExperimentalProductGateAllowed: Bool
    var runtimeGateAllowsReadiness: Bool
    var contentScriptRouteReady: Bool
    var serviceWorkerRouteReady: Bool
    var tabSurface: ChromeMV3WebViewSurface
    var syntheticHTTPSOrigin: String
    var frameID: Int
    var isTopFrame: Bool
    var contentWorld: ChromeMV3ContentScriptWorld
    var hostAccessDecision: ChromeMV3HostAccessDecision
    var reviewedResource: ChromeMV3ProductNormalTabReviewedResource
    var teardownPending: Bool
}

struct ChromeMV3ProductNormalTabReadinessPreflight:
    Codable,
    Equatable,
    Sendable
{
    var policy: ChromeMV3ProductNormalTabReadinessPolicy
    var profileID: String
    var extensionID: String
    var tabID: String
    var documentID: String
    var urlString: String
    var tabSurface: ChromeMV3WebViewSurface
    var frameID: Int
    var isTopFrame: Bool
    var contentWorld: ChromeMV3ContentScriptWorld
    var hostAccessDecision: ChromeMV3HostAccessDecision
    var reviewedResource: ChromeMV3ProductNormalTabReviewedResource
    var eligible: Bool
    var blockedByModule: Bool
    var blockedByExtension: Bool
    var blockedByProfile: Bool
    var blockedByLocalExperimentalGate: Bool
    var blockedBySurface: Bool
    var blockedByAuxiliarySurface: Bool
    var blockedByScheme: Bool
    var blockedByPermission: Bool
    var blockedByMissingReviewedResource: Bool
    var blockedByWorld: Bool
    var blockedByFrame: Bool
    var blockedByRuntimeGate: Bool
    var blockedByNonSyntheticOrigin: Bool
    var blockers: [ChromeMV3ProductNormalTabReadinessBlocker]
    var diagnostics: [String]
}

enum ChromeMV3ProductNormalTabReadinessPreflightEvaluator {
    static func evaluate(
        input: ChromeMV3ProductNormalTabReadinessPreflightInput
    ) -> ChromeMV3ProductNormalTabReadinessPreflight {
        let urlClassification =
            ChromeMV3ContentScriptURLClassification.classify(input.urlString)
        let blockedByModule = input.moduleEnabled == false
        let blockedByExtension = input.extensionEnabled == false
        let blockedByProfile = input.profileEnabled == false
        let blockedByLocalExperimentalGate =
            input.localExperimentalProductGateAllowed == false
        let blockedByAuxiliarySurface =
            input.policy.auxiliarySurfaceAllowed == false
                && input.tabSurface
                    .isAuxiliaryOrHelperSurfaceForChromeMV3Attachment
        let blockedBySurface =
            input.tabSurface != .normalTab
                || blockedByAuxiliarySurface
        let blockedByScheme =
            urlClassification != .httpFamily
                || (
                    input.policy.fileSchemeAllowed == false
                        && urlClassification == .file
                )
        let blockedByNonSyntheticOrigin =
            input.policy.syntheticHTTPSOriginOnly
                && ChromeMV3RuntimeMessagingURL.origin(from: input.urlString)
                    != input.syntheticHTTPSOrigin
        let blockedByPermission =
            input.policy.requiresHostPermissionOrActiveTab
                && input.hostAccessDecision.hasHostAccess == false
        let blockedByMissingReviewedResource =
            input.policy.reviewedGeneratedBundleFileOnly
                && (input.reviewedResource.present == false
                    || input.reviewedResource.generatedResourceHash == nil
                    || input.reviewedResource.packageOwned == false)
        let blockedByWorld =
            input.policy.isolatedWorldOnly
                && input.contentWorld != .isolated
        let blockedByFrame =
            input.policy.topFrameOnly
                && (input.isTopFrame == false || input.frameID != 0)
        let blockedByRuntimeGate =
            input.runtimeGateAllowsReadiness == false
                || input.contentScriptRouteReady == false
                || input.serviceWorkerRouteReady == false
                || input.teardownPending

        let pairs: [(ChromeMV3ProductNormalTabReadinessBlocker, Bool)] = [
            (.blockedByModule, blockedByModule),
            (.blockedByExtension, blockedByExtension),
            (.blockedByProfile, blockedByProfile),
            (.blockedByLocalExperimentalGate, blockedByLocalExperimentalGate),
            (.blockedBySurface, blockedBySurface),
            (.blockedByAuxiliarySurface, blockedByAuxiliarySurface),
            (.blockedByScheme, blockedByScheme),
            (.blockedByPermission, blockedByPermission),
            (.blockedByMissingReviewedResource, blockedByMissingReviewedResource),
            (.blockedByWorld, blockedByWorld),
            (.blockedByFrame, blockedByFrame),
            (.blockedByRuntimeGate, blockedByRuntimeGate),
            (.blockedByNonSyntheticOrigin, blockedByNonSyntheticOrigin),
        ]
        let blockers = pairs.compactMap { $0.1 ? $0.0 : nil }.sorted()
        let eligible = blockers.isEmpty

        return ChromeMV3ProductNormalTabReadinessPreflight(
            policy: input.policy,
            profileID: input.profileID,
            extensionID: input.extensionID,
            tabID: input.tabID,
            documentID: input.documentID,
            urlString: input.urlString,
            tabSurface: input.tabSurface,
            frameID: input.frameID,
            isTopFrame: input.isTopFrame,
            contentWorld: input.contentWorld,
            hostAccessDecision: input.hostAccessDecision,
            reviewedResource: input.reviewedResource,
            eligible: eligible,
            blockedByModule: blockedByModule,
            blockedByExtension: blockedByExtension,
            blockedByProfile: blockedByProfile,
            blockedByLocalExperimentalGate: blockedByLocalExperimentalGate,
            blockedBySurface: blockedBySurface,
            blockedByAuxiliarySurface: blockedByAuxiliarySurface,
            blockedByScheme: blockedByScheme,
            blockedByPermission: blockedByPermission,
            blockedByMissingReviewedResource:
                blockedByMissingReviewedResource,
            blockedByWorld: blockedByWorld,
            blockedByFrame: blockedByFrame,
            blockedByRuntimeGate: blockedByRuntimeGate,
            blockedByNonSyntheticOrigin: blockedByNonSyntheticOrigin,
            blockers: blockers,
            diagnostics:
                uniqueSortedProduct(
                    input.policy.diagnostics
                        + input.policy.sourceGaps
                        + input.hostAccessDecision.diagnostics
                        + input.reviewedResource.diagnostics
                        + [
                            "Candidate URL classification is \(urlClassification.rawValue).",
                            "Candidate surface is \(input.tabSurface.rawValue); only normalTab is accepted for this product-normal-tab readiness slice.",
                            "Synthetic HTTPS origin requirement is \(input.syntheticHTTPSOrigin).",
                            "Local experimental product gate allowed: \(input.localExperimentalProductGateAllowed).",
                            "Runtime gate allows readiness: \(input.runtimeGateAllowsReadiness).",
                            "Content-script route ready: \(input.contentScriptRouteReady).",
                            "Service-worker route ready: \(input.serviceWorkerRouteReady).",
                            "Product default runtime available: \(input.policy.productDefaultRuntimeAvailable).",
                            eligible
                                ? "Product normal-tab readiness preflight passed; execution still requires the explicit local smoke path."
                                : "Product normal-tab readiness preflight is blocked by \(blockers.map(\.rawValue).joined(separator: ", ")).",
                        ]
                )
        )
    }
}

struct ChromeMV3ProductNormalTabReviewedFileInjectionPlan:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var tabID: String
    var documentID: String
    var reviewedScriptPath: String
    var generatedResourceHash: String?
    var targetFrame: String
    var contentWorld: String
    var expectedTeardown: [ChromeMV3ProductNormalTabReadinessTeardownTrigger]
    var planOnly: Bool
    var executionAllowedNow: Bool
    var performsExecutionByManagerReadout: Bool
    var blockers: [ChromeMV3ProductNormalTabReadinessBlocker]
    var diagnostics: [String]

    static func make(
        preflight: ChromeMV3ProductNormalTabReadinessPreflight
    ) -> ChromeMV3ProductNormalTabReviewedFileInjectionPlan {
        let teardown =
            ChromeMV3ProductNormalTabReadinessTeardownTrigger
            .allCases
            .sorted()
        return ChromeMV3ProductNormalTabReviewedFileInjectionPlan(
            extensionID: preflight.extensionID,
            profileID: preflight.profileID,
            tabID: preflight.tabID,
            documentID: preflight.documentID,
            reviewedScriptPath: preflight.reviewedResource.reviewedScriptPath,
            generatedResourceHash:
                preflight.reviewedResource.generatedResourceHash,
            targetFrame:
                preflight.isTopFrame && preflight.frameID == 0
                    ? "topFrame"
                    : "blockedFrame-\(preflight.frameID)",
            contentWorld: preflight.contentWorld.rawValue,
            expectedTeardown: teardown,
            planOnly: true,
            executionAllowedNow: preflight.eligible,
            performsExecutionByManagerReadout: false,
            blockers: preflight.blockers,
            diagnostics:
                uniqueSortedProduct(
                    preflight.diagnostics
                        + [
                            "Reviewed-file injection planning names a generated-bundle file only; no arbitrary chrome.scripting.executeScript function or string body is accepted.",
                            "Manager detail readout never executes this plan.",
                            preflight.eligible
                                ? "A future manual smoke may execute only through the explicit local smoke path and must verify teardown immediately after completion."
                                : "Execution remains blocked until every readiness blocker is cleared in a local experimental test path.",
                        ]
                )
        )
    }
}

struct ChromeMV3ProductNormalTabManualSmokeReadiness:
    Codable,
    Equatable,
    Sendable
{
    var canAttemptFutureManualSmoke: Bool
    var prerequisiteGates: [String]
    var safeTestURLRequirement: String
    var whatWillExecute: [String]
    var whatRemainsBlocked: [String]
    var teardownVerification: [String]
    var diagnostics: [String]

    static func make(
        preflight: ChromeMV3ProductNormalTabReadinessPreflight,
        plan: ChromeMV3ProductNormalTabReviewedFileInjectionPlan
    ) -> ChromeMV3ProductNormalTabManualSmokeReadiness {
        ChromeMV3ProductNormalTabManualSmokeReadiness(
            canAttemptFutureManualSmoke: preflight.eligible,
            prerequisiteGates: [
                "extensions module enabled",
                "extension enabled in the local experimental extension manager",
                "profile enabled",
                "normalTab WebView surface only",
                "HTTPS fixture URL whose origin is covered by host permission or activeTab",
                "top-frame target",
                "isolated WKContentWorld",
                "reviewed generated-bundle file present with recorded hash",
                "content-script and service-worker route readiness",
                "explicit local experimental product gate",
            ],
            safeTestURLRequirement:
                "Use a synthetic HTTPS login fixture on a non-credential test origin; do not use real accounts, real vault data, network auth, native hosts, file URLs, about:blank, or auxiliary surfaces.",
            whatWillExecute:
                preflight.eligible
                    ? [
                        "Only \(plan.reviewedScriptPath) from the generated bundle hash \(plan.generatedResourceHash ?? "missing-hash") in an isolated world against the top frame.",
                    ]
                    : [],
            whatRemainsBlocked: [
                "Default product runtime",
                "general extension support in normal tabs",
                "arbitrary chrome.scripting.executeScript",
                "MAIN world",
                "multi-frame attachment",
                "file://, about:blank, match_about_blank, and match_origin_as_fallback",
                "auxiliary WebViews and extension-owned UI hosts",
                "network/auth/native host/Web Store/DNR runtime paths",
            ],
            teardownVerification:
                ChromeMV3ProductNormalTabReadinessTeardownTrigger
                .allCases
                .sorted()
                .map { "Verify teardown on \($0.rawValue)." },
            diagnostics:
                preflight.eligible
                    ? [
                        "Manual smoke readiness is allowed only for the explicit local experimental path after every smoke gate passes.",
                    ]
                    : [
                        "Manual smoke readiness is blocked by \(preflight.blockers.map(\.rawValue).joined(separator: ", ")).",
                    ]
        )
    }
}

struct ChromeMV3ProductNormalTabReadinessReport:
    Codable,
    Equatable,
    Sendable
{
    var policy: ChromeMV3ProductNormalTabReadinessPolicy
    var preflight: ChromeMV3ProductNormalTabReadinessPreflight
    var injectionPlan: ChromeMV3ProductNormalTabReviewedFileInjectionPlan
    var lifecycle: ChromeMV3ProductNormalTabReadinessLifetimeReport
    var manualSmokeReadiness: ChromeMV3ProductNormalTabManualSmokeReadiness
    var diagnostics: [String]

    static func make(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        normalTabPreflight: ChromeMV3ProductNormalTabRuntimePreflight,
        candidateURLString: String =
            "https://sumi.local.test/login"
    ) -> ChromeMV3ProductNormalTabReadinessReport {
        let manifestSummary = report?.chromeMV3ProductActiveManifestSummary
        let profileID = lifecycleRecord?.profileID
            ?? normalTabPreflight.profileID
        let extensionID = lifecycleRecord?.extensionID
            ?? normalTabPreflight.extensionID
        let activeVersion = report?.chromeMV3ProductActiveGeneratedVersion
        let reviewedPath =
            ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
            .bitwardenDetectFillBootstrapFile
        let reviewedHash = activeVersion.flatMap {
            generatedResourceSHA256(
                rootPath: $0.generatedBundleRootPath,
                relativePath: reviewedPath
            )
        }
        let reviewedResource =
            ChromeMV3ProductNormalTabReviewedResource.bootstrapAutofill(
                generatedBundleRootPath: activeVersion?.generatedBundleRootPath,
                copiedResourcePaths:
                    activeVersion?.generatedBundleRecord.copiedResourcePaths
                    ?? [],
                hash: reviewedHash
            )
        let broker = ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: extensionID,
                profileID: profileID,
                requiredPermissions: manifestSummary?.permissions ?? [],
                optionalPermissions:
                    manifestSummary?.optionalPermissions ?? [],
                hostPermissions: manifestSummary?.hostPermissions ?? [],
                optionalHostPermissions:
                    manifestSummary?.optionalHostPermissions ?? []
            )
        )
        let serviceWorkerRouteReady =
            manifestSummary?.backgroundServiceWorker == nil
                || normalTabPreflight.canWakeServiceWorkerNow
        let contentScriptRouteReady =
            (manifestSummary?.contentScriptCount ?? 0) == 0
                || normalTabPreflight.canInjectContentScriptsNow
        let preflight =
            ChromeMV3ProductNormalTabReadinessPreflightEvaluator.evaluate(
                input: ChromeMV3ProductNormalTabReadinessPreflightInput(
                    profileID: profileID,
                    extensionID: extensionID,
                    tabID: normalTabPreflight.tabID,
                    documentID: "manual-smoke-candidate-document",
                    urlString: candidateURLString,
                    moduleEnabled: lifecycleRecord != nil,
                    extensionEnabled:
                        lifecycleRecord?.runtimeState
                        .internalRuntimeEnabled == true,
                    profileEnabled:
                        lifecycleRecord.map { record in
                            switch record.lifecycleState {
                            case .uninstalled, .corrupt:
                                return false
                            default:
                                return true
                            }
                        } ?? false,
                    localExperimentalProductGateAllowed:
                        normalTabPreflight.gateSet.debugOverrideGate.state
                        == .allowed,
                    runtimeGateAllowsReadiness:
                        normalTabPreflight.canAttachToNormalTabNow,
                    contentScriptRouteReady: contentScriptRouteReady,
                    serviceWorkerRouteReady: serviceWorkerRouteReady,
                    tabSurface: normalTabPreflight.tabSurface,
                    syntheticHTTPSOrigin: "https://sumi.local.test",
                    frameID: 0,
                    isTopFrame: true,
                    contentWorld: .isolated,
                    hostAccessDecision:
                        broker.hostAccessDecision(
                            url: candidateURLString,
                            tabID: nil
                        ),
                    reviewedResource: reviewedResource,
                    teardownPending: false
                )
            )
        let plan =
            ChromeMV3ProductNormalTabReviewedFileInjectionPlan.make(
                preflight: preflight
            )
        let smoke =
            ChromeMV3ProductNormalTabManualSmokeReadiness.make(
                preflight: preflight,
                plan: plan
            )
        return ChromeMV3ProductNormalTabReadinessReport(
            policy: preflight.policy,
            preflight: preflight,
            injectionPlan: plan,
            lifecycle: .planOnly,
            manualSmokeReadiness: smoke,
            diagnostics:
                uniqueSortedProduct(
                    preflight.diagnostics
                        + plan.diagnostics
                        + smoke.diagnostics
                        + ChromeMV3ProductNormalTabReadinessLifetimeReport
                        .planOnly
                        .diagnostics
                )
        )
    }

    private static func generatedResourceSHA256(
        rootPath: String,
        relativePath: String
    ) -> String? {
        let fileURL = URL(fileURLWithPath: rootPath)
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
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
    var normalTabReadiness:
        ChromeMV3ProductNormalTabReadinessReport
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
        let readiness = ChromeMV3ProductNormalTabReadinessReport.make(
            report: report,
            lifecycleRecord: lifecycleRecord,
            normalTabPreflight: preflight
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
            normalTabReadiness: readiness,
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
