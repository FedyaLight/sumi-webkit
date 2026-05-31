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
    var moduleWorkerImportAvailable: Bool
    var permanentBackgroundAvailable: Bool
    var timersAllowed: Bool
    var pollingAllowed: Bool
    var blockers: [ChromeMV3ServiceWorkerJSExecutionPolicyBlocker]
    var diagnostics: [String]

    static func evaluate(
        moduleState: ChromeMV3ProfileHostModuleState,
        extensionEnabled: Bool,
        localExperimentalGateAllowed: Bool,
        generatedBundleRecordAvailable: Bool,
        dynamicImportRewriteExperimentAllowed: Bool = false
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
            moduleWorkerImportAvailable: false,
            permanentBackgroundAvailable: false,
            timersAllowed: false,
            pollingAllowed: false,
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
                        "Lifetime transitions are explicit fixture calls only.",
                        "Stable product runtime remains default-off.",
                    ]
                        + blockers.map { "Policy blocker: \($0.rawValue)." }
                        + dynamicImportCapability.diagnostics
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
            "runtime.onMessage, runtime.onConnect, MessageSender, Port, native messaging permission, and Port lifecycle were checked."
        ),
        source(
            "Chrome storage API",
            "https://developer.chrome.com/docs/extensions/reference/api/storage",
            "storage.onChanged dispatch shape was checked."
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

    init(
        manifest: ChromeMV3Manifest,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        extensionID: String,
        profileID: String,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        extensionEnabled: Bool = true,
        localExperimentalGateAllowed: Bool = false,
        dynamicImportRewriteExperimentAllowed: Bool = false
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
                containsServiceWorkerJSRegex("\\bimport\\s*\\(", in: $0)
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
    var blockers: [ChromeMV3ServiceWorkerJSExecutionStartBlocker]
    var lastErrorMessage: String?
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
    var dispatchRecords: [ChromeMV3ServiceWorkerJSDispatchRecord]
    var ports: [ChromeMV3ServiceWorkerJSPortRecord]
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
    private var dispatchRecords: [ChromeMV3ServiceWorkerJSDispatchRecord] = []
    private var ports: [String: ChromeMV3ServiceWorkerJSPortRecord] = [:]
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
            blockers: [],
            lastErrorMessage: nil,
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
                request.dynamicImportRewriteExperimentAllowed
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
            dispatchRecords: dispatchRecords,
            ports: ports.values.sorted { $0.portID < $1.portID },
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
            installImportScriptsHost(in: context)
            installDynamicImportRewriteHost(in: context)
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
            let message = evaluateScriptInContext(
                source,
                sourceURL: sourceURL,
                context: context
            )
            importEvaluationStack.removeAll()
            syncImportRecordsIntoResourceLoad()
            if let message {
                self.context = nil
                return finishStart(
                    status: .failed,
                    blockers: [.scriptEvaluationFailed],
                    lastErrorMessage: message,
                    diagnostics:
                        loaded.record.diagnostics
                            + [
                                "Extension-owned classic worker evaluation failed inside the isolated JavaScriptCore surface.",
                            ]
                )
            }
            if loaded.record.dynamicImportRewriteExperimentApplied,
               let blocker = resourceLoadRecord?.dynamicImportBlockers.first
            {
                self.context = nil
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
        guard startRecord.status == .running else { return nil }
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
        reason: String = "explicitPortDisconnect"
    ) -> Bool {
        guard ports[portID] != nil else { return false }
        #if canImport(JavaScriptCore)
            let _: ChromeMV3ServiceWorkerJSWirePort? = callJSON(
                "__sumiHarness.disconnectPort(\(jsonStringServiceWorkerJS(portID)), \(jsonStringServiceWorkerJS(reason)))"
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
        dispatchRecords.removeAll()
        ports.removeAll()
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
        guard start().status == .running, let session = lifecycleSession else {
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
            && startRecord.status == .running
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
            blockers: uniqueSortedServiceWorkerJS(blockers),
            lastErrorMessage: lastErrorMessage,
            diagnostics: uniqueSortedServiceWorkerJS(diagnostics)
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

        private func evaluateScriptInContext(
            _ source: String,
            sourceURL: URL,
            context: JSContext
        ) -> String? {
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
            let message = context.exception?.toString()
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
            return message
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
                let message = evaluateScriptInContext(
                    source,
                    sourceURL: sourceURL,
                    context: context
                )
                _ = importEvaluationStack.popLast()
                if let message {
                    let failed = appendImportScriptBlocker(
                        .scriptEvaluationFailed,
                        message:
                            "Imported script evaluation failed: \(message)"
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
            let message = evaluateScriptInContext(
                source,
                sourceURL: sourceURL,
                context: context
            )
            _ = importEvaluationStack.popLast()
            var record = loaded.record
            record.rewritten = true
            if let message {
                record.evaluated = false
                record.blockers =
                    uniqueSortedServiceWorkerJS(
                        record.blockers + [.scriptEvaluationFailed]
                    )
                record.diagnostics =
                    uniqueSortedServiceWorkerJS(
                        record.diagnostics
                            + [
                                "Rewritten dynamic import dependency evaluation failed: \(message)",
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
            let normalized = normalizeImportScriptsPath(requestPath)
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
            let parentDirectory = parentURL?
                .deletingLastPathComponent()
                .standardizedFileURL ?? root
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
            if containsServiceWorkerJSRegex("\\bimport\\s*\\(", in: source) {
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
                    ]
                ),
                source,
                candidate
            )
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
            let normalized = normalizeDynamicImportPath(requestPath)
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
            let parentDirectory = parentURL?
                .deletingLastPathComponent()
                .standardizedFileURL ?? root
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
                            ? "Async function registration detected; pending Promise completion remains deterministically deferred."
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
            .storageOnChanged,
            .permissionsOnAdded,
            .permissionsOnRemoved,
            .alarmsOnAlarm,
            .contextMenusOnClicked,
            .webNavigationOnBeforeNavigate,
            .webNavigationOnCommitted,
            .webNavigationOnCompleted,
            .webNavigationOnDOMContentLoaded,
            .webNavigationOnErrorOccurred,
            .webNavigationOnHistoryStateUpdated,
            .webNavigationOnReferenceFragmentUpdated,
            .nativePortOnMessage,
            .nativePortOnDisconnect,
        ]

    private static let registrationShim = #"""
    (() => {
      'use strict';
      const registrations = [];
      const blockedCalls = [];
      const ports = new Map();
      let registrationOrder = 0;

      const clone = (value) => {
        if (value === undefined) return null;
        try { return JSON.parse(JSON.stringify(value)); }
        catch (_) { return null; }
      };
      const noteBlocked = (path) => {
        if (!blockedCalls.includes(path)) blockedCalls.push(path);
      };
      const unsupported = (path) => new Proxy(function () {
        noteBlocked(path);
        return undefined;
      }, {
        get(_target, property) {
          if (property === 'then') return undefined;
          return unsupported(`${path}.${String(property)}`);
        },
        apply() {
          noteBlocked(path);
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
      const proxiedNamespace = (known, path) => new Proxy(known, {
        get(target, property) {
          if (Object.prototype.hasOwnProperty.call(target, property)) {
            return target[property];
          }
          return unsupported(`${path}.${String(property)}`);
        }
      });
      const createPort = (options, sender) => {
        const existing = ports.get(options.portID);
        if (existing) return existing.port;
        const onMessage = localEvent();
        const onDisconnect = localEvent();
        const state = {
          portID: options.portID,
          name: options.name || '',
          sender: sender || {},
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
          sender: state.sender,
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
      const disconnectPort = (portID, reason) => {
        const state = ports.get(portID);
        if (!state || !state.connected) return state ? portSnapshot(state) : null;
        state.connected = false;
        state.disconnectReason = reason || 'explicitDisconnect';
        for (const listener of [...state.onDisconnect.listeners]) {
          try { listener(state.port); }
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
          try { listener(clone(message), state.port); }
          catch (_) { noteBlocked(`port.${portID}.onMessage.listenerError`); }
        }
        return portSnapshot(state);
      };
      const runtime = proxiedNamespace({
        onMessage: event('runtimeOnMessage'),
        onConnect: event('runtimeOnConnect')
      }, 'chrome.runtime');
      const storage = proxiedNamespace({
        onChanged: event('storageOnChanged')
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
      const webNavigation = proxiedNamespace({
        onBeforeNavigate: event('webNavigationOnBeforeNavigate'),
        onCommitted: event('webNavigationOnCommitted'),
        onCompleted: event('webNavigationOnCompleted'),
        onDOMContentLoaded: event('webNavigationOnDOMContentLoaded'),
        onErrorOccurred: event('webNavigationOnErrorOccurred'),
        onHistoryStateUpdated: event('webNavigationOnHistoryStateUpdated'),
        onReferenceFragmentUpdated: event('webNavigationOnReferenceFragmentUpdated')
      }, 'chrome.webNavigation');
      globalThis.chrome = proxiedNamespace({
        runtime,
        storage,
        permissions,
        alarms,
        contextMenus,
        webNavigation
      }, 'chrome');
      globalThis.browser = globalThis.chrome;
      globalThis.self = globalThis;
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
      for (const name of [
        'fetch',
        'XMLHttpRequest',
        'WebSocket',
        'EventSource',
        'setTimeout',
        'setInterval',
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
            const listenerArgs = eventName === 'runtimeOnConnect'
              ? [port]
              : [...args, sender || {}, sendResponse];
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
              result.then(() => {}, () => {});
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
        ports: [...ports.values()].map(portSnapshot)
      });
      globalThis.__sumiHarness = {
        snapshot,
        dispatch,
        createPort,
        deliverPortMessage,
        disconnectPort
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
    var ports: [ChromeMV3ServiceWorkerJSWirePort]
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
        return ChromeMV3ServiceWorkerEventSenderMetadata(
            tabID: object["tabID"]?.serviceWorkerJSInt,
            frameID: object["frameID"]?.serviceWorkerJSInt,
            documentID: object["documentID"]?.serviceWorkerJSString,
            sourceURL: object["sourceURL"]?.serviceWorkerJSString,
            urlRedacted:
                object["urlRedacted"]?.serviceWorkerJSBool ?? true,
            redactionState:
                object["redactionState"]?.serviceWorkerJSString
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

private func rewriteDynamicImportsForHarnessServiceWorkerJS(
    _ source: String
) -> String {
    guard let expression = try? NSRegularExpression(
        pattern: #"\bimport\s*\(\s*(['"])(.*?)\1\s*\)"#
    ) else { return source }
    let range = NSRange(source.startIndex..., in: source)
    return expression.stringByReplacingMatches(
        in: source,
        range: range,
        withTemplate:
            #"globalThis.__sumiDynamicImportRewrite($1$2$1)"#
    )
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
    guard let expression = try? NSRegularExpression(
        pattern: #"\bimport\s*\(\s*(['"])(.*?)\1\s*\)"#
    ) else { return [] }
    let range = NSRange(source.startIndex..., in: source)
    let matches = expression.matches(in: source, range: range)
    var records: [ChromeMV3ServiceWorkerJSDynamicImportRecord] =
        matches.compactMap { match in
            guard let pathRange = Range(match.range(at: 2), in: source)
            else { return nil }
            return dynamicImportRecordServiceWorkerJS(
                requestPath: String(source[pathRange]),
                parentScriptRelativePath: parentScriptRelativePath,
                parentURL: parentURL,
                generatedBundleRecord: generatedBundleRecord,
                generatedBundleRoot: generatedBundleRoot,
                capability: capability,
                includeCapabilityBlockers: includeCapabilityBlockers
            )
        }
    let sourceWithoutStringLiteralImports = expression
        .stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: ""
        )
    if containsServiceWorkerJSRegex(
        "\\bimport\\s*\\(",
        in: sourceWithoutStringLiteralImports
    )
    {
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

private func normalizeImportScriptsPath(
    _ path: String
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
    if let scheme = URLComponents(string: trimmed)?.scheme?.lowercased() {
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

private func normalizeDynamicImportPath(
    _ path: String
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
    if let scheme = URLComponents(string: trimmed)?.scheme?.lowercased() {
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
