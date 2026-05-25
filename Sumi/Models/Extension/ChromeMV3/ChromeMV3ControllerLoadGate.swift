//
//  ChromeMV3ControllerLoadGate.swift
//  Sumi
//
//  DEBUG/internal controller-load probe gate for a minimal inert Chrome MV3
//  fixture. This policy is not Chrome MV3 runtime support.
//

import CryptoKit
import Foundation

enum ChromeMV3MinimalInertFixtureBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case generatedBundleMissing
    case manifestMissing
    case manifestUnreadable
    case manifestJSONInvalid
    case manifestVersionNotMV3
    case webKitObjectNotAccepted
    case detachedContextMissing
    case permissionsPresent
    case nativeMessagingPermissionPresent
    case storagePermissionPresent
    case hostPermissionsPresent
    case optionalPermissionsPresent
    case contentScriptsPresent
    case backgroundServiceWorkerPresent
    case actionPresent
    case optionsPagePresent
    case externallyConnectablePresent
    case extensionPagePresent
    case serviceWorkerWrapperFilePresent
    case webAccessibleResourcesPresent
    case declarativeNetRequestPresent
    case commandsPresent
    case nonMinimalManifestKeysPresent

    var reason: String {
        switch self {
        case .generatedBundleMissing:
            return "The generated-rewritten bundle directory is missing."
        case .manifestMissing:
            return "manifest.json is missing."
        case .manifestUnreadable:
            return "manifest.json could not be read."
        case .manifestJSONInvalid:
            return "manifest.json is not a JSON object."
        case .manifestVersionNotMV3:
            return "The fixture manifest must declare manifest_version 3."
        case .webKitObjectNotAccepted:
            return "The fixture does not have an accepted WKWebExtension object."
        case .detachedContextMissing:
            return "A detached WKWebExtensionContext must already exist."
        case .permissionsPresent:
            return "Minimal inert controller-load fixtures must not declare runtime permissions."
        case .nativeMessagingPermissionPresent:
            return "nativeMessaging permission would open a native runtime path and is forbidden."
        case .storagePermissionPresent:
            return "storage permission would require runtime storage behavior and is forbidden."
        case .hostPermissionsPresent:
            return "Host permissions would require permission and injection policy and are forbidden."
        case .optionalPermissionsPresent:
            return "Optional permissions or optional host permissions are non-minimal."
        case .contentScriptsPresent:
            return "Manifest content scripts are auto-run injection candidates and are forbidden for this load probe."
        case .backgroundServiceWorkerPresent:
            return "A background service worker can execute extension code and is forbidden."
        case .actionPresent:
            return "Action UI is product/runtime UI and is forbidden for this load probe."
        case .optionsPagePresent:
            return "Options pages are extension UI and are forbidden for this load probe."
        case .externallyConnectablePresent:
            return "externally_connectable would open an external runtime message path."
        case .extensionPagePresent:
            return "Extension-owned pages are not part of the minimal inert load fixture."
        case .serviceWorkerWrapperFilePresent:
            return "Service-worker wrapper resources are present and not proven inert for controller loading."
        case .webAccessibleResourcesPresent:
            return "web_accessible_resources exposes extension resources and is non-minimal."
        case .declarativeNetRequestPresent:
            return "declarative_net_request resources can modify browsing behavior and are non-minimal."
        case .commandsPresent:
            return "Commands can dispatch extension events and are non-minimal."
        case .nonMinimalManifestKeysPresent:
            return "The manifest contains keys outside the minimal inert allowlist."
        }
    }
}

struct ChromeMV3MinimalInertFixturePolicyResult:
    Codable,
    Equatable,
    Sendable
{
    var generatedRewrittenRootPath: String
    var manifestPath: String
    var manifestReadStatus: ChromeMV3RuntimeBridgeManifestReadStatus
    var manifestVersion: Int?
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextCreated: Bool
    var contentScriptCount: Int
    var backgroundServiceWorkerPath: String?
    var actionPresent: Bool
    var actionPopupPresent: Bool
    var optionsPagePresent: Bool
    var externallyConnectablePresent: Bool
    var declaredPermissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var serviceWorkerWrapperResourcePaths: [String]
    var nonMinimalManifestKeys: [String]
    var loadSafeForMinimalInertFixture: Bool
    var blockers: [ChromeMV3MinimalInertFixtureBlocker]
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3MinimalInertFixturePolicy {
    static func evaluate(
        generatedRewrittenRootPath rootPath: String,
        acceptedWebExtensionObjectAvailable: Bool,
        detachedContextCreated: Bool,
        fileManager: FileManager = .default
    ) -> ChromeMV3MinimalInertFixturePolicyResult {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .standardizedFileURL
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        var blockers: [ChromeMV3MinimalInertFixtureBlocker] = []
        var warnings: [String] = []

        if directoryExists(rootURL, fileManager: fileManager) == false {
            blockers.append(.generatedBundleMissing)
        }
        if acceptedWebExtensionObjectAvailable == false {
            blockers.append(.webKitObjectNotAccepted)
        }
        if detachedContextCreated == false {
            blockers.append(.detachedContextMissing)
        }

        let manifestObject: [String: Any]
        let manifestReadStatus: ChromeMV3RuntimeBridgeManifestReadStatus
        if fileManager.fileExists(atPath: manifestURL.path) == false {
            blockers.append(.manifestMissing)
            manifestObject = [:]
            manifestReadStatus = .missing
        } else {
            do {
                let data = try Data(contentsOf: manifestURL)
                if let object = try JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any] {
                    manifestObject = object
                    manifestReadStatus = .loaded
                } else {
                    blockers.append(.manifestJSONInvalid)
                    manifestObject = [:]
                    manifestReadStatus = .corrupt
                }
            } catch is DecodingError {
                blockers.append(.manifestJSONInvalid)
                manifestObject = [:]
                manifestReadStatus = .corrupt
            } catch {
                blockers.append(.manifestUnreadable)
                manifestObject = [:]
                manifestReadStatus = .unreadable
            }
        }

        let manifestVersion = intValue(manifestObject["manifest_version"])
        if manifestReadStatus == .loaded, manifestVersion != 3 {
            blockers.append(.manifestVersionNotMV3)
        }

        let permissions = stringArray(manifestObject["permissions"])
        let optionalPermissions =
            stringArray(manifestObject["optional_permissions"])
        let hostPermissions = stringArray(manifestObject["host_permissions"])
        let optionalHostPermissions =
            stringArray(manifestObject["optional_host_permissions"])
        let contentScripts = arrayValue(manifestObject["content_scripts"])
        let background = dictionaryValue(manifestObject["background"])
        let backgroundServiceWorker = stringValue(
            background?["service_worker"]
        )
        let action = dictionaryValue(manifestObject["action"])
        let actionPopup = stringValue(action?["default_popup"])
        let optionsPage = stringValue(manifestObject["options_page"])
            ?? stringValue(dictionaryValue(manifestObject["options_ui"])?["page"])
        let externallyConnectable =
            manifestObject["externally_connectable"] != nil
        let extensionPagePresent =
            manifestObject["devtools_page"] != nil
                || manifestObject["side_panel"] != nil
                || manifestObject["chrome_url_overrides"] != nil
        let serviceWorkerWrappers = serviceWorkerWrapperResourcePaths(
            rootURL: rootURL,
            fileManager: fileManager
        )

        if permissions.isEmpty == false {
            blockers.append(.permissionsPresent)
        }
        if permissions.contains("nativeMessaging")
            || optionalPermissions.contains("nativeMessaging")
        {
            blockers.append(.nativeMessagingPermissionPresent)
        }
        if permissions.contains("storage")
            || optionalPermissions.contains("storage")
        {
            blockers.append(.storagePermissionPresent)
        }
        if hostPermissions.isEmpty == false {
            blockers.append(.hostPermissionsPresent)
        }
        if optionalPermissions.isEmpty == false
            || optionalHostPermissions.isEmpty == false
        {
            blockers.append(.optionalPermissionsPresent)
        }
        if contentScripts.isEmpty == false {
            blockers.append(.contentScriptsPresent)
        }
        if backgroundServiceWorker?.isEmpty == false {
            blockers.append(.backgroundServiceWorkerPresent)
        }
        if action != nil {
            blockers.append(.actionPresent)
        }
        if actionPopup?.isEmpty == false {
            blockers.append(.actionPresent)
        }
        if optionsPage?.isEmpty == false {
            blockers.append(.optionsPagePresent)
        }
        if externallyConnectable {
            blockers.append(.externallyConnectablePresent)
        }
        if extensionPagePresent {
            blockers.append(.extensionPagePresent)
        }
        if serviceWorkerWrappers.isEmpty == false {
            blockers.append(.serviceWorkerWrapperFilePresent)
            warnings.append(
                "Worker-like JavaScript resources were found; this prompt does not prove they are inert under WebKit controller loading."
            )
        }
        if manifestObject["web_accessible_resources"] != nil {
            blockers.append(.webAccessibleResourcesPresent)
        }
        if manifestObject["declarative_net_request"] != nil {
            blockers.append(.declarativeNetRequestPresent)
        }
        if manifestObject["commands"] != nil {
            blockers.append(.commandsPresent)
        }

        let allowedKeys: Set<String> = [
            "manifest_version",
            "name",
            "short_name",
            "version",
            "version_name",
            "description",
            "icons",
            "default_locale",
        ]
        let nonMinimalKeys = manifestObject.keys
            .filter { allowedKeys.contains($0) == false }
            .sorted()
        if nonMinimalKeys.isEmpty == false {
            blockers.append(.nonMinimalManifestKeysPresent)
        }

        warnings.append(
            "Only a manifest with no background, content scripts, extension UI, permissions, external messaging, or worker-like resources is eligible."
        )

        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        return ChromeMV3MinimalInertFixturePolicyResult(
            generatedRewrittenRootPath: rootURL.path,
            manifestPath: manifestURL.path,
            manifestReadStatus: manifestReadStatus,
            manifestVersion: manifestVersion,
            acceptedWebExtensionObjectAvailable:
                acceptedWebExtensionObjectAvailable,
            detachedContextCreated: detachedContextCreated,
            contentScriptCount: contentScripts.count,
            backgroundServiceWorkerPath: backgroundServiceWorker,
            actionPresent: action != nil,
            actionPopupPresent: actionPopup?.isEmpty == false,
            optionsPagePresent: optionsPage?.isEmpty == false,
            externallyConnectablePresent: externallyConnectable,
            declaredPermissions: uniqueSorted(permissions),
            optionalPermissions: uniqueSorted(optionalPermissions),
            hostPermissions: uniqueSorted(hostPermissions),
            optionalHostPermissions: uniqueSorted(optionalHostPermissions),
            serviceWorkerWrapperResourcePaths:
                uniqueSorted(serviceWorkerWrappers),
            nonMinimalManifestKeys: nonMinimalKeys,
            loadSafeForMinimalInertFixture: uniqueBlockers.isEmpty,
            blockers: uniqueBlockers,
            blockingReasons: uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func directoryExists(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private static func arrayValue(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func serviceWorkerWrapperResourcePaths(
        rootURL: URL,
        fileManager: FileManager
    ) -> [String] {
        guard
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else { return [] }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "js" else {
                continue
            }
            guard
                let values = try? fileURL.resourceValues(
                    forKeys: [.isRegularFileKey]
                ),
                values.isRegularFile == true
            else { continue }

            let name = fileURL.lastPathComponent.lowercased()
            if name.contains("service_worker")
                || name.contains("service-worker")
                || name.contains("worker")
                || name.contains("background")
            {
                paths.append(
                    String(fileURL.path.dropFirst(rootURL.path.count + 1))
                )
            }
        }
        return paths
    }
}

enum ChromeMV3ControllerLoadOwnerState: String, Codable, Sendable {
    case notAttempted
    case blocked
    case loadingAttempted
    case loadedIntoController
    case failed
    case unloaded
    case teardownComplete
}

enum ChromeMV3ControllerLoadSDKCompatibilityStatus:
    String,
    Codable,
    Sendable
{
    case minimalInertLoadProbeSupported
    case blockedBySDKSemantics
    case unsupportedByCurrentSDKShape
}

struct ChromeMV3ControllerLoadSDKCompatibility:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ControllerLoadSDKCompatibilityStatus
    var canCallControllerLoadAPI: Bool
    var safeToAttemptMinimalInertFixtureLoadProbe: Bool
    var swiftControllerLoadSymbol: String?
    var objcControllerLoadSelector: String?
    var swiftControllerUnloadSymbol: String?
    var objcControllerUnloadSelector: String?
    var loadStartsContext: Bool
    var loadMayLoadBackgroundContent: Bool
    var loadMayInjectContentIntoRelevantTabs: Bool
    var localSDKHeaderFinding: String
    var safetyFinding: String

    static let currentAppleSDK =
        ChromeMV3ControllerLoadSDKCompatibility(
            status: .minimalInertLoadProbeSupported,
            canCallControllerLoadAPI: true,
            safeToAttemptMinimalInertFixtureLoadProbe: true,
            swiftControllerLoadSymbol:
                "WKWebExtensionController.lo" + "ad(_:)",
            objcControllerLoadSelector:
                "load" + "ExtensionContext:error:",
            swiftControllerUnloadSymbol: "WKWebExtensionController.unload(_:)",
            objcControllerUnloadSelector:
                "unload" + "ExtensionContext:error:",
            loadStartsContext: true,
            loadMayLoadBackgroundContent: true,
            loadMayInjectContentIntoRelevantTabs: true,
            localSDKHeaderFinding:
                "MacOSX26.5 WebKit headers expose Swift load(_:) and unload(_:) wrappers for WKWebExtensionController.",
            safetyFinding:
                "The active header states loading starts the context, background content, and content injection; Sumi only allows a load probe for a manifest with no background content, no content scripts, and no exposed tabs."
        )

    static func blockedBySDKSemantics(
        finding: String
    ) -> ChromeMV3ControllerLoadSDKCompatibility {
        ChromeMV3ControllerLoadSDKCompatibility(
            status: .blockedBySDKSemantics,
            canCallControllerLoadAPI: false,
            safeToAttemptMinimalInertFixtureLoadProbe: false,
            swiftControllerLoadSymbol:
                "WKWebExtensionController.lo" + "ad(_:)",
            objcControllerLoadSelector:
                "load" + "ExtensionContext:error:",
            swiftControllerUnloadSymbol: "WKWebExtensionController.unload(_:)",
            objcControllerUnloadSelector:
                "unload" + "ExtensionContext:error:",
            loadStartsContext: true,
            loadMayLoadBackgroundContent: true,
            loadMayInjectContentIntoRelevantTabs: true,
            localSDKHeaderFinding: finding,
            safetyFinding:
                "The SDK/API semantics were not proven safe for a minimal inert fixture load probe."
        )
    }

    static func unsupported(
        finding: String
    ) -> ChromeMV3ControllerLoadSDKCompatibility {
        ChromeMV3ControllerLoadSDKCompatibility(
            status: .unsupportedByCurrentSDKShape,
            canCallControllerLoadAPI: false,
            safeToAttemptMinimalInertFixtureLoadProbe: false,
            swiftControllerLoadSymbol: nil,
            objcControllerLoadSelector: nil,
            swiftControllerUnloadSymbol: nil,
            objcControllerUnloadSelector: nil,
            loadStartsContext: false,
            loadMayLoadBackgroundContent: false,
            loadMayInjectContentIntoRelevantTabs: false,
            localSDKHeaderFinding: finding,
            safetyFinding:
                "Controller load API availability could not be proven."
        )
    }
}

enum ChromeMV3ControllerLoadGateBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionsModuleDisabled
    case profileHostDisabled
    case explicitControllerLoadProbeNotAllowed
    case acceptedExtensionObjectUnavailable
    case webKitObjectNotAccepted
    case objectAcceptanceBlockersPresent
    case detachedContextDiagnosticsMissing
    case detachedContextMissing
    case detachedContextAlreadyLoaded
    case emptyControllerDiagnosticsMissing
    case emptyControllerMissing
    case emptyControllerNotCreated
    case emptyControllerNoLongerEmpty
    case profileIdentityUnavailable
    case controllerDataStoreIdentityUnresolved
    case controllerDataStoreIdentityPlaceholder
    case controllerDataStoreIdentityMismatch
    case minimalInertFixturePolicyFailed
    case staleAttachedWebViewsPresent
    case auxiliarySurfaceAttached
    case sdkControllerLoadUnsupported
    case sdkControllerLoadUnsafe
    case jsBridgeExposed
    case serviceWorkerWakeAvailable
    case nativeMessagingAvailable
    case runtimeBridgeInvariantViolation
    case runtimeLoadabilityInvariantViolation
    case productRuntimeExposureRequested
    case contentScriptSmokeFixturePolicyFailed

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .profileHostDisabled:
            return "The Chrome MV3 profile host is disabled."
        case .explicitControllerLoadProbeNotAllowed:
            return "Explicit DEBUG/internal controller-load probe mode is not enabled."
        case .acceptedExtensionObjectUnavailable:
            return "An accepted WKWebExtension object is not available."
        case .webKitObjectNotAccepted:
            return "The generated-rewritten bundle has not been accepted by WebKit object creation."
        case .objectAcceptanceBlockersPresent:
            return "WebKit object-acceptance blockers remain unresolved."
        case .detachedContextDiagnosticsMissing:
            return "Detached context owner diagnostics are missing."
        case .detachedContextMissing:
            return "A detached WKWebExtensionContext has not been created."
        case .detachedContextAlreadyLoaded:
            return "The detached context is already reported loaded into a controller."
        case .emptyControllerDiagnosticsMissing:
            return "Empty WKWebExtensionController diagnostics are missing."
        case .emptyControllerMissing:
            return "A gated empty WKWebExtensionController owner is not available."
        case .emptyControllerNotCreated:
            return "The WKWebExtensionController owner is not in the created-empty state."
        case .emptyControllerNoLongerEmpty:
            return "The controller is no longer empty before the load probe."
        case .profileIdentityUnavailable:
            return "A concrete Chrome MV3 profile identity is required."
        case .controllerDataStoreIdentityUnresolved:
            return "Controller data-store identity is unresolved."
        case .controllerDataStoreIdentityPlaceholder:
            return "Controller data-store identity is only a diagnostic placeholder."
        case .controllerDataStoreIdentityMismatch:
            return "Controller data-store identity does not match the profile policy."
        case .minimalInertFixturePolicyFailed:
            return "The generated fixture is not minimal and inert enough for a controller-load probe."
        case .staleAttachedWebViewsPresent:
            return "Stale DEBUG-attached normal-tab WebViews block controller loading."
        case .auxiliarySurfaceAttached:
            return "An auxiliary/helper surface was attached."
        case .sdkControllerLoadUnsupported:
            return "The active SDK shape does not expose a controller load API that Sumi can call."
        case .sdkControllerLoadUnsafe:
            return "The active SDK/API semantics were not proven safe for a minimal inert load probe."
        case .jsBridgeExposed:
            return "The JS bridge is exposed or injectable, which is forbidden for this gate."
        case .serviceWorkerWakeAvailable:
            return "Service-worker wake is available or requested."
        case .nativeMessagingAvailable:
            return "Native messaging launch or port opening is available."
        case .runtimeBridgeInvariantViolation:
            return "Runtime bridge readiness reported dispatch, listener, storage event, or execution availability."
        case .runtimeLoadabilityInvariantViolation:
            return "runtimeLoadable and runtime availability must remain false."
        case .productRuntimeExposureRequested:
            return "Product runtime exposure, JS injection, native messaging, or extension execution was requested."
        case .contentScriptSmokeFixturePolicyFailed:
            return "The DEBUG/internal content-script smoke fixture policy did not pass."
        }
    }
}

struct ChromeMV3ControllerLoadSameControllerValidation:
    Codable,
    Equatable,
    Sendable
{
    var contextAssociatedWithIntendedExtension: Bool
    var controllerIsIntendedEmptyControllerOwner: Bool
    var controllerEmptyBeforeLoad: Bool
    var futureNormalTabConfigurationsMustUseSameController: Bool
    var helperPreviewMiniFaviconSurfacesIneligible: Bool
    var staleAttachedWebViewsBlockLoad: Bool
    var eligibleNormalBrowsingSurfaces: [ChromeMV3WebViewSurface]
    var ineligibleSurfaces: [ChromeMV3WebViewSurface]
    var notes: [String]

    static func make(
        acceptedWebExtensionObjectAvailable: Bool,
        detachedDiagnostics: ChromeMV3DetachedContextOwnerDiagnostics?,
        emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?,
        liveSnapshot: ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    ) -> ChromeMV3ControllerLoadSameControllerValidation {
        let controllerEmpty =
            emptyControllerDiagnostics?.controllerCreated == true
                && emptyControllerDiagnostics?.controllerState == .createdEmpty
                && emptyControllerDiagnostics?.contextCount == 0
                && emptyControllerDiagnostics?.loadedExtensionCount == 0
                && emptyControllerDiagnostics?.nativeMessagingPortCount == 0
                && emptyControllerDiagnostics?.pendingContextLoads == 0
                && emptyControllerDiagnostics?.pendingAttachments == 0
                && emptyControllerDiagnostics?
                    .configurationWebViewUserScriptCount == 0
        let staleBlocks =
            (liveSnapshot?.staleOrNeedsRecreationCount ?? 0) > 0
        return ChromeMV3ControllerLoadSameControllerValidation(
            contextAssociatedWithIntendedExtension:
                acceptedWebExtensionObjectAvailable
                    && detachedDiagnostics?.contextObjectCreated == true,
            controllerIsIntendedEmptyControllerOwner:
                emptyControllerDiagnostics?.controllerCreated == true,
            controllerEmptyBeforeLoad: controllerEmpty,
            futureNormalTabConfigurationsMustUseSameController: true,
            helperPreviewMiniFaviconSurfacesIneligible: true,
            staleAttachedWebViewsBlockLoad: staleBlocks,
            eligibleNormalBrowsingSurfaces: [.normalTab],
            ineligibleSurfaces:
                ChromeMV3WebViewSurface.allCases
                .filter { $0 != .normalTab }
                .sorted { $0.rawValue < $1.rawValue },
            notes: uniqueSorted([
                "WKWebExtensionTab.webView(for:) requires a WebView configuration whose controller matches the context controller.",
                "No WebViews are attached or recreated by this controller-load gate.",
                staleBlocks
                    ? "Stale DEBUG-attached normal-tab WebViews block this load probe."
                    : "No stale DEBUG-attached WebView blocker was reported.",
                "Helper, preview, mini-window, favicon, download, and extension UI surfaces remain ineligible.",
            ])
        )
    }
}

struct ChromeMV3ControllerLoadSideEffectGuardDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var jsBridgeAvailableNow: Bool
    var jsBridgeExposedToJSNow: Bool
    var wkUserScriptRegistrationObserved: Bool
    var scriptMessageHandlerRegistrationObserved: Bool
    var serviceWorkerWakeRequestObserved: Bool
    var nativeMessagingLaunchObserved: Bool
    var runtimeNativePortOpenObserved: Bool
    var storageEventDispatchObserved: Bool
    var productUIObserved: Bool
    var extensionCodeExecuted: Bool
    var serviceWorkerWakeCount: Int
    var scriptInjectionCount: Int
    var nativeMessagingPortCount: Int
    var unverifiedWebKitInternalSideEffect: Bool
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var canExecuteExtensionCodeNow: Bool
    var notes: [String]

    static func make(
        emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?,
        runtimeBridgeReadinessReport: ChromeMV3RuntimeBridgeReadinessReport?,
        loadAttempted: Bool
    ) -> ChromeMV3ControllerLoadSideEffectGuardDiagnostics {
        let jsBridge = runtimeBridgeReadinessReport?
            .jsBridgeContractReportSummary
        let native = runtimeBridgeReadinessReport?
            .nativeMessagingReadinessReportSummary
        let serviceWorker = runtimeBridgeReadinessReport?
            .serviceWorkerLifecycleReportSummary
        let userScriptCount =
            emptyControllerDiagnostics?.configurationWebViewUserScriptCount
                ?? 0
        let nativePortCount =
            emptyControllerDiagnostics?.nativeMessagingPortCount ?? 0

        return ChromeMV3ControllerLoadSideEffectGuardDiagnostics(
            jsBridgeAvailableNow:
                jsBridge?.jsBridgeAvailableNow ?? false,
            jsBridgeExposedToJSNow: jsBridge?.exposedToJSNow ?? false,
            wkUserScriptRegistrationObserved: userScriptCount > 0,
            scriptMessageHandlerRegistrationObserved: false,
            serviceWorkerWakeRequestObserved:
                serviceWorker?.canWakeServiceWorkerNow ?? false,
            nativeMessagingLaunchObserved:
                native?.processLaunchAllowedNow ?? false,
            runtimeNativePortOpenObserved: nativePortCount > 0,
            storageEventDispatchObserved: false,
            productUIObserved: false,
            extensionCodeExecuted: false,
            serviceWorkerWakeCount: 0,
            scriptInjectionCount: 0,
            nativeMessagingPortCount: 0,
            unverifiedWebKitInternalSideEffect: loadAttempted,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            canExecuteExtensionCodeNow: false,
            notes: uniqueSorted([
                "Sumi did not expose the JS bridge, register WKUserScript, add script message handlers, dispatch storage events, open native/runtime ports, launch native messaging, or show product UI.",
                loadAttempted
                    ? "Internal WebKit side effects beyond public context/controller state are not directly observable and remain conservatively marked unverified."
                    : "No controller load was attempted.",
            ])
        )
    }
}

struct ChromeMV3ControllerLoadGateInput:
    Codable,
    Equatable,
    Sendable
{
    var candidateID: String
    var generatedRewrittenRootPath: String
    var extensionsModuleEnabled: Bool
    var profileHostModuleState: ChromeMV3ProfileHostModuleState
    var profileIdentifier: String
    var explicitInternalControllerLoadProbeAllowed: Bool
    var acceptedWebExtensionObjectAvailable: Bool
    var objectProbeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?
    var objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    var detachedContextOwnerDiagnostics:
        ChromeMV3DetachedContextOwnerDiagnostics?
    var emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?
    var liveNormalTabAttachmentSnapshot:
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var minimalInertFixturePolicy:
        ChromeMV3MinimalInertFixturePolicyResult
    var contentScriptSmokeFixturePolicy:
        ChromeMV3ContentScriptSmokeFixturePolicyResult? = nil
    var sdkCompatibility: ChromeMV3ControllerLoadSDKCompatibility
    var requestedProductRuntimeExposure: Bool
    var requestedExtensionCodeExecution: Bool
    var requestedUserScriptRegistration: Bool
    var requestedNativeMessagingLaunch: Bool
}

struct ChromeMV3ControllerLoadGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3ControllerLoadGateInput
    var canLoadContextIntoControllerNow: Bool
    var loadAttemptAllowed: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var canExecuteExtensionCodeNow: Bool
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3ControllerLoadGateBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var diagnostics: [String]
    var sameControllerValidation:
        ChromeMV3ControllerLoadSameControllerValidation
    var sideEffectGuardDiagnostics:
        ChromeMV3ControllerLoadSideEffectGuardDiagnostics
}

enum ChromeMV3ControllerLoadGate {
    static func evaluate(
        input: ChromeMV3ControllerLoadGateInput
    ) -> ChromeMV3ControllerLoadGateDecision {
        var blockers: [ChromeMV3ControllerLoadGateBlocker] = []
        var warnings = input.minimalInertFixturePolicy.warnings
        if let contentScriptSmokeFixturePolicy =
            input.contentScriptSmokeFixturePolicy {
            warnings.append(contentsOf: contentScriptSmokeFixturePolicy.warnings)
        }
        var diagnostics: [String] = []

        let objectBlockingFindings =
            ChromeMV3ContextReadinessReportGenerator
            .objectAcceptanceBlockingFindings(
                in: input.objectAcceptanceReport
            )
        let dataStoreStatus =
            ChromeMV3ContextReadinessReportGenerator
            .dataStoreIdentityStatus(
                input.emptyControllerDiagnostics?
                    .dataStoreIdentityPolicy
            )
        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? input.emptyControllerDiagnostics?
            .liveNormalTabAttachmentSnapshot
        let sameController =
            ChromeMV3ControllerLoadSameControllerValidation.make(
                acceptedWebExtensionObjectAvailable:
                    input.acceptedWebExtensionObjectAvailable,
                detachedDiagnostics:
                    input.detachedContextOwnerDiagnostics,
                emptyControllerDiagnostics:
                    input.emptyControllerDiagnostics,
                liveSnapshot: liveSnapshot
            )
        let sideEffects =
            ChromeMV3ControllerLoadSideEffectGuardDiagnostics.make(
                emptyControllerDiagnostics:
                    input.emptyControllerDiagnostics,
                runtimeBridgeReadinessReport:
                    input.runtimeBridgeReadinessReport,
                loadAttempted: false
            )

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }
        if input.profileHostModuleState != .enabled {
            blockers.append(.profileHostDisabled)
        }
        if input.explicitInternalControllerLoadProbeAllowed == false {
            blockers.append(.explicitControllerLoadProbeNotAllowed)
        }
        if input.acceptedWebExtensionObjectAvailable == false {
            blockers.append(.acceptedExtensionObjectUnavailable)
        }
        if input.objectAcceptanceReport?.objectAcceptedByWebKit != true {
            blockers.append(.webKitObjectNotAccepted)
        }
        if objectBlockingFindings.isEmpty == false {
            blockers.append(.objectAcceptanceBlockersPresent)
        }

        guard let detachedDiagnostics =
            input.detachedContextOwnerDiagnostics
        else {
            blockers.append(.detachedContextDiagnosticsMissing)
            return decision(
                input: input,
                blockers: blockers,
                warnings: warnings,
                diagnostics: diagnostics,
                sameController: sameController,
                sideEffects: sideEffects
            )
        }

        if detachedDiagnostics.contextObjectCreated == false
            || detachedDiagnostics.state != .createdDetached
        {
            blockers.append(.detachedContextMissing)
        }
        if detachedDiagnostics.contextLoadedIntoController {
            blockers.append(.detachedContextAlreadyLoaded)
        }

        guard let emptyController = input.emptyControllerDiagnostics else {
            blockers.append(.emptyControllerDiagnosticsMissing)
            return decision(
                input: input,
                blockers: blockers,
                warnings: warnings,
                diagnostics: diagnostics,
                sameController: sameController,
                sideEffects: sideEffects
            )
        }

        if emptyController.controllerCreated == false {
            blockers.append(.emptyControllerMissing)
        }
        if emptyController.controllerState != .createdEmpty {
            blockers.append(.emptyControllerNotCreated)
        }
        if sameController.controllerEmptyBeforeLoad == false {
            blockers.append(.emptyControllerNoLongerEmpty)
        }
        if input.profileIdentifier.isResolvedChromeMV3ControllerLoadProfile == false {
            blockers.append(.profileIdentityUnavailable)
        }
        switch dataStoreStatus.status {
        case .matched:
            break
        case .missing, .unresolved:
            blockers.append(.controllerDataStoreIdentityUnresolved)
        case .placeholder:
            blockers.append(.controllerDataStoreIdentityPlaceholder)
        case .mismatched:
            blockers.append(.controllerDataStoreIdentityMismatch)
        }

        let contentScriptSmokeFixtureSafe =
            input.contentScriptSmokeFixturePolicy?
            .loadSafeForContentScriptSmokeFixture == true
        if input.minimalInertFixturePolicy.loadSafeForMinimalInertFixture
            == false && contentScriptSmokeFixtureSafe == false {
            blockers.append(.minimalInertFixturePolicyFailed)
        }
        if let contentScriptSmokeFixturePolicy =
            input.contentScriptSmokeFixturePolicy,
           contentScriptSmokeFixturePolicy
            .loadSafeForContentScriptSmokeFixture == false {
            blockers.append(.contentScriptSmokeFixturePolicyFailed)
        }
        if let liveSnapshot {
            if liveSnapshot.staleOrNeedsRecreationCount > 0 {
                blockers.append(.staleAttachedWebViewsPresent)
            }
            if liveSnapshot.accidentallyAttachedAuxiliarySurface {
                blockers.append(.auxiliarySurfaceAttached)
            }
            if liveSnapshot.runtimeLoadable
                || liveSnapshot.canLoadContextNow
                || liveSnapshot.contextLoadCalled
                || liveSnapshot.generatedExtensionBundleLoaded
                || liveSnapshot.nativeMessagingLaunched
            {
                blockers.append(.runtimeBridgeInvariantViolation)
            }
        }

        if input.sdkCompatibility.canCallControllerLoadAPI == false {
            blockers.append(.sdkControllerLoadUnsupported)
        }
        if input.sdkCompatibility
            .safeToAttemptMinimalInertFixtureLoadProbe == false
        {
            blockers.append(.sdkControllerLoadUnsafe)
        }

        if sideEffects.jsBridgeAvailableNow
            || sideEffects.jsBridgeExposedToJSNow
        {
            blockers.append(.jsBridgeExposed)
        }
        if sideEffects.serviceWorkerWakeRequestObserved {
            blockers.append(.serviceWorkerWakeAvailable)
        }
        if sideEffects.nativeMessagingLaunchObserved
            || sideEffects.runtimeNativePortOpenObserved
        {
            blockers.append(.nativeMessagingAvailable)
        }
        if input.runtimeBridgeReadinessReport?
            .messagingGate.dispatchImplemented == true
            || input.runtimeBridgeReadinessReport?
            .messagingGate.listenerRegistrationImplemented == true
            || input.runtimeBridgeReadinessReport?
            .storageGate.storageRuntimeImplemented == true
            || input.runtimeBridgeReadinessReport?
            .permissionsActiveTabGate.permissionsReadyForContextLoad == true
            || input.runtimeBridgeReadinessReport?
            .nativeMessagingGate.nativeMessagingRuntimeImplemented == true
            || input.runtimeBridgeReadinessReport?
            .serviceWorkerLifecycleGate.serviceWorkerWakeImplemented == true
        {
            blockers.append(.runtimeBridgeInvariantViolation)
        }

        if input.objectProbeDiagnostics?.runtimeLoadable ?? false
            || input.objectAcceptanceReport?.runtimeLoadable ?? false
            || detachedDiagnostics.runtimeLoadable
            || emptyController.runtimeLoadable
            || input.runtimeBridgeReadinessReport?.runtimeLoadable ?? false
            || sideEffects.runtimeLoadable
            || sideEffects.chromeRuntimeAvailableNow
            || sideEffects.canExecuteExtensionCodeNow
        {
            blockers.append(.runtimeLoadabilityInvariantViolation)
        }

        if input.requestedProductRuntimeExposure
            || input.requestedExtensionCodeExecution
            || input.requestedUserScriptRegistration
            || input.requestedNativeMessagingLaunch
        {
            blockers.append(.productRuntimeExposureRequested)
        }

        diagnostics.append(
            "Minimal inert fixture policy: \(input.minimalInertFixturePolicy.loadSafeForMinimalInertFixture ? "passed" : "blocked")."
        )
        if let contentScriptSmokeFixturePolicy =
            input.contentScriptSmokeFixturePolicy {
            diagnostics.append(
                "Content-script smoke fixture policy: \(contentScriptSmokeFixturePolicy.loadSafeForContentScriptSmokeFixture ? "passed" : "blocked")."
            )
        }
        diagnostics.append(
            "Controller load API: \(input.sdkCompatibility.swiftControllerLoadSymbol ?? "unavailable")."
        )
        diagnostics.append(
            "Detached context state: \(detachedDiagnostics.state.rawValue)."
        )
        diagnostics.append(
            "Controller state before load: \(emptyController.controllerState.rawValue)."
        )
        diagnostics.append(
            "Runtime remains unavailable even if this load probe succeeds."
        )
        warnings.append(
            "A successful controller-load probe does not expose Chrome MV3 runtime, JS bridge, native messaging, service-worker wake, or product UI."
        )

        return decision(
            input: input,
            blockers: blockers,
            warnings: warnings,
            diagnostics: diagnostics,
            sameController: sameController,
            sideEffects: sideEffects
        )
    }

    private static func decision(
        input: ChromeMV3ControllerLoadGateInput,
        blockers: [ChromeMV3ControllerLoadGateBlocker],
        warnings: [String],
        diagnostics: [String],
        sameController: ChromeMV3ControllerLoadSameControllerValidation,
        sideEffects: ChromeMV3ControllerLoadSideEffectGuardDiagnostics
    ) -> ChromeMV3ControllerLoadGateDecision {
        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        return ChromeMV3ControllerLoadGateDecision(
            input: input,
            canLoadContextIntoControllerNow: uniqueBlockers.isEmpty,
            loadAttemptAllowed: uniqueBlockers.isEmpty,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            canExecuteExtensionCodeNow: false,
            runtimeLoadable: false,
            blockers: uniqueBlockers,
            blockingReasons: uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings),
            diagnostics: uniqueSorted(diagnostics),
            sameControllerValidation: sameController,
            sideEffectGuardDiagnostics: sideEffects
        )
    }
}

struct ChromeMV3ControllerLoadOwnerDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3ControllerLoadOwnerState
    var gateDecision: ChromeMV3ControllerLoadGateDecision
    var controllerLoadAttempted: Bool
    var contextLoadedIntoController: Bool
    var controllerLoadCount: Int
    var controllerUnloadAttempted: Bool
    var contextUnloadedFromController: Bool
    var teardownComplete: Bool
    var extensionCodeExecuted: Bool
    var serviceWorkerWakeCount: Int
    var scriptInjectionCount: Int
    var nativeMessagingPortCount: Int
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var canExecuteExtensionCodeNow: Bool
    var webKitError:
        ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    var unloadError:
        ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    var sameControllerValidation:
        ChromeMV3ControllerLoadSameControllerValidation
    var sideEffectGuardDiagnostics:
        ChromeMV3ControllerLoadSideEffectGuardDiagnostics
    var blockingReasons: [String]
    var warnings: [String]

    static func make(
        state: ChromeMV3ControllerLoadOwnerState,
        gateDecision: ChromeMV3ControllerLoadGateDecision,
        controllerLoadAttempted: Bool = false,
        contextLoadedIntoController: Bool = false,
        controllerLoadCount: Int = 0,
        controllerUnloadAttempted: Bool = false,
        contextUnloadedFromController: Bool = false,
        teardownComplete: Bool = false,
        webKitError:
            ChromeMV3ExtensionObjectProbeErrorDiagnostic? = nil,
        unloadError:
            ChromeMV3ExtensionObjectProbeErrorDiagnostic? = nil
    ) -> ChromeMV3ControllerLoadOwnerDiagnostics {
        let sideEffects =
            ChromeMV3ControllerLoadSideEffectGuardDiagnostics.make(
                emptyControllerDiagnostics:
                    gateDecision.input.emptyControllerDiagnostics,
                runtimeBridgeReadinessReport:
                    gateDecision.input.runtimeBridgeReadinessReport,
                loadAttempted: controllerLoadAttempted
            )
        return ChromeMV3ControllerLoadOwnerDiagnostics(
            state: state,
            gateDecision: gateDecision,
            controllerLoadAttempted: controllerLoadAttempted,
            contextLoadedIntoController: contextLoadedIntoController,
            controllerLoadCount: controllerLoadCount,
            controllerUnloadAttempted: controllerUnloadAttempted,
            contextUnloadedFromController: contextUnloadedFromController,
            teardownComplete: teardownComplete,
            extensionCodeExecuted: false,
            serviceWorkerWakeCount: 0,
            scriptInjectionCount: 0,
            nativeMessagingPortCount: 0,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            canExecuteExtensionCodeNow: false,
            webKitError: webKitError,
            unloadError: unloadError,
            sameControllerValidation:
                gateDecision.sameControllerValidation,
            sideEffectGuardDiagnostics: sideEffects,
            blockingReasons: gateDecision.blockingReasons,
            warnings: gateDecision.warnings + sideEffects.notes
        )
    }
}

struct ChromeMV3ControllerLoadGateReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var candidateID: String
    var minimalFixtureLoadSafe: Bool
    var canLoadContextIntoControllerNow: Bool
    var loadAttemptAllowed: Bool
    var controllerLoadAttempted: Bool
    var contextLoadedIntoController: Bool
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var canExecuteExtensionCodeNow: Bool
}

struct ChromeMV3ControllerLoadGateReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var generatedRewrittenRootPath: String
    var minimalInertFixturePolicy:
        ChromeMV3MinimalInertFixturePolicyResult
    var objectProbeStatus: ChromeMV3ContextReadinessObjectProbeStatus
    var objectAcceptedByWebKit: Bool
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextStatus:
        ChromeMV3ContextReadinessAvailabilityStatus
    var controllerOwnerStatus:
        ChromeMV3ContextReadinessAvailabilityStatus
    var sameControllerValidation:
        ChromeMV3ControllerLoadSameControllerValidation
    var staleWebViewStatus:
        ChromeMV3ContextReadinessStaleNeedsRecreationStatus
    var sdkCompatibilityStatus:
        ChromeMV3ControllerLoadSDKCompatibility
    var loadGateDecision: ChromeMV3ControllerLoadGateDecision
    var loadOwnerDiagnostics:
        ChromeMV3ControllerLoadOwnerDiagnostics
    var loadAttemptResultState: ChromeMV3ControllerLoadOwnerState
    var webKitError:
        ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    var sideEffectGuardDiagnostics:
        ChromeMV3ControllerLoadSideEffectGuardDiagnostics
    var canLoadContextIntoControllerNow: Bool
    var loadAttemptAllowed: Bool
    var controllerLoadAttempted: Bool
    var contextLoadedIntoController: Bool
    var controllerLoadCount: Int
    var extensionCodeExecuted: Bool
    var serviceWorkerWakeCount: Int
    var scriptInjectionCount: Int
    var nativeMessagingPortCount: Int
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var canExecuteExtensionCodeNow: Bool
    var runtimeLoadable: Bool
    var whyChromeRuntimeStillUnavailable: [String]
    var blockers: [ChromeMV3ControllerLoadGateBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var diagnostics: [String]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]

    var summary: ChromeMV3ControllerLoadGateReportSummary {
        ChromeMV3ControllerLoadGateReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            candidateID: candidateID,
            minimalFixtureLoadSafe:
                minimalInertFixturePolicy.loadSafeForMinimalInertFixture,
            canLoadContextIntoControllerNow:
                canLoadContextIntoControllerNow,
            loadAttemptAllowed: loadAttemptAllowed,
            controllerLoadAttempted: controllerLoadAttempted,
            contextLoadedIntoController: contextLoadedIntoController,
            runtimeLoadable: runtimeLoadable,
            chromeRuntimeAvailableNow: chromeRuntimeAvailableNow,
            jsBridgeAvailableNow: jsBridgeAvailableNow,
            canExecuteExtensionCodeNow: canExecuteExtensionCodeNow
        )
    }
}

enum ChromeMV3ControllerLoadGateReportWriter {
    static let reportFileName = "runtime-controller-load-gate-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ControllerLoadGateReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ControllerLoadGateReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3ControllerLoadGateReportGenerator {
    static func makeReport(
        decision: ChromeMV3ControllerLoadGateDecision,
        loadOwnerDiagnostics:
            ChromeMV3ControllerLoadOwnerDiagnostics? = nil
    ) -> ChromeMV3ControllerLoadGateReport {
        let input = decision.input
        let ownerDiagnostics = loadOwnerDiagnostics
            ?? ChromeMV3ControllerLoadOwnerDiagnostics.make(
                state:
                    decision.loadAttemptAllowed
                        ? .notAttempted
                        : .blocked,
                gateDecision: decision
            )
        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? input.emptyControllerDiagnostics?
            .liveNormalTabAttachmentSnapshot
        let staleStatus = staleStatus(liveSnapshot)

        return ChromeMV3ControllerLoadGateReport(
            schemaVersion: 1,
            id: id(
                candidateID: input.candidateID,
                generatedRewrittenRootPath:
                    input.generatedRewrittenRootPath,
                state: ownerDiagnostics.state,
                loadCount: ownerDiagnostics.controllerLoadCount
            ),
            reportFileName:
                ChromeMV3ControllerLoadGateReportWriter.reportFileName,
            candidateID: input.candidateID,
            generatedRewrittenRootPath:
                input.generatedRewrittenRootPath,
            minimalInertFixturePolicy:
                input.minimalInertFixturePolicy,
            objectProbeStatus:
                objectProbeStatus(input.objectProbeDiagnostics),
            objectAcceptedByWebKit:
                input.objectAcceptanceReport?.objectAcceptedByWebKit
                    ?? false,
            acceptedWebExtensionObjectAvailable:
                input.acceptedWebExtensionObjectAvailable,
            detachedContextStatus:
                detachedStatus(input.detachedContextOwnerDiagnostics),
            controllerOwnerStatus:
                controllerOwnerStatus(input.emptyControllerDiagnostics),
            sameControllerValidation:
                ownerDiagnostics.sameControllerValidation,
            staleWebViewStatus: staleStatus,
            sdkCompatibilityStatus: input.sdkCompatibility,
            loadGateDecision: decision,
            loadOwnerDiagnostics: ownerDiagnostics,
            loadAttemptResultState: ownerDiagnostics.state,
            webKitError: ownerDiagnostics.webKitError,
            sideEffectGuardDiagnostics:
                ownerDiagnostics.sideEffectGuardDiagnostics,
            canLoadContextIntoControllerNow:
                decision.canLoadContextIntoControllerNow,
            loadAttemptAllowed: decision.loadAttemptAllowed,
            controllerLoadAttempted:
                ownerDiagnostics.controllerLoadAttempted,
            contextLoadedIntoController:
                ownerDiagnostics.contextLoadedIntoController,
            controllerLoadCount:
                ownerDiagnostics.controllerLoadCount,
            extensionCodeExecuted: false,
            serviceWorkerWakeCount: 0,
            scriptInjectionCount: 0,
            nativeMessagingPortCount: 0,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            canExecuteExtensionCodeNow: false,
            runtimeLoadable: false,
            whyChromeRuntimeStillUnavailable: [
                "The load probe is DEBUG/internal and limited to a minimal inert fixture.",
                "Sumi does not expose chrome.runtime to JavaScript.",
                "No JS bridge injection, content script injection, service-worker wake, extension message dispatch, storage event dispatch, native/runtime port, native host launch, or product UI path is enabled.",
                "runtimeLoadable, chromeRuntimeAvailableNow, jsBridgeAvailableNow, and canExecuteExtensionCodeNow remain false.",
            ],
            blockers: decision.blockers,
            blockingReasons: decision.blockingReasons,
            warnings:
                uniqueSorted(decision.warnings + ownerDiagnostics.warnings),
            diagnostics: decision.diagnostics,
            documentationSources: documentationSources()
        )
    }

    private static func objectProbeStatus(
        _ diagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?
    ) -> ChromeMV3ContextReadinessObjectProbeStatus {
        guard let diagnostics else { return .reportMissing }
        switch diagnostics.state {
        case .notAttempted:
            return .notAttempted
        case .blocked:
            return .blocked
        case .created:
            return .created
        case .failed:
            return .failed
        case .released:
            return .released
        }
    }

    private static func detachedStatus(
        _ diagnostics: ChromeMV3DetachedContextOwnerDiagnostics?
    ) -> ChromeMV3ContextReadinessAvailabilityStatus {
        guard let diagnostics else { return .missing }
        return diagnostics.contextObjectCreated
            && diagnostics.state == .createdDetached
            && diagnostics.contextLoadedIntoController == false
            ? .available
            : .blocked
    }

    private static func controllerOwnerStatus(
        _ diagnostics: ChromeMV3EmptyControllerDiagnostics?
    ) -> ChromeMV3ContextReadinessAvailabilityStatus {
        guard let diagnostics else { return .missing }
        let empty = diagnostics.controllerCreated
            && diagnostics.controllerState == .createdEmpty
            && diagnostics.contextCount == 0
            && diagnostics.loadedExtensionCount == 0
            && diagnostics.nativeMessagingPortCount == 0
            && diagnostics.pendingContextLoads == 0
            && diagnostics.pendingAttachments == 0
            && diagnostics.configurationWebViewUserScriptCount == 0
        return empty ? .available : .blocked
    }

    private static func staleStatus(
        _ snapshot: ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    ) -> ChromeMV3ContextReadinessStaleNeedsRecreationStatus {
        let staleCount = snapshot?.staleOrNeedsRecreationCount ?? 0
        return ChromeMV3ContextReadinessStaleNeedsRecreationStatus(
            policy: staleCount > 0 ? .blocker : .clear,
            staleOrNeedsRecreationCount: staleCount,
            tabDiagnosticIdentifiers:
                snapshot?.staleOrNeedsRecreationTabDiagnosticIdentifiers
                    ?? [],
            blocksFutureContextEligibility: staleCount > 0,
            requiredFutureAction:
                staleCount > 0
                    ? "Recreate stale DEBUG-attached WebViews before a controller-load probe."
                    : nil
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller",
                note: "A controller manages loaded extension contexts; active SDK headers expose Swift load(_:) and unload(_:)."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionContext",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontext",
                note: "A context is the extension runtime environment; Sumi keeps Chrome runtime unavailable after the load probe."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionTab.webView(for:)",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensiontab/webview%28for%3A%29",
                note: "A tab WebView must use the same controller as the context; this prompt does not attach WebViews."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX26.5 WebKit WKWebExtensionController.h",
                url: nil,
                note: "The header says controller loading starts the context, background content, and content injection, so only a no-background/no-content/no-tab minimal fixture can reach the owner."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome MV3 manifest",
                url: "https://developer.chrome.com/docs/extensions/mv3/manifest",
                note: "The minimal inert fixture uses manifest_version 3 with only required descriptive keys."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome content scripts",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                note: "Static content scripts are auto-run injection candidates and are blocked by the policy."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Native messaging remains blocked and no native host process is launched."
            ),
        ]
    }

    private static func source(
        kind: String,
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }

    private static func id(
        candidateID: String,
        generatedRewrittenRootPath: String,
        state: ChromeMV3ControllerLoadOwnerState,
        loadCount: Int
    ) -> String {
        let input = [
            candidateID,
            generatedRewrittenRootPath,
            state.rawValue,
            String(loadCount),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private func uniqueSorted<T: Hashable & Comparable>(_ values: [T]) -> [T] {
    Array(Set(values)).sorted()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private extension String {
    var isResolvedChromeMV3ControllerLoadProfile: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false
            && trimmed != ChromeMV3ProfileHost.unresolvedProfileIdentifier
    }
}
