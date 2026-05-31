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
    var permanentBackgroundAvailable: Bool
    var timersAllowed: Bool
    var pollingAllowed: Bool
    var blockers: [ChromeMV3ServiceWorkerJSExecutionPolicyBlocker]
    var diagnostics: [String]

    static func evaluate(
        moduleState: ChromeMV3ProfileHostModuleState,
        extensionEnabled: Bool,
        localExperimentalGateAllowed: Bool,
        generatedBundleRecordAvailable: Bool
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
        blockers = uniqueSortedServiceWorkerJS(blockers)
        let available = blockers.isEmpty && javaScriptCoreAvailable
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
                        "Lifetime transitions are explicit fixture calls only.",
                        "Stable product runtime remains default-off.",
                    ]
                        + blockers.map { "Policy blocker: \($0.rawValue)." }
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
            "background.service_worker declares one packaged JavaScript file; module workers require background.type=module; dynamic import is unsupported."
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

    init(
        manifest: ChromeMV3Manifest,
        generatedBundleRecord: ChromeMV3GeneratedBundleRecord?,
        extensionID: String,
        profileID: String,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        extensionEnabled: Bool = true,
        localExperimentalGateAllowed: Bool = false
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
        if importScriptsDetected {
            blockers.append(.importScriptsUnsupported)
        }
        if staticImportDetected {
            blockers.append(.staticModuleImportUnsupported)
        }
        if dynamicImportDetected {
            blockers.append(.dynamicImportUnsupported)
        }
        blockers = uniqueSortedServiceWorkerJS(blockers)
        let canExecute =
            blockers.isEmpty
            && type == "classic"
            && source != nil
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
            webAccessibleResourcesRequiredForWorkerLoad: false,
            canExecuteClassicWorkerNow: canExecute,
            blockers: blockers,
            diagnostics:
                uniqueSortedServiceWorkerJS(
                    [
                        "Only an extension-owned resource copied into its generated bundle record may execute.",
                        "The worker path is checked for relative-path safety, generated-root containment, regular-file presence, and symbolic-link rejection.",
                        "web_accessible_resources is not required for internal service-worker package loading.",
                        "Generated inert wrapper and service-worker shim resources must already exist.",
                    ]
                        + blockers.map { "Resource blocker: \($0.rawValue)." }
                )
        )
        return ChromeMV3ServiceWorkerJSLoadedResource(
            record: loadRecord,
            source: canExecute ? source : nil,
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
    private var blockedUnsupportedCalls: [String] = []
    private var dispatchRecords: [ChromeMV3ServiceWorkerJSDispatchRecord] = []
    private var ports: [String: ChromeMV3ServiceWorkerJSPortRecord] = [:]
    private var lifecycleKeepaliveIDsByPort: [String: String] = [:]
    private var nextPortSequence = 1
    #if canImport(JavaScriptCore)
        private var virtualMachine: JSVirtualMachine?
        private var context: JSContext?
    #endif
    private(set) var startRecord =
        ChromeMV3ServiceWorkerJSExecutionStartRecord(
            status: .notStarted,
            executionSurface: .none,
            capturedListenerCount: 0,
            capturedListenerFamilies: [],
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
                request.generatedBundleRecord != nil
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
            _ = context.evaluateScript(
                Self.registrationShim,
                withSourceURL:
                    URL(fileURLWithPath: "/sumi-local-experimental/service-worker-shim.js")
            )
            if let message = context.exception?.toString() {
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
            _ = context.evaluateScript(source, withSourceURL: sourceURL)
            if let message = context.exception?.toString() {
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
            virtualMachine = vm
            self.context = context
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
        blockedUnsupportedCalls.removeAll()
        dispatchRecords.removeAll()
        ports.removeAll()
        lifecycleKeepaliveIDsByPort.removeAll()
        nextPortSequence = 1
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
            blockedUnsupportedCalls: blockedUnsupportedCalls,
            blockers: uniqueSortedServiceWorkerJS(blockers),
            lastErrorMessage: lastErrorMessage,
            diagnostics: uniqueSortedServiceWorkerJS(diagnostics)
        )
        return startRecord
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
                    listenerSourceFile: source,
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
          asyncFunction: item.asyncFunction
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
