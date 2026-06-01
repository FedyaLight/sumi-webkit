//
//  ChromeMV3ServiceWorkerJSExecutionHarness.swift
//  Sumi
//
//  Explicit local-experimental Chrome MV3 service-worker JavaScript harness.
//  This executes extension-owned generated-bundle classic worker resources in
//  a fresh JavaScriptCore VM with a minimal registration shim. It never
//  attaches a normal tab, creates a hidden page, exposes product runtime, or
//  schedules background work.
//

import CryptoKit
import Foundation
#if canImport(Security)
    import Security
#endif
#if canImport(JavaScriptCore)
    import JavaScriptCore
#endif

enum ChromeMV3ServiceWorkerJSExecutionSurface:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case none
    case javaScriptCore = "JavaScriptCore"
    case isolatedWKWebView = "isolated WKWebView"
    case existingHarnessSurface = "existing harness surface"
    case blocked

    static func < (
        lhs: ChromeMV3ServiceWorkerJSExecutionSurface,
        rhs: ChromeMV3ServiceWorkerJSExecutionSurface
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSExecutionPolicyBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case extensionDisabled
    case generatedBundleRecordMissing
    case javaScriptCoreUnavailable
    case localExperimentalGateRequired
    case moduleDisabled

    static func < (
        lhs: ChromeMV3ServiceWorkerJSExecutionPolicyBlocker,
        rhs: ChromeMV3ServiceWorkerJSExecutionPolicyBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSImportScriptsScope:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case generatedBundleOnly

    static func < (
        lhs: ChromeMV3ServiceWorkerJSImportScriptsScope,
        rhs: ChromeMV3ServiceWorkerJSImportScriptsScope
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSDynamicImportScope:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case generatedBundleOnly

    static func < (
        lhs: ChromeMV3ServiceWorkerJSDynamicImportScope,
        rhs: ChromeMV3ServiceWorkerJSDynamicImportScope
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case dynamicImportExecutionSurfaceUnsupported
    case dynamicImportGeneratedRootContainmentUnproven
    case dynamicImportLowerLevelAPINotAvailable
    case dynamicImportModuleNamespaceUnsupported
    case dynamicImportNoLoader
    case dynamicImportParseUnsupported
    case dynamicImportPromiseDrainUnavailable
    case dynamicImportResolverHookUnavailable
    case javaScriptCoreUnavailable

    static func < (
        lhs: ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker,
        rhs: ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSModuleWorkerReadinessBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case deterministicPromiseDrainUnavailable
    case generatedRootContainedModuleGraphUnproven
    case moduleNamespaceAccessUnavailable
    case moduleResolutionHookUnavailable
    case sourceTextModuleLoaderUnavailable
    case topLevelAwaitContainmentUnproven

    static func < (
        lhs: ChromeMV3ServiceWorkerJSModuleWorkerReadinessBlocker,
        rhs: ChromeMV3ServiceWorkerJSModuleWorkerReadinessBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSModuleWorkerReadinessProbe:
    Codable,
    Equatable,
    Sendable
{
    var probeExecuted: Bool
    var staticImportGraphInspectionAvailable: Bool
    var sourceTextModuleLoaderAvailable: Bool
    var moduleResolutionHookAvailable: Bool
    var generatedRootContainedModuleGraphProven: Bool
    var moduleNamespaceAccessAvailable: Bool
    var topLevelAwaitContainmentProven: Bool
    var deterministicPromiseDrainAvailable: Bool
    var moduleWorkerExecutionAvailableInLocalExperimentalGate: Bool
    var moduleWorkerExecutionAvailableByDefault: Bool
    var blockers: [ChromeMV3ServiceWorkerJSModuleWorkerReadinessBlocker]
    var diagnostics: [String]

    static func evaluate(
        moduleState: ChromeMV3ProfileHostModuleState,
        extensionEnabled: Bool
    ) -> ChromeMV3ServiceWorkerJSModuleWorkerReadinessProbe {
        guard moduleState == .enabled, extensionEnabled else {
            return ChromeMV3ServiceWorkerJSModuleWorkerReadinessProbe(
                probeExecuted: false,
                staticImportGraphInspectionAvailable: false,
                sourceTextModuleLoaderAvailable: false,
                moduleResolutionHookAvailable: false,
                generatedRootContainedModuleGraphProven: false,
                moduleNamespaceAccessAvailable: false,
                topLevelAwaitContainmentProven: false,
                deterministicPromiseDrainAvailable: false,
                moduleWorkerExecutionAvailableInLocalExperimentalGate: false,
                moduleWorkerExecutionAvailableByDefault: false,
                blockers: [],
                diagnostics: [
                    moduleState != .enabled
                        ? "Module-disabled state skipped module-worker readiness probing."
                        : "Extension-disabled state skipped module-worker readiness probing.",
                ]
            )
        }
        let blockers:
            [ChromeMV3ServiceWorkerJSModuleWorkerReadinessBlocker] = [
                .sourceTextModuleLoaderUnavailable,
                .moduleResolutionHookUnavailable,
                .generatedRootContainedModuleGraphUnproven,
                .moduleNamespaceAccessUnavailable,
                .topLevelAwaitContainmentUnproven,
                .deterministicPromiseDrainUnavailable,
            ]
        return ChromeMV3ServiceWorkerJSModuleWorkerReadinessProbe(
            probeExecuted: true,
            staticImportGraphInspectionAvailable: true,
            sourceTextModuleLoaderAvailable: false,
            moduleResolutionHookAvailable: false,
            generatedRootContainedModuleGraphProven: false,
            moduleNamespaceAccessAvailable: false,
            topLevelAwaitContainmentProven: false,
            deterministicPromiseDrainAvailable: false,
            moduleWorkerExecutionAvailableInLocalExperimentalGate: false,
            moduleWorkerExecutionAvailableByDefault: false,
            blockers: blockers,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    [
                        "Static module import/export, top-level await, and dynamic import tokens can be inventoried without executing a module worker.",
                        "The public JavaScriptCore JSContext and C API headers do not expose a source-text module loader, module-resolution hook, module namespace accessor, or deterministic Promise job-drain API.",
                        "Module-worker execution remains blocked until generated-root containment and lifecycle teardown can be proven through a public execution surface.",
                    ]
                        + blockers.map {
                            "Module-worker readiness blocker: \($0.rawValue)."
                        }
                )
        )
    }
}

struct ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe:
    Codable,
    Equatable,
    Sendable
{
    var probeExecuted: Bool
    var importExpressionParses: Bool
    var lowerLevelPublicModuleAPIAvailable: Bool
    var sourceTextModuleLoadSupported: Bool
    var moduleLoadingCanBeIntercepted: Bool
    var resolverHookAvailable: Bool
    var dynamicImportCallbackAvailable: Bool
    var generatedRootContainmentProven: Bool
    var promiseCompletionObservableWithoutScheduling: Bool
    var deterministicPromiseDrainAvailable: Bool
    var moduleNamespaceSupported: Bool
    var sourceURLMetadataControlAvailable: Bool
    var safeCancellationAvailable: Bool
    var teardownWithoutPersistentRuntimeAvailable: Bool
    var executionSurfaceSupported: Bool
    var dynamicImportAvailableInLocalExperimentalGate: Bool
    var dynamicImportAvailableByDefault: Bool
    var dynamicImportScope: ChromeMV3ServiceWorkerJSDynamicImportScope
    var blockers: [ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker]
    var diagnostics: [String]

    static func evaluate()
        -> ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
    {
        #if canImport(JavaScriptCore)
            guard let context = JSContext() else {
                return blocked(
                    probeExecuted: true,
                    importExpressionParses: false,
                    lowerLevelPublicModuleAPIAvailable: false,
                    sourceTextModuleLoadSupported: false,
                    moduleLoadingCanBeIntercepted: false,
                    resolverHookAvailable: false,
                    dynamicImportCallbackAvailable: false,
                    generatedRootContainmentProven: false,
                    promiseCompletionObservableWithoutScheduling: false,
                    deterministicPromiseDrainAvailable: false,
                    moduleNamespaceSupported: false,
                    sourceURLMetadataControlAvailable: false,
                    safeCancellationAvailable: false,
                    teardownWithoutPersistentRuntimeAvailable: false,
                    executionSurfaceSupported: false,
                    blockers: [.javaScriptCoreUnavailable],
                    diagnostics: [
                        "JavaScriptCore context construction failed during dynamic import capability probing.",
                    ]
                )
            }
            if #available(macOS 13.3, *) {
                context.isInspectable = false
            }
            let sourceURL = URL(
                fileURLWithPath:
                    "/sumi-local-experimental/dynamic-import-probe/background.js"
            )
            context.exception = nil
            let parseValue = context.evaluateScript(
                "(() => import('./dependency.js')); 'dynamicImportParsed';",
                withSourceURL: sourceURL
            )
            let importExpressionParses =
                context.exception == nil
                && parseValue?.toString() == "dynamicImportParsed"

            context.exception = nil
            _ = context.evaluateScript(
                """
                globalThis.__sumiPromiseProbe = 'pending';
                Promise.resolve('drained').then((value) => {
                  globalThis.__sumiPromiseProbe = value;
                });
                'scheduled';
                """,
                withSourceURL: sourceURL
            )
            let promiseCompletionObservable =
                context.exception == nil
                && context.objectForKeyedSubscript("__sumiPromiseProbe")?
                    .toString() == "drained"

            context.exception = nil
            _ = context.evaluateScript(
                """
                globalThis.__sumiDynamicImportProbe = {
                  state: 'pending',
                  message: null,
                  namespaceType: null
                };
                import('./dependency.js').then(
                  (namespace) => {
                    globalThis.__sumiDynamicImportProbe = {
                      state: 'resolved',
                      message: null,
                      namespaceType: typeof namespace
                    };
                  },
                  (error) => {
                    globalThis.__sumiDynamicImportProbe = {
                      state: 'rejected',
                      message: String(error && error.message ? error.message : error),
                      namespaceType: null
                    };
                  }
                );
                'scheduled';
                """,
                withSourceURL: sourceURL
            )
            let dynamicImportProbe = context
                .objectForKeyedSubscript("__sumiDynamicImportProbe")
            let importState = dynamicImportProbe?
                .objectForKeyedSubscript("state")?.toString()
            let importMessage = dynamicImportProbe?
                .objectForKeyedSubscript("message")?.toString()
            let namespaceType = dynamicImportProbe?
                .objectForKeyedSubscript("namespaceType")?.toString()

            let moduleNamespaceSupported =
                importState == "resolved" && namespaceType == "object"
            let lowerLevelPublicModuleAPIAvailable = false
            let sourceTextModuleLoadSupported = false
            let resolverHookAvailable = false
            let dynamicImportCallbackAvailable = false
            let generatedRootContainmentProven = false
            let deterministicPromiseDrainAvailable = false
            let sourceURLMetadataControlAvailable = true
            let safeCancellationAvailable = false
            let teardownWithoutPersistentRuntimeAvailable = true
            let moduleLoadingCanBeIntercepted = false
            var blockers:
                [ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker] = []
            if importExpressionParses == false {
                blockers.append(.dynamicImportParseUnsupported)
            }
            if lowerLevelPublicModuleAPIAvailable == false {
                blockers.append(.dynamicImportLowerLevelAPINotAvailable)
            }
            if resolverHookAvailable == false
                || dynamicImportCallbackAvailable == false
            {
                blockers.append(.dynamicImportResolverHookUnavailable)
            }
            if generatedRootContainmentProven == false {
                blockers.append(.dynamicImportGeneratedRootContainmentUnproven)
            }
            if deterministicPromiseDrainAvailable == false {
                blockers.append(.dynamicImportPromiseDrainUnavailable)
            }
            if importExpressionParses,
               moduleLoadingCanBeIntercepted == false
            {
                blockers.append(.dynamicImportNoLoader)
            }
            if moduleNamespaceSupported == false {
                blockers.append(.dynamicImportModuleNamespaceUnsupported)
            }
            let executionSurfaceSupported =
                importExpressionParses
                && lowerLevelPublicModuleAPIAvailable
                && sourceTextModuleLoadSupported
                && moduleLoadingCanBeIntercepted
                && resolverHookAvailable
                && dynamicImportCallbackAvailable
                && generatedRootContainmentProven
                && deterministicPromiseDrainAvailable
                && moduleNamespaceSupported
                && safeCancellationAvailable
                && teardownWithoutPersistentRuntimeAvailable
            if executionSurfaceSupported == false {
                blockers.append(.dynamicImportExecutionSurfaceUnsupported)
            }
            blockers = uniqueSortedServiceWorkerJS(blockers)
            let available = blockers.isEmpty
            var diagnostics = [
                importExpressionParses
                    ? "JavaScriptCore parses dynamic import expressions in the JSContext script surface."
                    : "JavaScriptCore did not parse dynamic import expressions in the JSContext script surface.",
                promiseCompletionObservable
                    ? "Promise microtask completion is observable immediately after evaluateScript without timers."
                    : "Promise completion could not be observed deterministically without timers.",
                "The public JavaScriptCore JSContext and C API headers expose script evaluation, script syntax checking, source URL metadata, context/VM lifecycle, and Promise construction helpers.",
                "The public JavaScriptCore headers do not expose a source-text module loader, module resolution hook, dynamic import callback, module namespace access API, or deterministic Promise job-drain API.",
                "The local JavaScriptCore binary exports unheadered JSScript and C++ module/import symbols, but they are not a public SDK surface and are ignored by this harness.",
                "Dynamic import module loading cannot be constrained to Sumi's generated bundle root through public JavaScriptCore API.",
            ]
            if let importState {
                diagnostics.append("Dynamic import probe state: \(importState).")
            }
            if let importMessage, importMessage != "null" {
                diagnostics.append(
                    "Dynamic import probe message: \(importMessage)."
                )
            }
            return ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe(
                probeExecuted: true,
                importExpressionParses: importExpressionParses,
                lowerLevelPublicModuleAPIAvailable:
                    lowerLevelPublicModuleAPIAvailable,
                sourceTextModuleLoadSupported:
                    sourceTextModuleLoadSupported,
                moduleLoadingCanBeIntercepted: moduleLoadingCanBeIntercepted,
                resolverHookAvailable: resolverHookAvailable,
                dynamicImportCallbackAvailable: dynamicImportCallbackAvailable,
                generatedRootContainmentProven:
                    generatedRootContainmentProven,
                promiseCompletionObservableWithoutScheduling:
                    promiseCompletionObservable,
                deterministicPromiseDrainAvailable:
                    deterministicPromiseDrainAvailable,
                moduleNamespaceSupported: moduleNamespaceSupported,
                sourceURLMetadataControlAvailable:
                    sourceURLMetadataControlAvailable,
                safeCancellationAvailable: safeCancellationAvailable,
                teardownWithoutPersistentRuntimeAvailable:
                    teardownWithoutPersistentRuntimeAvailable,
                executionSurfaceSupported: executionSurfaceSupported,
                dynamicImportAvailableInLocalExperimentalGate: available,
                dynamicImportAvailableByDefault: false,
                dynamicImportScope:
                    available ? .generatedBundleOnly : .blocked,
                blockers: blockers,
                diagnostics:
                    uniqueSortedServiceWorkerJS(
                        diagnostics
                            + blockers.map {
                                "Dynamic import capability blocker: \($0.rawValue)."
                            }
                    )
            )
        #else
            return blocked(
                probeExecuted: true,
                importExpressionParses: false,
                lowerLevelPublicModuleAPIAvailable: false,
                sourceTextModuleLoadSupported: false,
                moduleLoadingCanBeIntercepted: false,
                resolverHookAvailable: false,
                dynamicImportCallbackAvailable: false,
                generatedRootContainmentProven: false,
                promiseCompletionObservableWithoutScheduling: false,
                deterministicPromiseDrainAvailable: false,
                moduleNamespaceSupported: false,
                sourceURLMetadataControlAvailable: false,
                safeCancellationAvailable: false,
                teardownWithoutPersistentRuntimeAvailable: false,
                executionSurfaceSupported: false,
                blockers: [.javaScriptCoreUnavailable],
                diagnostics: [
                    "JavaScriptCore is unavailable, so dynamic import capability probing cannot run.",
                ]
            )
        #endif
    }

    static func skippedByPolicy(
        diagnostics: [String]
    ) -> ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe {
        blocked(
            probeExecuted: false,
            importExpressionParses: false,
            lowerLevelPublicModuleAPIAvailable: false,
            sourceTextModuleLoadSupported: false,
            moduleLoadingCanBeIntercepted: false,
            resolverHookAvailable: false,
            dynamicImportCallbackAvailable: false,
            generatedRootContainmentProven: false,
            promiseCompletionObservableWithoutScheduling: false,
            deterministicPromiseDrainAvailable: false,
            moduleNamespaceSupported: false,
            sourceURLMetadataControlAvailable: false,
            safeCancellationAvailable: false,
            teardownWithoutPersistentRuntimeAvailable: false,
            executionSurfaceSupported: false,
            blockers: [.dynamicImportExecutionSurfaceUnsupported],
            diagnostics:
                [
                    "Dynamic import capability probe was skipped because policy blocked JavaScript execution before resource loading.",
                ]
                    + diagnostics
        )
    }

    private static func blocked(
        probeExecuted: Bool,
        importExpressionParses: Bool,
        lowerLevelPublicModuleAPIAvailable: Bool,
        sourceTextModuleLoadSupported: Bool,
        moduleLoadingCanBeIntercepted: Bool,
        resolverHookAvailable: Bool,
        dynamicImportCallbackAvailable: Bool,
        generatedRootContainmentProven: Bool,
        promiseCompletionObservableWithoutScheduling: Bool,
        deterministicPromiseDrainAvailable: Bool,
        moduleNamespaceSupported: Bool,
        sourceURLMetadataControlAvailable: Bool,
        safeCancellationAvailable: Bool,
        teardownWithoutPersistentRuntimeAvailable: Bool,
        executionSurfaceSupported: Bool,
        blockers: [ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker],
        diagnostics: [String]
    ) -> ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe {
        let uniqueBlockers = uniqueSortedServiceWorkerJS(blockers)
        return ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe(
            probeExecuted: probeExecuted,
            importExpressionParses: importExpressionParses,
            lowerLevelPublicModuleAPIAvailable:
                lowerLevelPublicModuleAPIAvailable,
            sourceTextModuleLoadSupported: sourceTextModuleLoadSupported,
            moduleLoadingCanBeIntercepted: moduleLoadingCanBeIntercepted,
            resolverHookAvailable: resolverHookAvailable,
            dynamicImportCallbackAvailable: dynamicImportCallbackAvailable,
            generatedRootContainmentProven: generatedRootContainmentProven,
            promiseCompletionObservableWithoutScheduling:
                promiseCompletionObservableWithoutScheduling,
            deterministicPromiseDrainAvailable:
                deterministicPromiseDrainAvailable,
            moduleNamespaceSupported: moduleNamespaceSupported,
            sourceURLMetadataControlAvailable:
                sourceURLMetadataControlAvailable,
            safeCancellationAvailable: safeCancellationAvailable,
            teardownWithoutPersistentRuntimeAvailable:
                teardownWithoutPersistentRuntimeAvailable,
            executionSurfaceSupported: executionSurfaceSupported,
            dynamicImportAvailableInLocalExperimentalGate: false,
            dynamicImportAvailableByDefault: false,
            dynamicImportScope: .blocked,
            blockers: uniqueBlockers,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    diagnostics
                        + uniqueBlockers.map {
                            "Dynamic import capability blocker: \($0.rawValue)."
                        }
                )
        )
    }
}

private struct ChromeMV3ServiceWorkerJSUILanguageSelection: Equatable {
    var language: String
    var source: String
    var diagnostics: [String]

    static func select(
        override: String?
    ) -> ChromeMV3ServiceWorkerJSUILanguageSelection {
        if let override = normalizedUILanguageServiceWorkerJS(override) {
            return ChromeMV3ServiceWorkerJSUILanguageSelection(
                language: override,
                source: "testOverride",
                diagnostics: [
                    "chrome.i18n.getUILanguage uses the explicit test override for deterministic local experimental execution.",
                ]
            )
        }

        if let appLanguage = Bundle.main.preferredLocalizations.first,
           let normalized = normalizedUILanguageServiceWorkerJS(appLanguage),
           normalized.lowercased() != "base"
        {
            return ChromeMV3ServiceWorkerJSUILanguageSelection(
                language: normalized,
                source: "bundlePreferredLocalization",
                diagnostics: [
                    "chrome.i18n.getUILanguage selected Bundle.main.preferredLocalizations as the closest app UI language signal.",
                ]
            )
        }

        if let preferred = Locale.preferredLanguages.first,
           let normalized = normalizedUILanguageServiceWorkerJS(preferred)
        {
            return ChromeMV3ServiceWorkerJSUILanguageSelection(
                language: normalized,
                source: "localePreferredLanguages",
                diagnostics: [
                    "chrome.i18n.getUILanguage fell back to Locale.preferredLanguages because no app UI localization was available.",
                ]
            )
        }

        if let normalized = normalizedUILanguageServiceWorkerJS(
            Locale.current.identifier
        ) {
            return ChromeMV3ServiceWorkerJSUILanguageSelection(
                language: normalized,
                source: "localeCurrentIdentifier",
                diagnostics: [
                    "chrome.i18n.getUILanguage fell back to Locale.current.identifier.",
                ]
            )
        }

        return ChromeMV3ServiceWorkerJSUILanguageSelection(
            language: "en-US",
            source: "deterministicFallback",
            diagnostics: [
                "chrome.i18n.getUILanguage fell back to en-US after locale signals were unavailable or invalid.",
            ]
        )
    }
}

struct ChromeMV3ServiceWorkerJSExecutionPolicy:
    Codable,
    Equatable,
    Sendable
{
    var serviceWorkerJSExecutionAvailableInLocalExperimentalGate: Bool
    var serviceWorkerJSExecutionAvailableByDefault: Bool
    var executionSurface: ChromeMV3ServiceWorkerJSExecutionSurface
    var supportsClassicWorker: Bool
    var supportsModuleWorker: Bool
    var listenerCaptureAvailable: Bool
    var importScriptsAvailableInLocalExperimentalGate: Bool
    var importScriptsAvailableByDefault: Bool
    var importScriptsScope: ChromeMV3ServiceWorkerJSImportScriptsScope
    var networkImportsAllowed: Bool
    var filesystemAbsoluteImportsAllowed: Bool
    var symlinkEscapeAllowed: Bool
    var dynamicImportAvailableInLocalExperimentalGate: Bool
    var dynamicImportAvailableByDefault: Bool
    var dynamicImportScope: ChromeMV3ServiceWorkerJSDynamicImportScope
    var dynamicImportGeneratedBundleOnly: Bool
    var dynamicImportStringLiteralLocalOnly: Bool
    var dynamicImportAvailable: Bool
    var dynamicImportRewriteExperimentAvailableInLocalExperimentalGate: Bool
    var dynamicImportRewriteExperimentAvailableByDefault: Bool
    var dynamicImportRewriteExperimentScope:
        ChromeMV3ServiceWorkerJSDynamicImportScope
    var dynamicImportRewriteExperimentAllowed: Bool
    var dynamicImportRewriteExperimentMutatesGeneratedBundle: Bool
    var dynamicImportCapabilityProbe:
        ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
    var dynamicImportCapabilityBlockers:
        [ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker]
    var moduleWorkerReadinessProbe:
        ChromeMV3ServiceWorkerJSModuleWorkerReadinessProbe
    var moduleWorkerImportAvailable: Bool
    var permanentBackgroundAvailable: Bool
    var runtimeLastErrorAvailableInLocalExperimentalGate: Bool
    var runtimeLastErrorAvailableByDefault: Bool
    var runtimeLastErrorCallbackScoped: Bool
    var timersAvailableInLocalExperimentalGate: Bool
    var timersAvailableByDefault: Bool
    var wallClockTimersAllowed: Bool
    var timersAllowed: Bool
    var pollingAllowed: Bool
    var webCryptoAvailableInLocalExperimentalGate: Bool
    var webCryptoAvailableByDefault: Bool
    var cryptoGetRandomValuesAvailable: Bool
    var cryptoRandomUUIDAvailable: Bool
    var subtleCryptoAvailableInLocalExperimentalGate: Bool
    var subtleCryptoAvailableByDefault: Bool
    var subtleCryptoSupportedMethods: [String]
    var subtleCryptoBlockedMethods: [String]
    var subtleCryptoSupportedAlgorithms: [String]
    var subtleCryptoBlockedAlgorithms: [String]
    var i18nGetUILanguageAvailableInLocalExperimentalGate: Bool
    var i18nGetUILanguageAvailableByDefault: Bool
    var i18nSelectedUILanguage: String
    var i18nSelectedUILanguageSource: String
    var i18nUnsupportedAPIs: [String]
    var workerGlobalEventTargetAvailableInLocalExperimentalGate: Bool
    var workerGlobalEventTargetAvailableByDefault: Bool
    var workerGlobalEventTargetSupportedTypes: [String]
    var workerGlobalWindowDocumentExposed: Bool
    var fetchClassificationAvailableInLocalExperimentalGate: Bool
    var fetchAvailableInLocalExperimentalGate: Bool
    var fetchAvailableByDefault: Bool
    var networkFetchAllowed: Bool
    var extensionLocalFetchAllowed: Bool
    var generatedBundleOnly: Bool
    var credentialsAllowed: Bool
    var cacheAllowed: Bool
    var fetchNetworkExecutionAllowed: Bool
    var fetchExtensionLocalExecutionAllowed: Bool
    var fetchBlockers: [String]
    var blockers: [ChromeMV3ServiceWorkerJSExecutionPolicyBlocker]
    var diagnostics: [String]

    static func evaluate(
        moduleState: ChromeMV3ProfileHostModuleState,
        extensionEnabled: Bool,
        localExperimentalGateAllowed: Bool,
        generatedBundleRecordAvailable: Bool,
        dynamicImportRewriteExperimentAllowed: Bool = false,
        uiLanguageOverride: String? = nil
    ) -> ChromeMV3ServiceWorkerJSExecutionPolicy {
        var blockers: [ChromeMV3ServiceWorkerJSExecutionPolicyBlocker] = []
        if moduleState != .enabled {
            blockers.append(.moduleDisabled)
        }
        if extensionEnabled == false {
            blockers.append(.extensionDisabled)
        }
        if localExperimentalGateAllowed == false {
            blockers.append(.localExperimentalGateRequired)
        }
        if generatedBundleRecordAvailable == false {
            blockers.append(.generatedBundleRecordMissing)
        }
        #if canImport(JavaScriptCore)
            let javaScriptCoreAvailable = true
        #else
            let javaScriptCoreAvailable = false
            blockers.append(.javaScriptCoreUnavailable)
        #endif
        let dynamicImportCapability:
            ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
        if moduleState != .enabled || extensionEnabled == false {
            dynamicImportCapability =
                ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
                    .skippedByPolicy(
                        diagnostics: [
                            moduleState != .enabled
                                ? "Module-disabled state skipped JavaScriptCore dynamic import probing."
                                : "Extension-disabled state skipped JavaScriptCore dynamic import probing.",
                        ]
                    )
        } else {
            dynamicImportCapability =
                ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
                    .evaluate()
        }
        blockers = uniqueSortedServiceWorkerJS(blockers)
        let available = blockers.isEmpty && javaScriptCoreAvailable
        let dynamicImportAvailable =
            available
            && dynamicImportCapability
                .dynamicImportAvailableInLocalExperimentalGate
        let dynamicImportRewriteAvailable =
            available
            && dynamicImportRewriteExperimentAllowed
        let moduleWorkerReadiness =
            ChromeMV3ServiceWorkerJSModuleWorkerReadinessProbe.evaluate(
                moduleState: moduleState,
                extensionEnabled: extensionEnabled
            )
        let webCryptoAvailable = available
        let supportedSubtleMethods = webCryptoAvailable ? ["digest"] : []
        let blockedSubtleMethods =
            webCryptoAvailable
            ? [
                "decrypt",
                "deriveBits",
                "deriveKey",
                "encrypt",
                "exportKey",
                "generateKey",
                "importKey",
                "sign",
                "unwrapKey",
                "verify",
                "wrapKey",
            ] : []
        let supportedSubtleAlgorithms =
            webCryptoAvailable
            ? [
                "digest:SHA-1",
                "digest:SHA-256",
                "digest:SHA-384",
                "digest:SHA-512",
            ] : []
        let blockedSubtleAlgorithms =
            webCryptoAvailable
            ? [
                "AES-CBC",
                "AES-CTR",
                "AES-GCM",
                "ECDH",
                "ECDSA",
                "HKDF",
                "HMAC",
                "PBKDF2",
                "RSA-OAEP",
                "RSASSA-PKCS1-v1_5",
            ] : []
        let uiLanguage = ChromeMV3ServiceWorkerJSUILanguageSelection.select(
            override: uiLanguageOverride
        )
        let workerGlobalEventTypes =
            available
                ? [
                    "activate",
                    "error",
                    "fetch",
                    "install",
                    "message",
                    "unhandledrejection",
                ] : []
        let i18nUnsupportedAPIs =
            available
                ? [
                    "chrome.i18n.detectLanguage",
                    "chrome.i18n.getAcceptLanguages",
                    "chrome.i18n.getMessage",
                ] : []
        let surface: ChromeMV3ServiceWorkerJSExecutionSurface
        if moduleState != .enabled || extensionEnabled == false {
            surface = .none
        } else if available {
            surface = .javaScriptCore
        } else {
            surface = .blocked
        }
        return ChromeMV3ServiceWorkerJSExecutionPolicy(
            serviceWorkerJSExecutionAvailableInLocalExperimentalGate:
                available,
            serviceWorkerJSExecutionAvailableByDefault: false,
            executionSurface: surface,
            supportsClassicWorker: javaScriptCoreAvailable,
            supportsModuleWorker: false,
            listenerCaptureAvailable: available,
            importScriptsAvailableInLocalExperimentalGate: available,
            importScriptsAvailableByDefault: false,
            importScriptsScope: available ? .generatedBundleOnly : .blocked,
            networkImportsAllowed: false,
            filesystemAbsoluteImportsAllowed: false,
            symlinkEscapeAllowed: false,
            dynamicImportAvailableInLocalExperimentalGate:
                dynamicImportAvailable,
            dynamicImportAvailableByDefault: false,
            dynamicImportScope:
                dynamicImportAvailable ? .generatedBundleOnly : .blocked,
            dynamicImportGeneratedBundleOnly: true,
            dynamicImportStringLiteralLocalOnly: true,
            dynamicImportAvailable: dynamicImportAvailable,
            dynamicImportRewriteExperimentAvailableInLocalExperimentalGate:
                dynamicImportRewriteAvailable,
            dynamicImportRewriteExperimentAvailableByDefault: false,
            dynamicImportRewriteExperimentScope:
                dynamicImportRewriteAvailable ? .generatedBundleOnly : .blocked,
            dynamicImportRewriteExperimentAllowed:
                dynamicImportRewriteExperimentAllowed,
            dynamicImportRewriteExperimentMutatesGeneratedBundle: false,
            dynamicImportCapabilityProbe: dynamicImportCapability,
            dynamicImportCapabilityBlockers: dynamicImportCapability.blockers,
            moduleWorkerReadinessProbe: moduleWorkerReadiness,
            moduleWorkerImportAvailable: false,
            permanentBackgroundAvailable: false,
            runtimeLastErrorAvailableInLocalExperimentalGate: available,
            runtimeLastErrorAvailableByDefault: false,
            runtimeLastErrorCallbackScoped: available,
            timersAvailableInLocalExperimentalGate: available,
            timersAvailableByDefault: false,
            wallClockTimersAllowed: false,
            timersAllowed: available,
            pollingAllowed: false,
            webCryptoAvailableInLocalExperimentalGate: webCryptoAvailable,
            webCryptoAvailableByDefault: false,
            cryptoGetRandomValuesAvailable: webCryptoAvailable,
            cryptoRandomUUIDAvailable: webCryptoAvailable,
            subtleCryptoAvailableInLocalExperimentalGate: webCryptoAvailable,
            subtleCryptoAvailableByDefault: false,
            subtleCryptoSupportedMethods: supportedSubtleMethods,
            subtleCryptoBlockedMethods: blockedSubtleMethods,
            subtleCryptoSupportedAlgorithms: supportedSubtleAlgorithms,
            subtleCryptoBlockedAlgorithms: blockedSubtleAlgorithms,
            i18nGetUILanguageAvailableInLocalExperimentalGate: available,
            i18nGetUILanguageAvailableByDefault: false,
            i18nSelectedUILanguage: uiLanguage.language,
            i18nSelectedUILanguageSource: uiLanguage.source,
            i18nUnsupportedAPIs: i18nUnsupportedAPIs,
            workerGlobalEventTargetAvailableInLocalExperimentalGate:
                available,
            workerGlobalEventTargetAvailableByDefault: false,
            workerGlobalEventTargetSupportedTypes: workerGlobalEventTypes,
            workerGlobalWindowDocumentExposed: false,
            fetchClassificationAvailableInLocalExperimentalGate: available,
            fetchAvailableInLocalExperimentalGate: available,
            fetchAvailableByDefault: false,
            networkFetchAllowed: false,
            extensionLocalFetchAllowed: available,
            generatedBundleOnly: true,
            credentialsAllowed: false,
            cacheAllowed: false,
            fetchNetworkExecutionAllowed: false,
            fetchExtensionLocalExecutionAllowed: available,
            fetchBlockers: available ? [] : blockers.map(\.rawValue),
            blockers: blockers,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    [
                        "JavaScript execution is explicit local-experimental fixture state only.",
                        "The selected JavaScriptCore surface has no normal-tab attachment, hidden page, network bridge, credential bridge, or native-host launch bridge.",
                        "Classic worker execution is supported; module worker execution is precisely blocked until a verified module loader exists.",
                        "Classic importScripts is available only while the local experimental gate is open and only for generated-bundle-contained extension resources.",
                        "Dynamic import policy is local-experimental only, default-off, string-literal-only if ever enabled, and constrained to generated-bundle-contained extension resources.",
                        "Dynamic import rewrite experiment is an explicit harness-only transform, default-off, generated-bundle-only, string-literal-only, and never mutates generated bundle artifacts.",
                        "Network imports, file/data/blob URL imports, absolute filesystem imports, symlink escapes, and module worker import remain blocked.",
                        "setTimeout, clearTimeout, setInterval, and clearInterval are available only as an explicit manually drained harness queue; no wall-clock timer or polling loop is created.",
                        "WebCrypto is exposed only inside the local experimental MV3 gate; getRandomValues and randomUUID require Security.framework secure random bytes.",
                        "SubtleCrypto is local-experimental and default-off; this slice supports digest only and rejects key, signing, derivation, encryption, wrapping, and unsupported algorithm calls precisely.",
                        "chrome.i18n.getUILanguage is available only in the local experimental gate and returns a deterministic UI language string; message catalogs and language detection remain unsupported.",
                        "Worker-global addEventListener/removeEventListener/dispatchEvent are modeled as a non-DOM EventTarget surface without window or document.",
                        "fetch is local-experimental and default-off; remote/network fetch remains blocked, while generated-bundle-contained extension-local resources can return a minimal modeled Response after containment checks.",
                        "chrome.runtime.lastError is local-experimental and default-off; failing callback paths expose a callback-scoped object with a string message and clear it after callback return.",
                        "Chrome documents the generic callback-scoped runtime.lastError contract, but individual API references do not exhaustively specify every unsupported-method failure shape; this harness sets lastError only when an existing failing callback path or unsupported call with a final callback is observed.",
                        "Lifetime transitions are explicit fixture calls only.",
                        "Stable product runtime remains default-off.",
                    ]
                        + blockers.map { "Policy blocker: \($0.rawValue)." }
                        + uiLanguage.diagnostics
                        + dynamicImportCapability.diagnostics
                        + moduleWorkerReadiness.diagnostics
                )
        )
    }
}

struct ChromeMV3ServiceWorkerJSExecutionDocumentationSource:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    var id: String { url }
    var title: String
    var url: String
    var finding: String

    static let checkedSources: [ChromeMV3ServiceWorkerJSExecutionDocumentationSource] = [
        source(
            "Chrome extension service-worker basics",
            "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/basics",
            "background.service_worker declares one packaged JavaScript file; module workers require background.type=module; classic workers may use importScripts; dynamic import is unsupported."
        ),
        source(
            "Chrome extension service-worker lifecycle",
            "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
            "Workers are event driven and finite-lived; Chrome documents idle shutdown and hard request limits rather than permanent background execution."
        ),
        source(
            "Chrome events in service workers",
            "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/events",
            "Extension event listeners should be registered synchronously at script top level so incoming events can be dispatched after worker start."
        ),
        source(
            "Chrome message passing",
            "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
            "runtime.onMessage supports sendResponse and asynchronous response modes; this harness models synchronous completion and reports deferred modes precisely."
        ),
        source(
            "Chrome runtime API",
            "https://developer.chrome.com/docs/extensions/reference/api/runtime",
            "runtime.lastError is an object defined only within a failing API callback, its optional message is a string, Promise-returning APIs do not set it, and Port disconnect callbacks may expose it after an error."
        ),
        source(
            "MDN Symbol.toPrimitive",
            "https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Symbol/toPrimitive",
            "JavaScript coercion checks Symbol.toPrimitive on objects before valueOf/toString fallback; runtime.lastError.message is modeled as a primitive string so String(), templates, concatenation, and Symbol.toPrimitive property access stay ordinary."
        ),
        source(
            "Chrome storage API",
            "https://developer.chrome.com/docs/extensions/reference/api/storage",
            "storage.onChanged dispatch shape was checked; documented callback quota failures set runtime.lastError while Promise failures reject."
        ),
        source(
            "Chrome permissions API",
            "https://developer.chrome.com/docs/extensions/reference/api/permissions",
            "permissions.onAdded and permissions.onRemoved dispatch shapes were checked."
        ),
        source(
            "Chrome alarms API",
            "https://developer.chrome.com/docs/extensions/reference/api/alarms",
            "alarms.onAlarm dispatch shape was checked."
        ),
        source(
            "Chrome contextMenus API",
            "https://developer.chrome.com/docs/extensions/reference/api/contextMenus",
            "contextMenus.onClicked dispatch shape was checked."
        ),
        source(
            "Chrome webNavigation API",
            "https://developer.chrome.com/docs/extensions/reference/api/webNavigation",
            "Selected synthetic webNavigation event dispatch shapes were checked."
        ),
        source(
            "Chrome native messaging",
            "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
            "Native Port lifecycle was checked; arbitrary host discovery and launch remain outside this harness."
        ),
        source(
            "WHATWG HTML WorkerGlobalScope importScripts",
            "https://html.spec.whatwg.org/multipage/workers.html#importing-scripts-and-libraries",
            "importScripts processes each supplied URL synchronously in argument order, fetches a classic worker-imported script, runs it, and aborts the remaining imports on exception."
        ),
        source(
            "MDN WorkerGlobalScope self",
            "https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/self",
            "Worker self is a reference to the WorkerGlobalScope itself; the harness exposes self and WorkerGlobalScope without adding window or document."
        ),
        source(
            "MDN Web Crypto API",
            "https://developer.mozilla.org/en-US/docs/Web/API/Web_Crypto_API",
            "WebCrypto is available in workers and exposes Crypto.subtle for low-level primitives; the harness keeps only explicitly implemented methods available."
        ),
        source(
            "MDN Crypto.getRandomValues",
            "https://developer.mozilla.org/en-US/docs/Web/API/Crypto/getRandomValues",
            "getRandomValues accepts integer typed arrays, writes in place, and rejects requests over 65,536 bytes."
        ),
        source(
            "MDN Crypto.randomUUID",
            "https://developer.mozilla.org/en-US/docs/Web/API/Crypto/randomUUID",
            "randomUUID returns a 36-character v4 UUID generated with cryptographically secure random bytes."
        ),
        source(
            "MDN SubtleCrypto.digest",
            "https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/digest",
            "digest accepts SHA-1, SHA-256, SHA-384, and SHA-512 with ArrayBuffer or ArrayBufferView data and returns a Promise for an ArrayBuffer digest."
        ),
        source(
            "W3C Web Cryptography API Level 2",
            "https://w3c.github.io/webcrypto/",
            "Checked Crypto, getRandomValues, randomUUID, and SubtleCrypto.digest semantics before exposing the local experimental compatibility slice."
        ),
        source(
            "MDN WorkerGlobalScope setTimeout",
            "https://developer.mozilla.org/en-US/docs/Web/API/WorkerGlobalScope/setTimeout",
            "Worker timers return cancellable integer identifiers and invoke callbacks after a delay. The local experimental harness intentionally substitutes an explicit manual queue and never waits on wall clock time."
        ),
        source(
            "WHATWG HTML timers",
            "https://html.spec.whatwg.org/multipage/timers-and-user-prompts.html#timers",
            "WindowOrWorkerGlobalScope timers use positive identifiers shared by setTimeout/setInterval and removable by clearTimeout/clearInterval. The harness keeps those cancellation semantics while replacing elapsed-time scheduling with explicit test drains."
        ),
        source(
            "W3C Service Workers importScripts",
            "https://w3c.github.io/ServiceWorker/v1/#importscripts",
            "Service workers maintain a script resource map for imported classic scripts; the spec does not define a local filesystem resolver or extension generated-bundle policy."
        ),
        source(
            "Apple JSContext documentation",
            "https://developer.apple.com/documentation/javascriptcore/jscontext",
            "JavaScriptCore provides an isolated JavaScript execution context."
        ),
        source(
            "Apple JSContext SDK header",
            "xcode://MacOSX.sdk/System/Library/Frameworks/JavaScriptCore.framework/Headers/JSContext.h",
            "The local SDK exposes evaluateScript:withSourceURL:, exception handling, a VM association, and an inspectable flag that defaults off."
        ),
        source(
            "Apple JavaScriptCore C API SDK headers",
            "xcode://MacOSX.sdk/System/Library/Frameworks/JavaScriptCore.framework/Headers/JSBase.h",
            "Checked JSBase, JSObjectRef, JSValue, and JSVirtualMachine headers. They expose script evaluation, script syntax checks, source URL metadata, Promise construction helpers, and VM lifecycle, but no public module loader, resolver hook, dynamic import callback, module namespace accessor, or deterministic job-drain API."
        ),
        source(
            "Apple JavaScriptCore binary symbol table",
            "xcode://MacOSX.sdk/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore.tbd",
            "The local SDK binary exports unheadered JSScript and C++ module/import symbols. They are not declared in public SDK headers or Swift overlay and are not used by the harness."
        ),
        source(
            "Apple Security randomization services",
            "https://developer.apple.com/documentation/security/randomization-services",
            "SecRandomCopyBytes generates cryptographically secure random bytes; the harness treats any SecRandom failure as a precise WebCrypto blocker."
        ),
        source(
            "Apple Security SecRandom SDK header",
            "xcode://MacOSX.sdk/System/Library/Frameworks/Security.framework/Headers/SecRandom.h",
            "The local SDK documents kSecRandomDefault as the default cryptographically secure RNG and requires SecRandomCopyBytes return status checks."
        ),
        source(
            "Apple CryptoKit SDK interface",
            "xcode://MacOSX.sdk/System/Library/Frameworks/CryptoKit.framework/Modules/CryptoKit.swiftmodule",
            "The local SDK exposes SHA-1 through Insecure.SHA1 and SHA-256/SHA-384/SHA-512 digest implementations used by the digest-only SubtleCrypto slice."
        ),
        source(
            "Apple WKWebExtensionController SDK header",
            "xcode://MacOSX.sdk/System/Library/Frameworks/WebKit.framework/Headers/WKWebExtensionController.h",
            "Loading a WebKit extension context manages background content and WebView association, so this harness avoids that broader surface."
        ),
    ]

    private static func source(
        _ title: String,
        _ url: String,
        _ finding: String
    ) -> ChromeMV3ServiceWorkerJSExecutionDocumentationSource {
        ChromeMV3ServiceWorkerJSExecutionDocumentationSource(
            title: title,
            url: url,
            finding: finding
        )
    }
}

struct ChromeMV3ServiceWorkerJSExecutionRequest {
    var manifest: ChromeMV3Manifest
    var generatedBundleRecord: ChromeMV3GeneratedBundleRecord?
    var extensionID: String
    var profileID: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var extensionEnabled: Bool
    var localExperimentalGateAllowed: Bool
    var dynamicImportRewriteExperimentAllowed: Bool
    var uiLanguageOverride: String?

    init(
        manifest: ChromeMV3Manifest,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        extensionID: String,
        profileID: String,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        extensionEnabled: Bool = true,
        localExperimentalGateAllowed: Bool = false,
        dynamicImportRewriteExperimentAllowed: Bool = false,
        uiLanguageOverride: String? = nil
    ) {
        self.manifest = manifest
        self.generatedBundleRecord = generatedBundleRecord
        self.extensionID = normalizedServiceWorkerJS(
            extensionID,
            fallback: "unknown-extension"
        )
        self.profileID = normalizedServiceWorkerJS(
            profileID,
            fallback: "unknown-profile"
        )
        self.moduleState = moduleState
        self.extensionEnabled = extensionEnabled
        self.localExperimentalGateAllowed = localExperimentalGateAllowed
        self.dynamicImportRewriteExperimentAllowed =
            dynamicImportRewriteExperimentAllowed
        self.uiLanguageOverride = uiLanguageOverride
    }
}

enum ChromeMV3ServiceWorkerJSResourceLoadBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case backgroundServiceWorkerMissing
    case dynamicImportExecutionSurfaceUnsupported
    case dynamicImportGeneratedRootContainmentUnproven
    case dynamicImportLowerLevelAPINotAvailable
    case dynamicImportModuleNamespaceUnsupported
    case dynamicImportNoLoader
    case dynamicImportParseUnsupported
    case dynamicImportPromiseDrainUnavailable
    case dynamicImportResolverHookUnavailable
    case dynamicImportUnsupported
    case generatedBundleRecordMissing
    case generatedBundleRootMismatch
    case generatedBundleRootMissing
    case importScriptsUnsupported
    case moduleWorkerUnsupported
    case serviceWorkerFileMissing
    case serviceWorkerFileNotCopiedFromGeneratedBundleRecord
    case serviceWorkerPathEscapesGeneratedBundle
    case serviceWorkerPathUnsafe
    case serviceWorkerSymbolicLinkRejected
    case serviceWorkerTypeUnsupported
    case serviceWorkerUTF8Required
    case serviceWorkerWrapperMissing
    case staticModuleImportUnsupported
    case wrapperShimMissing

    static func < (
        lhs: ChromeMV3ServiceWorkerJSResourceLoadBlocker,
        rhs: ChromeMV3ServiceWorkerJSResourceLoadBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSImportScriptsBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case absoluteFilesystemPathRejected
    case blobURLRejected
    case circularImportBlocked
    case computedImportScriptsCandidateSetUnbounded
    case computedImportScriptsConstantMapCandidateUnsafe
    case computedImportScriptsRuntimeVariableRejected
    case dataURLRejected
    case dynamicImportExecutionSurfaceUnsupported
    case dynamicImportGeneratedRootContainmentUnproven
    case dynamicImportLowerLevelAPINotAvailable
    case dynamicImportModuleNamespaceUnsupported
    case dynamicImportNoLoader
    case dynamicImportParseUnsupported
    case dynamicImportPromiseDrainUnavailable
    case dynamicImportResolverHookUnavailable
    case dynamicImportUnsupported
    case fileURLRejected
    case generatedBundleRecordMissing
    case generatedBundleRootMissing
    case importArgumentNonString
    case importPathEscapesGeneratedBundle
    case importPathTraversalRejected
    case importPathUnsafe
    case importedScriptDirectoryRejected
    case importedScriptMissing
    case importedScriptNotCopiedFromGeneratedBundleRecord
    case importedScriptSymbolicLinkRejected
    case importedScriptUTF8Required
    case remoteURLRejected
    case scriptEvaluationFailed
    case staticModuleImportUnsupported
    case unsupportedScheme

    static func < (
        lhs: ChromeMV3ServiceWorkerJSImportScriptsBlocker,
        rhs: ChromeMV3ServiceWorkerJSImportScriptsBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSTimerKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case interval
    case timeout

    static func < (
        lhs: ChromeMV3ServiceWorkerJSTimerKind,
        rhs: ChromeMV3ServiceWorkerJSTimerKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSTimerRecord:
    Codable,
    Equatable,
    Sendable
{
    var timerID: Int
    var kind: ChromeMV3ServiceWorkerJSTimerKind
    var delayMilliseconds: Double
    var active: Bool
    var queued: Bool
    var invocationCount: Int
}

struct ChromeMV3ServiceWorkerJSTimerDrainRecord:
    Codable,
    Equatable,
    Sendable
{
    var mode: String
    var callbackCount: Int
    var callbackErrors: [String]
    var pendingTimeoutCount: Int
    var activeIntervalCount: Int
    var limitReached: Bool
    var diagnostics: [String]
}

enum ChromeMV3ServiceWorkerJSDynamicImportBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case absoluteFilesystemPathRejected
    case blobURLRejected
    case circularImportBlocked
    case dataURLRejected
    case dynamicImportArgumentNonString
    case dynamicImportExecutionSurfaceUnsupported
    case dynamicImportGeneratedRootContainmentUnproven
    case dynamicImportLowerLevelAPINotAvailable
    case dynamicImportModuleNamespaceUnsupported
    case dynamicImportNoLoader
    case dynamicImportParseUnsupported
    case dynamicImportPromiseDrainUnavailable
    case dynamicImportResolverHookUnavailable
    case fileURLRejected
    case generatedBundleRecordMissing
    case generatedBundleRootMissing
    case importPathEscapesGeneratedBundle
    case importPathTraversalRejected
    case importPathUnsafe
    case importedModuleDirectoryRejected
    case importedModuleMissing
    case importedModuleSyntaxUnsupported
    case importedModuleNotCopiedFromGeneratedBundleRecord
    case importedModuleSymbolicLinkRejected
    case importedModuleUTF8Required
    case remoteURLRejected
    case scriptEvaluationFailed
    case staticModuleImportUnsupported
    case unsupportedScheme

    static func < (
        lhs: ChromeMV3ServiceWorkerJSDynamicImportBlocker,
        rhs: ChromeMV3ServiceWorkerJSDynamicImportBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSImportedScriptRecord:
    Codable,
    Equatable,
    Sendable
{
    var requestPath: String
    var parentScriptRelativePath: String
    var resolvedRelativePath: String?
    var resolvedPath: String?
    var importChain: [String]
    var imported: Bool
    var evaluationOrder: Int?
    var sourceSHA256: String?
    var sourceByteCount: Int?
    var blockers: [ChromeMV3ServiceWorkerJSImportScriptsBlocker]
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSDynamicImportRecord:
    Codable,
    Equatable,
    Sendable
{
    var requestPath: String
    var parentScriptRelativePath: String
    var resolvedRelativePath: String?
    var resolvedPath: String?
    var stringLiteral: Bool
    var generatedBundlePathValidated: Bool
    var rewriteEligible: Bool
    var rewritten: Bool
    var evaluated: Bool
    var evaluationOrder: Int?
    var sourceSHA256: String?
    var sourceByteCount: Int?
    var blockers: [ChromeMV3ServiceWorkerJSDynamicImportBlocker]
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSResourceLoadRecord:
    Codable,
    Equatable,
    Sendable
{
    var generatedBundleRecordID: String?
    var generatedBundleRootPath: String?
    var serviceWorkerRelativePath: String?
    var serviceWorkerResolvedPath: String?
    var serviceWorkerType: String?
    var wrapperRelativePath: String?
    var shimRelativePath: String?
    var sourceLoaded: Bool
    var sourceSHA256: String?
    var sourceByteCount: Int?
    var importScriptsDetected: Bool
    var staticModuleImportDetected: Bool
    var dynamicImportDetected: Bool
    var dynamicImportCapabilityProbe:
        ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
    var dynamicImportRecords: [ChromeMV3ServiceWorkerJSDynamicImportRecord]
    var dynamicImportBlockers: [ChromeMV3ServiceWorkerJSDynamicImportBlocker]
    var dynamicImportRewriteExperimentApplied: Bool
    var dynamicImportRewriteEvaluationCount: Int
    var dynamicImportRewriteGeneratedBundleArtifactsMutated: Bool
    var importScriptsResolvedCount: Int
    var importedScripts: [ChromeMV3ServiceWorkerJSImportedScriptRecord]
    var importScriptsBlockers: [ChromeMV3ServiceWorkerJSImportScriptsBlocker]
    var webAccessibleResourcesRequiredForWorkerLoad: Bool
    var canExecuteClassicWorkerNow: Bool
    var blockers: [ChromeMV3ServiceWorkerJSResourceLoadBlocker]
    var diagnostics: [String]
}

private struct ChromeMV3ServiceWorkerJSLoadedResource {
    var record: ChromeMV3ServiceWorkerJSResourceLoadRecord
    var source: String?
    var sourceURL: URL?
}

enum ChromeMV3ServiceWorkerJSResourceLoader {
    static func load(
        request: ChromeMV3ServiceWorkerJSExecutionRequest
    ) -> ChromeMV3ServiceWorkerJSResourceLoadRecord {
        loadResource(request: request).record
    }

    fileprivate static func loadResource(
        request: ChromeMV3ServiceWorkerJSExecutionRequest
    ) -> ChromeMV3ServiceWorkerJSLoadedResource {
        let path = normalizedOptionalServiceWorkerJS(
            request.manifest.background?.serviceWorker
        )
        let type =
            normalizedOptionalServiceWorkerJS(
                request.manifest.background?.type
            ) ?? "classic"
        let record = request.generatedBundleRecord
        let root = record.map {
            URL(
                fileURLWithPath: $0.generatedBundleRootPath,
                isDirectory: true
            ).standardizedFileURL
        }
        let wrapperModule: ChromeMV3RuntimeTemplateModuleName =
            type == "module"
                ? .serviceWorkerWrapperModule
                : .serviceWorkerWrapperClassic
        let wrapperPath = ChromeMV3RuntimeResourceTemplateCatalog
            .template(named: wrapperModule)
            .outputRelativePath
        let shimPath = ChromeMV3RuntimeResourceTemplateCatalog
            .template(named: .chromeShimServiceWorker)
            .outputRelativePath
        var blockers: [ChromeMV3ServiceWorkerJSResourceLoadBlocker] = []
        if record == nil {
            blockers.append(.generatedBundleRecordMissing)
        }
        if path == nil {
            blockers.append(.backgroundServiceWorkerMissing)
        }
        if let root, directoryExistsServiceWorkerJS(root) == false {
            blockers.append(.generatedBundleRootMissing)
        }
        if let record, let root,
           root.path != URL(
                fileURLWithPath: record.generatedBundleRootPath,
                isDirectory: true
           ).standardizedFileURL.path
        {
            blockers.append(.generatedBundleRootMismatch)
        }
        let pathSafe = path.map(isSafeRelativeServiceWorkerJSPath) ?? false
        if path != nil, pathSafe == false {
            blockers.append(.serviceWorkerPathUnsafe)
        }
        let candidate = path.flatMap {
            pathSafe ? root?.appendingPathComponent($0).standardizedFileURL : nil
        }
        if let root, let candidate,
           containsServiceWorkerJS(root: root, candidate: candidate) == false
        {
            blockers.append(.serviceWorkerPathEscapesGeneratedBundle)
        }
        if let record, let path,
           record.copiedResourcePaths.contains(path) == false
        {
            blockers.append(
                .serviceWorkerFileNotCopiedFromGeneratedBundleRecord
            )
        }
        if let candidate {
            if regularFileExistsServiceWorkerJS(candidate) == false {
                blockers.append(.serviceWorkerFileMissing)
            }
            if symbolicLinkServiceWorkerJS(candidate) {
                blockers.append(.serviceWorkerSymbolicLinkRejected)
            }
        } else if pathSafe {
            blockers.append(.serviceWorkerFileMissing)
        }
        if type == "module" {
            blockers.append(.moduleWorkerUnsupported)
        } else if type != "classic" {
            blockers.append(.serviceWorkerTypeUnsupported)
        }
        if let root {
            if regularFileExistsServiceWorkerJS(
                root.appendingPathComponent(wrapperPath)
            ) == false {
                blockers.append(.serviceWorkerWrapperMissing)
            }
            if regularFileExistsServiceWorkerJS(
                root.appendingPathComponent(shimPath)
            ) == false {
                blockers.append(.wrapperShimMissing)
            }
        } else {
            blockers.append(.serviceWorkerWrapperMissing)
            blockers.append(.wrapperShimMissing)
        }
        var source: String?
        if let candidate, regularFileExistsServiceWorkerJS(candidate),
           symbolicLinkServiceWorkerJS(candidate) == false
        {
            source = try? String(contentsOf: candidate, encoding: .utf8)
            if source == nil {
                blockers.append(.serviceWorkerUTF8Required)
            }
        }
        let importScriptsDetected =
            source.map {
                containsServiceWorkerJSRegex(
                    "\\bimportScripts\\s*\\(",
                    in: $0
                )
            } ?? false
        let staticImportDetected =
            source.map {
                containsServiceWorkerJSRegex(
                    "(?m)^\\s*import\\s+(?!\\()",
                    in: $0
                )
            } ?? false
        let dynamicImportDetected =
            source.map {
                dynamicImportArgumentSourcesServiceWorkerJS(in: $0)
                    .isEmpty == false
            } ?? false
        let dynamicImportCapability =
            ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe.evaluate()
        let dynamicImportRewriteAllowed =
            request.localExperimentalGateAllowed
            && request.dynamicImportRewriteExperimentAllowed
            && request.moduleState == .enabled
            && request.extensionEnabled
        let dynamicImportRecords =
            source.map {
                dynamicImportRecordsServiceWorkerJS(
                    in: $0,
                    parentScriptRelativePath: path ?? "unknown-worker.js",
                    parentURL: candidate,
                    generatedBundleRecord: record,
                    generatedBundleRoot: root,
                    capability: dynamicImportCapability,
                    includeCapabilityBlockers:
                        dynamicImportRewriteAllowed == false
                )
            } ?? []
        let dynamicImportBlockers = uniqueSortedServiceWorkerJS(
            dynamicImportRecords.flatMap(\.blockers)
        )
        if staticImportDetected {
            blockers.append(.staticModuleImportUnsupported)
        }
        if dynamicImportDetected {
            if dynamicImportRewriteAllowed == false {
                blockers.append(
                    contentsOf:
                        dynamicImportCapability.blockers.compactMap(
                            resourceLoadBlockerServiceWorkerJS
                        )
                )
            }
        }
        blockers = uniqueSortedServiceWorkerJS(blockers)
        let transformedSource =
            dynamicImportDetected
                && dynamicImportRewriteAllowed
                && dynamicImportBlockers.isEmpty
                && staticImportDetected == false
                ? source.map(rewriteDynamicImportsForHarnessServiceWorkerJS)
                : nil
        let executionSource = transformedSource ?? source
        let canExecute =
            blockers.isEmpty
            && dynamicImportBlockers.isEmpty
            && type == "classic"
            && executionSource != nil
        let data = source.map { Data($0.utf8) }
        let loadRecord = ChromeMV3ServiceWorkerJSResourceLoadRecord(
            generatedBundleRecordID: record?.id,
            generatedBundleRootPath: root?.path,
            serviceWorkerRelativePath: path,
            serviceWorkerResolvedPath: candidate?.path,
            serviceWorkerType: type,
            wrapperRelativePath: wrapperPath,
            shimRelativePath: shimPath,
            sourceLoaded: source != nil,
            sourceSHA256: data.map(sha256HexServiceWorkerJS),
            sourceByteCount: data?.count,
            importScriptsDetected: importScriptsDetected,
            staticModuleImportDetected: staticImportDetected,
            dynamicImportDetected: dynamicImportDetected,
            dynamicImportCapabilityProbe: dynamicImportCapability,
            dynamicImportRecords: dynamicImportRecords,
            dynamicImportBlockers: dynamicImportBlockers,
            dynamicImportRewriteExperimentApplied:
                transformedSource != nil,
            dynamicImportRewriteEvaluationCount: 0,
            dynamicImportRewriteGeneratedBundleArtifactsMutated: false,
            importScriptsResolvedCount: 0,
            importedScripts: [],
            importScriptsBlockers: [],
            webAccessibleResourcesRequiredForWorkerLoad: false,
            canExecuteClassicWorkerNow: canExecute,
            blockers: blockers,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    [
                        "Only an extension-owned resource copied into its generated bundle record may execute.",
                        "The worker path is checked for relative-path safety, generated-root containment, regular-file presence, and symbolic-link rejection.",
                        "Classic importScripts calls are resolved synchronously at execution time and remain constrained to copied generated-bundle resources.",
                        dynamicImportRewriteAllowed
                            ? "Dynamic import expressions were scanned for a harness-only string-literal rewrite; safe candidates may execute through the generated-root-contained helper."
                            : "Dynamic import expressions are capability-probed separately; without a JavaScriptCore module loader hook they remain blocked before execution.",
                        "The dynamic-import rewrite experiment uses transformed in-memory source and does not mutate generated bundle artifacts.",
                        "web_accessible_resources is not required for internal service-worker package loading.",
                        "Generated inert wrapper and service-worker shim resources must already exist.",
                    ]
                        + blockers.map { "Resource blocker: \($0.rawValue)." }
                        + dynamicImportBlockers.map {
                            "Dynamic import blocker: \($0.rawValue)."
                        }
                )
        )
        return ChromeMV3ServiceWorkerJSLoadedResource(
            record: loadRecord,
            source: canExecute ? executionSource : nil,
            sourceURL: canExecute ? candidate : nil
        )
    }
}

enum ChromeMV3ServiceWorkerJSListenerResponseMode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case callbackSendResponse
    case promiseObservableButDeferred
    case syncReturn
    case unsupportedDeferred

    static func < (
        lhs: ChromeMV3ServiceWorkerJSListenerResponseMode,
        rhs: ChromeMV3ServiceWorkerJSListenerResponseMode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSCapturedListenerRegistration:
    Codable,
    Equatable,
    Sendable
{
    var listenerID: String
    var event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var listenerSourceFile: String
    var registrationOrder: Int
    var listenerArity: Int
    var asyncFunctionDetected: Bool
    var supportedResponseModes:
        [ChromeMV3ServiceWorkerJSListenerResponseMode]
    var diagnostics: [String]
}

enum ChromeMV3ServiceWorkerJSExecutionStartStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case failed
    case notStarted
    case running
    case stoppedAfterDisable
    case stoppedAfterHardTimeout
    case stoppedAfterIdle
    case stoppedAfterProfileClose
    case stoppedAfterReset
    case stoppedAfterUninstall

    static func < (
        lhs: ChromeMV3ServiceWorkerJSExecutionStartStatus,
        rhs: ChromeMV3ServiceWorkerJSExecutionStartStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSExecutionStartBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case executionPolicyBlocked
    case lifecycleSessionUnavailable
    case resourceLoadBlocked
    case scriptEvaluationFailed
    case shimEvaluationFailed

    static func < (
        lhs: ChromeMV3ServiceWorkerJSExecutionStartBlocker,
        rhs: ChromeMV3ServiceWorkerJSExecutionStartBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerJSExceptionClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case bundlerRuntimeAssumption
    case missingChromeAPIShim
    case missingStandardWorkerGlobal
    case missingWebAPI
    case unknownVendorCodeAssumption
    case unsupportedAsyncOrTimerBehavior
    case unsupportedModuleOrImportShape

    static func < (
        lhs: ChromeMV3ServiceWorkerJSExceptionClassification,
        rhs: ChromeMV3ServiceWorkerJSExceptionClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSExceptionDetails:
    Codable,
    Equatable,
    Sendable
{
    var message: String
    var sourcePath: String?
    var line: Int?
    var column: Int?
    var stack: String?
    var inferredMissingGlobal: String?
    var inferredMissingProperty: String?
    var classification: ChromeMV3ServiceWorkerJSExceptionClassification
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSExecutionStartRecord:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ServiceWorkerJSExecutionStartStatus
    var executionSurface: ChromeMV3ServiceWorkerJSExecutionSurface
    var capturedListenerCount: Int
    var capturedListenerFamilies:
        [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var importScriptsResolvedCount: Int
    var importedScriptPaths: [String]
    var importScriptsBlockers: [ChromeMV3ServiceWorkerJSImportScriptsBlocker]
    var blockedUnsupportedCalls: [String]
    var cryptoOperationRecords:
        [ChromeMV3ServiceWorkerJSCryptoOperationRecord]
    var i18nOperationRecords:
        [ChromeMV3ServiceWorkerJSI18nOperationRecord]
    var workerGlobalEventRecords:
        [ChromeMV3ServiceWorkerJSWorkerGlobalEventRecord]
    var fetchClassificationRecords:
        [ChromeMV3ServiceWorkerJSFetchClassificationRecord]
    var webAssemblyCapability:
        ChromeMV3ServiceWorkerJSWebAssemblyCapabilityRecord?
    var blockers: [ChromeMV3ServiceWorkerJSExecutionStartBlocker]
    var lastErrorMessage: String?
    var exceptionDetails: ChromeMV3ServiceWorkerJSExceptionDetails?
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSWebAssemblyCapabilityRecord:
    Codable,
    Equatable,
    Sendable
{
    var globalPresent: Bool
    var instantiatePresent: Bool
    var instantiateStreamingPresent: Bool
    var compilePresent: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSCryptoOperationRecord:
    Codable,
    Equatable,
    Sendable
{
    var operation: String
    var algorithm: String?
    var byteCount: Int?
    var status: String
    var blocker: String?
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSI18nOperationRecord:
    Codable,
    Equatable,
    Sendable
{
    var operation: String
    var status: String
    var value: String?
    var source: String?
    var blocker: String?
    var diagnostics: [String]
}

enum ChromeMV3ServiceWorkerJSWorkerGlobalEventOperation:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case addEventListener
    case dispatchEvent
    case removeEventListener

    static func < (
        lhs: ChromeMV3ServiceWorkerJSWorkerGlobalEventOperation,
        rhs: ChromeMV3ServiceWorkerJSWorkerGlobalEventOperation
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSWorkerGlobalEventRecord:
    Codable,
    Equatable,
    Sendable
{
    var operation: ChromeMV3ServiceWorkerJSWorkerGlobalEventOperation
    var eventType: String
    var listenerCount: Int
    var dispatchListenerCount: Int
    var defaultPrevented: Bool
    var blocked: Bool
    var diagnostics: [String]
}

enum ChromeMV3ServiceWorkerJSFetchRequestKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case absoluteFilesystemBlocked
    case blobURLBlocked
    case dataURLBlocked
    case extensionLocalResource
    case extensionLocalGeneratedResource
    case fileURLBlocked
    case missingResource
    case relativeGeneratedResource
    case remoteNetworkBlocked
    case remoteNetwork
    case requestLikeObject
    case symlinkEscapeBlocked
    case traversalBlocked
    case unknownInput
    case unsupportedRequestShape
    case unsupportedScheme

    static func < (
        lhs: ChromeMV3ServiceWorkerJSFetchRequestKind,
        rhs: ChromeMV3ServiceWorkerJSFetchRequestKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSFetchClassificationRecord:
    Codable,
    Equatable,
    Sendable
{
    var callIndex: Int
    var sourcePath: String?
    var line: Int?
    var requestPreview: String
    var resolvedURL: String?
    var requestKind: ChromeMV3ServiceWorkerJSFetchRequestKind
    var networkAccessRequired: Bool
    var extensionLocalResource: Bool
    var executionAllowed: Bool
    var blocker: String
    var fetchedResourcePath: String?
    var sourceByteCount: Int?
    var status: Int?
    var diagnostics: [String]
}

enum ChromeMV3ServiceWorkerJSDispatchResultKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blockedByGate
    case blockedByPermission
    case delivered
    case listenerError
    case noListener
    case noReceiver
    case promiseRejected
    case sendResponseTimeoutDiagnostic
    case unsupportedListenerMode

    static func < (
        lhs: ChromeMV3ServiceWorkerJSDispatchResultKind,
        rhs: ChromeMV3ServiceWorkerJSDispatchResultKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerJSDispatchRecord:
    Codable,
    Equatable,
    Sendable
{
    var event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var source: ChromeMV3ServiceWorkerEventSource
    var resultKind: ChromeMV3ServiceWorkerJSDispatchResultKind
    var respondingListenerID: String?
    var responsePayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var portID: String?
    var lifecycleRoutingRecord: ChromeMV3ServiceWorkerEventRoutingRecord?
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSPortRecord:
    Codable,
    Equatable,
    Sendable
{
    var portID: String
    var name: String
    var sender: ChromeMV3ServiceWorkerEventSenderMetadata
    var nativeFixturePort: Bool
    var connected: Bool
    var onMessageListenerCount: Int
    var onDisconnectListenerCount: Int
    var postedMessages: [ChromeMV3StorageValue]
    var disconnectReason: String?
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerJSExecutionSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var policy: ChromeMV3ServiceWorkerJSExecutionPolicy
    var resourceLoad: ChromeMV3ServiceWorkerJSResourceLoadRecord?
    var startRecord: ChromeMV3ServiceWorkerJSExecutionStartRecord
    var capturedListeners:
        [ChromeMV3ServiceWorkerJSCapturedListenerRegistration]
    var importScriptsResolvedCount: Int
    var importedScripts: [ChromeMV3ServiceWorkerJSImportedScriptRecord]
    var importScriptsBlockers: [ChromeMV3ServiceWorkerJSImportScriptsBlocker]
    var blockedUnsupportedCalls: [String]
    var cryptoOperationRecords:
        [ChromeMV3ServiceWorkerJSCryptoOperationRecord]
    var i18nOperationRecords:
        [ChromeMV3ServiceWorkerJSI18nOperationRecord]
    var workerGlobalEventRecords:
        [ChromeMV3ServiceWorkerJSWorkerGlobalEventRecord]
    var fetchClassificationRecords:
        [ChromeMV3ServiceWorkerJSFetchClassificationRecord]
    var webAssemblyCapability:
        ChromeMV3ServiceWorkerJSWebAssemblyCapabilityRecord?
    var dispatchRecords: [ChromeMV3ServiceWorkerJSDispatchRecord]
    var ports: [ChromeMV3ServiceWorkerJSPortRecord]
    var timers: [ChromeMV3ServiceWorkerJSTimerRecord]
    var timerDrainRecords: [ChromeMV3ServiceWorkerJSTimerDrainRecord]
    var lifecycleSnapshot: ChromeMV3ServiceWorkerInternalLifecycleSnapshot?
    var documentationSources:
        [ChromeMV3ServiceWorkerJSExecutionDocumentationSource]
    var permanentBackgroundAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

final class ChromeMV3ServiceWorkerJSExecutionHarness {
    let request: ChromeMV3ServiceWorkerJSExecutionRequest
    let policy: ChromeMV3ServiceWorkerJSExecutionPolicy

    private let lifecycleRegistry =
        ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
    private var lifecycleSession:
        ChromeMV3ServiceWorkerSharedLifecycleSession?
    private var resourceLoadRecord:
        ChromeMV3ServiceWorkerJSResourceLoadRecord?
    private var capturedListeners:
        [ChromeMV3ServiceWorkerJSCapturedListenerRegistration] = []
    private var importedScriptRecords:
        [ChromeMV3ServiceWorkerJSImportedScriptRecord] = []
    private var blockedUnsupportedCalls: [String] = []
    private var cryptoOperationRecords:
        [ChromeMV3ServiceWorkerJSCryptoOperationRecord] = []
    private var i18nOperationRecords:
        [ChromeMV3ServiceWorkerJSI18nOperationRecord] = []
    private var workerGlobalEventRecords:
        [ChromeMV3ServiceWorkerJSWorkerGlobalEventRecord] = []
    private var fetchClassificationRecords:
        [ChromeMV3ServiceWorkerJSFetchClassificationRecord] = []
    private var webAssemblyCapability:
        ChromeMV3ServiceWorkerJSWebAssemblyCapabilityRecord?
    private var dispatchRecords: [ChromeMV3ServiceWorkerJSDispatchRecord] = []
    private var ports: [String: ChromeMV3ServiceWorkerJSPortRecord] = [:]
    private var timers: [ChromeMV3ServiceWorkerJSTimerRecord] = []
    private var timerDrainRecords:
        [ChromeMV3ServiceWorkerJSTimerDrainRecord] = []
    private var lifecycleKeepaliveIDsByPort: [String: String] = [:]
    private var nextPortSequence = 1
    private var nextImportEvaluationOrder = 1
    private var nextDynamicImportEvaluationOrder = 1
    #if canImport(JavaScriptCore)
        private var virtualMachine: JSVirtualMachine?
        private var context: JSContext?
        private var importEvaluationStack: [URL] = []
    #endif
    private(set) var startRecord =
        ChromeMV3ServiceWorkerJSExecutionStartRecord(
            status: .notStarted,
            executionSurface: .none,
            capturedListenerCount: 0,
            capturedListenerFamilies: [],
            importScriptsResolvedCount: 0,
            importedScriptPaths: [],
            importScriptsBlockers: [],
            blockedUnsupportedCalls: [],
            cryptoOperationRecords: [],
            i18nOperationRecords: [],
            workerGlobalEventRecords: [],
            fetchClassificationRecords: [],
            webAssemblyCapability: nil,
            blockers: [],
            lastErrorMessage: nil,
            exceptionDetails: nil,
            diagnostics: [
                "The local experimental service-worker JavaScript harness has not started.",
            ]
        )

    init(request: ChromeMV3ServiceWorkerJSExecutionRequest) {
        self.request = request
        self.policy = ChromeMV3ServiceWorkerJSExecutionPolicy.evaluate(
            moduleState: request.moduleState,
            extensionEnabled: request.extensionEnabled,
            localExperimentalGateAllowed:
                request.localExperimentalGateAllowed,
            generatedBundleRecordAvailable:
                request.generatedBundleRecord != nil,
            dynamicImportRewriteExperimentAllowed:
                request.dynamicImportRewriteExperimentAllowed,
            uiLanguageOverride: request.uiLanguageOverride
        )
    }

    var snapshot: ChromeMV3ServiceWorkerJSExecutionSnapshot {
        ChromeMV3ServiceWorkerJSExecutionSnapshot(
            extensionID: request.extensionID,
            profileID: request.profileID,
            policy: policy,
            resourceLoad: resourceLoadRecord,
            startRecord: startRecord,
            capturedListeners: capturedListeners,
            importScriptsResolvedCount:
                importedScriptRecords.filter(\.imported).count,
            importedScripts: importedScriptRecords,
            importScriptsBlockers: currentImportScriptBlockers(),
            blockedUnsupportedCalls: blockedUnsupportedCalls,
            cryptoOperationRecords: cryptoOperationRecords,
            i18nOperationRecords: i18nOperationRecords,
            workerGlobalEventRecords: workerGlobalEventRecords,
            fetchClassificationRecords: fetchClassificationRecords,
            webAssemblyCapability: webAssemblyCapability,
            dispatchRecords: dispatchRecords,
            ports: ports.values.sorted { $0.portID < $1.portID },
            timers: timers.sorted { $0.timerID < $1.timerID },
            timerDrainRecords: timerDrainRecords,
            lifecycleSnapshot: lifecycleSession?.runtimeOwner.snapshot,
            documentationSources:
                ChromeMV3ServiceWorkerJSExecutionDocumentationSource
                .checkedSources,
            permanentBackgroundAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    policy.diagnostics
                        + [
                            "The harness creates no product runtime exposure.",
                            "Captured registrations replace static token detection as fixture proof after successful execution.",
                        ]
                )
        )
    }

    var canDispatchCapturedListeners: Bool {
        #if canImport(JavaScriptCore)
            return context != nil
                && lifecycleSession != nil
                && capturedListeners.isEmpty == false
                && (
                    startRecord.status == .running
                        || startRecord.blockers.contains(
                            .scriptEvaluationFailed
                        )
                )
        #else
            return false
        #endif
    }

    @discardableResult
    func start() -> ChromeMV3ServiceWorkerJSExecutionStartRecord {
        if startRecord.status == .running {
            return startRecord
        }
        guard
            policy
                .serviceWorkerJSExecutionAvailableInLocalExperimentalGate
        else {
            return finishStart(
                status: .blocked,
                blockers: [.executionPolicyBlocked],
                lastErrorMessage:
                    "Service-worker JavaScript execution is blocked by the local experimental policy.",
                diagnostics: policy.diagnostics
            )
        }
        let loaded = ChromeMV3ServiceWorkerJSResourceLoader.loadResource(
            request: request
        )
        resourceLoadRecord = loaded.record
        guard loaded.record.canExecuteClassicWorkerNow,
              let source = loaded.source,
              let sourceURL = loaded.sourceURL
        else {
            return finishStart(
                status: .blocked,
                blockers: [.resourceLoadBlocked],
                lastErrorMessage:
                    "Generated service-worker resource validation blocked execution.",
                diagnostics: loaded.record.diagnostics
            )
        }
        guard let session = lifecycleRegistry.session(
            profileID: request.profileID,
            extensionID: request.extensionID,
            moduleState: request.moduleState,
            explicitInternalLifecycleAllowed:
                request.localExperimentalGateAllowed
                    && request.extensionEnabled
        ) else {
            return finishStart(
                status: .blocked,
                blockers: [.lifecycleSessionUnavailable],
                lastErrorMessage:
                    "No explicit local experimental lifecycle session is available.",
                diagnostics: policy.diagnostics
            )
        }
        lifecycleSession = session
        _ = session.attachComponent(
            kind: .runtimeJSHarness,
            componentID: "service-worker-js-execution-harness",
            eventSurfaces: Self.captureEvents,
            keepaliveSources: [
                .runtimePort,
                .nativeMessagingPort,
                .pendingResponse,
            ],
            diagnostics: [
                "JavaScriptCore service-worker fixture execution is explicitly scoped.",
            ]
        )
        #if canImport(JavaScriptCore)
            let vm = JSVirtualMachine()
            guard let context = JSContext(virtualMachine: vm) else {
                return finishStart(
                    status: .failed,
                    blockers: [.shimEvaluationFailed],
                    lastErrorMessage:
                        "JavaScriptCore context construction failed.",
                    diagnostics: loaded.record.diagnostics
                )
            }
            context.name = "Sumi local experimental MV3 service-worker harness"
            if #available(macOS 13.3, *) {
                context.isInspectable = false
            }
            context.exception = nil
            self.context = context
            installWorkerGlobalConfiguration(in: context, sourceURL: sourceURL)
            installCryptoHost(in: context)
            installImportScriptsHost(in: context)
            installDynamicImportRewriteHost(in: context)
            installFetchHost(in: context)
            _ = context.evaluateScript(
                Self.registrationShim,
                withSourceURL:
                    URL(fileURLWithPath: "/sumi-local-experimental/service-worker-shim.js")
            )
            if let message = context.exception?.toString() {
                self.context = nil
                return finishStart(
                    status: .failed,
                    blockers: [.shimEvaluationFailed],
                    lastErrorMessage: message,
                    diagnostics:
                        loaded.record.diagnostics
                            + ["Injected registration shim evaluation failed."]
                )
            }
            context.exception = nil
            importEvaluationStack = [sourceURL]
            let exceptionDetails = evaluateScriptInContext(
                source,
                sourceURL: sourceURL,
                context: context
            )
            importEvaluationStack.removeAll()
            syncImportRecordsIntoResourceLoad()
            if let exceptionDetails {
                refreshJSSnapshot()
                if capturedListeners.isEmpty {
                    self.context = nil
                } else {
                    virtualMachine = vm
                    context.exception = nil
                    syncCapturedListenersIntoLifecycle()
                }
                return finishStart(
                    status: .failed,
                    blockers: [.scriptEvaluationFailed],
                    lastErrorMessage: exceptionDetails.message,
                    exceptionDetails: exceptionDetails,
                    diagnostics:
                        loaded.record.diagnostics
                            + [
                                "Extension-owned classic worker evaluation failed inside the isolated JavaScriptCore surface.",
                                capturedListeners.isEmpty
                                    ? "No listener registration was available for synthetic dispatch after the failure."
                                    : "Captured listener registrations remain available only for explicit local diagnostic synthetic dispatch before teardown.",
                            ]
                )
            }
            if loaded.record.dynamicImportRewriteExperimentApplied,
               let blocker = resourceLoadRecord?.dynamicImportBlockers.first
            {
                refreshJSSnapshot()
                if capturedListeners.isEmpty {
                    self.context = nil
                } else {
                    virtualMachine = vm
                    context.exception = nil
                    syncCapturedListenersIntoLifecycle()
                }
                return finishStart(
                    status: .failed,
                    blockers: [.scriptEvaluationFailed],
                    lastErrorMessage:
                        "Rewritten dynamic import blocked by \(blocker.rawValue).",
                    diagnostics:
                        (resourceLoadRecord?.diagnostics
                            ?? loaded.record.diagnostics)
                            + [
                                "Harness-only dynamic import rewrite dependency evaluation did not complete safely.",
                                capturedListeners.isEmpty
                                    ? "No listener registration was available for synthetic dispatch after the failure."
                                    : "Captured listener registrations remain available only for explicit local diagnostic synthetic dispatch before teardown.",
                            ]
                )
            }
            virtualMachine = vm
            refreshJSSnapshot()
            syncCapturedListenersIntoLifecycle()
            return finishStart(
                status: .running,
                diagnostics:
                    loaded.record.diagnostics
                        + [
                            "Extension-owned classic worker executed inside a fresh JavaScriptCore VM.",
                            "Real top-level listener registrations were captured from the injected minimal chrome shim.",
                        ]
            )
        #else
            return finishStart(
                status: .blocked,
                blockers: [.executionPolicyBlocked],
                lastErrorMessage: "JavaScriptCore is unavailable.",
                diagnostics: policy.diagnostics
            )
        #endif
    }

    func capturedListener(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> Bool {
        capturedListeners.contains { $0.event == event }
    }

    func dispatch(
        source: ChromeMV3ServiceWorkerEventSource,
        arguments: [ChromeMV3StorageValue] = [],
        sender: ChromeMV3ServiceWorkerEventSenderMetadata = .none,
        payloadSummary: String,
        sourceComponentID: String = "service-worker-js-harness",
        sourceComponentKind:
            ChromeMV3ServiceWorkerSharedLifecycleComponentKind =
                .runtimeJSHarness
    ) -> ChromeMV3ServiceWorkerJSDispatchRecord {
        dispatch(
            source: source,
            listenerEvent: source.listenerEvent,
            arguments: arguments,
            sender: sender,
            payloadSummary: payloadSummary,
            sourceComponentID: sourceComponentID,
            sourceComponentKind: sourceComponentKind,
            portOptions: nil,
            keepaliveKind: nil
        )
    }

    func connectRuntime(
        name: String,
        sender: ChromeMV3ServiceWorkerEventSenderMetadata = .none,
        source: ChromeMV3ServiceWorkerEventSource =
            .popupOptionsRuntimeConnect
    ) -> ChromeMV3ServiceWorkerJSDispatchRecord {
        let portID = nextPortID(prefix: "runtime-port")
        return dispatch(
            source: source,
            listenerEvent: .runtimeOnConnect,
            arguments: [],
            sender: sender,
            payloadSummary: "runtime.connect",
            sourceComponentID: "service-worker-js-runtime-port",
            sourceComponentKind: .runtimeJSHarness,
            portOptions:
                ChromeMV3ServiceWorkerJSPortOptions(
                    portID: portID,
                    name: name,
                    nativeFixturePort: false
                ),
            keepaliveKind: .runtimePort
        )
    }

    func openTrustedNativeFixturePort(
        name: String,
        sender: ChromeMV3ServiceWorkerEventSenderMetadata = .none,
        trustedFixturePolicyAllowed: Bool
    ) -> ChromeMV3ServiceWorkerJSDispatchRecord {
        guard trustedFixturePolicyAllowed else {
            let record = ChromeMV3ServiceWorkerJSDispatchRecord(
                event: .nativePortOnMessage,
                source: .nativeMessagingConnect,
                resultKind: .blockedByPermission,
                respondingListenerID: nil,
                responsePayload: nil,
                lastErrorMessage:
                    "Trusted native fixture policy is required before opening a native Port.",
                portID: nil,
                lifecycleRoutingRecord: nil,
                diagnostics: [
                    "Arbitrary native host launch remains blocked.",
                    "No native host was launched.",
                ]
            )
            dispatchRecords.append(record)
            return record
        }
        guard start().status == .running else {
            return blockedDispatch(
                source: .nativeMessagingConnect,
                event: .nativePortOnMessage,
                message:
                    "Service-worker JavaScript harness is not running for trusted native fixture Port creation."
            )
        }
        let portID = nextPortID(prefix: "native-fixture-port")
        let options = ChromeMV3ServiceWorkerJSPortOptions(
            portID: portID,
            name: name,
            nativeFixturePort: true
        )
        #if canImport(JavaScriptCore)
            guard
                let created: Bool = callJSON(
                    "(() => { __sumiHarness.createPort(\(options.json), \(sender.serviceWorkerJSJSON)); return true; })()"
                ),
                created
            else {
                return blockedDispatch(
                    source: .nativeMessagingConnect,
                    event: .nativePortOnMessage,
                    message: "Native fixture Port creation failed."
                )
            }
        #else
            return blockedDispatch(
                source: .nativeMessagingConnect,
                event: .nativePortOnMessage,
                message: "JavaScriptCore is unavailable."
            )
        #endif
        refreshJSSnapshot()
        guard let session = lifecycleSession else {
            return blockedDispatch(
                source: .nativeMessagingConnect,
                event: .nativePortOnMessage,
                message: "Lifecycle session is unavailable."
            )
        }
        clearLifecycleListeners(for: .nativePortOnMessage)
        session.registerListener(
            event: .nativePortOnMessage,
            listenerID: "js-native-fixture-port-open",
            outcome:
                .modelDispatched(
                    .object(["portID": .string(portID)]),
                    diagnostics: [
                        "Trusted native fixture Port open participated in the service-worker lifecycle.",
                    ]
                )
        )
        let routing = ChromeMV3ServiceWorkerEventRouter.route(
            source: .nativeMessagingConnect,
            readiness: readinessUsingExecutedCapture(
                additionallyCaptured: [.nativePortOnMessage]
            ),
            sharedLifecycleSession: session,
            payload: .object(["portID": .string(portID)]),
            payloadSummary: "trusted fixture native Port connect",
            sender: sender,
            sourceComponentID: "service-worker-js-native-fixture-port",
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            keepaliveKind: .nativeMessagingPort,
            portID: portID
        )
        if let keepaliveID = routing.wakeResult?.keepaliveRecord?.keepaliveID {
            lifecycleKeepaliveIDsByPort[portID] = keepaliveID
        }
        let record = ChromeMV3ServiceWorkerJSDispatchRecord(
            event: .nativePortOnMessage,
            source: .nativeMessagingConnect,
            resultKind: .delivered,
            respondingListenerID: nil,
            responsePayload: .object(["portID": .string(portID)]),
            lastErrorMessage: nil,
            portID: portID,
            lifecycleRoutingRecord: routing,
            diagnostics: [
                "Trusted fixture native Port state was created without native host discovery or launch.",
            ]
        )
        dispatchRecords.append(record)
        return record
    }

    func deliverPortMessage(
        portID: String,
        message: ChromeMV3StorageValue
    ) -> ChromeMV3ServiceWorkerJSPortRecord? {
        guard startRecord.status == .running || canDispatchCapturedListeners
        else { return nil }
        #if canImport(JavaScriptCore)
            let _: ChromeMV3ServiceWorkerJSWirePort? = callJSON(
                "__sumiHarness.deliverPortMessage(\(jsonStringServiceWorkerJS(portID)), \(message.serviceWorkerJSJSON))"
            )
        #endif
        refreshJSSnapshot()
        return ports[portID]
    }

    func deliverTrustedNativeFixturePortMessage(
        portID: String,
        message: ChromeMV3StorageValue
    ) -> ChromeMV3ServiceWorkerJSDispatchRecord {
        guard let port = deliverPortMessage(portID: portID, message: message),
              port.nativeFixturePort,
              let session = lifecycleSession
        else {
            return blockedDispatch(
                source: .nativeMessagingMessage,
                event: .nativePortOnMessage,
                message: "Trusted native fixture Port message delivery is unavailable."
            )
        }
        clearLifecycleListeners(for: .nativePortOnMessage)
        session.registerListener(
            event: .nativePortOnMessage,
            listenerID: "js-native-fixture-port-message",
            outcome:
                .modelDispatched(
                    diagnostics: [
                        "Trusted native fixture Port message participated in the service-worker lifecycle.",
                    ]
                )
        )
        let routing = ChromeMV3ServiceWorkerEventRouter.route(
            source: .nativeMessagingMessage,
            readiness: readinessUsingExecutedCapture(
                additionallyCaptured: [.nativePortOnMessage]
            ),
            sharedLifecycleSession: session,
            payload: message,
            payloadSummary: "trusted fixture native Port message",
            sourceComponentID: "service-worker-js-native-fixture-port",
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            portID: portID
        )
        let record = ChromeMV3ServiceWorkerJSDispatchRecord(
            event: .nativePortOnMessage,
            source: .nativeMessagingMessage,
            resultKind: .delivered,
            respondingListenerID: nil,
            responsePayload: nil,
            lastErrorMessage: nil,
            portID: portID,
            lifecycleRoutingRecord: routing,
            diagnostics: [
                "Trusted native fixture Port message dispatched without arbitrary host launch.",
            ]
        )
        dispatchRecords.append(record)
        return record
    }

    func revokeTrustedNativeFixturePolicy() {
        for port in ports.values
        where port.nativeFixturePort && port.connected {
            _ = disconnectPort(
                portID: port.portID,
                reason: "trustedNativeFixturePolicyRevoked"
            )
        }
    }

    @discardableResult
    func disconnectPort(
        portID: String,
        reason: String = "explicitPortDisconnect",
        lastErrorMessage: String? = nil
    ) -> Bool {
        guard ports[portID] != nil else { return false }
        #if canImport(JavaScriptCore)
            let lastErrorJSON =
                lastErrorMessage.map(jsonStringServiceWorkerJS) ?? "null"
            let _: ChromeMV3ServiceWorkerJSWirePort? = callJSON(
                "__sumiHarness.disconnectPort(\(jsonStringServiceWorkerJS(portID)), \(jsonStringServiceWorkerJS(reason)), \(lastErrorJSON))"
            )
        #endif
        if let keepaliveID = lifecycleKeepaliveIDsByPort.removeValue(
            forKey: portID
        ) {
            _ = lifecycleSession?.disconnectKeepalive(
                keepaliveID: keepaliveID,
                reason: .reset
            )
        }
        refreshJSSnapshot()
        return true
    }

    @discardableResult
    func drainQueuedTimeouts(
        maxCallbacks: Int = 100
    ) -> ChromeMV3ServiceWorkerJSTimerDrainRecord? {
        guard start().status == .running else { return nil }
        #if canImport(JavaScriptCore)
            guard
                let record: ChromeMV3ServiceWorkerJSTimerDrainRecord =
                    callJSON(
                        "__sumiHarness.drainTimeouts(\(max(0, maxCallbacks)))"
                    )
            else { return nil }
            timerDrainRecords.append(record)
            refreshJSSnapshot()
            return record
        #else
            return nil
        #endif
    }

    @discardableResult
    func tickIntervals(
        maxCallbacks: Int = 100
    ) -> ChromeMV3ServiceWorkerJSTimerDrainRecord? {
        guard start().status == .running else { return nil }
        #if canImport(JavaScriptCore)
            guard
                let record: ChromeMV3ServiceWorkerJSTimerDrainRecord =
                    callJSON(
                        "__sumiHarness.tickIntervals(\(max(0, maxCallbacks)))"
                    )
            else { return nil }
            timerDrainRecords.append(record)
            refreshJSSnapshot()
            return record
        #else
            return nil
        #endif
    }

    @discardableResult
    func triggerIdleRelease()
        -> ChromeMV3ServiceWorkerInternalWakeResult?
    {
        disconnectAllPorts(reason: "explicitIdleRelease")
        let result = lifecycleSession?.triggerIdleRelease(
            reason: "explicitJSExecutionHarnessIdleRelease"
        )
        tearDownJavaScriptSurface(status: .stoppedAfterIdle)
        return result
    }

    @discardableResult
    func triggerHardTimeout()
        -> ChromeMV3ServiceWorkerInternalWakeResult?
    {
        disconnectAllPorts(reason: "explicitHardTimeout")
        let result = lifecycleSession?.triggerHardTimeout(
            reason: "explicitJSExecutionHarnessHardTimeout"
        )
        tearDownJavaScriptSurface(status: .stoppedAfterHardTimeout)
        return result
    }

    func tearDownForExtensionDisable() {
        disconnectAllPorts(reason: "extensionDisabled")
        lifecycleSession?.tearDownForExtensionDisable()
        tearDownJavaScriptSurface(status: .stoppedAfterDisable)
    }

    func tearDownForExtensionUninstall() {
        disconnectAllPorts(reason: "extensionUninstalled")
        lifecycleSession?.tearDownForExtensionUninstall()
        tearDownJavaScriptSurface(status: .stoppedAfterUninstall)
    }

    func tearDownForProfileClose() {
        disconnectAllPorts(reason: "profileClosed")
        lifecycleSession?.tearDownForProfileClose()
        tearDownJavaScriptSurface(status: .stoppedAfterProfileClose)
    }

    func reset() {
        disconnectAllPorts(reason: "reset")
        lifecycleSession?.reset()
        lifecycleSession = nil
        lifecycleRegistry.reset()
        resourceLoadRecord = nil
        capturedListeners.removeAll()
        importedScriptRecords.removeAll()
        blockedUnsupportedCalls.removeAll()
        cryptoOperationRecords.removeAll()
        i18nOperationRecords.removeAll()
        workerGlobalEventRecords.removeAll()
        fetchClassificationRecords.removeAll()
        dispatchRecords.removeAll()
        ports.removeAll()
        timers.removeAll()
        timerDrainRecords.removeAll()
        lifecycleKeepaliveIDsByPort.removeAll()
        nextPortSequence = 1
        nextImportEvaluationOrder = 1
        nextDynamicImportEvaluationOrder = 1
        tearDownJavaScriptSurface(status: .stoppedAfterReset)
    }

    private func dispatch(
        source: ChromeMV3ServiceWorkerEventSource,
        listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        arguments: [ChromeMV3StorageValue],
        sender: ChromeMV3ServiceWorkerEventSenderMetadata,
        payloadSummary: String,
        sourceComponentID: String,
        sourceComponentKind:
            ChromeMV3ServiceWorkerSharedLifecycleComponentKind,
        portOptions: ChromeMV3ServiceWorkerJSPortOptions?,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind?
    ) -> ChromeMV3ServiceWorkerJSDispatchRecord {
        let currentStart =
            startRecord.status == .notStarted ? start() : startRecord
        guard currentStart.status == .running || canDispatchCapturedListeners,
              let session = lifecycleSession
        else {
            return blockedDispatch(
                source: source,
                event: listenerEvent,
                message:
                    "Service-worker JavaScript dispatch is blocked because the explicit local experimental harness is unavailable."
            )
        }
        #if canImport(JavaScriptCore)
            let optionsJSON = portOptions?.json ?? "null"
            guard let wire: ChromeMV3ServiceWorkerJSWireDispatch = callJSON(
                "__sumiHarness.dispatch(\(jsonStringServiceWorkerJS(listenerEvent.rawValue)), \(arguments.serviceWorkerJSJSON), \(sender.serviceWorkerJSJSON), \(optionsJSON))"
            ) else {
                return blockedDispatch(
                    source: source,
                    event: listenerEvent,
                    message: "JavaScriptCore dispatch result could not be decoded."
                )
            }
            refreshJSSnapshot()
            let outcome = syntheticOutcome(for: wire)
            clearLifecycleListeners(for: listenerEvent)
            if wire.kind != .noListener {
                session.registerListener(
                    event: listenerEvent,
                    listenerID:
                        "js-executed-\(wire.listenerID ?? listenerEvent.rawValue)",
                    outcome: outcome
                )
            }
            let routing = ChromeMV3ServiceWorkerEventRouter.route(
                source: source,
                readiness: readinessUsingExecutedCapture(),
                sharedLifecycleSession: session,
                payload: arguments.first,
                payloadSummary: payloadSummary,
                sender: sender,
                sourceComponentID: sourceComponentID,
                sourceComponentKind: sourceComponentKind,
                keepaliveKind: keepaliveKind,
                portID: wire.portID
            )
            if let portID = wire.portID,
               let keepaliveID =
                    routing.wakeResult?.keepaliveRecord?.keepaliveID
            {
                lifecycleKeepaliveIDsByPort[portID] = keepaliveID
            }
            var routed = routing
            routed.resultKind = wire.kind.eventRoutingKind(
                for: listenerEvent
            )
            routed.responsePayload = wire.response
            routed.lastErrorMessage = wire.error
            routed.diagnostics =
                uniqueSortedServiceWorkerJS(
                    routed.diagnostics
                        + wire.diagnostics
                        + [
                            "Captured JavaScript listener dispatch was integrated with the existing lifecycle queue.",
                        ]
                )
            let record = ChromeMV3ServiceWorkerJSDispatchRecord(
                event: listenerEvent,
                source: source,
                resultKind: wire.kind.publicKind(
                    for: listenerEvent
                ),
                respondingListenerID: wire.listenerID,
                responsePayload: wire.response,
                lastErrorMessage: wire.error,
                portID: wire.portID,
                lifecycleRoutingRecord: routed,
                diagnostics:
                    uniqueSortedServiceWorkerJS(
                        wire.diagnostics
                            + [
                                "No Chrome parity claim is made for deterministic completion handling.",
                            ]
                    )
            )
            dispatchRecords.append(record)
            return record
        #else
            return blockedDispatch(
                source: source,
                event: listenerEvent,
                message: "JavaScriptCore is unavailable."
            )
        #endif
    }

    private func blockedDispatch(
        source: ChromeMV3ServiceWorkerEventSource,
        event: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        message: String
    ) -> ChromeMV3ServiceWorkerJSDispatchRecord {
        let record = ChromeMV3ServiceWorkerJSDispatchRecord(
            event: event,
            source: source,
            resultKind: .blockedByGate,
            respondingListenerID: nil,
            responsePayload: nil,
            lastErrorMessage: message,
            portID: nil,
            lifecycleRoutingRecord: nil,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    policy.diagnostics + [message]
                )
        )
        dispatchRecords.append(record)
        return record
    }

    private func syntheticOutcome(
        for wire: ChromeMV3ServiceWorkerJSWireDispatch
    ) -> ChromeMV3ServiceWorkerSyntheticListenerOutcome {
        switch wire.kind {
        case .delivered:
            return .modelDispatched(
                wire.response ?? .null,
                diagnostics: wire.diagnostics
            )
        case .listenerError, .promiseRejected:
            return .modeledError(
                wire.error ?? "Captured JavaScript listener failed.",
                diagnostics: wire.diagnostics
            )
        case .sendResponseTimeoutDiagnostic:
            return .pendingResponse(diagnostics: wire.diagnostics)
        case .unsupportedListenerMode:
            return .noResponse(diagnostics: wire.diagnostics)
        case .noListener:
            return .noResponse(diagnostics: wire.diagnostics)
        }
    }

    private func readinessUsingExecutedCapture(
        additionallyCaptured:
            [ChromeMV3ServiceWorkerSyntheticListenerEvent] = []
    ) -> ChromeMV3ServiceWorkerDeclarationReadiness {
        let root = request.generatedBundleRecord.map {
            URL(
                fileURLWithPath: $0.generatedBundleRootPath,
                isDirectory: true
            )
        }
        var readiness =
            ChromeMV3ServiceWorkerDeclarationReadinessEvaluator.evaluate(
                manifest: request.manifest,
                generatedBundleRootURL: root,
                extensionID: request.extensionID,
                profileID: request.profileID,
                moduleState: request.moduleState,
                extensionEnabled: request.extensionEnabled,
                localExperimentalGateAllowed:
                    request.localExperimentalGateAllowed
            )
        let additionallyCapturedSet = Set(additionallyCaptured)
        readiness.listenerDiscoveryStrategy =
            "executed JavaScriptCore listener registration capture"
        readiness.listenerCoverage = Self.captureEvents.map { event in
            let detected =
                capturedListener(for: event)
                || additionallyCapturedSet.contains(event)
            return ChromeMV3ServiceWorkerListenerCoverage(
                event: event,
                listenerSurface: event.listenerSurface,
                listenerDetected: detected,
                detectionPattern:
                    detected
                        ? "executed JavaScriptCore registration capture"
                        : nil,
                diagnostics: [
                    detected
                        ? "Captured real listener registration during isolated classic worker execution."
                        : "No listener registration was captured during isolated classic worker execution.",
                    "Static token detection is fallback diagnostic state only after successful execution capture.",
                ]
            )
        }
        readiness.eventRoutingAvailable =
            readiness.eventRoutingAvailable
            && resourceLoadRecord?.canExecuteClassicWorkerNow == true
            && (
                startRecord.status == .running
                    || canDispatchCapturedListeners
            )
        return readiness
    }

    private func syncCapturedListenersIntoLifecycle() {
        guard let session = lifecycleSession else { return }
        for event in Set(capturedListeners.map(\.event)).sorted() {
            clearLifecycleListeners(for: event)
            session.registerListener(
                event: event,
                listenerID: "js-captured-\(event.rawValue)",
                outcome:
                    .noResponse(
                        diagnostics: [
                            "Real JavaScript listener registration was captured before dispatch.",
                        ]
                    )
            )
        }
    }

    private func clearLifecycleListeners(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) {
        guard let registry = lifecycleSession?.runtimeOwner.listenerRegistry
        else { return }
        for registration in registry.listeners(for: event) {
            _ = registry.remove(
                event: event,
                listenerID: registration.listenerID
            )
        }
    }

    private func finishStart(
        status: ChromeMV3ServiceWorkerJSExecutionStartStatus,
        blockers: [ChromeMV3ServiceWorkerJSExecutionStartBlocker] = [],
        lastErrorMessage: String? = nil,
        exceptionDetails: ChromeMV3ServiceWorkerJSExceptionDetails? = nil,
        diagnostics: [String]
    ) -> ChromeMV3ServiceWorkerJSExecutionStartRecord {
        startRecord = ChromeMV3ServiceWorkerJSExecutionStartRecord(
            status: status,
            executionSurface:
                status == .running ? .javaScriptCore : policy.executionSurface,
            capturedListenerCount: capturedListeners.count,
            capturedListenerFamilies:
                capturedListeners.map(\.event).uniqueSortedServiceWorkerJS(),
            importScriptsResolvedCount:
                importedScriptRecords.filter(\.imported).count,
            importedScriptPaths:
                importedScriptRecords.compactMap(\.resolvedRelativePath)
                    .sorted(),
            importScriptsBlockers: currentImportScriptBlockers(),
            blockedUnsupportedCalls: blockedUnsupportedCalls,
            cryptoOperationRecords: cryptoOperationRecords,
            i18nOperationRecords: i18nOperationRecords,
            workerGlobalEventRecords: workerGlobalEventRecords,
            fetchClassificationRecords: fetchClassificationRecords,
            webAssemblyCapability: webAssemblyCapability,
            blockers: uniqueSortedServiceWorkerJS(blockers),
            lastErrorMessage: lastErrorMessage,
            exceptionDetails: exceptionDetails,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    diagnostics + (exceptionDetails?.diagnostics ?? [])
                )
        )
        return startRecord
    }

    private func syncImportRecordsIntoResourceLoad() {
        guard var record = resourceLoadRecord else { return }
        record.importedScripts = importedScriptRecords.sorted { lhs, rhs in
            let lhsOrder = lhs.evaluationOrder ?? Int.max
            let rhsOrder = rhs.evaluationOrder ?? Int.max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.requestPath < rhs.requestPath
        }
        record.importScriptsResolvedCount =
            importedScriptRecords.filter(\.imported).count
        record.importScriptsBlockers = currentImportScriptBlockers()
        resourceLoadRecord = record
    }

    private func currentImportScriptBlockers()
        -> [ChromeMV3ServiceWorkerJSImportScriptsBlocker]
    {
        uniqueSortedServiceWorkerJS(
            importedScriptRecords.flatMap(\.blockers)
        )
    }

    private func relativePathInGeneratedBundle(_ url: URL) -> String? {
        guard let rootPath = request.generatedBundleRecord?
            .generatedBundleRootPath
        else { return nil }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        return Sumi.relativePathInGeneratedBundle(url, root: root)
    }

    private func nextPortID(prefix: String) -> String {
        defer { nextPortSequence += 1 }
        return stableIDServiceWorkerJS(
            prefix: prefix,
            parts: [
                request.profileID,
                request.extensionID,
                String(nextPortSequence),
            ]
        )
    }

    private func disconnectAllPorts(reason: String) {
        for portID in ports.keys.sorted() {
            _ = disconnectPort(portID: portID, reason: reason)
        }
    }

    private func tearDownJavaScriptSurface(
        status: ChromeMV3ServiceWorkerJSExecutionStartStatus
    ) {
        #if canImport(JavaScriptCore)
            context = nil
            virtualMachine = nil
        #endif
        startRecord.status = status
        startRecord.diagnostics =
            uniqueSortedServiceWorkerJS(
                startRecord.diagnostics
                    + [
                        "JavaScriptCore execution surface was released deterministically.",
                    ]
            )
    }

    #if canImport(JavaScriptCore)
        private func installWorkerGlobalConfiguration(
            in context: JSContext,
            sourceURL: URL
        ) {
            let workerRelativePath =
                relativePathInGeneratedBundle(sourceURL)
                ?? resourceLoadRecord?.serviceWorkerRelativePath
                ?? sourceURL.lastPathComponent
            let origin = "chrome-extension://\(request.extensionID)"
            let uiLanguage =
                ChromeMV3ServiceWorkerJSUILanguageSelection.select(
                    override: request.uiLanguageOverride
                )
            context.setObject(
                [
                    "extensionID": request.extensionID,
                    "extensionOrigin": origin,
                    "locationHref": "\(origin)/\(workerRelativePath)",
                    "locationPathname": "/\(workerRelativePath)",
                    "manifest": workerManifestSnapshotServiceWorkerJS(
                        request.manifest
                    ),
                    "uiLanguage": uiLanguage.language,
                    "uiLanguageSource": uiLanguage.source,
                    "userAgent":
                        "Sumi local experimental MV3 service-worker harness",
                ] as NSDictionary,
                forKeyedSubscript:
                    "__sumiWorkerGlobalConfig" as NSString
            )
        }

        private func workerManifestSnapshotServiceWorkerJS(
            _ manifest: ChromeMV3Manifest
        ) -> NSDictionary {
            var object: [String: Any] = [
                "manifest_version": manifest.manifestVersion,
                "name": manifest.name,
                "version": manifest.version,
                "permissions": manifest.permissions,
                "optional_permissions": manifest.optionalPermissions,
                "host_permissions": manifest.hostPermissions,
                "optional_host_permissions": manifest.optionalHostPermissions,
            ]
            if let description = manifest.description {
                object["description"] = description
            }
            if let background = manifest.background {
                var backgroundObject: [String: String] = [:]
                if let serviceWorker = background.serviceWorker {
                    backgroundObject["service_worker"] = serviceWorker
                }
                if let type = background.type {
                    backgroundObject["type"] = type
                }
                object["background"] = backgroundObject
            }
            if let action = manifest.action {
                var actionObject: [String: Any] = [:]
                if let defaultPopup = action.defaultPopup {
                    actionObject["default_popup"] = defaultPopup
                }
                if let defaultTitle = action.defaultTitle {
                    actionObject["default_title"] = defaultTitle
                }
                if action.defaultIconPaths.isEmpty == false {
                    actionObject["default_icon"] = action.defaultIconPaths
                }
                object["action"] = actionObject
            }
            if let optionsPage = manifest.optionsPage {
                object["options_page"] = optionsPage
            }
            if let optionsUI = manifest.optionsUI {
                var optionsObject: [String: Any] = [:]
                if let page = optionsUI.page {
                    optionsObject["page"] = page
                }
                if let openInTab = optionsUI.openInTab {
                    optionsObject["open_in_tab"] = openInTab
                }
                object["options_ui"] = optionsObject
            }
            return object as NSDictionary
        }

        private func installCryptoHost(in context: JSContext) {
            let randomHost: @convention(block) (NSNumber) -> NSDictionary = {
                countValue in
                let count = countValue.intValue
                guard count >= 0 && count <= 65_536 else {
                    return webCryptoHostErrorServiceWorkerJS(
                        "Requested random byte count is outside the WebCrypto getRandomValues limit."
                    )
                }
                switch secureRandomBytesServiceWorkerJS(count: count) {
                case .success(let bytes):
                    return [
                        "ok": true,
                        "bytes":
                            bytes.map { NSNumber(value: $0) } as NSArray,
                    ] as NSDictionary
                case .failure(let error):
                    return webCryptoHostErrorServiceWorkerJS(error.message)
                }
            }
            let uuidHost: @convention(block) () -> NSDictionary = {
                switch secureRandomBytesServiceWorkerJS(count: 16) {
                case .success(var bytes):
                    bytes[6] = (bytes[6] & 0x0f) | 0x40
                    bytes[8] = (bytes[8] & 0x3f) | 0x80
                    return [
                        "ok": true,
                        "uuid": uuidV4StringServiceWorkerJS(bytes),
                    ] as NSDictionary
                case .failure(let error):
                    return webCryptoHostErrorServiceWorkerJS(error.message)
                }
            }
            let digestHost:
                @convention(block) (NSString, JSValue) -> NSDictionary =
            { algorithmValue, byteValues in
                let algorithm = String(algorithmValue)
                guard let values = byteValues.toArray() else {
                    return webCryptoHostErrorServiceWorkerJS(
                        "SubtleCrypto.digest received non-array byte material from the JavaScript bridge."
                    )
                }
                var bytes: [UInt8] = []
                bytes.reserveCapacity(values.count)
                for value in values {
                    guard let number = value as? NSNumber else {
                        return webCryptoHostErrorServiceWorkerJS(
                            "SubtleCrypto.digest received a non-numeric byte."
                        )
                    }
                    let intValue = number.intValue
                    guard intValue >= 0 && intValue <= 255 else {
                        return webCryptoHostErrorServiceWorkerJS(
                            "SubtleCrypto.digest received a byte outside 0...255."
                        )
                    }
                    bytes.append(UInt8(intValue))
                }
                guard
                    let normalized =
                        normalizedWebCryptoDigestAlgorithmServiceWorkerJS(
                            algorithm
                        ),
                    let digest = webCryptoDigestBytesServiceWorkerJS(
                        algorithm: normalized,
                        bytes: bytes
                    )
                else {
                    return webCryptoHostErrorServiceWorkerJS(
                        "Unsupported SubtleCrypto.digest algorithm \(algorithm)."
                    )
                }
                return [
                    "ok": true,
                    "algorithm": normalized,
                    "bytes": digest.map { NSNumber(value: $0) } as NSArray,
                ] as NSDictionary
            }
            context.setObject(
                randomHost,
                forKeyedSubscript:
                    "__sumiCryptoGetRandomValuesHost" as NSString
            )
            context.setObject(
                uuidHost,
                forKeyedSubscript:
                    "__sumiCryptoRandomUUIDHost" as NSString
            )
            context.setObject(
                digestHost,
                forKeyedSubscript:
                    "__sumiCryptoDigestHost" as NSString
            )
        }

        private func installImportScriptsHost(in context: JSContext) {
            let host: @convention(block) (JSValue) -> NSDictionary = {
                [weak self] arguments in
                guard let self else {
                    return [
                        "ok": false,
                        "blocker":
                            ChromeMV3ServiceWorkerJSImportScriptsBlocker
                            .generatedBundleRecordMissing.rawValue,
                        "error":
                            "importScripts resolver owner is unavailable.",
                    ]
                }
                return self.evaluateImportScripts(arguments: arguments)
            }
            context.setObject(
                host,
                forKeyedSubscript:
                    "__sumiImportScriptsHost" as NSString
            )
        }

        private func installDynamicImportRewriteHost(in context: JSContext) {
            let host: @convention(block) (JSValue) -> NSDictionary = {
                [weak self] specifier in
                guard let self else {
                    return [
                        "ok": false,
                        "blocker":
                            ChromeMV3ServiceWorkerJSDynamicImportBlocker
                            .generatedBundleRecordMissing.rawValue,
                        "error":
                            "Dynamic import rewrite resolver owner is unavailable.",
                    ]
                }
                guard let requestPath = specifier.toString(),
                      requestPath.isEmpty == false
                else {
                    return self.recordFailedDynamicImport(
                        requestPath: "<non-string>",
                        blocker: .dynamicImportArgumentNonString,
                        message:
                            "Dynamic import rewrite accepts only string specifiers."
                    )
                }
                return self.evaluateDynamicImportRewrite(
                    requestPath: requestPath
                )
            }
            context.setObject(
                host,
                forKeyedSubscript:
                    "__sumiDynamicImportRewriteHost" as NSString
            )
        }

        private func installFetchHost(in context: JSContext) {
            let host: @convention(block) (JSValue) -> NSDictionary = {
                [weak self] payload in
                guard let self else {
                    return fetchHostFailureResponseServiceWorkerJS(
                        requestKind: .unsupportedRequestShape,
                        networkAccessRequired: false,
                        extensionLocalResource: false,
                        blocker: "fetchResolverUnavailable",
                        message:
                            "fetch resolver owner is unavailable for the local experimental harness.",
                        diagnostics: [
                            "No network, browser fetch, or arbitrary filesystem fallback was attempted.",
                        ]
                    )
                }
                guard let dictionary = payload.toDictionary() else {
                    return fetchHostFailureResponseServiceWorkerJS(
                        requestKind: .unsupportedRequestShape,
                        networkAccessRequired: false,
                        extensionLocalResource: false,
                        blocker: "unsupportedRequestShape",
                        message:
                            "fetch host received an uninspectable request payload.",
                        diagnostics: [
                            "The local harness accepts only serialized fetch request metadata.",
                        ]
                    )
                }
                return self.evaluateFetchRequest(dictionary)
            }
            context.setObject(
                host,
                forKeyedSubscript: "__sumiFetchHost" as NSString
            )
        }

        private func evaluateFetchRequest(
            _ payload: [AnyHashable: Any]
        ) -> NSDictionary {
            func string(_ key: String) -> String? {
                if let value = payload[key] as? String {
                    return value
                }
                if let value = payload[key] as? NSString {
                    return String(value)
                }
                return nil
            }
            func bool(_ key: String) -> Bool {
                if let value = payload[key] as? Bool {
                    return value
                }
                if let value = payload[key] as? NSNumber {
                    return value.boolValue
                }
                return false
            }

            let rawURL = string("rawURL") ?? ""
            let resolvedURL = string("resolvedURL") ?? rawURL
            let method = (string("method") ?? "GET").uppercased()
            let inputWasExtensionURL = bool("inputWasExtensionURL")
            let inputWasRelative = bool("inputWasRelative")
            let extensionLocalKind:
                ChromeMV3ServiceWorkerJSFetchRequestKind =
                    inputWasExtensionURL
                        ? .extensionLocalGeneratedResource
                        : .relativeGeneratedResource

            guard method == "GET" || method == "HEAD" else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .unsupportedRequestShape,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "methodUnsupported",
                    message:
                        "Only GET and HEAD are modeled for generated-bundle-contained extension-local fetch.",
                    diagnostics: [
                        "Mutating request methods are outside this local harness fetch slice.",
                        "No browser network stack or extension runtime fetch implementation was invoked.",
                    ]
                )
            }
            if bool("explicitCredentials") {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .unsupportedRequestShape,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "credentialsUnsupported",
                    message:
                        "credentials options are blocked by the local harness fetch policy.",
                    diagnostics: [
                        "The modeled fetch surface has no credential bridge.",
                    ]
                )
            }
            if bool("explicitCache") {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .unsupportedRequestShape,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "cacheUnsupported",
                    message:
                        "cache options are blocked by the local harness fetch policy.",
                    diagnostics: [
                        "The modeled fetch surface has no cache bridge.",
                    ]
                )
            }
            if rawFetchPathContainsTraversalServiceWorkerJS(rawURL) {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .traversalBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "pathTraversalBlocked",
                    message:
                        "fetch request path contains parent-directory traversal.",
                    diagnostics: [
                        "Traversal was rejected from the original fetch input before any file read.",
                    ]
                )
            }
            if looksLikeAbsoluteFilesystemFetchPathServiceWorkerJS(rawURL) {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .absoluteFilesystemBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "absoluteFilesystemFetchBlocked",
                    message:
                        "Absolute filesystem fetch paths are blocked.",
                    diagnostics: [
                        "Generated-bundle fetch accepts extension URLs or relative extension paths only.",
                        "No arbitrary local file read was attempted.",
                    ]
                )
            }
            guard rawURL.isEmpty == false,
                  let components = URLComponents(string: resolvedURL),
                  let scheme = components.scheme?.lowercased()
            else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .unsupportedRequestShape,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "unsupportedRequestShape",
                    message:
                        "fetch request URL could not be resolved to a supported extension-local URL.",
                    diagnostics: [
                        "Only generated-bundle-contained extension-local resources are modeled.",
                    ]
                )
            }
            if scheme == "http" || scheme == "https" {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .remoteNetworkBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: true,
                    extensionLocalResource: false,
                    blocker: "networkFetchDisabled",
                    message: "Remote http(s) fetch remains disabled.",
                    diagnostics: [
                        "No URLSession, WebKit network load, or fake remote response was used.",
                    ]
                )
            }
            if scheme == "file" {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .fileURLBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "fileURLFetchBlocked",
                    message: "file: fetch URLs are blocked.",
                    diagnostics: [
                        "The local harness fetch resolver does not read arbitrary file URLs.",
                    ]
                )
            }
            if scheme == "data" {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .dataURLBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "dataURLFetchBlocked",
                    message: "data: fetch URLs are blocked.",
                    diagnostics: [
                        "The local harness does not synthesize responses from data URLs.",
                    ]
                )
            }
            if scheme == "blob" {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .blobURLBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "blobURLFetchBlocked",
                    message: "blob: fetch URLs are blocked.",
                    diagnostics: [
                        "The local harness has no Blob URL store.",
                    ]
                )
            }
            guard scheme == "chrome-extension",
                  components.host == request.extensionID
            else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .unsupportedRequestShape,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: false,
                    blocker: "fetchSchemeOrInputUnsupported",
                    message:
                        "fetch request is not for this extension's generated bundle.",
                    diagnostics: [
                        "Cross-extension and unsupported-scheme fetch requests are blocked.",
                    ]
                )
            }
            guard policy.fetchExtensionLocalExecutionAllowed else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: extensionLocalKind,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "extensionLocalFetchDisabled",
                    message:
                        "Extension-local fetch execution is disabled by policy.",
                    diagnostics: policy.diagnostics
                )
            }
            guard let record = request.generatedBundleRecord else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .missingResource,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "generatedBundleRecordMissing",
                    message:
                        "No generated bundle record is available for fetch resolution.",
                    diagnostics: [
                        "Generated-bundle containment could not be proven.",
                    ]
                )
            }
            let root = URL(
                fileURLWithPath: record.generatedBundleRootPath,
                isDirectory: true
            ).standardizedFileURL
            guard directoryExistsServiceWorkerJS(root) else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .missingResource,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "generatedBundleRootMissing",
                    message: "Generated bundle root is missing.",
                    diagnostics: [
                        "Generated-bundle containment could not be proven.",
                    ]
                )
            }
            let normalized =
                normalizedFetchResourcePathServiceWorkerJS(
                    components.percentEncodedPath
                )
            if let blocker = normalized.blocker {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: blocker,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: blocker.fetchBlockerName,
                    message: normalized.message,
                    diagnostics: [
                        "Fetch path normalization failed before any file read.",
                    ]
                )
            }
            guard let normalizedPath = normalized.path else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .unsupportedRequestShape,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "unsupportedRequestShape",
                    message:
                        "fetch resource path could not be normalized.",
                    diagnostics: [
                        "Fetch path normalization failed before any file read.",
                    ]
                )
            }
            let candidate = root
                .appendingPathComponent(normalizedPath)
                .standardizedFileURL
            guard
                let resolvedRelative = Sumi.relativePathInGeneratedBundle(
                    candidate,
                    root: root
                )
            else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .traversalBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "pathTraversalBlocked",
                    message:
                        "fetch resource path resolves outside the generated bundle root.",
                    diagnostics: [
                        "Generated-bundle containment was required before reading.",
                    ]
                )
            }
            if pathContainsSymbolicLinkServiceWorkerJS(candidate, root: root)
            {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .symlinkEscapeBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "symlinkEscapeBlocked",
                    message:
                        "fetch resource path contains a symbolic link and was rejected.",
                    fetchedResourcePath: resolvedRelative,
                    diagnostics: [
                        "Symlink traversal is not allowed for generated-bundle fetch.",
                    ]
                )
            }
            guard containsServiceWorkerJS(root: root, candidate: candidate)
            else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .traversalBlocked,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "pathTraversalBlocked",
                    message:
                        "fetch resource path resolves outside the generated bundle root after symlink resolution.",
                    fetchedResourcePath: resolvedRelative,
                    diagnostics: [
                        "Generated-bundle containment was required before reading.",
                    ]
                )
            }
            guard record.copiedResourcePaths.contains(resolvedRelative) else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .missingResource,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "notCopiedGeneratedResource",
                    message:
                        "fetch resource is not recorded as a copied generated-bundle resource.",
                    fetchedResourcePath: resolvedRelative,
                    diagnostics: [
                        "Generated-bundle fetch never falls back to arbitrary files under the root.",
                    ]
                )
            }
            guard regularFileExistsServiceWorkerJS(candidate) else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .missingResource,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "missingResource",
                    message:
                        "fetch resource is missing or is not a regular file.",
                    fetchedResourcePath: resolvedRelative,
                    diagnostics: [
                        "Directories and missing paths do not receive synthetic Response bodies.",
                    ]
                )
            }
            guard let data = try? Data(contentsOf: candidate) else {
                return fetchHostFailureResponseServiceWorkerJS(
                    requestKind: .missingResource,
                    resolvedURL: resolvedURL,
                    networkAccessRequired: false,
                    extensionLocalResource: true,
                    blocker: "resourceReadFailed",
                    message:
                        "fetch resource could not be read from the generated bundle.",
                    fetchedResourcePath: resolvedRelative,
                    diagnostics: [
                        "No fallback path was attempted after the generated-bundle read failed.",
                    ]
                )
            }
            let responseBytes = method == "HEAD" ? Data() : data
            let status = 200
            return fetchHostSuccessResponseServiceWorkerJS(
                requestKind: extensionLocalKind,
                resolvedURL: resolvedURL,
                fetchedResourcePath: resolvedRelative,
                sourceByteCount: data.count,
                status: status,
                statusText: "OK",
                headers: [
                    "content-length": "\(data.count)",
                    "content-type":
                        mimeTypeServiceWorkerJS(for: resolvedRelative),
                ],
                bytes: responseBytes,
                diagnostics: uniqueSortedServiceWorkerJS(
                    [
                        inputWasRelative
                            ? "Relative extension fetch resolved against the worker location."
                            : "Extension URL fetch targeted this extension ID.",
                        "Fetch resource was resolved inside the generated bundle root.",
                        "Fetch resource is recorded as a copied generated-bundle resource.",
                        "No network, credential bridge, cache bridge, browser fetch, or arbitrary local file access was used.",
                    ]
                )
            )
        }

        private func evaluateScriptInContext(
            _ source: String,
            sourceURL: URL,
            context: JSContext
        ) -> ChromeMV3ServiceWorkerJSExceptionDetails? {
            let sourceName =
                relativePathInGeneratedBundle(sourceURL)
                ?? sourceURL.lastPathComponent
            let previous = context
                .objectForKeyedSubscript("__sumiCurrentScript")?
                .toString()
            context.setObject(
                sourceName,
                forKeyedSubscript: "__sumiCurrentScript" as NSString
            )
            context.exception = nil
            _ = context.evaluateScript(source, withSourceURL: sourceURL)
            let exceptionDetails = context.exception.map {
                exceptionDetailsServiceWorkerJS(
                    exception: $0,
                    source: source,
                    sourceURL: sourceURL,
                    sourceName: sourceName
                )
            }
            if let previous {
                context.setObject(
                    previous,
                    forKeyedSubscript: "__sumiCurrentScript" as NSString
                )
            } else {
                context.setObject(
                    JSValue(undefinedIn: context),
                    forKeyedSubscript: "__sumiCurrentScript" as NSString
                )
            }
            return exceptionDetails
        }

        private func evaluateImportScripts(
            arguments: JSValue
        ) -> NSDictionary {
            guard let values = arguments.toArray() else {
                return recordFailedImport(
                    requestPath: "<arguments-unavailable>",
                    blocker: .importArgumentNonString,
                    message:
                        "importScripts arguments could not be inspected as a deterministic argument array."
                )
            }
            guard values.isEmpty == false else {
                return ["ok": true]
            }
            guard let context else {
                return recordFailedImport(
                    requestPath: "<context-unavailable>",
                    blocker: .scriptEvaluationFailed,
                    message:
                        "JavaScriptCore context is unavailable during importScripts evaluation."
                )
            }
            for value in values {
                guard let requestPath = value as? String else {
                    return recordFailedImport(
                        requestPath: "<non-string>",
                        blocker: .importArgumentNonString,
                        message:
                            "importScripts accepts only string arguments in the local experimental harness."
                    )
                }
                let loaded = resolveImportScript(requestPath)
                importedScriptRecords.append(loaded.record)
                syncImportRecordsIntoResourceLoad()
                if loaded.record.imported == false {
                    return importFailureResponse(loaded.record)
                }
                guard let source = loaded.source,
                      let sourceURL = loaded.sourceURL
                else {
                    return importFailureResponse(loaded.record)
                }
                importEvaluationStack.append(sourceURL)
                let exceptionDetails = evaluateScriptInContext(
                    source,
                    sourceURL: sourceURL,
                    context: context
                )
                _ = importEvaluationStack.popLast()
                if let exceptionDetails {
                    let failed = appendImportScriptBlocker(
                        .scriptEvaluationFailed,
                        message:
                            "Imported script evaluation failed: \(exceptionDetails.message)"
                    )
                    return importFailureResponse(failed)
                }
            }
            syncImportRecordsIntoResourceLoad()
            return ["ok": true]
        }

        private func evaluateDynamicImportRewrite(
            requestPath: String
        ) -> NSDictionary {
            guard policy
                .dynamicImportRewriteExperimentAvailableInLocalExperimentalGate
            else {
                return recordFailedDynamicImport(
                    requestPath: requestPath,
                    blocker: .dynamicImportExecutionSurfaceUnsupported,
                    message:
                        "Dynamic import rewrite experiment is not enabled for this local scoped harness run."
                )
            }
            guard let context else {
                return recordFailedDynamicImport(
                    requestPath: requestPath,
                    blocker: .scriptEvaluationFailed,
                    message:
                        "JavaScriptCore context is unavailable during dynamic import rewrite evaluation."
                )
            }
            let loaded = resolveDynamicImportModule(requestPath)
            if loaded.record.rewriteEligible == false {
                recordDynamicImport(loaded.record)
                return dynamicImportFailureResponse(loaded.record)
            }
            guard let source = loaded.source,
                  let sourceURL = loaded.sourceURL
            else {
                recordDynamicImport(loaded.record)
                return dynamicImportFailureResponse(loaded.record)
            }
            importEvaluationStack.append(sourceURL)
            let exceptionDetails = evaluateScriptInContext(
                source,
                sourceURL: sourceURL,
                context: context
            )
            _ = importEvaluationStack.popLast()
            var record = loaded.record
            record.rewritten = true
            if let exceptionDetails {
                record.evaluated = false
                record.blockers =
                    uniqueSortedServiceWorkerJS(
                        record.blockers + [.scriptEvaluationFailed]
                    )
                record.diagnostics =
                    uniqueSortedServiceWorkerJS(
                        record.diagnostics
                            + [
                                "Rewritten dynamic import dependency evaluation failed: \(exceptionDetails.message)",
                            ]
                    )
                recordDynamicImport(record)
                return dynamicImportFailureResponse(record)
            }
            record.evaluated = true
            record.evaluationOrder = nextDynamicImportEvaluationOrder
            nextDynamicImportEvaluationOrder += 1
            record.diagnostics =
                uniqueSortedServiceWorkerJS(
                    record.diagnostics
                        + [
                            "Rewritten dynamic import dependency executed inside the same JavaScriptCore context.",
                            "The modeled module namespace is intentionally empty; CommonJS/global side effects and listener registration are the only supported diagnostic effects.",
                        ]
                )
            recordDynamicImport(record)
            return [
                "ok": true,
                "namespace": [:],
            ]
        }

        private func resolveImportScript(
            _ requestPath: String
        ) -> (
            record: ChromeMV3ServiceWorkerJSImportedScriptRecord,
            source: String?,
            sourceURL: URL?
        ) {
            let parentURL = importEvaluationStack.last
            let parentRelative =
                parentURL.flatMap(relativePathInGeneratedBundle)
                    ?? resourceLoadRecord?.serviceWorkerRelativePath
                    ?? "unknown-worker.js"
            let chain = importEvaluationStack.compactMap {
                relativePathInGeneratedBundle($0)
            }
            guard let record = request.generatedBundleRecord else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    chain: chain,
                    blocker: .generatedBundleRecordMissing,
                    message:
                        "No generated bundle record is available for importScripts resolution."
                )
            }
            let root = URL(
                fileURLWithPath: record.generatedBundleRootPath,
                isDirectory: true
            ).standardizedFileURL
            guard directoryExistsServiceWorkerJS(root) else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    chain: chain,
                    blocker: .generatedBundleRootMissing,
                    message:
                        "Generated bundle root is missing for importScripts resolution."
                )
            }
            let authorization = authorizeImportScriptRequest(
                requestPath,
                parentURL: parentURL,
                record: record,
                root: root
            )
            if let blocker = authorization.blocker {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    chain: chain,
                    blocker: blocker,
                    message: authorization.message
                )
            }
            let normalized = normalizeImportScriptsPath(
                requestPath,
                extensionID: request.extensionID
            )
            if let blocker = normalized.blocker {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    chain: chain,
                    blocker: blocker,
                    message: normalized.message
                )
            }
            guard let normalizedPath = normalized.path else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    chain: chain,
                    blocker: .importPathUnsafe,
                    message:
                        "importScripts path could not be normalized safely."
                )
            }
            let parentDirectory =
                isSameExtensionURLServiceWorkerJS(
                    requestPath,
                    extensionID: request.extensionID
                )
                    ? root
                    : (
                        parentURL?
                            .deletingLastPathComponent()
                            .standardizedFileURL ?? root
                    )
            let candidate = parentDirectory
                .appendingPathComponent(normalizedPath)
                .standardizedFileURL
            let resolvedRelative =
                Sumi.relativePathInGeneratedBundle(candidate, root: root)
            guard let resolvedRelative else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    chain: chain,
                    blocker: .importPathEscapesGeneratedBundle,
                    message:
                        "importScripts path resolves outside the generated bundle root."
                )
            }
            if pathContainsSymbolicLinkServiceWorkerJS(
                candidate,
                root: root
            ) {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .importedScriptSymbolicLinkRejected,
                    message:
                        "Imported script path contains a symbolic link and was rejected."
                )
            }
            guard containsServiceWorkerJS(root: root, candidate: candidate)
            else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .importPathEscapesGeneratedBundle,
                    message:
                        "importScripts path resolves outside the generated bundle root."
                )
            }
            if importEvaluationStack.contains(where: {
                $0.standardizedFileURL.path == candidate.path
            }) {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .circularImportBlocked,
                    message:
                        "Circular importScripts dependency was blocked deterministically."
                )
            }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: candidate.path,
                isDirectory: &isDirectory
            )
            guard exists else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .importedScriptMissing,
                    message: "Imported script is missing."
                )
            }
            guard isDirectory.boolValue == false else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .importedScriptDirectoryRejected,
                    message:
                        "importScripts resolved to a directory, not a script file."
                )
            }
            if record.copiedResourcePaths.contains(resolvedRelative) == false {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .importedScriptNotCopiedFromGeneratedBundleRecord,
                    message:
                        "Imported script is not recorded as a copied generated-bundle resource."
                )
            }
            guard let data = try? Data(contentsOf: candidate),
                  let source = String(data: data, encoding: .utf8)
            else {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .importedScriptUTF8Required,
                    message:
                        "Imported script is not valid UTF-8 JavaScript source."
                )
            }
            if containsServiceWorkerJSRegex(
                "(?m)^\\s*import\\s+(?!\\()",
                in: source
            ) {
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: .staticModuleImportUnsupported,
                    message:
                        "Static module import inside imported classic script is unsupported."
                )
            }
            if dynamicImportArgumentSourcesServiceWorkerJS(in: source)
                .isEmpty == false
            {
                let capability =
                    ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe
                    .evaluate()
                let blocker = capability.blockers
                    .compactMap(importScriptsBlockerServiceWorkerJS)
                    .first ?? .dynamicImportUnsupported
                return failedImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    chain: chain,
                    blocker: blocker,
                    message:
                        "Dynamic import inside imported classic script is blocked by \(blocker.rawValue)."
                )
            }
            let order = nextImportEvaluationOrder
            nextImportEvaluationOrder += 1
            return (
                ChromeMV3ServiceWorkerJSImportedScriptRecord(
                    requestPath: requestPath,
                    parentScriptRelativePath: parentRelative,
                    resolvedRelativePath: resolvedRelative,
                    resolvedPath: candidate.path,
                    importChain: chain,
                    imported: true,
                    evaluationOrder: order,
                    sourceSHA256: sha256HexServiceWorkerJS(data),
                    sourceByteCount: data.count,
                    blockers: [],
                    diagnostics: [
                        "Imported script was resolved inside the generated bundle root.",
                        "Imported script is recorded as a copied generated-bundle resource.",
                        "Import order is deterministic and synchronous.",
                        authorization.message,
                    ]
                ),
                source,
                candidate
            )
        }

        private func authorizeImportScriptRequest(
            _ requestPath: String,
            parentURL: URL?,
            record: ChromeMV3GeneratedBundleRecord,
            root: URL
        ) -> (
            blocker: ChromeMV3ServiceWorkerJSImportScriptsBlocker?,
            message: String
        ) {
            guard let parentURL,
                  containsServiceWorkerJS(root: root, candidate: parentURL),
                  let source = try? String(
                    contentsOf: parentURL,
                    encoding: .utf8
                  )
            else {
                return (
                    .computedImportScriptsCandidateSetUnbounded,
                    "importScripts parent source could not be inspected for a statically bounded candidate set."
                )
            }
            let authorization =
                boundedImportScriptsAuthorizationServiceWorkerJS(in: source)
            let matching = authorization.candidateGroups.filter { group in
                group.candidates.contains { candidate in
                    importScriptsRequest(
                        requestPath,
                        matchesCandidate: candidate,
                        parentURL: parentURL,
                        root: root,
                        extensionID: request.extensionID
                    )
                }
            }
            guard matching.isEmpty == false else {
                return (
                    authorization.unboundedExpressionDetected
                        ? .computedImportScriptsRuntimeVariableRejected
                        : .computedImportScriptsCandidateSetUnbounded,
                    authorization.unboundedExpressionDetected
                        ? "Runtime-variable or otherwise unbounded importScripts dependency paths are blocked."
                        : "importScripts dependency path was not present in a statically bounded candidate set."
                )
            }
            for group in matching {
                let rejectedCandidates = group.candidates.filter {
                    generatedBundleContainsImportScriptServiceWorkerJS(
                        $0,
                        parentURL: parentURL,
                        record: record,
                        root: root,
                        extensionID: request.extensionID
                    ) == false
                }
                if group.requiresAllCandidatesContained,
                   rejectedCandidates.isEmpty == false
                {
                    return (
                        .computedImportScriptsConstantMapCandidateUnsafe,
                        "Known constant-map importScripts resolution was blocked because every statically visible candidate was not proven generated-root-contained: \(rejectedCandidates.joined(separator: ", "))."
                    )
                }
                return (
                    nil,
                    group.message
                )
            }
            return (
                .computedImportScriptsCandidateSetUnbounded,
                "importScripts dependency authorization did not find a bounded generated-bundle candidate."
            )
        }

        private func importScriptsRequest(
            _ requestPath: String,
            matchesCandidate candidate: String,
            parentURL: URL,
            root: URL,
            extensionID: String
        ) -> Bool {
            let normalizedRequest = normalizeImportScriptsPath(
                requestPath,
                extensionID: extensionID
            )
            let normalizedCandidate = normalizeImportScriptsPath(
                candidate,
                extensionID: extensionID
            )
            guard normalizedRequest.blocker == nil,
                  normalizedCandidate.blocker == nil,
                  let requestRelative = normalizedRequest.path,
                  let candidateRelative = normalizedCandidate.path
            else {
                return requestPath == candidate
            }
            let parentDirectory = parentURL.deletingLastPathComponent()
                .standardizedFileURL
            let requestBase =
                isSameExtensionURLServiceWorkerJS(
                    requestPath,
                    extensionID: extensionID
                )
                    ? root
                    : parentDirectory
            let candidateBase =
                isSameExtensionURLServiceWorkerJS(
                    candidate,
                    extensionID: extensionID
                )
                    ? root
                    : parentDirectory
            let requestURL = requestBase
                .appendingPathComponent(requestRelative)
                .standardizedFileURL
            let candidateURL = candidateBase
                .appendingPathComponent(candidateRelative)
                .standardizedFileURL
            return requestURL.path == candidateURL.path
        }

        private func resolveDynamicImportModule(
            _ requestPath: String
        ) -> (
            record: ChromeMV3ServiceWorkerJSDynamicImportRecord,
            source: String?,
            sourceURL: URL?
        ) {
            let parentURL = importEvaluationStack.last
            let parentRelative =
                parentURL.flatMap(relativePathInGeneratedBundle)
                    ?? resourceLoadRecord?.serviceWorkerRelativePath
                    ?? "unknown-worker.js"
            guard let record = request.generatedBundleRecord else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    blocker: .generatedBundleRecordMissing,
                    message:
                        "No generated bundle record is available for dynamic import rewrite resolution."
                )
            }
            let root = URL(
                fileURLWithPath: record.generatedBundleRootPath,
                isDirectory: true
            ).standardizedFileURL
            guard directoryExistsServiceWorkerJS(root) else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    blocker: .generatedBundleRootMissing,
                    message:
                        "Generated bundle root is missing for dynamic import rewrite resolution."
                )
            }
            let normalized = normalizeDynamicImportPath(
                requestPath,
                extensionID: request.extensionID
            )
            if let blocker = normalized.blocker {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    blocker: blocker,
                    message: normalized.message
                )
            }
            guard let normalizedPath = normalized.path else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    blocker: .importPathUnsafe,
                    message:
                        "Dynamic import rewrite path could not be normalized safely."
                )
            }
            let parentDirectory =
                isSameExtensionURLServiceWorkerJS(
                    requestPath,
                    extensionID: request.extensionID
                )
                    ? root
                    : (
                        parentURL?
                            .deletingLastPathComponent()
                            .standardizedFileURL ?? root
                    )
            let candidate = parentDirectory
                .appendingPathComponent(normalizedPath)
                .standardizedFileURL
            let resolvedRelative =
                Sumi.relativePathInGeneratedBundle(candidate, root: root)
            guard let resolvedRelative else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedPath: candidate.path,
                    blocker: .importPathEscapesGeneratedBundle,
                    message:
                        "Dynamic import rewrite path resolves outside the generated bundle root."
                )
            }
            if pathContainsSymbolicLinkServiceWorkerJS(
                candidate,
                root: root
            ) {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .importedModuleSymbolicLinkRejected,
                    message:
                        "Dynamic import rewrite path contains a symbolic link and was rejected."
                )
            }
            guard containsServiceWorkerJS(root: root, candidate: candidate)
            else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .importPathEscapesGeneratedBundle,
                    message:
                        "Dynamic import rewrite path resolves outside the generated bundle root after symlink resolution."
                )
            }
            if importEvaluationStack.contains(where: {
                $0.standardizedFileURL.path == candidate.path
            }) {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .circularImportBlocked,
                    message:
                        "Circular dynamic import rewrite dependency was blocked deterministically."
                )
            }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: candidate.path,
                isDirectory: &isDirectory
            )
            guard exists else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .importedModuleMissing,
                    message:
                        "Dynamic import rewrite dependency is missing."
                )
            }
            guard isDirectory.boolValue == false else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .importedModuleDirectoryRejected,
                    message:
                        "Dynamic import rewrite dependency resolved to a directory, not a script file."
                )
            }
            if record.copiedResourcePaths.contains(resolvedRelative) == false {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker:
                        .importedModuleNotCopiedFromGeneratedBundleRecord,
                    message:
                        "Dynamic import rewrite dependency is not recorded as a copied generated-bundle resource."
                )
            }
            guard let data = try? Data(contentsOf: candidate),
                  let source = String(data: data, encoding: .utf8)
            else {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .importedModuleUTF8Required,
                    message:
                        "Dynamic import rewrite dependency is not valid UTF-8 JavaScript source."
                )
            }
            if containsServiceWorkerJSRegex(
                "(?m)^\\s*import\\s+(?!\\()",
                in: source
            ) {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .staticModuleImportUnsupported,
                    message:
                        "Static module import inside a rewritten dynamic dependency is unsupported."
                )
            }
            if containsServiceWorkerJSRegex(
                "(?m)^\\s*export\\s+",
                in: source
            ) {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: .importedModuleSyntaxUnsupported,
                    message:
                        "ES module export syntax inside a rewritten dependency is unsupported by the classic JavaScriptCore harness."
                )
            }
            let nestedRecords = dynamicImportRecordsServiceWorkerJS(
                in: source,
                parentScriptRelativePath: resolvedRelative,
                parentURL: candidate,
                generatedBundleRecord: record,
                generatedBundleRoot: root,
                capability: policy.dynamicImportCapabilityProbe,
                includeCapabilityBlockers: false
            )
            let nestedBlockers = uniqueSortedServiceWorkerJS(
                nestedRecords.flatMap(\.blockers)
            )
            if let blocker = nestedBlockers.first {
                return failedDynamicImport(
                    requestPath: requestPath,
                    parentRelative: parentRelative,
                    resolvedRelative: resolvedRelative,
                    resolvedPath: candidate.path,
                    blocker: blocker,
                    message:
                        "Nested dynamic import rewrite dependency failed validation with \(blocker.rawValue)."
                )
            }
            let transformedSource =
                nestedRecords.isEmpty
                    ? source
                    : rewriteDynamicImportsForHarnessServiceWorkerJS(source)
            return (
                dynamicImportRecordServiceWorkerJS(
                    requestPath: requestPath,
                    parentScriptRelativePath: parentRelative,
                    resolvedRelativePath: resolvedRelative,
                    resolvedPath: candidate.path,
                    stringLiteral: true,
                    generatedBundlePathValidated: true,
                    sourceData: data,
                    blockers: [],
                    diagnostics: [
                        "Dynamic import rewrite dependency was resolved inside the generated bundle root.",
                        "Dynamic import rewrite dependency is recorded as a copied generated-bundle resource.",
                        "Dependency source will be evaluated as classic script in the existing JavaScriptCore context.",
                    ]
                ),
                transformedSource,
                candidate
            )
        }

        private func failedDynamicImport(
            requestPath: String,
            parentRelative: String,
            resolvedRelative: String? = nil,
            resolvedPath: String? = nil,
            blocker: ChromeMV3ServiceWorkerJSDynamicImportBlocker,
            message: String
        ) -> (
            record: ChromeMV3ServiceWorkerJSDynamicImportRecord,
            source: String?,
            sourceURL: URL?
        ) {
            (
                dynamicImportRecordServiceWorkerJS(
                    requestPath: requestPath,
                    parentScriptRelativePath: parentRelative,
                    resolvedRelativePath: resolvedRelative,
                    resolvedPath: resolvedPath,
                    stringLiteral: true,
                    generatedBundlePathValidated: false,
                    sourceData: nil,
                    blockers: [blocker],
                    diagnostics: [message]
                ),
                nil,
                nil
            )
        }

        private func failedImport(
            requestPath: String,
            parentRelative: String,
            resolvedRelative: String? = nil,
            resolvedPath: String? = nil,
            chain: [String],
            blocker: ChromeMV3ServiceWorkerJSImportScriptsBlocker,
            message: String
        ) -> (
            record: ChromeMV3ServiceWorkerJSImportedScriptRecord,
            source: String?,
            sourceURL: URL?
        ) {
            (
                ChromeMV3ServiceWorkerJSImportedScriptRecord(
                    requestPath: requestPath,
                    parentScriptRelativePath: parentRelative,
                    resolvedRelativePath: resolvedRelative,
                    resolvedPath: resolvedPath,
                    importChain: chain,
                    imported: false,
                    evaluationOrder: nil,
                    sourceSHA256: nil,
                    sourceByteCount: nil,
                    blockers: [blocker],
                    diagnostics: [message]
                ),
                nil,
                nil
            )
        }

        private func recordFailedImport(
            requestPath: String,
            blocker: ChromeMV3ServiceWorkerJSImportScriptsBlocker,
            message: String
        ) -> NSDictionary {
            let parentRelative = importEvaluationStack.last
                .flatMap(relativePathInGeneratedBundle)
                ?? resourceLoadRecord?.serviceWorkerRelativePath
                ?? "unknown-worker.js"
            let record = ChromeMV3ServiceWorkerJSImportedScriptRecord(
                requestPath: requestPath,
                parentScriptRelativePath: parentRelative,
                resolvedRelativePath: nil,
                resolvedPath: nil,
                importChain: importEvaluationStack.compactMap {
                    relativePathInGeneratedBundle($0)
                },
                imported: false,
                evaluationOrder: nil,
                sourceSHA256: nil,
                sourceByteCount: nil,
                blockers: [blocker],
                diagnostics: [message]
            )
            importedScriptRecords.append(record)
            syncImportRecordsIntoResourceLoad()
            return importFailureResponse(record)
        }

        @discardableResult
        private func appendImportScriptBlocker(
            _ blocker: ChromeMV3ServiceWorkerJSImportScriptsBlocker,
            message: String
        ) -> ChromeMV3ServiceWorkerJSImportedScriptRecord {
            guard importedScriptRecords.isEmpty == false else {
                let record = ChromeMV3ServiceWorkerJSImportedScriptRecord(
                    requestPath: "<unknown>",
                    parentScriptRelativePath: "unknown-worker.js",
                    resolvedRelativePath: nil,
                    resolvedPath: nil,
                    importChain: [],
                    imported: false,
                    evaluationOrder: nil,
                    sourceSHA256: nil,
                    sourceByteCount: nil,
                    blockers: [blocker],
                    diagnostics: [message]
                )
                importedScriptRecords.append(record)
                syncImportRecordsIntoResourceLoad()
                return record
            }
            var record = importedScriptRecords.removeLast()
            record.imported = false
            record.blockers =
                uniqueSortedServiceWorkerJS(record.blockers + [blocker])
            record.diagnostics =
                uniqueSortedServiceWorkerJS(record.diagnostics + [message])
            importedScriptRecords.append(record)
            syncImportRecordsIntoResourceLoad()
            return record
        }

        private func importFailureResponse(
            _ record: ChromeMV3ServiceWorkerJSImportedScriptRecord
        ) -> NSDictionary {
            let blocker = record.blockers.first ?? .scriptEvaluationFailed
            return [
                "ok": false,
                "blocker": blocker.rawValue,
                "error":
                    record.diagnostics.first
                    ?? "importScripts import failed.",
            ]
        }

        private func recordFailedDynamicImport(
            requestPath: String,
            blocker: ChromeMV3ServiceWorkerJSDynamicImportBlocker,
            message: String
        ) -> NSDictionary {
            let parentRelative = importEvaluationStack.last
                .flatMap(relativePathInGeneratedBundle)
                ?? resourceLoadRecord?.serviceWorkerRelativePath
                ?? "unknown-worker.js"
            let record = dynamicImportRecordServiceWorkerJS(
                requestPath: requestPath,
                parentScriptRelativePath: parentRelative,
                resolvedRelativePath: nil,
                resolvedPath: nil,
                stringLiteral: requestPath != "<non-string>",
                generatedBundlePathValidated: false,
                sourceData: nil,
                blockers: [blocker],
                diagnostics: [message]
            )
            recordDynamicImport(record)
            return dynamicImportFailureResponse(record)
        }

        private func recordDynamicImport(
            _ record: ChromeMV3ServiceWorkerJSDynamicImportRecord
        ) {
            guard var load = resourceLoadRecord else { return }
            let existingIndex = load.dynamicImportRecords.firstIndex {
                $0.requestPath == record.requestPath
                    && $0.parentScriptRelativePath
                        == record.parentScriptRelativePath
                    && $0.resolvedRelativePath == record.resolvedRelativePath
                    && $0.evaluated == false
            }
            if let existingIndex {
                load.dynamicImportRecords[existingIndex] = record
            } else {
                load.dynamicImportRecords.append(record)
            }
            load.dynamicImportBlockers = uniqueSortedServiceWorkerJS(
                load.dynamicImportRecords.flatMap(\.blockers)
            )
            load.dynamicImportRewriteEvaluationCount =
                load.dynamicImportRecords.filter(\.evaluated).count
            resourceLoadRecord = load
        }

        private func dynamicImportFailureResponse(
            _ record: ChromeMV3ServiceWorkerJSDynamicImportRecord
        ) -> NSDictionary {
            let blocker =
                record.blockers.first ?? .dynamicImportExecutionSurfaceUnsupported
            return [
                "ok": false,
                "blocker": blocker.rawValue,
                "error":
                    record.diagnostics.first
                    ?? "Dynamic import rewrite failed.",
            ]
        }

        private func refreshJSSnapshot() {
            guard
                let wire: ChromeMV3ServiceWorkerJSWireSnapshot = callJSON(
                    "__sumiHarness.snapshot()"
                )
            else { return }
            let source =
                resourceLoadRecord?.serviceWorkerRelativePath
                ?? request.manifest.background?.serviceWorker
                ?? "unknown-worker.js"
            capturedListeners = wire.registrations.compactMap { item in
                guard let event =
                    ChromeMV3ServiceWorkerSyntheticListenerEvent(
                        rawValue: item.event
                    )
                else { return nil }
                var modes:
                    [ChromeMV3ServiceWorkerJSListenerResponseMode] = [
                        .syncReturn,
                    ]
                if event == .runtimeOnMessage && item.arity >= 3 {
                    modes.append(.callbackSendResponse)
                }
                if event == .runtimeOnMessage {
                    modes.append(.promiseObservableButDeferred)
                }
                return ChromeMV3ServiceWorkerJSCapturedListenerRegistration(
                    listenerID: item.listenerID,
                    event: event,
                    listenerSourceFile: item.source ?? source,
                    registrationOrder: item.order,
                    listenerArity: item.arity,
                    asyncFunctionDetected: item.asyncFunction,
                    supportedResponseModes:
                        uniqueSortedServiceWorkerJS(modes),
                    diagnostics: [
                        "Registration was captured from executed service-worker JavaScript.",
                        item.asyncFunction
                            ? (
                                event == .runtimeOnMessage
                                    ? "Async runtime.onMessage registration detected; Promise response completion remains diagnostic-only."
                                    : "Async fire-and-forget event registration detected; returned Promise completion is not used as the event response."
                            )
                            : "Listener function registration captured.",
                    ]
                )
            }
            .sorted {
                if $0.registrationOrder != $1.registrationOrder {
                    return $0.registrationOrder < $1.registrationOrder
                }
                return $0.listenerID < $1.listenerID
            }
            blockedUnsupportedCalls =
                uniqueSortedServiceWorkerJS(wire.blockedCalls)
            cryptoOperationRecords = wire.cryptoOperations.map {
                ChromeMV3ServiceWorkerJSCryptoOperationRecord(
                    operation: $0.operation,
                    algorithm: $0.algorithm,
                    byteCount: $0.byteCount,
                    status: $0.status,
                    blocker: $0.blocker,
                    diagnostics: $0.diagnostics
                )
            }
            i18nOperationRecords = wire.i18nOperations
            workerGlobalEventRecords = wire.workerGlobalEvents
            fetchClassificationRecords = wire.fetchClassifications
            webAssemblyCapability = wire.webAssemblyCapability
            ports = Dictionary(
                uniqueKeysWithValues:
                    wire.ports.map {
                        (
                            $0.portID,
                            ChromeMV3ServiceWorkerJSPortRecord(
                                portID: $0.portID,
                                name: $0.name,
                                sender: $0.sender
                                    .serviceWorkerJSSenderMetadata,
                                nativeFixturePort: $0.nativeFixturePort,
                                connected: $0.connected,
                                onMessageListenerCount:
                                    $0.onMessageListenerCount,
                                onDisconnectListenerCount:
                                    $0.onDisconnectListenerCount,
                                postedMessages: $0.outbox,
                                disconnectReason: $0.disconnectReason,
                                diagnostics: [
                                    "Port state exists only inside the explicit local experimental harness.",
                                ]
                            )
                        )
                    }
            )
            timers = wire.timers.sorted { $0.timerID < $1.timerID }
        }

        private func callJSON<T: Decodable>(_ expression: String) -> T? {
            guard let context else { return nil }
            context.exception = nil
            guard
                let json = context.evaluateScript(
                    "JSON.stringify(\(expression))"
                )?.toString(),
                context.exception == nil,
                let data = json.data(using: .utf8)
            else {
                return nil
            }
            return try? JSONDecoder().decode(T.self, from: data)
        }
    #endif

    private static let captureEvents:
        [ChromeMV3ServiceWorkerSyntheticListenerEvent] = [
            .runtimeOnMessage,
            .runtimeOnConnect,
            .runtimeOnInstalled,
            .runtimeOnMessageExternal,
            .runtimeOnStartup,
            .runtimeOnUpdateAvailable,
            .storageOnChanged,
            .permissionsOnAdded,
            .permissionsOnRemoved,
            .alarmsOnAlarm,
            .commandsOnCommand,
            .contextMenusOnClicked,
            .tabsOnRemoved,
            .tabsOnUpdated,
            .webNavigationOnBeforeNavigate,
            .webNavigationOnCommitted,
            .webNavigationOnCompleted,
            .webNavigationOnDOMContentLoaded,
            .webNavigationOnErrorOccurred,
            .webNavigationOnHistoryStateUpdated,
            .webNavigationOnReferenceFragmentUpdated,
            .webRequestOnAuthRequired,
            .webRequestOnBeforeRequest,
            .webRequestOnBeforeSendHeaders,
            .webRequestOnCompleted,
            .webRequestOnErrorOccurred,
            .webRequestOnHeadersReceived,
            .webRequestOnResponseStarted,
            .webRequestOnSendHeaders,
            .nativePortOnMessage,
            .nativePortOnDisconnect,
        ]

    private static let registrationShim = #"""
    (() => {
      'use strict';
      const registrations = [];
      const blockedCalls = [];
      const cryptoOperations = [];
      const i18nOperations = [];
      const workerGlobalEvents = [];
      const fetchClassifications = [];
      const ports = new Map();
      const asyncCompletions = [];
      const timers = new Map();
      const pendingTimeoutIDs = [];
      let registrationOrder = 0;
      let nextTimerID = 1;
      let fetchCallIndex = 0;
      const workerConfig = globalThis.__sumiWorkerGlobalConfig || {};
      const extensionID = String(workerConfig.extensionID || '');
      const extensionOrigin = String(workerConfig.extensionOrigin || `chrome-extension://${extensionID || 'extension'}`);
      const uiLanguage = String(workerConfig.uiLanguage || 'en-US');
      const uiLanguageSource = String(workerConfig.uiLanguageSource || 'deterministicFallback');
      const manifestSnapshot = workerConfig.manifest || { manifest_version: 3 };
      const webAssemblyCapability = (() => {
        const wasm = globalThis.WebAssembly;
        const globalPresent = typeof wasm === 'object' && wasm !== null;
        return {
          globalPresent,
          instantiatePresent: globalPresent && typeof wasm.instantiate === 'function',
          instantiateStreamingPresent: globalPresent && typeof wasm.instantiateStreaming === 'function',
          compilePresent: globalPresent && typeof wasm.compile === 'function',
          diagnostics: [
            globalPresent
              ? 'WebAssembly global is present on the JavaScriptCore surface.'
              : 'WebAssembly global is absent on the JavaScriptCore surface.',
            globalPresent && typeof wasm.instantiateStreaming === 'function'
              ? 'WebAssembly.instantiateStreaming is available when a modeled Response has application/wasm.'
              : 'WebAssembly.instantiateStreaming is not available; package code must use its arrayBuffer fallback if present.'
          ]
        };
      })();
      const defineWorkerGlobal = (name, value) => {
        if (typeof globalThis[name] !== 'undefined') return;
        Object.defineProperty(globalThis, name, {
          value,
          enumerable: true,
          configurable: false,
          writable: false
        });
      };
      globalThis.self = globalThis;
      if (typeof globalThis.WorkerGlobalScope !== 'function') {
        function SumiWorkerGlobalScope() {
          throw new TypeError('Illegal constructor');
        }
        if (typeof Symbol === 'function' && Symbol.hasInstance) {
          Object.defineProperty(SumiWorkerGlobalScope, Symbol.hasInstance, {
            value(value) { return value === globalThis; }
          });
        }
        defineWorkerGlobal('WorkerGlobalScope', SumiWorkerGlobalScope);
        defineWorkerGlobal('ServiceWorkerGlobalScope', SumiWorkerGlobalScope);
      }
      if (typeof globalThis.DOMException !== 'function') {
        const domExceptionCodes = {
          IndexSizeError: 1,
          DOMStringSizeError: 2,
          HierarchyRequestError: 3,
          WrongDocumentError: 4,
          InvalidCharacterError: 5,
          NoDataAllowedError: 6,
          NoModificationAllowedError: 7,
          NotFoundError: 8,
          NotSupportedError: 9,
          InUseAttributeError: 10,
          InvalidStateError: 11,
          SyntaxError: 12,
          InvalidModificationError: 13,
          NamespaceError: 14,
          InvalidAccessError: 15,
          ValidationError: 16,
          TypeMismatchError: 17,
          SecurityError: 18,
          NetworkError: 19,
          AbortError: 20,
          URLMismatchError: 21,
          QuotaExceededError: 22,
          TimeoutError: 23,
          InvalidNodeTypeError: 24,
          DataCloneError: 25
        };
        class SumiDOMException extends Error {
          constructor(message = '', name = 'Error') {
            super(String(message));
            this.name = String(name);
            this.code = domExceptionCodes[this.name] || 0;
          }
        }
        for (const [name, code] of Object.entries(domExceptionCodes)) {
          const constant = name
            .replace(/([a-z0-9])([A-Z])/g, '$1_$2')
            .toUpperCase()
            .replace(/ERROR$/, 'ERR');
          Object.defineProperty(SumiDOMException, constant, { value: code });
          Object.defineProperty(SumiDOMException.prototype, constant, { value: code });
        }
        defineWorkerGlobal('DOMException', SumiDOMException);
      }
      const workerGlobalEventListeners = new Map();
      const supportedWorkerGlobalEventTypes = new Set([
        'activate',
        'error',
        'fetch',
        'install',
        'message',
        'unhandledrejection'
      ]);
      const workerGlobalListenerList = (type) => {
        const eventType = String(type);
        if (!workerGlobalEventListeners.has(eventType)) {
          workerGlobalEventListeners.set(eventType, []);
        }
        return workerGlobalEventListeners.get(eventType);
      };
      const workerGlobalEventSnapshot = (operation, type, dispatchCount = 0, defaultPrevented = false, blocked = false, diagnostics = []) => {
        const eventType = String(type || '');
        workerGlobalEvents.push({
          operation,
          eventType,
          listenerCount: workerGlobalListenerList(eventType).length,
          dispatchListenerCount: dispatchCount,
          defaultPrevented: defaultPrevented === true,
          blocked: blocked === true,
          diagnostics: diagnostics.map((value) => String(value))
        });
      };
      const normalizeWorkerGlobalListenerOptions = (options) => ({
        once: options && typeof options === 'object'
          ? options.once === true
          : false
      });
      const invokeWorkerGlobalListener = (entry, event) => {
        if (typeof entry.listener === 'function') {
          entry.listener.call(globalThis, event);
          return;
        }
        if (entry.listener && typeof entry.listener.handleEvent === 'function') {
          entry.listener.handleEvent(event);
          return;
        }
        throw new TypeError('Worker-global listener is not callable.');
      };
      const makeWorkerGlobalEvent = (input) => {
        const source = input && typeof input === 'object' ? input : {};
        const type = String(source.type || input || '');
        if (!type) throw new TypeError('dispatchEvent requires an event object with a non-empty type.');
        let defaultPrevented = source.defaultPrevented === true;
        let immediateStopped = false;
        let propagationStopped = false;
        const event = Object.create(source);
        Object.defineProperties(event, {
          type: { value: type, enumerable: true },
          target: { value: globalThis, enumerable: true },
          currentTarget: { value: globalThis, enumerable: true },
          defaultPrevented: { get() { return defaultPrevented; }, enumerable: true },
          cancelable: { value: source.cancelable === true, enumerable: true },
          preventDefault: {
            value() {
              if (event.cancelable) defaultPrevented = true;
            }
          },
          stopPropagation: {
            value() { propagationStopped = true; }
          },
          stopImmediatePropagation: {
            value() {
              propagationStopped = true;
              immediateStopped = true;
            }
          },
          __sumiImmediateStopped: { get() { return immediateStopped; } },
          __sumiPropagationStopped: { get() { return propagationStopped; } }
        });
        return event;
      };
      defineWorkerGlobal('addEventListener', (type, listener, options) => {
        const eventType = String(type || '');
        if (!eventType || !(typeof listener === 'function'
            || (listener && typeof listener.handleEvent === 'function'))) {
          noteBlocked(`globalThis.addEventListener.${eventType || 'invalid'}`);
          workerGlobalEventSnapshot(
            'addEventListener',
            eventType,
            0,
            false,
            true,
            ['Only non-empty event types and callable listeners are accepted by the worker-global EventTarget model.']
          );
          return;
        }
        const listeners = workerGlobalListenerList(eventType);
        if (!listeners.some((entry) => entry.listener === listener)) {
          listeners.push({
            listener,
            options: normalizeWorkerGlobalListenerOptions(options)
          });
        }
        workerGlobalEventSnapshot(
          'addEventListener',
          eventType,
          0,
          false,
          false,
          [
            supportedWorkerGlobalEventTypes.has(eventType)
              ? 'Registered a supported service-worker global event type.'
              : 'Registered an extension-observed worker-global event type for diagnostics; dispatch remains explicit only.',
            'No DOM Window or document object is exposed.'
          ]
        );
      });
      defineWorkerGlobal('removeEventListener', (type, listener) => {
        const eventType = String(type || '');
        const listeners = workerGlobalListenerList(eventType);
        const before = listeners.length;
        for (let index = listeners.length - 1; index >= 0; index -= 1) {
          if (listeners[index].listener === listener) listeners.splice(index, 1);
        }
        workerGlobalEventSnapshot(
          'removeEventListener',
          eventType,
          0,
          false,
          false,
          [before === listeners.length ? 'No matching worker-global listener was registered.' : 'Removed worker-global listener.']
        );
      });
      defineWorkerGlobal('dispatchEvent', (input) => {
        const event = makeWorkerGlobalEvent(input);
        const listeners = [...workerGlobalListenerList(event.type)];
        let blocked = false;
        const diagnostics = [
          'dispatchEvent runs synchronously inside the explicit local experimental harness only.',
          event.type === 'fetch'
            ? 'fetch event dispatch does not enable request interception or network access.'
            : 'No browser event loop, DOM Window, or document is created.'
        ];
        for (const entry of listeners) {
          try { invokeWorkerGlobalListener(entry, event); }
          catch (error) {
            blocked = true;
            noteBlocked(`globalThis.dispatchEvent.${event.type}.listenerError`);
            diagnostics.push(String(error && error.message ? error.message : error));
          }
          if (entry.options.once) {
            const current = workerGlobalListenerList(event.type);
            const index = current.indexOf(entry);
            if (index >= 0) current.splice(index, 1);
          }
          if (event.__sumiImmediateStopped) break;
        }
        workerGlobalEventSnapshot(
          'dispatchEvent',
          event.type,
          listeners.length,
          event.defaultPrevented,
          blocked,
          diagnostics
        );
        if (blocked) return false;
        return !event.defaultPrevented;
      });
      defineWorkerGlobal('navigator', Object.freeze({
        appCodeName: 'Mozilla',
        appName: 'Netscape',
        appVersion: '5.0',
        hardwareConcurrency: 1,
        onLine: true,
        platform: 'MacIntel',
        product: 'Gecko',
        userAgent: String(workerConfig.userAgent || 'Sumi local experimental MV3 service-worker harness')
      }));
      const locationHref = String(workerConfig.locationHref || `${extensionOrigin}/background.js`);
      const locationPathname = String(workerConfig.locationPathname || '/background.js');
      defineWorkerGlobal('location', Object.freeze({
        href: locationHref,
        origin: extensionOrigin,
        protocol: 'chrome-extension:',
        host: extensionID,
        hostname: extensionID,
        port: '',
        pathname: locationPathname,
        search: '',
        hash: '',
        toString() { return this.href; }
      }));
      const base64Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      if (typeof globalThis.btoa !== 'function') {
        defineWorkerGlobal('btoa', (input) => {
          const text = String(input);
          let output = '';
          for (let block = 0, charCode, index = 0, map = base64Alphabet;
               text.charAt(index | 0) || (map = '=', index % 1);
               output += map.charAt(63 & block >> 8 - index % 1 * 8)) {
            charCode = text.charCodeAt(index += 3 / 4);
            if (charCode > 0xff) throw new DOMException('The string contains characters outside Latin1.', 'InvalidCharacterError');
            block = block << 8 | charCode;
          }
          return output;
        });
      }
      if (typeof globalThis.atob !== 'function') {
        defineWorkerGlobal('atob', (input) => {
          const text = String(input).replace(/=+$/, '');
          if (text.length % 4 === 1 || /[^+/0-9A-Za-z]/.test(text)) {
            throw new DOMException('The string is not correctly encoded.', 'InvalidCharacterError');
          }
          let output = '';
          for (let bc = 0, bs = 0, buffer, index = 0;
               buffer = text.charAt(index++);
               ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
                 bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
            buffer = base64Alphabet.indexOf(buffer);
          }
          return output;
        });
      }
      if (typeof globalThis.TextEncoder !== 'function') {
        defineWorkerGlobal('TextEncoder', class TextEncoder {
          get encoding() { return 'utf-8'; }
          encode(input = '') {
            const bytes = [];
            for (const char of String(input)) {
              const point = char.codePointAt(0);
              if (point <= 0x7f) bytes.push(point);
              else if (point <= 0x7ff) bytes.push(0xc0 | point >> 6, 0x80 | point & 0x3f);
              else if (point <= 0xffff) bytes.push(0xe0 | point >> 12, 0x80 | point >> 6 & 0x3f, 0x80 | point & 0x3f);
              else bytes.push(0xf0 | point >> 18, 0x80 | point >> 12 & 0x3f, 0x80 | point >> 6 & 0x3f, 0x80 | point & 0x3f);
            }
            return new Uint8Array(bytes);
          }
        });
      }
      if (typeof globalThis.TextDecoder !== 'function') {
        defineWorkerGlobal('TextDecoder', class TextDecoder {
          constructor(label = 'utf-8') {
            if (!/^utf-?8$/i.test(String(label))) {
              throw new RangeError('The local harness TextDecoder supports utf-8 only.');
            }
            this.encoding = 'utf-8';
            this.fatal = false;
            this.ignoreBOM = false;
          }
          decode(input = new Uint8Array()) {
            const bytes = input instanceof Uint8Array
              ? input
              : input instanceof ArrayBuffer
                ? new Uint8Array(input)
                : new Uint8Array(input.buffer, input.byteOffset || 0, input.byteLength);
            let output = '';
            for (let index = 0; index < bytes.length;) {
              const first = bytes[index++];
              if (first < 0x80) {
                output += String.fromCodePoint(first);
              } else if (first >= 0xc0 && first < 0xe0 && index < bytes.length) {
                output += String.fromCodePoint(((first & 0x1f) << 6) | (bytes[index++] & 0x3f));
              } else if (first >= 0xe0 && first < 0xf0 && index + 1 < bytes.length) {
                output += String.fromCodePoint(((first & 0x0f) << 12) | ((bytes[index++] & 0x3f) << 6) | (bytes[index++] & 0x3f));
              } else if (first >= 0xf0 && index + 2 < bytes.length) {
                output += String.fromCodePoint(((first & 0x07) << 18) | ((bytes[index++] & 0x3f) << 12) | ((bytes[index++] & 0x3f) << 6) | (bytes[index++] & 0x3f));
              } else {
                output += '\ufffd';
              }
            }
            return output;
          }
        });
      }
      const decodeParam = (value) => decodeURIComponent(String(value).replace(/\+/g, ' '));
      const encodeParam = (value) => encodeURIComponent(String(value)).replace(/%20/g, '+');
      if (typeof globalThis.URLSearchParams !== 'function') {
        defineWorkerGlobal('URLSearchParams', class URLSearchParams {
          constructor(init = '') {
            this._pairs = [];
            if (typeof init === 'string') {
              const text = init.startsWith('?') ? init.slice(1) : init;
              if (text) {
                for (const pair of text.split('&')) {
                  if (!pair) continue;
                  const index = pair.indexOf('=');
                  this.append(
                    decodeParam(index >= 0 ? pair.slice(0, index) : pair),
                    decodeParam(index >= 0 ? pair.slice(index + 1) : '')
                  );
                }
              }
            } else if (Array.isArray(init)) {
              for (const pair of init) this.append(pair[0], pair[1]);
            } else if (init && typeof init === 'object') {
              for (const key of Object.keys(init)) this.append(key, init[key]);
            }
          }
          append(name, value) { this._pairs.push([String(name), String(value)]); }
          delete(name) { this._pairs = this._pairs.filter((pair) => pair[0] !== String(name)); }
          get(name) {
            const pair = this._pairs.find((item) => item[0] === String(name));
            return pair ? pair[1] : null;
          }
          has(name) { return this._pairs.some((pair) => pair[0] === String(name)); }
          set(name, value) {
            const key = String(name);
            this.delete(key);
            this.append(key, value);
          }
          entries() { return this._pairs[Symbol.iterator](); }
          keys() { return this._pairs.map((pair) => pair[0])[Symbol.iterator](); }
          values() { return this._pairs.map((pair) => pair[1])[Symbol.iterator](); }
          forEach(callback, thisArg) {
            for (const [key, value] of this._pairs) callback.call(thisArg, value, key, this);
          }
          toString() {
            return this._pairs.map(([key, value]) => `${encodeParam(key)}=${encodeParam(value)}`).join('&');
          }
          [Symbol.iterator]() { return this.entries(); }
        });
      }
      if (typeof globalThis.URL !== 'function') {
        defineWorkerGlobal('URL', class URL {
          constructor(input, base) {
            const resolved = URL._resolve(String(input), base === undefined ? undefined : String(base));
            Object.defineProperty(this, '_href', { value: resolved.href, writable: true });
            this.protocol = resolved.protocol;
            this.host = resolved.host;
            this.hostname = resolved.hostname;
            this.port = resolved.port;
            this.pathname = resolved.pathname;
            this.search = resolved.search;
            this.hash = resolved.hash;
            this.origin = resolved.origin;
            this.searchParams = new URLSearchParams(this.search);
          }
          get href() { return this._href; }
          set href(value) {
            const next = new URL(value);
            Object.assign(this, next);
            this._href = next.href;
          }
          toString() { return this.href; }
          toJSON() { return this.href; }
          static _resolve(input, base) {
            let text = input.trim();
            if (!/^[A-Za-z][A-Za-z0-9+.-]*:/.test(text)) {
              const baseURL = base ? new URL(base) : null;
              if (!baseURL) throw new TypeError('Invalid URL');
              if (text.startsWith('/')) text = `${baseURL.origin}${text}`;
              else {
                const directory = baseURL.pathname.replace(/[^/]*$/, '');
                text = `${baseURL.origin}${directory}${text}`;
              }
            }
            const match = text.match(/^([A-Za-z][A-Za-z0-9+.-]*:)(?:\/\/([^/?#]*))?([^?#]*)(\?[^#]*)?(#.*)?$/);
            if (!match) throw new TypeError('Invalid URL');
            const protocol = match[1];
            const authority = match[2] || '';
            const path = match[3] || '/';
            const search = match[4] || '';
            const hash = match[5] || '';
            const hostParts = authority.split(':');
            const hostname = hostParts[0] || '';
            const port = hostParts.length > 1 ? hostParts.slice(1).join(':') : '';
            const origin = authority ? `${protocol}//${authority}` : 'null';
            return {
              href: `${protocol}//${authority}${path || '/'}${search}${hash}`,
              protocol,
              host: authority,
              hostname,
              port,
              pathname: path || '/',
              search,
              hash,
              origin
            };
          }
        });
      }
      if (typeof globalThis.crypto !== 'object' || globalThis.crypto === null) {
        const cryptoHostError = (message) => new DOMException(String(message), 'OperationError');
        const recordCryptoOperation = (operation, algorithm, byteCount, status, blocker, diagnostics = []) => {
          cryptoOperations.push({
            operation: String(operation),
            algorithm: algorithm ? String(algorithm) : null,
            byteCount: Number.isFinite(byteCount) ? Number(byteCount) : null,
            status: String(status),
            blocker: blocker ? String(blocker) : null,
            diagnostics: diagnostics.map((value) => String(value))
          });
        };
        const algorithmName = (algorithm) => {
          if (typeof algorithm === 'string') return algorithm;
          if (algorithm && typeof algorithm.name === 'string') return algorithm.name;
          return null;
        };
        const normalizeDigestAlgorithm = (algorithm) => {
          const name = algorithmName(algorithm);
          if (!name) return null;
          const normalized = String(name).trim().toUpperCase().replace(/_/g, '-');
          if (normalized === 'SHA-1' || normalized === 'SHA1') return 'SHA-1';
          if (normalized === 'SHA-256' || normalized === 'SHA256') return 'SHA-256';
          if (normalized === 'SHA-384' || normalized === 'SHA384') return 'SHA-384';
          if (normalized === 'SHA-512' || normalized === 'SHA512') return 'SHA-512';
          return null;
        };
        const bufferSourceBytes = (data) => {
          if (data instanceof ArrayBuffer) return new Uint8Array(data);
          if (ArrayBuffer.isView(data)) {
            return new Uint8Array(data.buffer, data.byteOffset || 0, data.byteLength);
          }
          throw new TypeError('SubtleCrypto.digest requires an ArrayBuffer or ArrayBufferView.');
        };
        const unsupportedSubtleAlgorithmName = (method, args) => {
          if (method === 'importKey') return algorithmName(args[2]);
          if (method === 'exportKey') return String(args[0] || '');
          return algorithmName(args[0]);
        };
        const unsupportedSubtleMethod = (method) => function (...args) {
          const name = unsupportedSubtleAlgorithmName(method, args);
          recordCryptoOperation(
            `subtle.${method}`,
            name,
            null,
            'blocked',
            'unsupportedMethod',
            [
              'SubtleCrypto method is outside the digest-only local experimental MV3 slice.',
              'No dummy keys, signatures, ciphertexts, or derived bits are returned.'
            ]
          );
          return Promise.reject(new DOMException(
            `SubtleCrypto.${method} is not supported by the digest-only local experimental MV3 service-worker harness.`,
            'NotSupportedError'
          ));
        };
        const subtle = Object.freeze({
          digest(algorithm, data) {
            try {
              const normalized = normalizeDigestAlgorithm(algorithm);
              const bytes = bufferSourceBytes(data);
              if (!normalized) {
                const requested = algorithmName(algorithm) || 'unknown';
                recordCryptoOperation(
                  'subtle.digest',
                  requested,
                  bytes.byteLength,
                  'blocked',
                  'unsupportedAlgorithm',
                  ['Unsupported digest algorithm rejected deterministically.']
                );
                return Promise.reject(new DOMException(
                  `SubtleCrypto.digest unsupported algorithm: ${requested}.`,
                  'NotSupportedError'
                ));
              }
              if (typeof globalThis.__sumiCryptoDigestHost !== 'function') {
                recordCryptoOperation(
                  'subtle.digest',
                  normalized,
                  bytes.byteLength,
                  'blocked',
                  'hostUnavailable',
                  ['Native digest host is unavailable.']
                );
                return Promise.reject(cryptoHostError('SubtleCrypto.digest host is unavailable.'));
              }
              const result = globalThis.__sumiCryptoDigestHost(normalized, Array.from(bytes));
              if (!result || result.ok !== true) {
                recordCryptoOperation(
                  'subtle.digest',
                  normalized,
                  bytes.byteLength,
                  'blocked',
                  'hostUnavailable',
                  ['Native digest host rejected the request.']
                );
                return Promise.reject(cryptoHostError(result && result.error
                  ? String(result.error)
                  : 'SubtleCrypto.digest host failed.'));
              }
              const output = Uint8Array.from(Array.from(result.bytes || []));
              recordCryptoOperation(
                'subtle.digest',
                String(result.algorithm || normalized),
                bytes.byteLength,
                'fulfilled',
                null,
                ['Digest fulfilled with native CryptoKit-backed bytes; input material is not recorded.']
              );
              return Promise.resolve(output.buffer);
            } catch (error) {
              recordCryptoOperation(
                'subtle.digest',
                algorithmName(algorithm),
                null,
                'blocked',
                'invalidInput',
                ['Digest rejected invalid BufferSource or algorithm input.']
              );
              return Promise.reject(error);
            }
          },
          decrypt: unsupportedSubtleMethod('decrypt'),
          deriveBits: unsupportedSubtleMethod('deriveBits'),
          deriveKey: unsupportedSubtleMethod('deriveKey'),
          encrypt: unsupportedSubtleMethod('encrypt'),
          exportKey: unsupportedSubtleMethod('exportKey'),
          generateKey: unsupportedSubtleMethod('generateKey'),
          importKey: unsupportedSubtleMethod('importKey'),
          sign: unsupportedSubtleMethod('sign'),
          unwrapKey: unsupportedSubtleMethod('unwrapKey'),
          verify: unsupportedSubtleMethod('verify'),
          wrapKey: unsupportedSubtleMethod('wrapKey')
        });
        defineWorkerGlobal('crypto', Object.freeze({
          getRandomValues(array) {
            const valid =
              array instanceof Int8Array || array instanceof Uint8Array
              || array instanceof Uint8ClampedArray || array instanceof Int16Array
              || array instanceof Uint16Array || array instanceof Int32Array
              || array instanceof Uint32Array
              || (typeof BigInt64Array !== 'undefined' && array instanceof BigInt64Array)
              || (typeof BigUint64Array !== 'undefined' && array instanceof BigUint64Array);
            if (!valid) throw new TypeError('Expected an integer typed array.');
            if (array.byteLength > 65536) {
              throw new DOMException('getRandomValues byte length exceeds 65536.', 'QuotaExceededError');
            }
            if (typeof globalThis.__sumiCryptoGetRandomValuesHost !== 'function') {
              recordCryptoOperation(
                'getRandomValues',
                null,
                array.byteLength,
                'blocked',
                'hostUnavailable',
                ['Secure random host is unavailable.']
              );
              throw cryptoHostError('crypto.getRandomValues host is unavailable.');
            }
            const result = globalThis.__sumiCryptoGetRandomValuesHost(array.byteLength);
            if (!result || result.ok !== true) {
              recordCryptoOperation(
                'getRandomValues',
                null,
                array.byteLength,
                'blocked',
                'secureRandomUnavailable',
                ['Security.framework secure random bytes were unavailable.']
              );
              throw cryptoHostError(result && result.error
                ? String(result.error)
                : 'crypto.getRandomValues host failed.');
            }
            const bytes = Array.from(result.bytes || []);
            const view = new Uint8Array(array.buffer, array.byteOffset, array.byteLength);
            for (let index = 0; index < view.length; index += 1) {
              view[index] = Number(bytes[index]) & 0xff;
            }
            recordCryptoOperation(
              'getRandomValues',
              null,
              array.byteLength,
              'fulfilled',
              null,
              ['Secure random bytes came from the native Security.framework host and were not recorded.']
            );
            return array;
          },
          randomUUID() {
            if (typeof globalThis.__sumiCryptoRandomUUIDHost !== 'function') {
              recordCryptoOperation(
                'randomUUID',
                null,
                16,
                'blocked',
                'hostUnavailable',
                ['Secure UUID host is unavailable.']
              );
              throw cryptoHostError('crypto.randomUUID host is unavailable.');
            }
            const result = globalThis.__sumiCryptoRandomUUIDHost();
            if (!result || result.ok !== true || typeof result.uuid !== 'string') {
              recordCryptoOperation(
                'randomUUID',
                null,
                16,
                'blocked',
                'secureRandomUnavailable',
                ['Security.framework secure random bytes were unavailable for UUID generation.']
              );
              throw cryptoHostError(result && result.error
                ? String(result.error)
                : 'crypto.randomUUID host failed.');
            }
            recordCryptoOperation(
              'randomUUID',
              null,
              16,
              'fulfilled',
              null,
              ['UUID v4 was generated from native secure random bytes; random bytes are not recorded.']
            );
            return result.uuid;
          },
          subtle
        }));
      }
      if (typeof globalThis.queueMicrotask !== 'function') {
        defineWorkerGlobal('queueMicrotask', (callback) => {
          if (typeof callback !== 'function') {
            throw new TypeError('queueMicrotask callback must be a function.');
          }
          Promise.resolve().then(callback);
        });
      }

      const clone = (value) => {
        if (value === undefined) return null;
        try { return JSON.parse(JSON.stringify(value)); }
        catch (_) { return null; }
      };
      const noteBlocked = (path) => {
        if (!blockedCalls.includes(path)) blockedCalls.push(path);
      };
      let runtimeLastErrorValue;
      const invokeCallbackNow = (callback, errorMessage, ...values) => {
        if (typeof callback !== 'function') return;
        runtimeLastErrorValue = errorMessage == null
          ? undefined
          : Object.freeze({ message: String(errorMessage) });
        try {
          callback(...values);
        } finally {
          runtimeLastErrorValue = undefined;
        }
      };
      const callbackLater = (callback, ...values) => {
        if (typeof callback === 'function') {
          Promise.resolve().then(() => invokeCallbackNow(callback, null, ...values));
        }
      };
      const callbackErrorLater = (callback, errorMessage, ...values) => {
        if (typeof callback === 'function') {
          Promise.resolve().then(() => invokeCallbackNow(callback, errorMessage, ...values));
        }
      };
      const unsupported = (path) => new Proxy(function () {
        noteBlocked(path);
        return undefined;
      }, {
        get(_target, property) {
          if (property === 'then') return undefined;
          return unsupported(`${path}.${String(property)}`);
        },
        apply(_target, _thisArg, args) {
          noteBlocked(path);
          const callback = args.length ? args[args.length - 1] : undefined;
          callbackErrorLater(callback, `Unsupported API call ${path}.`);
          return undefined;
        }
      });
      const event = (eventName) => ({
        addListener(listener) {
          if (typeof listener !== 'function') {
            noteBlocked(`${eventName}.addListener.nonFunction`);
            return;
          }
          registrationOrder += 1;
          const listenerID = `js-listener-${registrationOrder}-${eventName}`;
          registrations.push({
            listenerID,
            event: eventName,
            order: registrationOrder,
            arity: listener.length,
            asyncFunction: listener.constructor
              && listener.constructor.name === 'AsyncFunction',
            source: globalThis.__sumiCurrentScript || null,
            listener
          });
        },
        removeListener(listener) {
          const index = registrations.findIndex((item) =>
            item.event === eventName && item.listener === listener);
          if (index >= 0) registrations.splice(index, 1);
        },
        hasListener(listener) {
          return registrations.some((item) =>
            item.event === eventName && item.listener === listener);
        }
      });
      const localEvent = () => {
        const listeners = [];
        return {
          addListener(listener) {
            if (typeof listener === 'function') listeners.push(listener);
          },
          removeListener(listener) {
            const index = listeners.indexOf(listener);
            if (index >= 0) listeners.splice(index, 1);
          },
          listeners
        };
      };
      const storageStores = {
        local: Object.create(null),
        sync: Object.create(null),
        session: Object.create(null),
        managed: Object.create(null)
      };
      const storageKeys = (keys, store) => {
        if (keys == null) return Object.keys(store);
        if (typeof keys === 'string') return [keys];
        if (Array.isArray(keys)) return keys.map((key) => String(key));
        if (typeof keys === 'object') return Object.keys(keys);
        return [];
      };
      const storageGet = (keys, store) => {
        const result = {};
        if (keys == null) {
          for (const key of Object.keys(store)) result[key] = clone(store[key]);
          return result;
        }
        if (typeof keys === 'string') {
          if (Object.prototype.hasOwnProperty.call(store, keys)) {
            result[keys] = clone(store[keys]);
          }
          return result;
        }
        if (Array.isArray(keys)) {
          for (const key of keys.map((item) => String(item))) {
            if (Object.prototype.hasOwnProperty.call(store, key)) {
              result[key] = clone(store[key]);
            }
          }
          return result;
        }
        if (typeof keys === 'object') {
          for (const key of Object.keys(keys)) {
            result[key] = Object.prototype.hasOwnProperty.call(store, key)
              ? clone(store[key])
              : clone(keys[key]);
          }
        }
        return result;
      };
      const storageBytes = (keys, store) => {
        const selected = storageGet(keys, store);
        try { return new TextEncoder().encode(JSON.stringify(selected)).length; }
        catch (_) { return 0; }
      };
      const storageArea = (areaName, readOnly = false) => {
        const store = storageStores[areaName];
        return {
          get(keys, callback) {
            const result = storageGet(keys, store);
            callbackLater(callback, clone(result));
            return Promise.resolve(clone(result));
          },
          getBytesInUse(keys, callback) {
            const result = storageBytes(keys, store);
            callbackLater(callback, result);
            return Promise.resolve(result);
          },
          getKeys(callback) {
            const result = Object.keys(store);
            callbackLater(callback, result.slice());
            return Promise.resolve(result.slice());
          },
          set(items, callback) {
            if (readOnly) {
              const error = new Error('chrome.storage.managed is read-only.');
              callbackErrorLater(callback, error.message);
              return Promise.reject(error);
            }
            if (items && typeof items === 'object') {
              for (const key of Object.keys(items)) {
                store[key] = clone(items[key]);
              }
            }
            callbackLater(callback);
            return Promise.resolve();
          },
          remove(keys, callback) {
            if (readOnly) {
              const error = new Error('chrome.storage.managed is read-only.');
              callbackErrorLater(callback, error.message);
              return Promise.reject(error);
            }
            for (const key of storageKeys(keys, store)) delete store[key];
            callbackLater(callback);
            return Promise.resolve();
          },
          clear(callback) {
            if (readOnly) {
              const error = new Error('chrome.storage.managed is read-only.');
              callbackErrorLater(callback, error.message);
              return Promise.reject(error);
            }
            for (const key of Object.keys(store)) delete store[key];
            callbackLater(callback);
            return Promise.resolve();
          },
          setAccessLevel(_details, callback) {
            callbackLater(callback);
            return Promise.resolve();
          }
        };
      };
      const proxiedNamespace = (known, path) => new Proxy(known, {
        has(target, property) {
          return Object.prototype.hasOwnProperty.call(target, property);
        },
        ownKeys(target) {
          return Reflect.ownKeys(target);
        },
        getOwnPropertyDescriptor(target, property) {
          if (!Object.prototype.hasOwnProperty.call(target, property)) {
            return undefined;
          }
          return Object.getOwnPropertyDescriptor(target, property) || {
            configurable: true,
            enumerable: true,
            value: target[property],
            writable: false
          };
        },
        get(target, property) {
          if (Object.prototype.hasOwnProperty.call(target, property)) {
            return target[property];
          }
          return unsupported(`${path}.${String(property)}`);
        }
      });
      const chromeMessageSender = (metadata = {}) => {
        const sender = { id: extensionID };
        const frameId = Number(metadata.frameID ?? metadata.frameId);
        if (Number.isFinite(frameId)) sender.frameId = frameId;
        const documentId = metadata.documentID ?? metadata.documentId;
        if (documentId != null && String(documentId)) {
          sender.documentId = String(documentId);
        }
        const sourceURL = metadata.sourceURL ?? metadata.url;
        const urlRedacted = metadata.urlRedacted !== false;
        if (sourceURL != null && String(sourceURL) && !urlRedacted) {
          sender.url = String(sourceURL);
          try { sender.origin = new URL(sender.url).origin; } catch (_) {}
        }
        const tabID = Number(metadata.tabID ?? (metadata.tab && metadata.tab.id));
        if (Number.isFinite(tabID)) {
          sender.tab = {
            id: tabID,
            index: -1,
            windowId: -1,
            active: false,
            highlighted: false,
            pinned: false,
            incognito: false,
            selected: false,
            discarded: false,
            autoDiscardable: true
          };
        }
        sender.__sumiUrlRedacted = urlRedacted;
        sender.__sumiRedactionState = String(
          metadata.redactionState
            || metadata.__sumiRedactionState
            || (urlRedacted ? 'synthetic sender URL redacted' : 'synthetic sender URL available')
        );
        return sender;
      };
      const normalizeAlarm = (input) => {
        const source = input && typeof input === 'object' ? input : {};
        const scheduledTime = Number(source.scheduledTime);
        const alarm = {
          name: String(source.name || ''),
          scheduledTime: Number.isFinite(scheduledTime) ? scheduledTime : 0
        };
        const periodInMinutes = Number(source.periodInMinutes);
        if (Number.isFinite(periodInMinutes)) {
          alarm.periodInMinutes = periodInMinutes;
        }
        alarm.__sumiEventSource = 'localExperimentalSyntheticAlarm';
        return alarm;
      };
      const listenerArguments = (eventName, args, sender, sendResponse, port) => {
        const chromeSender = chromeMessageSender(sender || {});
        switch (eventName) {
          case 'runtimeOnConnect':
            return [port];
          case 'runtimeOnMessage':
          case 'runtimeOnMessageExternal':
            return [clone(args[0]), chromeSender, sendResponse];
          case 'storageOnChanged':
            return [clone(args[0] || {}), args[1] == null ? 'local' : String(args[1])];
          case 'permissionsOnAdded':
          case 'permissionsOnRemoved':
            return [clone(args[0] || { permissions: [], origins: [] })];
          case 'alarmsOnAlarm':
            return [normalizeAlarm(args[0])];
          case 'contextMenusOnClicked':
            return [clone(args[0] || {}), clone(args[1])];
          case 'webNavigationOnBeforeNavigate':
          case 'webNavigationOnCommitted':
          case 'webNavigationOnCompleted':
          case 'webNavigationOnDOMContentLoaded':
          case 'webNavigationOnErrorOccurred':
          case 'webNavigationOnHistoryStateUpdated':
          case 'webNavigationOnReferenceFragmentUpdated':
            return [clone(args[0] || {})];
          case 'tabsOnRemoved':
            return [args[0] == null ? -1 : Number(args[0]), clone(args[1] || {})];
          case 'tabsOnUpdated':
            return [
              args[0] == null ? -1 : Number(args[0]),
              clone(args[1] || {}),
              clone(args[2] || {})
            ];
          default:
            return (Array.isArray(args) ? args : []).map((value) => clone(value));
        }
      };
      const trackPromiseCompletion = (eventName, listenerID, promise) => {
        const completion = {
          event: eventName,
          listenerID,
          state: 'pending',
          value: null,
          error: null
        };
        asyncCompletions.push(completion);
        promise.then(
          (value) => {
            completion.state = 'fulfilled';
            completion.value = clone(value);
          },
          (error) => {
            completion.state = 'rejected';
            completion.error = String(error && error.message ? error.message : error);
            noteBlocked(`${eventName}.promiseRejected`);
          }
        );
      };
      const createPort = (options, sender) => {
        const existing = ports.get(options.portID);
        if (existing) return existing.port;
        const onMessage = localEvent();
        const onDisconnect = localEvent();
        const state = {
          portID: options.portID,
          name: options.name || '',
          sender: chromeMessageSender(sender || {}),
          nativeFixturePort: options.nativeFixturePort === true,
          connected: true,
          outbox: [],
          disconnectReason: null,
          onMessage,
          onDisconnect,
          port: null
        };
        state.port = {
          name: state.name,
            sender: clone(state.sender),
          onMessage,
          onDisconnect,
          postMessage(message) {
            if (!state.connected) return;
            state.outbox.push(clone(message));
          },
          disconnect() {
            disconnectPort(state.portID, 'listenerRequestedDisconnect');
          }
        };
        ports.set(state.portID, state);
        return state.port;
      };
      const disconnectPort = (portID, reason, errorMessage = null) => {
        const state = ports.get(portID);
        if (!state || !state.connected) return state ? portSnapshot(state) : null;
        state.connected = false;
        state.disconnectReason = reason || 'explicitDisconnect';
        for (const listener of [...state.onDisconnect.listeners]) {
          try { invokeCallbackNow(listener, errorMessage, state.port); }
          catch (_) { noteBlocked(`port.${portID}.onDisconnect.listenerError`); }
        }
        return portSnapshot(state);
      };
      const portSnapshot = (state) => ({
        portID: state.portID,
        name: state.name,
        sender: clone(state.sender),
        nativeFixturePort: state.nativeFixturePort,
        connected: state.connected,
        onMessageListenerCount: state.onMessage.listeners.length,
        onDisconnectListenerCount: state.onDisconnect.listeners.length,
        outbox: clone(state.outbox),
        disconnectReason: state.disconnectReason
      });
      const deliverPortMessage = (portID, message) => {
        const state = ports.get(portID);
        if (!state || !state.connected) return state ? portSnapshot(state) : null;
        for (const listener of [...state.onMessage.listeners]) {
          try { invokeCallbackNow(listener, null, clone(message), state.port); }
          catch (_) { noteBlocked(`port.${portID}.onMessage.listenerError`); }
        }
        return portSnapshot(state);
      };
      const runtime = proxiedNamespace({
        id: extensionID,
        get lastError() {
          return runtimeLastErrorValue;
        },
        getURL(path = '') {
          const value = String(path || '').replace(/^\/+/, '');
          return value ? `${extensionOrigin}/${value}` : `${extensionOrigin}/`;
        },
        getManifest() {
          return clone(manifestSnapshot);
        },
        onMessage: event('runtimeOnMessage'),
        onConnect: event('runtimeOnConnect'),
        onInstalled: event('runtimeOnInstalled'),
        onMessageExternal: event('runtimeOnMessageExternal'),
        onStartup: event('runtimeOnStartup'),
        onUpdateAvailable: event('runtimeOnUpdateAvailable')
      }, 'chrome.runtime');
      const storage = proxiedNamespace({
        onChanged: event('storageOnChanged'),
        local: storageArea('local'),
        sync: storageArea('sync'),
        session: storageArea('session'),
        managed: storageArea('managed', true)
      }, 'chrome.storage');
      const permissions = proxiedNamespace({
        onAdded: event('permissionsOnAdded'),
        onRemoved: event('permissionsOnRemoved')
      }, 'chrome.permissions');
      const alarms = proxiedNamespace({
        onAlarm: event('alarmsOnAlarm')
      }, 'chrome.alarms');
      const contextMenus = proxiedNamespace({
        onClicked: event('contextMenusOnClicked')
      }, 'chrome.contextMenus');
      const tabs = proxiedNamespace({
        onRemoved: event('tabsOnRemoved'),
        onUpdated: event('tabsOnUpdated')
      }, 'chrome.tabs');
      const commands = proxiedNamespace({
        onCommand: event('commandsOnCommand')
      }, 'chrome.commands');
      const webNavigation = proxiedNamespace({
        onBeforeNavigate: event('webNavigationOnBeforeNavigate'),
        onCommitted: event('webNavigationOnCommitted'),
        onCompleted: event('webNavigationOnCompleted'),
        onDOMContentLoaded: event('webNavigationOnDOMContentLoaded'),
        onErrorOccurred: event('webNavigationOnErrorOccurred'),
        onHistoryStateUpdated: event('webNavigationOnHistoryStateUpdated'),
        onReferenceFragmentUpdated: event('webNavigationOnReferenceFragmentUpdated')
      }, 'chrome.webNavigation');
      const webRequest = proxiedNamespace({
        onAuthRequired: event('webRequestOnAuthRequired'),
        onBeforeRequest: event('webRequestOnBeforeRequest'),
        onBeforeSendHeaders: event('webRequestOnBeforeSendHeaders'),
        onCompleted: event('webRequestOnCompleted'),
        onErrorOccurred: event('webRequestOnErrorOccurred'),
        onHeadersReceived: event('webRequestOnHeadersReceived'),
        onResponseStarted: event('webRequestOnResponseStarted'),
        onSendHeaders: event('webRequestOnSendHeaders')
      }, 'chrome.webRequest');
      const recordI18nOperation = (operation, status, value, source, blocker, diagnostics = []) => {
        i18nOperations.push({
          operation: String(operation),
          status: String(status),
          value: value == null ? null : String(value),
          source: source == null ? null : String(source),
          blocker: blocker == null ? null : String(blocker),
          diagnostics: diagnostics.map((item) => String(item))
        });
      };
      const unsupportedI18nMethod = (name) => function () {
        const path = `chrome.i18n.${name}`;
        noteBlocked(path);
        recordI18nOperation(
          path,
          'blocked',
          null,
          null,
          'unsupportedI18nAPI',
          [
            'Only chrome.i18n.getUILanguage is implemented in this local experimental service-worker slice.',
            'No message catalog, accept-language list, or CLD language detection result is faked.'
          ]
        );
        return undefined;
      };
      const i18n = proxiedNamespace({
        getUILanguage() {
          recordI18nOperation(
            'chrome.i18n.getUILanguage',
            'fulfilled',
            uiLanguage,
            uiLanguageSource,
            null,
            [
              'Returned deterministic browser UI language string from the local experimental harness configuration.',
              'This does not enable chrome.i18n message catalog lookup.'
            ]
          );
          return uiLanguage;
        },
        getMessage: unsupportedI18nMethod('getMessage'),
        getAcceptLanguages: unsupportedI18nMethod('getAcceptLanguages'),
        detectLanguage: unsupportedI18nMethod('detectLanguage')
      }, 'chrome.i18n');
      globalThis.chrome = proxiedNamespace({
        runtime,
        i18n,
        storage,
        permissions,
        alarms,
        commands,
        contextMenus,
        tabs,
        webNavigation,
        webRequest
      }, 'chrome');
      globalThis.importScripts = function (...urls) {
        if (typeof globalThis.__sumiImportScriptsHost !== 'function') {
          noteBlocked('importScripts.hostMissing');
          throw new Error('importScripts host resolver is unavailable.');
        }
        const result = globalThis.__sumiImportScriptsHost(urls);
        if (!result || result.ok !== true) {
          const blocker = result && result.blocker
            ? String(result.blocker)
            : 'unknown';
          noteBlocked(`importScripts.${blocker}`);
          throw new Error(result && result.error
            ? String(result.error)
            : 'importScripts import failed.');
        }
        return undefined;
      };
      globalThis.__sumiDynamicImportRewrite = function (specifier) {
        if (typeof specifier !== 'string') {
          noteBlocked('dynamicImportRewrite.nonStringSpecifier');
          return Promise.reject(new Error('Dynamic import rewrite requires a string specifier.'));
        }
        if (typeof globalThis.__sumiDynamicImportRewriteHost !== 'function') {
          noteBlocked('dynamicImportRewrite.hostMissing');
          return Promise.reject(new Error('Dynamic import rewrite host resolver is unavailable.'));
        }
        const result = globalThis.__sumiDynamicImportRewriteHost(specifier);
        if (result && result.ok === true) {
          return Promise.resolve(result.namespace || {});
        }
        const blocker = result && result.blocker
          ? String(result.blocker)
          : 'unknown';
        noteBlocked(`dynamicImportRewrite.${blocker}`);
        return Promise.reject(new Error(result && result.error
          ? String(result.error)
          : 'Dynamic import rewrite failed.'));
      };
      const normalizeDelay = (delay) => {
        const number = Number(delay);
        if (!Number.isFinite(number) || number < 0) return 0;
        return Math.min(number, 2147483647);
      };
      const scheduleQueuedCallback = (kind, callback, delay, args) => {
        if (typeof callback !== 'function') {
          noteBlocked(`globalThis.${kind === 'timeout' ? 'setTimeout' : 'setInterval'}.nonFunction`);
          throw new TypeError('The local experimental timer shim accepts function callbacks only.');
        }
        const timerID = nextTimerID++;
        timers.set(timerID, {
          timerID,
          kind,
          delayMilliseconds: normalizeDelay(delay),
          active: true,
          queued: kind === 'timeout',
          invocationCount: 0,
          callback,
          args
        });
        if (kind === 'timeout') pendingTimeoutIDs.push(timerID);
        return timerID;
      };
      const clearTimer = (timerID) => {
        const state = timers.get(Number(timerID));
        if (!state) return;
        state.active = false;
        state.queued = false;
        timers.delete(state.timerID);
      };
      const invokeQueuedCallback = (state, callbackErrors) => {
        if (!state || !state.active) return false;
        if (state.kind === 'timeout') {
          state.active = false;
          state.queued = false;
          timers.delete(state.timerID);
        }
        state.invocationCount += 1;
        try { state.callback(...state.args); }
        catch (error) {
          const message = String(error && error.message ? error.message : error);
          callbackErrors.push(message);
          noteBlocked(`timer.${state.timerID}.callbackError`);
        }
        return true;
      };
      const timerDrainSnapshot = (mode, callbackCount, callbackErrors, limitReached) => ({
        mode,
        callbackCount,
        callbackErrors,
        pendingTimeoutCount: pendingTimeoutIDs.filter((timerID) => timers.has(timerID)).length,
        activeIntervalCount: [...timers.values()].filter((state) =>
          state.kind === 'interval' && state.active).length,
        limitReached,
        diagnostics: [
          'Queued callbacks run only when the explicit local experimental harness drains or ticks them.',
          'No wall-clock wait, background wake loop, or polling scheduler is created.'
        ]
      });
      const drainTimeouts = (maxCallbacks = 100) => {
        const limit = Math.max(0, Math.floor(Number(maxCallbacks) || 0));
        const callbackErrors = [];
        let callbackCount = 0;
        while (pendingTimeoutIDs.length && callbackCount < limit) {
          const timerID = pendingTimeoutIDs.shift();
          const state = timers.get(timerID);
          if (invokeQueuedCallback(state, callbackErrors)) callbackCount += 1;
        }
        return timerDrainSnapshot(
          'drainTimeouts',
          callbackCount,
          callbackErrors,
          pendingTimeoutIDs.some((timerID) => timers.has(timerID))
        );
      };
      const tickIntervals = (maxCallbacks = 100) => {
        const limit = Math.max(0, Math.floor(Number(maxCallbacks) || 0));
        const callbackErrors = [];
        let callbackCount = 0;
        const activeIntervals = [...timers.values()]
          .filter((state) => state.kind === 'interval' && state.active)
          .sort((lhs, rhs) => lhs.timerID - rhs.timerID);
        for (const state of activeIntervals) {
          if (callbackCount >= limit) break;
          if (invokeQueuedCallback(state, callbackErrors)) callbackCount += 1;
        }
        return timerDrainSnapshot(
          'tickIntervals',
          callbackCount,
          callbackErrors,
          activeIntervals.length > callbackCount
        );
      };
      globalThis.setTimeout = (callback, delay, ...args) =>
        scheduleQueuedCallback('timeout', callback, delay, args);
      globalThis.clearTimeout = clearTimer;
      globalThis.setInterval = (callback, delay, ...args) =>
        scheduleQueuedCallback('interval', callback, delay, args);
      globalThis.clearInterval = clearTimer;
      const normalizeHeaderName = (name) => String(name).toLowerCase();
      const normalizeHeaderValue = (value) => String(value);
      if (typeof globalThis.Headers !== 'function') {
        defineWorkerGlobal('Headers', class Headers {
          constructor(init = undefined) {
            this._pairs = [];
            if (init == null) return;
            if (init instanceof Headers) {
              init.forEach((value, key) => this.append(key, value));
            } else if (Array.isArray(init)) {
              for (const pair of init) this.append(pair[0], pair[1]);
            } else if (typeof init === 'object') {
              for (const key of Object.keys(init)) this.append(key, init[key]);
            }
          }
          append(name, value) {
            this._pairs.push([
              normalizeHeaderName(name),
              normalizeHeaderValue(value)
            ]);
          }
          delete(name) {
            const key = normalizeHeaderName(name);
            this._pairs = this._pairs.filter((pair) => pair[0] !== key);
          }
          get(name) {
            const key = normalizeHeaderName(name);
            const values = this._pairs
              .filter((pair) => pair[0] === key)
              .map((pair) => pair[1]);
            return values.length ? values.join(', ') : null;
          }
          has(name) {
            const key = normalizeHeaderName(name);
            return this._pairs.some((pair) => pair[0] === key);
          }
          set(name, value) {
            const key = normalizeHeaderName(name);
            this.delete(key);
            this._pairs.push([key, normalizeHeaderValue(value)]);
          }
          entries() { return this._pairs.slice()[Symbol.iterator](); }
          keys() { return this._pairs.map((pair) => pair[0])[Symbol.iterator](); }
          values() { return this._pairs.map((pair) => pair[1])[Symbol.iterator](); }
          forEach(callback, thisArg = undefined) {
            for (const [key, value] of this._pairs) {
              callback.call(thisArg, value, key, this);
            }
          }
          [Symbol.iterator]() { return this.entries(); }
        });
      }
      const copyBytes = (bytes) => {
        const copy = new Uint8Array(bytes.byteLength);
        copy.set(bytes);
        return copy;
      };
      const bodyBytes = (body = null) => {
        if (body == null) return new Uint8Array();
        if (body instanceof Uint8Array) return copyBytes(body);
        if (body instanceof ArrayBuffer) return new Uint8Array(body.slice(0));
        if (ArrayBuffer.isView(body)) {
          return new Uint8Array(
            body.buffer.slice(
              body.byteOffset || 0,
              (body.byteOffset || 0) + body.byteLength
            )
          );
        }
        if (Array.isArray(body)) return new Uint8Array(body.map((value) => Number(value) & 0xff));
        return new TextEncoder().encode(String(body));
      };
      if (typeof globalThis.Request !== 'function') {
        defineWorkerGlobal('Request', class Request {
          constructor(input, init = {}) {
            init = init || {};
            const source = input instanceof Request ? input : null;
            const requestLike = input && typeof input === 'object' ? input : null;
            const url = source
              ? source.url
              : input instanceof URL
                ? input.href
                : requestLike && typeof requestLike.url === 'string'
                  ? requestLike.url
                  : String(input);
            this.url = url;
            this.method = String(
              init.method != null
                ? init.method
                : source
                  ? source.method
                  : requestLike && requestLike.method != null
                    ? requestLike.method
                    : 'GET'
            ).toUpperCase();
            this.headers = new Headers(
              init.headers != null
                ? init.headers
                : source
                  ? source.headers
                  : requestLike ? requestLike.headers : undefined
            );
            this.credentials = String(
              init.credentials != null
                ? init.credentials
                : source
                  ? source.credentials
                  : requestLike && requestLike.credentials != null
                    ? requestLike.credentials
                    : 'omit'
            );
            this.cache = String(
              init.cache != null
                ? init.cache
                : source
                  ? source.cache
                  : requestLike && requestLike.cache != null
                    ? requestLike.cache
                    : 'default'
            );
            this._sumiExplicitCredentials =
              Object.prototype.hasOwnProperty.call(init, 'credentials')
              || (source && source._sumiExplicitCredentials === true)
              || (requestLike && requestLike._sumiExplicitCredentials === true);
            this._sumiExplicitCache =
              Object.prototype.hasOwnProperty.call(init, 'cache')
              || (source && source._sumiExplicitCache === true)
              || (requestLike && requestLike._sumiExplicitCache === true);
          }
          clone() { return new Request(this); }
        });
      }
      if (typeof globalThis.Response !== 'function') {
        defineWorkerGlobal('Response', class Response {
          constructor(body = null, init = {}) {
            init = init || {};
            this._bytes = bodyBytes(body);
            this.status = init.status == null ? 200 : Number(init.status);
            this.statusText = String(init.statusText || '');
            this.headers = new Headers(init.headers);
            this.url = String(init.url || '');
            this.type = 'basic';
            this.redirected = false;
            this.body = null;
            this.bodyUsed = false;
            this.ok = this.status >= 200 && this.status <= 299;
          }
          _consumeBytes() {
            if (this.bodyUsed) {
              throw new TypeError('Response body has already been used.');
            }
            this.bodyUsed = true;
            return copyBytes(this._bytes);
          }
          arrayBuffer() {
            return Promise.resolve().then(() => {
              const bytes = this._consumeBytes();
              return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
            });
          }
          blob() {
            return Promise.reject(new DOMException(
              'Response.blob is outside the minimal local harness Response model.',
              'NotSupportedError'
            ));
          }
          bytes() {
            return Promise.resolve().then(() => this._consumeBytes());
          }
          clone() {
            if (this.bodyUsed) {
              throw new TypeError('Response body has already been used.');
            }
            return new Response(copyBytes(this._bytes), {
              status: this.status,
              statusText: this.statusText,
              headers: new Headers(this.headers),
              url: this.url
            });
          }
          formData() {
            return Promise.reject(new DOMException(
              'Response.formData is outside the minimal local harness Response model.',
              'NotSupportedError'
            ));
          }
          json() { return this.text().then((text) => JSON.parse(text)); }
          text() {
            return Promise.resolve().then(() =>
              new TextDecoder('utf-8').decode(this._consumeBytes()));
          }
        });
      }
      const previewFetchInput = (input) => {
        try {
          if (typeof input === 'string') return input.slice(0, 240);
          if (input instanceof URL) return input.href.slice(0, 240);
          if (input && typeof input.url === 'string') return input.url.slice(0, 240);
          return String(input).slice(0, 240);
        } catch (_) {
          return '<uninspectable>';
        }
      };
      const fetchCallSite = () => {
        const stack = String(new Error().stack || '');
        const line = stack.split('\n').find((entry) =>
          entry.includes('.js:') && !entry.includes('service-worker-shim.js'));
        const match = line && line.match(/([^@\s]+\.js):(\d+):\d+/);
        return {
          sourcePath: globalThis.__sumiCurrentScript || null,
          line: match ? Number(match[2]) : null
        };
      };
      const fetchFallbackResult = (requestKind, resolvedURL, blocker, error, diagnostics) => ({
        ok: false,
        requestKind,
        resolvedURL,
        networkAccessRequired: requestKind === 'remoteNetworkBlocked',
        extensionLocalResource: requestKind === 'extensionLocalGeneratedResource' || requestKind === 'relativeGeneratedResource',
        executionAllowed: false,
        blocker,
        error,
        diagnostics
      });
      const recordFetchClassification = (result, preview, fallbackResolvedURL, callSite) => {
        fetchCallIndex += 1;
        const blocker = String(result && result.blocker ? result.blocker : 'fetchSchemeOrInputUnsupported');
        const requestKind = String(result && result.requestKind ? result.requestKind : 'unsupportedRequestShape');
        const executionAllowed = !!(result && result.executionAllowed);
        if (!executionAllowed) noteBlocked(`globalThis.fetch.${requestKind}.${blocker}`);
        fetchClassifications.push({
          callIndex: fetchCallIndex,
          sourcePath: callSite.sourcePath,
          line: callSite.line,
          requestPreview: preview,
          resolvedURL: result && result.resolvedURL ? String(result.resolvedURL) : fallbackResolvedURL,
          requestKind,
          networkAccessRequired: !!(result && result.networkAccessRequired),
          extensionLocalResource: !!(result && result.extensionLocalResource),
          executionAllowed,
          blocker,
          fetchedResourcePath: result && result.fetchedResourcePath ? String(result.fetchedResourcePath) : null,
          sourceByteCount: result && result.sourceByteCount != null ? Number(result.sourceByteCount) : null,
          status: result && result.status != null ? Number(result.status) : null,
          diagnostics: Array.isArray(result && result.diagnostics)
            ? result.diagnostics.map((item) => String(item))
            : ['fetch request was evaluated by the local harness policy.']
        });
      };
      globalThis.fetch = function (input, init = {}) {
        const preview = previewFetchInput(input);
        const callSite = fetchCallSite();
        try {
          const request = new Request(input, init || {});
          const rawURL = String(request.url || '');
          let resolvedURL = null;
          let url = null;
          try {
            url = new URL(rawURL, location.href);
            resolvedURL = url.href;
          } catch (_) {
            const result = fetchFallbackResult(
              'unsupportedRequestShape',
              null,
              'unsupportedRequestShape',
              'fetch request URL could not be resolved.',
              ['Only generated-bundle-contained extension-local resources are modeled.']
            );
            recordFetchClassification(result, preview, null, callSite);
            return Promise.reject(new TypeError(result.error));
          }
          const inputWasRelative = !/^[A-Za-z][A-Za-z0-9+.-]*:/.test(rawURL);
          const inputWasExtensionURL = !inputWasRelative && url.protocol === 'chrome-extension:';
          const payload = {
            rawURL,
            resolvedURL,
            method: request.method,
            inputWasRelative,
            inputWasExtensionURL,
            explicitCredentials: request._sumiExplicitCredentials === true,
            credentials: request.credentials,
            explicitCache: request._sumiExplicitCache === true,
            cache: request.cache
          };
          const result = typeof globalThis.__sumiFetchHost === 'function'
            ? globalThis.__sumiFetchHost(payload)
            : fetchFallbackResult(
                'unsupportedRequestShape',
                resolvedURL,
                'fetchResolverUnavailable',
                'fetch resolver host is unavailable.',
                ['No network or arbitrary filesystem fallback was attempted.']
              );
          recordFetchClassification(result, preview, resolvedURL, callSite);
          if (!result || !result.ok) {
            const error = new TypeError(String(result && result.error
              ? result.error
              : 'fetch request was blocked by the local harness policy.'));
            return Promise.reject(error);
          }
          return Promise.resolve(new Response(result.bytes || [], {
            status: Number(result.status || 200),
            statusText: String(result.statusText || 'OK'),
            headers: result.headers || {},
            url: String(result.resolvedURL || resolvedURL)
          }));
        } catch (error) {
          const result = fetchFallbackResult(
            'unsupportedRequestShape',
            null,
            'unsupportedRequestShape',
            String(error && error.message ? error.message : error),
            ['fetch request normalization threw before any host resolver action.']
          );
          recordFetchClassification(result, preview, null, callSite);
          return Promise.reject(error);
        }
      };
      for (const name of [
        'XMLHttpRequest',
        'WebSocket',
        'EventSource',
        'requestAnimationFrame'
      ]) {
        globalThis[name] = function () {
          noteBlocked(`globalThis.${name}`);
          throw new Error(`${name} is blocked in the local experimental service-worker harness.`);
        };
      }
      const dispatch = (eventName, args, sender, portOptions) => {
        const listeners = registrations.filter((item) => item.event === eventName);
        if (!listeners.length) {
          return {
            kind: 'noListener',
            diagnostics: [`No executed listener registration exists for ${eventName}.`]
          };
        }
        let port = null;
        if (eventName === 'runtimeOnConnect') {
          port = createPort(portOptions, sender);
        }
        for (const item of listeners) {
          let responseCalled = false;
          let response = null;
          const sendResponse = (value) => {
            responseCalled = true;
            response = clone(value);
          };
          try {
            const listenerArgs = listenerArguments(
              eventName,
              Array.isArray(args) ? args : [],
              sender || {},
              sendResponse,
              port
            );
            const result = item.listener(...listenerArgs);
            if (responseCalled) {
              return {
                kind: 'delivered',
                listenerID: item.listenerID,
                response,
                portID: portOptions ? portOptions.portID : null,
                diagnostics: ['Synchronous sendResponse result captured.']
              };
            }
            if (result && typeof result.then === 'function') {
              trackPromiseCompletion(eventName, item.listenerID, result);
              if (eventName !== 'runtimeOnMessage'
                  && eventName !== 'runtimeOnMessageExternal') {
                return {
                  kind: 'delivered',
                  listenerID: item.listenerID,
                  portID: portOptions ? portOptions.portID : null,
                  diagnostics: [
                    'Promise-returning fire-and-forget listener was invoked.',
                    'Completion is tracked as diagnostics only; no response channel is modeled for this event family.'
                  ]
                };
              }
              return {
                kind: 'unsupportedListenerMode',
                listenerID: item.listenerID,
                portID: portOptions ? portOptions.portID : null,
                error: 'Promise completion is observable but deferred by the deterministic no-wait harness policy.',
                diagnostics: ['Promise-returning listener was detected without scheduling a wait.']
              };
            }
            if (eventName === 'runtimeOnMessage' && result === true) {
              return {
                kind: 'sendResponseTimeoutDiagnostic',
                listenerID: item.listenerID,
                error: 'Listener returned true without synchronous sendResponse; deterministic harness does not wait.',
                diagnostics: ['sendResponse channel was left open without scheduling a wait.']
              };
            }
            if (eventName === 'runtimeOnMessage' && result !== undefined) {
              return {
                kind: 'delivered',
                listenerID: item.listenerID,
                response: clone(result),
                diagnostics: ['Synchronous return value captured as an approximated local experimental response.']
              };
            }
          } catch (error) {
            return {
              kind: 'listenerError',
              listenerID: item.listenerID,
              error: String(error && error.message ? error.message : error),
              diagnostics: ['Listener threw during deterministic dispatch.']
            };
          }
        }
        return {
          kind: 'delivered',
          listenerID: listeners[0].listenerID,
          portID: portOptions ? portOptions.portID : null,
          diagnostics: ['Listener dispatch completed without a response payload.']
        };
      };
      const snapshot = () => ({
        registrations: registrations.map((item) => ({
          listenerID: item.listenerID,
          event: item.event,
          order: item.order,
          arity: item.arity,
          asyncFunction: item.asyncFunction,
          source: item.source
        })),
        blockedCalls: [...blockedCalls],
        cryptoOperations: cryptoOperations.map((item) => clone(item)),
        i18nOperations: i18nOperations.map((item) => clone(item)),
        workerGlobalEvents: workerGlobalEvents.map((item) => clone(item)),
        fetchClassifications: fetchClassifications.map((item) => clone(item)),
        webAssemblyCapability: clone(webAssemblyCapability),
        ports: [...ports.values()].map(portSnapshot),
        asyncCompletions: asyncCompletions.map((item) => clone(item)),
        timers: [...timers.values()].map((state) => ({
          timerID: state.timerID,
          kind: state.kind,
          delayMilliseconds: state.delayMilliseconds,
          active: state.active,
          queued: state.queued,
          invocationCount: state.invocationCount
        }))
      });
      globalThis.__sumiHarness = {
        snapshot,
        dispatch,
        createPort,
        deliverPortMessage,
        disconnectPort,
        drainTimeouts,
        tickIntervals
      };
    })();
    """#
}

private struct ChromeMV3ServiceWorkerJSPortOptions {
    var portID: String
    var name: String
    var nativeFixturePort: Bool

    var json: String {
        ChromeMV3StorageValue.object([
            "portID": .string(portID),
            "name": .string(name),
            "nativeFixturePort": .bool(nativeFixturePort),
        ]).serviceWorkerJSJSON
    }
}

private struct ChromeMV3ServiceWorkerJSWireRegistration: Decodable {
    var listenerID: String
    var event: String
    var order: Int
    var arity: Int
    var asyncFunction: Bool
    var source: String?
}

private struct ChromeMV3ServiceWorkerJSWireSnapshot: Decodable {
    var registrations: [ChromeMV3ServiceWorkerJSWireRegistration]
    var blockedCalls: [String]
    var cryptoOperations: [ChromeMV3ServiceWorkerJSWireCryptoOperation]
    var i18nOperations: [ChromeMV3ServiceWorkerJSI18nOperationRecord]
    var workerGlobalEvents: [ChromeMV3ServiceWorkerJSWorkerGlobalEventRecord]
    var fetchClassifications:
        [ChromeMV3ServiceWorkerJSFetchClassificationRecord]
    var webAssemblyCapability:
        ChromeMV3ServiceWorkerJSWebAssemblyCapabilityRecord?
    var ports: [ChromeMV3ServiceWorkerJSWirePort]
    var timers: [ChromeMV3ServiceWorkerJSTimerRecord]
}

private struct ChromeMV3ServiceWorkerJSWireCryptoOperation: Decodable {
    var operation: String
    var algorithm: String?
    var byteCount: Int?
    var status: String
    var blocker: String?
    var diagnostics: [String]
}

private struct ChromeMV3ServiceWorkerJSWirePort: Decodable {
    var portID: String
    var name: String
    var sender: ChromeMV3StorageValue
    var nativeFixturePort: Bool
    var connected: Bool
    var onMessageListenerCount: Int
    var onDisconnectListenerCount: Int
    var outbox: [ChromeMV3StorageValue]
    var disconnectReason: String?
}

private enum ChromeMV3ServiceWorkerJSWireDispatchKind:
    String,
    Decodable
{
    case delivered
    case listenerError
    case noListener
    case promiseRejected
    case sendResponseTimeoutDiagnostic
    case unsupportedListenerMode

    func publicKind(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> ChromeMV3ServiceWorkerJSDispatchResultKind {
        switch self {
        case .delivered:
            return .delivered
        case .listenerError:
            return .listenerError
        case .noListener:
            return event == .runtimeOnMessage || event == .runtimeOnConnect
                ? .noReceiver : .noListener
        case .promiseRejected:
            return .promiseRejected
        case .sendResponseTimeoutDiagnostic:
            return .sendResponseTimeoutDiagnostic
        case .unsupportedListenerMode:
            return .unsupportedListenerMode
        }
    }

    func eventRoutingKind(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> ChromeMV3ServiceWorkerEventRoutingResultKind {
        switch self {
        case .delivered:
            return .delivered
        case .listenerError:
            return .listenerError
        case .noListener:
            return event == .runtimeOnMessage || event == .runtimeOnConnect
                ? .noReceiver : .noListener
        case .promiseRejected:
            return .promiseRejected
        case .sendResponseTimeoutDiagnostic:
            return .sendResponseTimeoutDiagnostic
        case .unsupportedListenerMode:
            return .unsupportedListenerMode
        }
    }
}

private struct ChromeMV3ServiceWorkerJSWireDispatch: Decodable {
    var kind: ChromeMV3ServiceWorkerJSWireDispatchKind
    var listenerID: String?
    var response: ChromeMV3StorageValue?
    var error: String?
    var portID: String?
    var diagnostics: [String]
}

private extension ChromeMV3ServiceWorkerEventSenderMetadata {
    var serviceWorkerJSJSON: String {
        ChromeMV3StorageValue.object([
            "tabID": tabID.map { .number(Double($0)) } ?? .null,
            "frameID": frameID.map { .number(Double($0)) } ?? .null,
            "documentID": documentID.map(ChromeMV3StorageValue.string) ?? .null,
            "sourceURL": sourceURL.map(ChromeMV3StorageValue.string) ?? .null,
            "urlRedacted": .bool(urlRedacted),
            "redactionState": .string(redactionState),
        ]).serviceWorkerJSJSON
    }
}

private extension ChromeMV3StorageValue {
    var serviceWorkerJSJSON: String {
        (try? canonicalJSONString()) ?? "null"
    }

    var serviceWorkerJSSenderMetadata:
        ChromeMV3ServiceWorkerEventSenderMetadata
    {
        guard case .object(let object) = self else { return .none }
        let chromeTabID: Int?
        if case .object(let tab)? = object["tab"] {
            chromeTabID = tab["id"]?.serviceWorkerJSInt
        } else {
            chromeTabID = nil
        }
        return ChromeMV3ServiceWorkerEventSenderMetadata(
            tabID: object["tabID"]?.serviceWorkerJSInt ?? chromeTabID,
            frameID:
                object["frameID"]?.serviceWorkerJSInt
                    ?? object["frameId"]?.serviceWorkerJSInt,
            documentID:
                object["documentID"]?.serviceWorkerJSString
                    ?? object["documentId"]?.serviceWorkerJSString,
            sourceURL:
                object["sourceURL"]?.serviceWorkerJSString
                    ?? object["url"]?.serviceWorkerJSString,
            urlRedacted:
                object["urlRedacted"]?.serviceWorkerJSBool
                    ?? object["__sumiUrlRedacted"]?.serviceWorkerJSBool
                    ?? true,
            redactionState:
                object["redactionState"]?.serviceWorkerJSString
                    ?? object["__sumiRedactionState"]?.serviceWorkerJSString
                    ?? "sender metadata unavailable"
        )
    }

    private var serviceWorkerJSString: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    private var serviceWorkerJSBool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    private var serviceWorkerJSInt: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }
}

private extension Array where Element == ChromeMV3StorageValue {
    var serviceWorkerJSJSON: String {
        ChromeMV3StorageValue.array(self).serviceWorkerJSJSON
    }
}

private extension Array
where Element == ChromeMV3ServiceWorkerSyntheticListenerEvent {
    func uniqueSortedServiceWorkerJS()
        -> [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    {
        Array(Set(self)).sorted()
    }
}

private func normalizedServiceWorkerJS(
    _ value: String,
    fallback: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func normalizedOptionalServiceWorkerJS(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func normalizedUILanguageServiceWorkerJS(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: "-")
    guard trimmed.isEmpty == false else { return nil }
    let parts = trimmed.split(separator: "-", omittingEmptySubsequences: true)
    guard let language = parts.first,
          language.range(
            of: #"^[A-Za-z]{2,3}$"#,
            options: .regularExpression
          ) != nil
    else { return nil }
    let normalizedLanguage = language.lowercased()
    guard let region = parts.dropFirst().first,
          region.range(
            of: #"^(?:[A-Za-z]{2}|\d{3})$"#,
            options: .regularExpression
          ) != nil
    else {
        return normalizedLanguage
    }
    return "\(normalizedLanguage)-\(region.uppercased())"
}

private func isSafeRelativeServiceWorkerJSPath(_ path: String) -> Bool {
    guard path.isEmpty == false,
          path.hasPrefix("/") == false,
          path.hasPrefix("~") == false,
          path.contains("\\") == false
    else { return false }
    return path.split(separator: "/", omittingEmptySubsequences: false)
        .allSatisfy {
            $0.isEmpty == false && $0 != "." && $0 != ".."
        }
}

private func containsServiceWorkerJS(root: URL, candidate: URL) -> Bool {
    let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
    let resolvedCandidate =
        candidate.resolvingSymlinksInPath().standardizedFileURL.path
    return resolvedCandidate.hasPrefix(resolvedRoot + "/")
}

private func relativePathInGeneratedBundle(
    _ candidate: URL,
    root: URL
) -> String? {
    let rootPath = root.standardizedFileURL.path
    let candidatePath = candidate.standardizedFileURL.path
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard candidatePath.hasPrefix(prefix) else { return nil }
    let relative = String(candidatePath.dropFirst(prefix.count))
    return relative.isEmpty ? nil : relative
}

private func pathContainsSymbolicLinkServiceWorkerJS(
    _ candidate: URL,
    root: URL
) -> Bool {
    guard let relative = relativePathInGeneratedBundle(candidate, root: root)
    else { return true }
    var current = root.standardizedFileURL
    for segment in relative.split(separator: "/").map(String.init) {
        current = current.appendingPathComponent(segment)
        if (try? FileManager.default.destinationOfSymbolicLink(
            atPath: current.path
        )) != nil {
            return true
        }
    }
    return false
}

private func directoryExistsServiceWorkerJS(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
    ) && isDirectory.boolValue
}

private func regularFileExistsServiceWorkerJS(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
    ) && isDirectory.boolValue == false
}

private func symbolicLinkServiceWorkerJS(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        .isSymbolicLink) == true
}

private func fetchHostFailureResponseServiceWorkerJS(
    requestKind: ChromeMV3ServiceWorkerJSFetchRequestKind,
    resolvedURL: String? = nil,
    networkAccessRequired: Bool,
    extensionLocalResource: Bool,
    blocker: String,
    message: String,
    fetchedResourcePath: String? = nil,
    diagnostics: [String]
) -> NSDictionary {
    var object: [String: Any] = [
        "ok": false,
        "requestKind": requestKind.rawValue,
        "networkAccessRequired": networkAccessRequired,
        "extensionLocalResource": extensionLocalResource,
        "executionAllowed": false,
        "blocker": blocker,
        "error": message,
        "diagnostics": diagnostics,
    ]
    if let resolvedURL {
        object["resolvedURL"] = resolvedURL
    }
    if let fetchedResourcePath {
        object["fetchedResourcePath"] = fetchedResourcePath
    }
    return object as NSDictionary
}

private func fetchHostSuccessResponseServiceWorkerJS(
    requestKind: ChromeMV3ServiceWorkerJSFetchRequestKind,
    resolvedURL: String,
    fetchedResourcePath: String,
    sourceByteCount: Int,
    status: Int,
    statusText: String,
    headers: [String: String],
    bytes: Data,
    diagnostics: [String]
) -> NSDictionary {
    [
        "ok": true,
        "requestKind": requestKind.rawValue,
        "resolvedURL": resolvedURL,
        "networkAccessRequired": false,
        "extensionLocalResource": true,
        "executionAllowed": true,
        "blocker": "none",
        "fetchedResourcePath": fetchedResourcePath,
        "sourceByteCount": sourceByteCount,
        "status": status,
        "statusText": statusText,
        "headers": headers,
        "bytes": bytes.map { NSNumber(value: $0) } as NSArray,
        "diagnostics": diagnostics,
    ] as NSDictionary
}

private func looksLikeAbsoluteFilesystemFetchPathServiceWorkerJS(
    _ rawURL: String
) -> Bool {
    let lower = rawURL.lowercased()
    guard lower.hasPrefix("file:") == false else { return false }
    for prefix in [
        "/applications/",
        "/etc/",
        "/library/",
        "/opt/",
        "/private/",
        "/system/",
        "/tmp/",
        "/users/",
        "/usr/",
        "/var/",
        "/volumes/",
    ] where lower.hasPrefix(prefix) {
        return true
    }
    return false
}

private func rawFetchPathContainsTraversalServiceWorkerJS(
    _ rawURL: String
) -> Bool {
    let decoded = rawURL.removingPercentEncoding ?? rawURL
    return decoded == ".."
        || decoded.hasPrefix("../")
        || decoded.hasPrefix("..\\")
        || decoded.contains("/../")
        || decoded.contains("\\..\\")
}

private func normalizedFetchResourcePathServiceWorkerJS(
    _ percentEncodedPath: String
) -> (
    path: String?,
    blocker: ChromeMV3ServiceWorkerJSFetchRequestKind?,
    message: String
) {
    guard percentEncodedPath.isEmpty == false else {
        return (
            nil,
            .unsupportedRequestShape,
            "fetch resource path is empty."
        )
    }
    guard
        let decoded = percentEncodedPath.removingPercentEncoding,
        decoded.contains("\0") == false,
        decoded.contains("\\") == false
    else {
        return (
            nil,
            .unsupportedRequestShape,
            "fetch resource path contains unsupported encoded or path separator material."
        )
    }
    let withoutLeadingSlash =
        decoded.hasPrefix("/") ? String(decoded.dropFirst()) : decoded
    let rawSegments =
        withoutLeadingSlash.split(separator: "/", omittingEmptySubsequences: false)
    guard rawSegments.isEmpty == false else {
        return (
            nil,
            .missingResource,
            "fetch resource path does not name a generated-bundle file."
        )
    }
    var segments: [String] = []
    for rawSegment in rawSegments {
        let segment = String(rawSegment)
        if segment.isEmpty {
            return (
                nil,
                .unsupportedRequestShape,
                "fetch resource path contains an empty segment."
            )
        }
        if segment == "." {
            continue
        }
        if segment == ".." {
            return (
                nil,
                .traversalBlocked,
                "fetch resource path contains parent-directory traversal."
            )
        }
        segments.append(segment)
    }
    guard segments.isEmpty == false else {
        return (
            nil,
            .missingResource,
            "fetch resource path does not name a generated-bundle file."
        )
    }
    return (segments.joined(separator: "/"), nil, "fetch path normalized.")
}

private func mimeTypeServiceWorkerJS(for relativePath: String) -> String {
    switch URL(fileURLWithPath: relativePath).pathExtension.lowercased() {
    case "css":
        return "text/css; charset=utf-8"
    case "gif":
        return "image/gif"
    case "htm", "html":
        return "text/html; charset=utf-8"
    case "jpeg", "jpg":
        return "image/jpeg"
    case "js", "mjs":
        return "text/javascript; charset=utf-8"
    case "json", "map":
        return "application/json; charset=utf-8"
    case "png":
        return "image/png"
    case "svg":
        return "image/svg+xml"
    case "txt":
        return "text/plain; charset=utf-8"
    case "wasm":
        return "application/wasm"
    default:
        return "application/octet-stream"
    }
}

private extension ChromeMV3ServiceWorkerJSFetchRequestKind {
    var fetchBlockerName: String {
        switch self {
        case .absoluteFilesystemBlocked:
            return "absoluteFilesystemFetchBlocked"
        case .blobURLBlocked:
            return "blobURLFetchBlocked"
        case .dataURLBlocked:
            return "dataURLFetchBlocked"
        case .fileURLBlocked:
            return "fileURLFetchBlocked"
        case .missingResource:
            return "missingResource"
        case .remoteNetworkBlocked, .remoteNetwork:
            return "networkFetchDisabled"
        case .symlinkEscapeBlocked:
            return "symlinkEscapeBlocked"
        case .traversalBlocked:
            return "pathTraversalBlocked"
        case .extensionLocalGeneratedResource,
             .extensionLocalResource,
             .relativeGeneratedResource:
            return "extensionLocalFetchDisabled"
        case .requestLikeObject,
             .unknownInput,
             .unsupportedRequestShape,
             .unsupportedScheme:
            return "fetchSchemeOrInputUnsupported"
        }
    }
}

private func containsServiceWorkerJSRegex(
    _ pattern: String,
    in source: String
) -> Bool {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
        return false
    }
    let range = NSRange(source.startIndex..., in: source)
    return expression.firstMatch(in: source, range: range) != nil
}

#if canImport(JavaScriptCore)
    private func exceptionDetailsServiceWorkerJS(
        exception: JSValue,
        source: String,
        sourceURL: URL,
        sourceName: String
    ) -> ChromeMV3ServiceWorkerJSExceptionDetails {
        let message = exception.toString() ?? "JavaScript exception"
        let line = exceptionIntPropertyServiceWorkerJS(exception, "line")
        let column = exceptionIntPropertyServiceWorkerJS(exception, "column")
        let sourcePath =
            exception.objectForKeyedSubscript("sourceURL")?.toString()
            ?? sourceURL.path
        let stack = exception.objectForKeyedSubscript("stack")?.toString()
        let sourceLine = line.flatMap {
            sourceLineServiceWorkerJS(source, line: $0)
        }
        let inference = exceptionInferenceServiceWorkerJS(
            message: message,
            sourceLine: sourceLine,
            stack: stack
        )
        var diagnostics = [
            "JavaScriptCore exception: \(message)",
            "Exception source: \(sourceName)"
                + (line.map { ":\($0)" } ?? "")
                + (column.map { ":\($0)" } ?? "") + ".",
            "Exception classification: \(inference.classification.rawValue).",
        ]
        if let missing = inference.missingGlobal {
            diagnostics.append("Inferred missing global: \(missing).")
        }
        if let missing = inference.missingProperty {
            diagnostics.append("Inferred missing property: \(missing).")
        }
        if let sourceLine {
            diagnostics.append(
                "Exception source line preview: \(previewServiceWorkerJS(sourceLine))."
            )
        }
        if let stack, stack.isEmpty == false {
            diagnostics.append(
                "Exception stack captured from JavaScriptCore."
            )
        }
        return ChromeMV3ServiceWorkerJSExceptionDetails(
            message: message,
            sourcePath: sourcePath,
            line: line,
            column: column,
            stack: stack,
            inferredMissingGlobal: inference.missingGlobal,
            inferredMissingProperty: inference.missingProperty,
            classification: inference.classification,
            diagnostics: uniqueSortedServiceWorkerJS(diagnostics)
        )
    }

    private func exceptionIntPropertyServiceWorkerJS(
        _ exception: JSValue,
        _ property: String
    ) -> Int? {
        guard let value = exception.objectForKeyedSubscript(property),
              value.isUndefined == false,
              value.isNull == false
        else { return nil }
        let number = Int(value.toInt32())
        return number > 0 ? number : nil
    }
#endif

private func exceptionInferenceServiceWorkerJS(
    message: String,
    sourceLine: String?,
    stack: String?
) -> (
    classification: ChromeMV3ServiceWorkerJSExceptionClassification,
    missingGlobal: String?,
    missingProperty: String?
) {
    let standardWorkerGlobals: Set<String> = [
        "DOMException",
        "URL",
        "URLSearchParams",
        "ServiceWorkerGlobalScope",
        "TextDecoder",
        "TextEncoder",
        "WorkerGlobalScope",
        "atob",
        "btoa",
        "crypto",
        "location",
        "navigator",
        "queueMicrotask",
        "self",
    ]
    let missingVariable = firstRegexCaptureServiceWorkerJS(
        #"ReferenceError: Can't find variable: ([A-Za-z_$][\w$]*)"#,
        in: message
    )
    if let missingVariable {
        if standardWorkerGlobals.contains(missingVariable) {
            return (.missingStandardWorkerGlobal, missingVariable, nil)
        }
        if missingVariable == "chrome" || missingVariable == "browser" {
            return (.missingChromeAPIShim, missingVariable, nil)
        }
        if ["fetch", "XMLHttpRequest", "WebSocket", "EventSource"]
            .contains(missingVariable)
        {
            return (.missingWebAPI, missingVariable, nil)
        }
        if ["document", "localStorage", "sessionStorage", "window"]
            .contains(missingVariable)
        {
            return (.missingWebAPI, missingVariable, nil)
        }
        return (.unknownVendorCodeAssumption, missingVariable, nil)
    }
    if message.localizedCaseInsensitiveContains("Subtle crypto")
        || message.localizedCaseInsensitiveContains("SubtleCrypto")
        || message.localizedCaseInsensitiveContains("crypto.subtle")
    {
        return (.missingWebAPI, "SubtleCrypto", "crypto.subtle")
    }
    let property = firstRegexCaptureServiceWorkerJS(
        #"\(evaluating '([^']+)'\)"#,
        in: message
    )
    if message.contains("b.prototype"),
       (sourceLine?.contains("DOMException") == true
        || stack?.contains("DOMException") == true)
    {
        return (.missingStandardWorkerGlobal, "DOMException", "prototype")
    }
    if let property, property.contains("chrome.")
        || property.contains("browser.")
    {
        return (.missingChromeAPIShim, nil, property)
    }
    if message.localizedCaseInsensitiveContains("import")
        || message.localizedCaseInsensitiveContains("module")
    {
        return (.unsupportedModuleOrImportShape, nil, property)
    }
    if message.localizedCaseInsensitiveContains("setTimeout")
        || message.localizedCaseInsensitiveContains("setInterval")
    {
        return (.unsupportedAsyncOrTimerBehavior, nil, property)
    }
    if let property {
        return (.bundlerRuntimeAssumption, nil, property)
    }
    return (.unknownVendorCodeAssumption, nil, nil)
}

private func firstRegexCaptureServiceWorkerJS(
    _ pattern: String,
    in source: String
) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern)
    else { return nil }
    let range = NSRange(source.startIndex..., in: source)
    guard let match = regex.firstMatch(in: source, range: range),
          match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: source)
    else { return nil }
    return String(source[captureRange])
}

private func sourceLineServiceWorkerJS(
    _ source: String,
    line: Int
) -> String? {
    guard line > 0 else { return nil }
    let lines = source.split(
        separator: "\n",
        omittingEmptySubsequences: false
    )
    guard line <= lines.count else { return nil }
    return String(lines[line - 1])
}

private func previewServiceWorkerJS(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 240 else { return trimmed }
    return String(trimmed.prefix(240)) + "..."
}

private func webCryptoHostErrorServiceWorkerJS(_ message: String)
    -> NSDictionary
{
    [
        "ok": false,
        "error": message,
    ] as NSDictionary
}

private struct WebCryptoHostBridgeErrorServiceWorkerJS: Error {
    var message: String
}

private func secureRandomBytesServiceWorkerJS(count: Int)
    -> Result<[UInt8], WebCryptoHostBridgeErrorServiceWorkerJS>
{
    guard count >= 0 && count <= 65_536 else {
        return .failure(
            WebCryptoHostBridgeErrorServiceWorkerJS(
                message:
                    "Requested secure random byte count is outside the supported range."
            )
        )
    }
    guard count > 0 else { return .success([]) }
    #if canImport(Security)
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            return .failure(
                WebCryptoHostBridgeErrorServiceWorkerJS(
                    message: "SecRandomCopyBytes failed with status \(status)."
                )
            )
        }
        return .success(bytes)
    #else
        return .failure(
            WebCryptoHostBridgeErrorServiceWorkerJS(
                message:
                    "Security.framework SecRandomCopyBytes is unavailable."
            )
        )
    #endif
}

private func uuidV4StringServiceWorkerJS(_ bytes: [UInt8]) -> String {
    guard bytes.count == 16 else { return "" }
    let hex = Array("0123456789abcdef")
    let byteString: (UInt8) -> String = { byte in
        String(hex[Int(byte >> 4)]) + String(hex[Int(byte & 0x0f)])
    }
    return [
        bytes[0...3].map(byteString).joined(),
        bytes[4...5].map(byteString).joined(),
        bytes[6...7].map(byteString).joined(),
        bytes[8...9].map(byteString).joined(),
        bytes[10...15].map(byteString).joined(),
    ].joined(separator: "-")
}

private func normalizedWebCryptoDigestAlgorithmServiceWorkerJS(
    _ algorithm: String
) -> String? {
    let value = algorithm
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
        .replacingOccurrences(of: "_", with: "-")
    switch value {
    case "SHA-1", "SHA1":
        return "SHA-1"
    case "SHA-256", "SHA256":
        return "SHA-256"
    case "SHA-384", "SHA384":
        return "SHA-384"
    case "SHA-512", "SHA512":
        return "SHA-512"
    default:
        return nil
    }
}

private func webCryptoDigestBytesServiceWorkerJS(
    algorithm: String,
    bytes: [UInt8]
) -> [UInt8]? {
    let data = Data(bytes)
    switch normalizedWebCryptoDigestAlgorithmServiceWorkerJS(algorithm) {
    case "SHA-1":
        return Array(Insecure.SHA1.hash(data: data))
    case "SHA-256":
        return Array(SHA256.hash(data: data))
    case "SHA-384":
        return Array(SHA384.hash(data: data))
    case "SHA-512":
        return Array(SHA512.hash(data: data))
    default:
        return nil
    }
}

private func rewriteDynamicImportsForHarnessServiceWorkerJS(
    _ source: String
) -> String {
    var rewritten = source
    for call in dynamicImportCallRangesServiceWorkerJS(in: source).reversed() {
        let argument = String(source[call.argumentRange])
        guard let literal = dynamicImportStringLiteralServiceWorkerJS(argument)
        else { continue }
        let escaped = literal
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        rewritten.replaceSubrange(
            call.callRange,
            with:
                "globalThis.__sumiDynamicImportRewrite('\(escaped)')"
        )
    }
    return rewritten
}

private struct ChromeMV3ServiceWorkerJSDynamicImportCallRange {
    var callRange: Range<String.Index>
    var argumentRange: Range<String.Index>
}

private func dynamicImportArgumentSourcesServiceWorkerJS(
    in source: String
) -> [String] {
    dynamicImportCallRangesServiceWorkerJS(in: source).map {
        String(source[$0.argumentRange])
    }
}

private func dynamicImportCallRangesServiceWorkerJS(
    in source: String
) -> [ChromeMV3ServiceWorkerJSDynamicImportCallRange] {
    let bytes = Array(source.utf8)
    var results: [ChromeMV3ServiceWorkerJSDynamicImportCallRange] = []
    var index = 0
    while index < bytes.count {
        if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96 {
            index = skipQuotedServiceWorkerJS(bytes, start: index)
            continue
        }
        if bytes[index] == 47,
           let regexClose = skipRegexLiteralServiceWorkerJS(
                bytes,
                start: index
           )
        {
            index = regexClose
            continue
        }
        if bytes[index] == 47, index + 1 < bytes.count,
           bytes[index + 1] == 47
        {
            index += 2
            while index < bytes.count, bytes[index] != 10 { index += 1 }
            continue
        }
        if bytes[index] == 47, index + 1 < bytes.count,
           bytes[index + 1] == 42
        {
            index += 2
            while index + 1 < bytes.count,
                  !(bytes[index] == 42 && bytes[index + 1] == 47)
            {
                index += 1
            }
            index = min(bytes.count, index + 2)
            continue
        }
        guard isIdentifierStartServiceWorkerJS(bytes[index]) else {
            index += 1
            continue
        }
        let start = index
        index += 1
        while index < bytes.count,
              isIdentifierPartServiceWorkerJS(bytes[index])
        {
            index += 1
        }
        guard String(decoding: bytes[start..<index], as: UTF8.self)
            == "import"
        else { continue }
        if previousSignificantByteServiceWorkerJS(bytes, before: start) == 46 {
            continue
        }
        var open = index
        while open < bytes.count, isWhitespaceServiceWorkerJS(bytes[open]) {
            open += 1
        }
        guard open < bytes.count, bytes[open] == 40,
              let close = matchingParenCloseServiceWorkerJS(bytes, open: open)
        else { continue }
        if followingSignificantByteServiceWorkerJS(bytes, after: close) == 123 {
            index = close + 1
            continue
        }
        guard let callStart = stringIndexServiceWorkerJS(start, in: source),
              let argumentStart = stringIndexServiceWorkerJS(
                open + 1,
                in: source
              ),
              let argumentEnd = stringIndexServiceWorkerJS(close, in: source),
              let callEnd = stringIndexServiceWorkerJS(close + 1, in: source)
        else {
            index = close + 1
            continue
        }
        results.append(
            ChromeMV3ServiceWorkerJSDynamicImportCallRange(
                callRange: callStart..<callEnd,
                argumentRange: argumentStart..<argumentEnd
            )
        )
        index = close + 1
    }
    return results
}

private func dynamicImportStringLiteralServiceWorkerJS(
    _ expression: String
) -> String? {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first,
          let last = trimmed.last,
          (first == "'" || first == "\""),
          last == first
    else { return nil }
    let value = String(trimmed.dropFirst().dropLast())
    guard value.contains("\\") == false,
          value.contains(first) == false
    else { return nil }
    return value
}

private func dynamicImportRecordsServiceWorkerJS(
    in source: String,
    parentScriptRelativePath: String,
    parentURL: URL?,
    generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
    generatedBundleRoot: URL?,
    capability: ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe,
    includeCapabilityBlockers: Bool
) -> [ChromeMV3ServiceWorkerJSDynamicImportRecord] {
    var records: [ChromeMV3ServiceWorkerJSDynamicImportRecord] = []
    for argument in dynamicImportArgumentSourcesServiceWorkerJS(in: source) {
        if let path = dynamicImportStringLiteralServiceWorkerJS(argument) {
            records.append(
                dynamicImportRecordServiceWorkerJS(
                    requestPath: path,
                    parentScriptRelativePath: parentScriptRelativePath,
                    parentURL: parentURL,
                    generatedBundleRecord: generatedBundleRecord,
                    generatedBundleRoot: generatedBundleRoot,
                    capability: capability,
                    includeCapabilityBlockers: includeCapabilityBlockers
                )
            )
        } else {
            records.append(
                ChromeMV3ServiceWorkerJSDynamicImportRecord(
                    requestPath: "<non-string-literal>",
                    parentScriptRelativePath: parentScriptRelativePath,
                    resolvedRelativePath: nil,
                    resolvedPath: nil,
                    stringLiteral: false,
                    generatedBundlePathValidated: false,
                    rewriteEligible: false,
                    rewritten: false,
                    evaluated: false,
                    evaluationOrder: nil,
                    sourceSHA256: nil,
                    sourceByteCount: nil,
                    blockers:
                        uniqueSortedServiceWorkerJS(
                            [.dynamicImportArgumentNonString]
                                + (
                                    includeCapabilityBlockers
                                        ? capability.blockers.compactMap(
                                            dynamicImportBlockerServiceWorkerJS
                                        )
                                        : []
                                )
                        ),
                    diagnostics:
                        uniqueSortedServiceWorkerJS(
                            [
                                "Dynamic import uses a non-string-literal specifier; the local harness only permits string-literal generated-bundle imports if support is ever enabled.",
                            ]
                                + capability.diagnostics
                        )
                )
            )
        }
    }
    return records
}

private func dynamicImportRecordServiceWorkerJS(
    requestPath: String,
    parentScriptRelativePath: String,
    parentURL: URL?,
    generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
    generatedBundleRoot: URL?,
    capability: ChromeMV3ServiceWorkerJSDynamicImportCapabilityProbe,
    includeCapabilityBlockers: Bool
) -> ChromeMV3ServiceWorkerJSDynamicImportRecord {
    var blockers =
        includeCapabilityBlockers
            ? capability.blockers.compactMap(
                dynamicImportBlockerServiceWorkerJS
            )
            : []
    var diagnostics =
        includeCapabilityBlockers
            ? capability.diagnostics
            : [
                "Dynamic import native JavaScriptCore capability blockers are reported by policy, but omitted from this rewrite-candidate path validation.",
            ]
    guard let record = generatedBundleRecord else {
        blockers.append(.generatedBundleRecordMissing)
        diagnostics.append(
            "No generated bundle record is available for dynamic import path validation."
        )
        return dynamicImportRecordServiceWorkerJS(
            requestPath: requestPath,
            parentScriptRelativePath: parentScriptRelativePath,
            resolvedRelativePath: nil,
            resolvedPath: nil,
            stringLiteral: true,
            generatedBundlePathValidated: false,
            sourceData: nil,
            blockers: blockers,
            diagnostics: diagnostics
        )
    }
    guard let root = generatedBundleRoot,
          directoryExistsServiceWorkerJS(root)
    else {
        blockers.append(.generatedBundleRootMissing)
        diagnostics.append(
            "Generated bundle root is missing for dynamic import path validation."
        )
        return dynamicImportRecordServiceWorkerJS(
            requestPath: requestPath,
            parentScriptRelativePath: parentScriptRelativePath,
            resolvedRelativePath: nil,
            resolvedPath: nil,
            stringLiteral: true,
            generatedBundlePathValidated: false,
            sourceData: nil,
            blockers: blockers,
            diagnostics: diagnostics
        )
    }
    let normalized = normalizeDynamicImportPath(requestPath)
    if let blocker = normalized.blocker {
        blockers.append(blocker)
        diagnostics.append(normalized.message)
        return dynamicImportRecordServiceWorkerJS(
            requestPath: requestPath,
            parentScriptRelativePath: parentScriptRelativePath,
            resolvedRelativePath: nil,
            resolvedPath: nil,
            stringLiteral: true,
            generatedBundlePathValidated: false,
            sourceData: nil,
            blockers: blockers,
            diagnostics: diagnostics
        )
    }
    guard let normalizedPath = normalized.path else {
        blockers.append(.importPathUnsafe)
        diagnostics.append(
            "Dynamic import path could not be normalized safely."
        )
        return dynamicImportRecordServiceWorkerJS(
            requestPath: requestPath,
            parentScriptRelativePath: parentScriptRelativePath,
            resolvedRelativePath: nil,
            resolvedPath: nil,
            stringLiteral: true,
            generatedBundlePathValidated: false,
            sourceData: nil,
            blockers: blockers,
            diagnostics: diagnostics
        )
    }
    let parentDirectory = parentURL?
        .deletingLastPathComponent()
        .standardizedFileURL ?? root
    let candidate = parentDirectory
        .appendingPathComponent(normalizedPath)
        .standardizedFileURL
    let resolvedRelative =
        Sumi.relativePathInGeneratedBundle(candidate, root: root)
    guard let resolvedRelative else {
        blockers.append(.importPathEscapesGeneratedBundle)
        diagnostics.append(
            "Dynamic import path resolves outside the generated bundle root."
        )
        return dynamicImportRecordServiceWorkerJS(
            requestPath: requestPath,
            parentScriptRelativePath: parentScriptRelativePath,
            resolvedRelativePath: nil,
            resolvedPath: candidate.path,
            stringLiteral: true,
            generatedBundlePathValidated: false,
            sourceData: nil,
            blockers: blockers,
            diagnostics: diagnostics
        )
    }
    if pathContainsSymbolicLinkServiceWorkerJS(candidate, root: root) {
        blockers.append(.importedModuleSymbolicLinkRejected)
        diagnostics.append(
            "Dynamic import path contains a symbolic link and was rejected."
        )
    }
    if containsServiceWorkerJS(root: root, candidate: candidate) == false {
        blockers.append(.importPathEscapesGeneratedBundle)
        diagnostics.append(
            "Dynamic import path resolves outside the generated bundle root after symlink resolution."
        )
    }
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(
        atPath: candidate.path,
        isDirectory: &isDirectory
    )
    if exists == false {
        blockers.append(.importedModuleMissing)
        diagnostics.append("Dynamic import module is missing.")
    } else if isDirectory.boolValue {
        blockers.append(.importedModuleDirectoryRejected)
        diagnostics.append(
            "Dynamic import resolved to a directory, not a JavaScript module file."
        )
    }
    if record.copiedResourcePaths.contains(resolvedRelative) == false {
        blockers.append(.importedModuleNotCopiedFromGeneratedBundleRecord)
        diagnostics.append(
            "Dynamic import module is not recorded as a copied generated-bundle resource."
        )
    }
    let sourceData = try? Data(contentsOf: candidate)
    if exists, isDirectory.boolValue == false {
        if let sourceData,
           String(data: sourceData, encoding: .utf8) == nil
        {
            blockers.append(.importedModuleUTF8Required)
            diagnostics.append(
                "Dynamic import module is not valid UTF-8 JavaScript source."
            )
        } else if sourceData == nil {
            blockers.append(.importedModuleMissing)
            diagnostics.append(
                "Dynamic import module data could not be read."
            )
        }
    }
    let pathBlockers = blockers.filter {
        dynamicImportBlockerServiceWorkerJS($0) == nil
    }
    diagnostics.append(
        pathBlockers.isEmpty
            ? (
                includeCapabilityBlockers
                    ? "Dynamic import string-literal path was validated inside the generated bundle root, but execution remains blocked by JavaScriptCore capability."
                    : "Dynamic import string-literal path is eligible for harness-only generated-root-contained rewrite."
            )
            : "Dynamic import string-literal path failed generated-bundle validation."
    )
    return dynamicImportRecordServiceWorkerJS(
        requestPath: requestPath,
        parentScriptRelativePath: parentScriptRelativePath,
        resolvedRelativePath: resolvedRelative,
        resolvedPath: candidate.path,
        stringLiteral: true,
        generatedBundlePathValidated: pathBlockers.isEmpty,
        sourceData: sourceData,
        blockers: blockers,
        diagnostics: diagnostics
    )
}

private func dynamicImportRecordServiceWorkerJS(
    requestPath: String,
    parentScriptRelativePath: String,
    resolvedRelativePath: String?,
    resolvedPath: String?,
    stringLiteral: Bool,
    generatedBundlePathValidated: Bool,
    sourceData: Data?,
    blockers: [ChromeMV3ServiceWorkerJSDynamicImportBlocker],
    diagnostics: [String]
) -> ChromeMV3ServiceWorkerJSDynamicImportRecord {
    let uniqueBlockers = uniqueSortedServiceWorkerJS(blockers)
    return ChromeMV3ServiceWorkerJSDynamicImportRecord(
        requestPath: requestPath,
        parentScriptRelativePath: parentScriptRelativePath,
        resolvedRelativePath: resolvedRelativePath,
        resolvedPath: resolvedPath,
        stringLiteral: stringLiteral,
        generatedBundlePathValidated: generatedBundlePathValidated,
        rewriteEligible:
            stringLiteral && generatedBundlePathValidated
                && uniqueBlockers.isEmpty,
        rewritten: false,
        evaluated: false,
        evaluationOrder: nil,
        sourceSHA256: sourceData.map(sha256HexServiceWorkerJS),
        sourceByteCount: sourceData?.count,
        blockers: uniqueBlockers,
        diagnostics: uniqueSortedServiceWorkerJS(diagnostics)
    )
}

private func resourceLoadBlockerServiceWorkerJS(
    _ blocker: ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker
) -> ChromeMV3ServiceWorkerJSResourceLoadBlocker? {
    switch blocker {
    case .dynamicImportExecutionSurfaceUnsupported:
        return .dynamicImportExecutionSurfaceUnsupported
    case .dynamicImportGeneratedRootContainmentUnproven:
        return .dynamicImportGeneratedRootContainmentUnproven
    case .dynamicImportLowerLevelAPINotAvailable:
        return .dynamicImportLowerLevelAPINotAvailable
    case .dynamicImportModuleNamespaceUnsupported:
        return .dynamicImportModuleNamespaceUnsupported
    case .dynamicImportNoLoader:
        return .dynamicImportNoLoader
    case .dynamicImportParseUnsupported:
        return .dynamicImportParseUnsupported
    case .dynamicImportPromiseDrainUnavailable:
        return .dynamicImportPromiseDrainUnavailable
    case .dynamicImportResolverHookUnavailable:
        return .dynamicImportResolverHookUnavailable
    case .javaScriptCoreUnavailable:
        return nil
    }
}

private func importScriptsBlockerServiceWorkerJS(
    _ blocker: ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker
) -> ChromeMV3ServiceWorkerJSImportScriptsBlocker? {
    switch blocker {
    case .dynamicImportExecutionSurfaceUnsupported:
        return .dynamicImportExecutionSurfaceUnsupported
    case .dynamicImportGeneratedRootContainmentUnproven:
        return .dynamicImportGeneratedRootContainmentUnproven
    case .dynamicImportLowerLevelAPINotAvailable:
        return .dynamicImportLowerLevelAPINotAvailable
    case .dynamicImportModuleNamespaceUnsupported:
        return .dynamicImportModuleNamespaceUnsupported
    case .dynamicImportNoLoader:
        return .dynamicImportNoLoader
    case .dynamicImportParseUnsupported:
        return .dynamicImportParseUnsupported
    case .dynamicImportPromiseDrainUnavailable:
        return .dynamicImportPromiseDrainUnavailable
    case .dynamicImportResolverHookUnavailable:
        return .dynamicImportResolverHookUnavailable
    case .javaScriptCoreUnavailable:
        return nil
    }
}

private func dynamicImportBlockerServiceWorkerJS(
    _ blocker: ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker
) -> ChromeMV3ServiceWorkerJSDynamicImportBlocker? {
    switch blocker {
    case .dynamicImportExecutionSurfaceUnsupported:
        return .dynamicImportExecutionSurfaceUnsupported
    case .dynamicImportGeneratedRootContainmentUnproven:
        return .dynamicImportGeneratedRootContainmentUnproven
    case .dynamicImportLowerLevelAPINotAvailable:
        return .dynamicImportLowerLevelAPINotAvailable
    case .dynamicImportModuleNamespaceUnsupported:
        return .dynamicImportModuleNamespaceUnsupported
    case .dynamicImportNoLoader:
        return .dynamicImportNoLoader
    case .dynamicImportParseUnsupported:
        return .dynamicImportParseUnsupported
    case .dynamicImportPromiseDrainUnavailable:
        return .dynamicImportPromiseDrainUnavailable
    case .dynamicImportResolverHookUnavailable:
        return .dynamicImportResolverHookUnavailable
    case .javaScriptCoreUnavailable:
        return .dynamicImportExecutionSurfaceUnsupported
    }
}

private func dynamicImportBlockerServiceWorkerJS(
    _ blocker: ChromeMV3ServiceWorkerJSDynamicImportBlocker
) -> ChromeMV3ServiceWorkerJSDynamicImportCapabilityBlocker? {
    switch blocker {
    case .dynamicImportExecutionSurfaceUnsupported:
        return .dynamicImportExecutionSurfaceUnsupported
    case .dynamicImportGeneratedRootContainmentUnproven:
        return .dynamicImportGeneratedRootContainmentUnproven
    case .dynamicImportLowerLevelAPINotAvailable:
        return .dynamicImportLowerLevelAPINotAvailable
    case .dynamicImportModuleNamespaceUnsupported:
        return .dynamicImportModuleNamespaceUnsupported
    case .dynamicImportNoLoader:
        return .dynamicImportNoLoader
    case .dynamicImportParseUnsupported:
        return .dynamicImportParseUnsupported
    case .dynamicImportPromiseDrainUnavailable:
        return .dynamicImportPromiseDrainUnavailable
    case .dynamicImportResolverHookUnavailable:
        return .dynamicImportResolverHookUnavailable
    default:
        return nil
    }
}

private struct ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup {
    var candidates: [String]
    var requiresAllCandidatesContained: Bool
    var message: String
}

private struct ChromeMV3ServiceWorkerJSImportScriptsAuthorization {
    var candidateGroups: [ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup]
    var unboundedExpressionDetected: Bool
}

private func boundedImportScriptsAuthorizationServiceWorkerJS(
    in source: String
) -> ChromeMV3ServiceWorkerJSImportScriptsAuthorization {
    let constantMaps = constantImportScriptsMapsServiceWorkerJS(in: source)
    let webpackChunkGroups =
        webpackImportScriptsCandidateGroupsServiceWorkerJS(in: source)
    var groups: [ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup] = []
    var unbounded = false
    for argument in importScriptsArgumentSourcesServiceWorkerJS(in: source) {
        if let literal = staticImportScriptsStringServiceWorkerJS(argument) {
            groups.append(
                ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup(
                    candidates: [literal.value],
                    requiresAllCandidatesContained: false,
                    message:
                        "importScripts dependency was authorized from a statically bounded \(literal.kind) expression."
                )
            )
            continue
        }
        if let mapName = constantMapAccessServiceWorkerJS(argument),
           let candidates = constantMaps[mapName],
           candidates.isEmpty == false
        {
            groups.append(
                ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup(
                    candidates: candidates,
                    requiresAllCandidatesContained: true,
                    message:
                        "importScripts dependency was authorized from a statically visible constant map whose complete candidate set is generated-root-contained."
                )
            )
            continue
        }
        if let runtimeName = webpackImportScriptsRuntimeNameServiceWorkerJS(
            argument
        ),
           let webpackGroup = webpackChunkGroups[runtimeName]
        {
            groups.append(webpackGroup)
            continue
        }
        unbounded = true
    }
    return ChromeMV3ServiceWorkerJSImportScriptsAuthorization(
        candidateGroups: groups,
        unboundedExpressionDetected: unbounded
    )
}

func staticallyBoundedImportScriptsCandidatesServiceWorkerJS(
    in source: String
) -> [String] {
    Array(
        Set(
            boundedImportScriptsAuthorizationServiceWorkerJS(in: source)
                .candidateGroups.flatMap(\.candidates)
        )
    ).sorted()
}

private func generatedBundleContainsImportScriptServiceWorkerJS(
    _ requestPath: String,
    parentURL: URL,
    record: ChromeMV3GeneratedBundleRecord,
    root: URL,
    extensionID: String? = nil
) -> Bool {
    let normalized = normalizeImportScriptsPath(
        requestPath,
        extensionID: extensionID
    )
    guard let normalizedPath = normalized.path,
          normalized.blocker == nil
    else { return false }
    let baseURL =
        extensionID.flatMap {
            isSameExtensionURLServiceWorkerJS(
                requestPath,
                extensionID: $0
            ) ? root : nil
        } ?? parentURL.deletingLastPathComponent()
            .standardizedFileURL
    let candidate = baseURL
        .appendingPathComponent(normalizedPath)
        .standardizedFileURL
    guard
        let relative = Sumi.relativePathInGeneratedBundle(
            candidate,
            root: root
        ),
        containsServiceWorkerJS(root: root, candidate: candidate),
        pathContainsSymbolicLinkServiceWorkerJS(candidate, root: root) == false,
        regularFileExistsServiceWorkerJS(candidate),
        record.copiedResourcePaths.contains(relative)
    else { return false }
    return true
}

private func constantImportScriptsMapsServiceWorkerJS(
    in source: String
) -> [String: [String]] {
    guard
        let regex = try? NSRegularExpression(
            pattern:
                #"\bconst\s+([A-Za-z_$][\w$]*)\s*=\s*\{([^{}]*)\}\s*;"#
        )
    else { return [:] }
    let range = NSRange(source.startIndex..., in: source)
    var maps: [String: [String]] = [:]
    for match in regex.matches(in: source, range: range) {
        guard
            let nameRange = Range(match.range(at: 1), in: source),
            let bodyRange = Range(match.range(at: 2), in: source)
        else { continue }
        let name = String(source[nameRange])
        let entries = splitTopLevelServiceWorkerJS(
            String(source[bodyRange]),
            separator: ","
        )
        var values: [String] = []
        var valid = entries.isEmpty == false
        for entry in entries {
            let pair = splitTopLevelServiceWorkerJS(entry, separator: ":")
            guard pair.count == 2,
                  let value = staticImportScriptsStringServiceWorkerJS(pair[1])
            else {
                valid = false
                break
            }
            values.append(value.value)
        }
        if valid {
            maps[name] = Array(Set(values)).sorted()
        }
    }
    return maps
}

private func constantMapAccessServiceWorkerJS(_ expression: String) -> String? {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        let regex = try? NSRegularExpression(
            pattern:
                #"^([A-Za-z_$][\w$]*)(?:\.[A-Za-z_$][\w$]*|\[\s*["'][^"']+["']\s*\])$"#
        )
    else { return nil }
    let range = NSRange(trimmed.startIndex..., in: trimmed)
    guard let match = regex.firstMatch(in: trimmed, range: range),
          let nameRange = Range(match.range(at: 1), in: trimmed)
    else { return nil }
    return String(trimmed[nameRange])
}

private func webpackImportScriptsRuntimeNameServiceWorkerJS(
    _ expression: String
) -> String? {
    let compact = expression.replacingOccurrences(
        of: #"\s+"#,
        with: "",
        options: .regularExpression
    )
    guard
        let regex = try? NSRegularExpression(
            pattern:
                #"^([A-Za-z_$][\w$]*)\.p\+\1\.u\([^)]*\)$"#
        )
    else { return nil }
    let range = NSRange(compact.startIndex..., in: compact)
    guard let match = regex.firstMatch(in: compact, range: range),
          let runtimeRange = Range(match.range(at: 1), in: compact)
    else { return nil }
    return String(compact[runtimeRange])
}

private func webpackImportScriptsCandidateGroupsServiceWorkerJS(
    in source: String
) -> [String: ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup] {
    let suffixes = webpackChunkFilenameSuffixesServiceWorkerJS(in: source)
    guard suffixes.isEmpty == false else { return [:] }
    var groups:
        [String: ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup] = [:]
    for (runtimeName, suffix) in suffixes {
        let chunkIDs = webpackChunkIDsServiceWorkerJS(
            runtimeName: runtimeName,
            in: source
        )
        guard chunkIDs.isEmpty == false else { continue }
        let candidates = Array(Set(chunkIDs.map { "\($0)\(suffix)" }))
            .sorted()
        groups[runtimeName] =
            ChromeMV3ServiceWorkerJSImportScriptsCandidateGroup(
                candidates: candidates,
                requiresAllCandidatesContained: true,
                message:
                    "importScripts dependency was authorized from a statically bounded Webpack chunk filename map whose complete candidate set is generated-root-contained."
            )
    }
    return groups
}

private func webpackChunkFilenameSuffixesServiceWorkerJS(
    in source: String
) -> [String: String] {
    let patterns = [
        #"\b([A-Za-z_$][\w$]*)\.u\s*=\s*[A-Za-z_$][\w$]*\s*=>\s*[A-Za-z_$][\w$]*\s*\+\s*(['"])([^'"]+)\2"#,
        #"\b([A-Za-z_$][\w$]*)\.u\s*=\s*function\s*\(\s*[A-Za-z_$][\w$]*\s*\)\s*\{\s*return\s+[A-Za-z_$][\w$]*\s*\+\s*(['"])([^'"]+)\2"#,
    ]
    var suffixes: [String: String] = [:]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern)
        else { continue }
        let range = NSRange(source.startIndex..., in: source)
        for match in regex.matches(in: source, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let suffixRange = Range(match.range(at: 3), in: source)
            else { continue }
            suffixes[String(source[nameRange])] = String(source[suffixRange])
        }
    }
    return suffixes
}

private func webpackChunkIDsServiceWorkerJS(
    runtimeName: String,
    in source: String
) -> [String] {
    let escaped = NSRegularExpression.escapedPattern(for: runtimeName)
    guard let regex = try? NSRegularExpression(
        pattern: #"\b"# + escaped + #"\.e\s*\(\s*([0-9]+)\s*\)"#
    ) else { return [] }
    let range = NSRange(source.startIndex..., in: source)
    return Array(
        Set(
            regex.matches(in: source, range: range).compactMap { match in
                Range(match.range(at: 1), in: source).map {
                    String(source[$0])
                }
            }
        )
    ).sorted()
}

private func staticImportScriptsStringServiceWorkerJS(
    _ expression: String
) -> (value: String, kind: String)? {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    if let first = trimmed.first, let last = trimmed.last,
       (first == "'" || first == "\""), last == first
    {
        let value = String(trimmed.dropFirst().dropLast())
        if value.contains("\\") == false,
           value.contains(first) == false
        {
            return (value, "string-literal")
        }
    }
    if trimmed.first == "`", trimmed.last == "`" {
        let value = String(trimmed.dropFirst().dropLast())
        guard value.contains("${") == false,
              value.contains("\\") == false
        else { return nil }
        return (value, "static-template-literal")
    }
    let parts = splitTopLevelServiceWorkerJS(trimmed, separator: "+")
    guard parts.count > 1 else { return nil }
    var result = ""
    for part in parts {
        guard let value = staticImportScriptsStringServiceWorkerJS(part)
        else { return nil }
        result += value.value
    }
    return (result, "static-string-concatenation")
}

private func importScriptsArgumentSourcesServiceWorkerJS(
    in source: String
) -> [String] {
    let bytes = Array(source.utf8)
    var results: [String] = []
    var index = 0
    while index < bytes.count {
        if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96 {
            index = skipQuotedServiceWorkerJS(bytes, start: index)
            continue
        }
        if bytes[index] == 47,
           let regexClose = skipRegexLiteralServiceWorkerJS(
                bytes,
                start: index
           )
        {
            index = regexClose
            continue
        }
        if bytes[index] == 47, index + 1 < bytes.count,
           bytes[index + 1] == 47
        {
            index += 2
            while index < bytes.count, bytes[index] != 10 { index += 1 }
            continue
        }
        if bytes[index] == 47, index + 1 < bytes.count,
           bytes[index + 1] == 42
        {
            index += 2
            while index + 1 < bytes.count,
                  !(bytes[index] == 42 && bytes[index + 1] == 47)
            {
                index += 1
            }
            index = min(bytes.count, index + 2)
            continue
        }
        guard isIdentifierStartServiceWorkerJS(bytes[index]) else {
            index += 1
            continue
        }
        let start = index
        index += 1
        while index < bytes.count,
              isIdentifierPartServiceWorkerJS(bytes[index])
        {
            index += 1
        }
        guard String(decoding: bytes[start..<index], as: UTF8.self)
            == "importScripts"
        else { continue }
        var open = index
        while open < bytes.count, isWhitespaceServiceWorkerJS(bytes[open]) {
            open += 1
        }
        guard open < bytes.count, bytes[open] == 40,
              let close = matchingParenCloseServiceWorkerJS(bytes, open: open)
        else { continue }
        results.append(
            contentsOf:
                splitTopLevelServiceWorkerJS(
                    String(
                        decoding: bytes[(open + 1)..<close],
                        as: UTF8.self
                    ),
                    separator: ","
                )
        )
        index = close + 1
    }
    return results
}

private func matchingParenCloseServiceWorkerJS(
    _ bytes: [UInt8],
    open: Int
) -> Int? {
    var depth = 1
    var index = open + 1
    while index < bytes.count {
        if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96 {
            index = skipQuotedServiceWorkerJS(bytes, start: index)
            continue
        }
        if bytes[index] == 40 {
            depth += 1
        } else if bytes[index] == 41 {
            depth -= 1
            if depth == 0 { return index }
        }
        index += 1
    }
    return nil
}

private func splitTopLevelServiceWorkerJS(
    _ source: String,
    separator: Character
) -> [String] {
    let bytes = Array(source.utf8)
    guard let needle = String(separator).utf8.first else { return [source] }
    var results: [String] = []
    var start = 0
    var index = 0
    var parenDepth = 0
    var braceDepth = 0
    var bracketDepth = 0
    while index < bytes.count {
        if bytes[index] == 34 || bytes[index] == 39 || bytes[index] == 96 {
            index = skipQuotedServiceWorkerJS(bytes, start: index)
            continue
        }
        switch bytes[index] {
        case 40: parenDepth += 1
        case 41: parenDepth = max(0, parenDepth - 1)
        case 123: braceDepth += 1
        case 125: braceDepth = max(0, braceDepth - 1)
        case 91: bracketDepth += 1
        case 93: bracketDepth = max(0, bracketDepth - 1)
        default:
            if bytes[index] == needle,
               parenDepth == 0, braceDepth == 0, bracketDepth == 0
            {
                results.append(
                    String(decoding: bytes[start..<index], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                start = index + 1
            }
        }
        index += 1
    }
    results.append(
        String(decoding: bytes[start...], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    )
    return results
}

private func skipQuotedServiceWorkerJS(
    _ bytes: [UInt8],
    start: Int
) -> Int {
    let quote = bytes[start]
    var index = start + 1
    var escaped = false
    while index < bytes.count {
        if escaped {
            escaped = false
        } else if bytes[index] == 92 {
            escaped = true
        } else if bytes[index] == quote {
            return index + 1
        }
        index += 1
    }
    return index
}

private func skipRegexLiteralServiceWorkerJS(
    _ bytes: [UInt8],
    start: Int
) -> Int? {
    guard bytes[start] == 47,
          start + 1 < bytes.count,
          bytes[start + 1] != 47,
          bytes[start + 1] != 42
    else { return nil }
    if let previous = previousSignificantByteServiceWorkerJS(
        bytes,
        before: start
    ),
       regexLiteralCanFollowServiceWorkerJS(previous) == false
    {
        return nil
    }

    var index = start + 1
    var escaped = false
    var inCharacterClass = false
    while index < bytes.count {
        let byte = bytes[index]
        if escaped {
            escaped = false
        } else if byte == 92 {
            escaped = true
        } else if byte == 91 {
            inCharacterClass = true
        } else if byte == 93 {
            inCharacterClass = false
        } else if byte == 47, inCharacterClass == false {
            index += 1
            while index < bytes.count,
                  isIdentifierPartServiceWorkerJS(bytes[index])
            {
                index += 1
            }
            return index
        } else if byte == 10 || byte == 13 {
            return nil
        }
        index += 1
    }
    return nil
}

private func regexLiteralCanFollowServiceWorkerJS(_ byte: UInt8) -> Bool {
    switch byte {
    case 33, 37, 38, 40, 42, 43, 44, 45, 58, 59, 60, 61, 62,
         63, 91, 94, 123, 124, 126:
        return true
    default:
        return false
    }
}

private func stringIndexServiceWorkerJS(
    _ utf8Offset: Int,
    in source: String
) -> String.Index? {
    guard utf8Offset >= 0,
          utf8Offset <= source.utf8.count
    else { return nil }
    let utf8Index = source.utf8.index(
        source.utf8.startIndex,
        offsetBy: utf8Offset
    )
    return utf8Index.samePosition(in: source)
}

private func previousSignificantByteServiceWorkerJS(
    _ bytes: [UInt8],
    before index: Int
) -> UInt8? {
    guard index > 0 else { return nil }
    var cursor = index - 1
    while cursor >= 0 {
        if isWhitespaceServiceWorkerJS(bytes[cursor]) == false {
            return bytes[cursor]
        }
        if cursor == 0 { break }
        cursor -= 1
    }
    return nil
}

private func followingSignificantByteServiceWorkerJS(
    _ bytes: [UInt8],
    after index: Int
) -> UInt8? {
    var cursor = index + 1
    while cursor < bytes.count {
        if isWhitespaceServiceWorkerJS(bytes[cursor]) == false {
            return bytes[cursor]
        }
        cursor += 1
    }
    return nil
}

private func isIdentifierStartServiceWorkerJS(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte)
        || byte == 36 || byte == 95
}

private func isIdentifierPartServiceWorkerJS(_ byte: UInt8) -> Bool {
    isIdentifierStartServiceWorkerJS(byte) || (48...57).contains(byte)
}

private func isWhitespaceServiceWorkerJS(_ byte: UInt8) -> Bool {
    byte == 9 || byte == 10 || byte == 13 || byte == 32
}

private func normalizeImportScriptsPath(
    _ path: String,
    extensionID: String? = nil
) -> (
    path: String?,
    blocker: ChromeMV3ServiceWorkerJSImportScriptsBlocker?,
    message: String
) {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false,
          trimmed.contains("\0") == false,
          trimmed.contains("\\") == false,
          trimmed.contains("?") == false,
          trimmed.contains("#") == false
    else {
        return (
            nil,
            .importPathUnsafe,
            "importScripts path is empty or contains unsupported characters."
        )
    }
    if let components = URLComponents(string: trimmed),
       let scheme = components.scheme?.lowercased()
    {
        switch scheme {
        case "http", "https":
            return (
                nil,
                .remoteURLRejected,
                "Remote importScripts URL imports are blocked."
            )
        case "file":
            return (
                nil,
                .fileURLRejected,
                "file: importScripts URL imports are blocked."
            )
        case "data":
            return (
                nil,
                .dataURLRejected,
                "data: importScripts URL imports are blocked."
            )
        case "blob":
            return (
                nil,
                .blobURLRejected,
                "blob: importScripts URL imports are blocked."
            )
        case "chrome-extension":
            guard let extensionID,
                  components.host == extensionID
            else {
                return (
                    nil,
                    .unsupportedScheme,
                    "Cross-extension chrome-extension importScripts URL imports are blocked."
                )
            }
            let relativePath = components.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return normalizeImportScriptsPath(
                relativePath,
                extensionID: nil
            )
        default:
            return (
                nil,
                .unsupportedScheme,
                "Unsupported importScripts URL scheme \(scheme) is blocked."
            )
        }
    }
    guard trimmed.hasPrefix("/") == false,
          trimmed.hasPrefix("~") == false
    else {
        return (
            nil,
            .absoluteFilesystemPathRejected,
            "Absolute importScripts paths are blocked."
        )
    }
    var components: [String] = []
    for component in trimmed.split(
        separator: "/",
        omittingEmptySubsequences: false
    ).map(String.init) {
        if component == "." { continue }
        if component == ".." {
            return (
                nil,
                .importPathTraversalRejected,
                "Traversal importScripts paths are blocked."
            )
        }
        guard component.isEmpty == false else {
            return (
                nil,
                .importPathUnsafe,
                "importScripts path contains an empty path segment."
            )
        }
        components.append(component)
    }
    guard components.isEmpty == false else {
        return (
            nil,
            .importPathUnsafe,
            "importScripts path did not contain a file segment."
        )
    }
    return (
        components.joined(separator: "/"),
        nil,
        "importScripts path normalized safely."
    )
}

private func isSameExtensionURLServiceWorkerJS(
    _ path: String,
    extensionID: String
) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let components = URLComponents(string: trimmed),
          components.scheme?.lowercased() == "chrome-extension"
    else { return false }
    return components.host == extensionID
}

private func normalizeDynamicImportPath(
    _ path: String,
    extensionID: String? = nil
) -> (
    path: String?,
    blocker: ChromeMV3ServiceWorkerJSDynamicImportBlocker?,
    message: String
) {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false,
          trimmed.contains("\0") == false,
          trimmed.contains("\\") == false,
          trimmed.contains("?") == false,
          trimmed.contains("#") == false
    else {
        return (
            nil,
            .importPathUnsafe,
            "Dynamic import path is empty or contains unsupported characters."
        )
    }
    if let components = URLComponents(string: trimmed),
       let scheme = components.scheme?.lowercased()
    {
        switch scheme {
        case "http", "https":
            return (
                nil,
                .remoteURLRejected,
                "Remote dynamic import URL imports are blocked."
            )
        case "file":
            return (
                nil,
                .fileURLRejected,
                "file: dynamic import URL imports are blocked."
            )
        case "data":
            return (
                nil,
                .dataURLRejected,
                "data: dynamic import URL imports are blocked."
            )
        case "blob":
            return (
                nil,
                .blobURLRejected,
                "blob: dynamic import URL imports are blocked."
            )
        case "chrome-extension":
            guard let extensionID,
                  components.host == extensionID
            else {
                return (
                    nil,
                    .unsupportedScheme,
                    "Cross-extension chrome-extension dynamic import URL imports are blocked."
                )
            }
            let relativePath = components.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return normalizeDynamicImportPath(
                relativePath,
                extensionID: nil
            )
        default:
            return (
                nil,
                .unsupportedScheme,
                "Unsupported dynamic import URL scheme \(scheme) is blocked."
            )
        }
    }
    guard trimmed.hasPrefix("/") == false,
          trimmed.hasPrefix("~") == false
    else {
        return (
            nil,
            .absoluteFilesystemPathRejected,
            "Absolute dynamic import paths are blocked."
        )
    }
    var components: [String] = []
    for component in trimmed.split(
        separator: "/",
        omittingEmptySubsequences: false
    ).map(String.init) {
        if component == "." { continue }
        if component == ".." {
            return (
                nil,
                .importPathTraversalRejected,
                "Traversal dynamic import paths are blocked."
            )
        }
        guard component.isEmpty == false else {
            return (
                nil,
                .importPathUnsafe,
                "Dynamic import path contains an empty path segment."
            )
        }
        components.append(component)
    }
    guard components.isEmpty == false else {
        return (
            nil,
            .importPathUnsafe,
            "Dynamic import path did not contain a file segment."
        )
    }
    return (
        components.joined(separator: "/"),
        nil,
        "Dynamic import path normalized safely."
    )
}

private func jsonStringServiceWorkerJS(_ value: String) -> String {
    guard
        let data = try? JSONSerialization.data(
            withJSONObject: [value],
            options: []
        ),
        let json = String(data: data, encoding: .utf8)
    else {
        return "\"\""
    }
    return String(json.dropFirst().dropLast())
}

private func stableIDServiceWorkerJS(
    prefix: String,
    parts: [String]
) -> String {
    let seed = parts.joined(separator: "|")
    return "\(prefix)-\(sha256HexServiceWorkerJS(Data(seed.utf8)).prefix(32))"
}

private func sha256HexServiceWorkerJS(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func uniqueSortedServiceWorkerJS<T: Comparable & Hashable>(
    _ values: [T]
) -> [T] {
    Array(Set(values)).sorted()
}
