//
//  ChromeMV3ProductPopupOptionsUI.swift
//  Sumi
//
//  Developer-preview product UI plumbing for extension-owned action popup and
//  options pages. This layer does not attach normal tabs, inject content
//  scripts, expose a normal-tab bridge, wake service workers, launch native
//  hosts, or make generated bundles globally runtime-loadable.
//

import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(WebKit)
import WebKit
#endif

enum ChromeMV3ProductPopupOptionsLoadingMode:
    String,
    Codable,
    Equatable,
    Sendable
{
    case fileBacked
    #if DEBUG
    case diagnosticCustomScheme
    #endif
}

enum ChromeMV3ProductPopupOptionsSurface:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case optionsPage
    case optionsUI

    static func < (
        lhs: ChromeMV3ProductPopupOptionsSurface,
        rhs: ChromeMV3ProductPopupOptionsSurface
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var pageKind: ChromeMV3ExtensionPageKind {
        switch self {
        case .actionPopup:
            return .actionPopup
        case .optionsPage:
            return .optionsPage
        case .optionsUI:
            return .optionsUI
        }
    }

    var title: String {
        switch self {
        case .actionPopup:
            return "Action Popup"
        case .optionsPage:
            return "Options Page"
        case .optionsUI:
            return "Embedded Options"
        }
    }
}

enum ChromeMV3PopupOptionsResourceValidationState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notEvaluated
    case valid
    case missingDeclaration
    case missingResource
    case unsafePath
    case unsafeHTML
    case generatedBundleMissing

    static func < (
        lhs: ChromeMV3PopupOptionsResourceValidationState,
        rhs: ChromeMV3PopupOptionsResourceValidationState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PopupOptionsProductGateState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case developerPreviewAllowed
    case extensionDisabled
    case publicProductBlocked

    static func < (
        lhs: ChromeMV3PopupOptionsProductGateState,
        rhs: ChromeMV3PopupOptionsProductGateState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PopupOptionsHostCreationState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequested
    case blocked
    case created
    case failed
    case tornDown

    static func < (
        lhs: ChromeMV3PopupOptionsHostCreationState,
        rhs: ChromeMV3PopupOptionsHostCreationState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PopupOptionsBridgeAvailabilityState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notRequired
    case unavailable
    case limitedAllowed
    case blocked

    static func < (
        lhs: ChromeMV3PopupOptionsBridgeAvailabilityState,
        rhs: ChromeMV3PopupOptionsBridgeAvailabilityState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PopupOptionsLifecycleState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case notOpened
    case opened
    case loaded
    case failed
    case closed
    case disabledWhileOpen
    case uninstalledWhileOpen
    case resetWhileOpen
    case teardownComplete

    static func < (
        lhs: ChromeMV3PopupOptionsLifecycleState,
        rhs: ChromeMV3PopupOptionsLifecycleState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PopupOptionsLifecycleEvent:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case opened
    case loaded
    case failed
    case closed
    case disabledWhileOpen
    case uninstalledWhileOpen
    case resetWhileOpen
    case teardownComplete

    static func < (
        lhs: ChromeMV3PopupOptionsLifecycleEvent,
        rhs: ChromeMV3PopupOptionsLifecycleEvent
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PopupOptionsBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case moduleDisabled
    case developerPreviewGateBlocked
    case publicProductBlocked
    case recordMissing
    case extensionUninstalled
    case extensionDisabled
    case generatedBundleMissing
    case generatedRewrittenBundleMissing
    case noActionDeclared
    case actionDeclaredWithoutPopup
    case noOptionsPageDeclared
    case unsafePagePath
    case missingPageResource
    case unsafePageHTML
    case productGateBlocked
    case bridgeUnavailableForPageAPI
    case normalTabRuntimeUnavailable
    case contentScriptAttachmentUnavailable
    case serviceWorkerWakeBlocked
    case nativeMessagingBlocked
    case hostCreationFailed

    static func < (
        lhs: ChromeMV3PopupOptionsBlocker,
        rhs: ChromeMV3PopupOptionsBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var reason: String {
        switch self {
        case .moduleDisabled:
            return "The extensions module is disabled."
        case .developerPreviewGateBlocked:
            return "Popup/options UI requires the internal developer-preview manager gate."
        case .publicProductBlocked:
            return "Popup/options UI is not available in the public product gate."
        case .recordMissing:
            return "The internal MV3 lifecycle record is missing."
        case .extensionUninstalled:
            return "The internal MV3 extension record is uninstalled."
        case .extensionDisabled:
            return "The internal MV3 extension record is disabled."
        case .generatedBundleMissing:
            return "No active generated bundle version is available."
        case .generatedRewrittenBundleMissing:
            return "The active generated rewritten bundle is missing."
        case .noActionDeclared:
            return "The manifest does not declare an action."
        case .actionDeclaredWithoutPopup:
            return "The manifest declares an action without action.default_popup."
        case .noOptionsPageDeclared:
            return "The manifest does not declare options_page or options_ui.page."
        case .unsafePagePath:
            return "The declared popup/options page path is unsafe."
        case .missingPageResource:
            return "The declared popup/options page resource is missing."
        case .unsafePageHTML:
            return "The popup/options HTML or linked resources failed validation."
        case .productGateBlocked:
            return "Popup/options product UI gates did not pass."
        case .bridgeUnavailableForPageAPI:
            return "The page references extension APIs, but the popup/options bridge is not enabled."
        case .normalTabRuntimeUnavailable:
            return "Normal-tab runtime remains unavailable."
        case .contentScriptAttachmentUnavailable:
            return "Product content-script attachment remains unavailable."
        case .serviceWorkerWakeBlocked:
            return "Service-worker wake is not allowed from popup/options in this phase."
        case .nativeMessagingBlocked:
            return "Native messaging is not allowed from popup/options in this phase."
        case .hostCreationFailed:
            return "The controlled popup/options WebKit host failed to create."
        }
    }
}

struct ChromeMV3ProductPopupOptionsUIGateRecord:
    Codable,
    Equatable,
    Sendable
{
    var actionPopupUIAvailableInDeveloperPreview: Bool
    var actionPopupUIAvailableInPublicProduct: Bool
    var optionsUIAvailableInDeveloperPreview: Bool
    var optionsUIAvailableInPublicProduct: Bool
    var popupOptionsJSBridgeAvailableInDeveloperPreview: Bool
    var popupOptionsJSBridgeAvailableInPublicProduct: Bool
    var popupOptionsRuntimeAllowed: Bool
    var popupOptionsBridgeAllowed: Bool
    var popupOptionsRuntimeNamespaceAllowed: Bool
    var popupOptionsStorageNamespaceAllowed: Bool
    var popupOptionsPermissionsNamespaceAllowed: Bool
    var popupOptionsTabsNamespaceAllowed: Bool
    var popupOptionsScriptingNamespaceAllowed: Bool
    var popupOptionsNativeMessagingNamespaceAllowed: Bool
    var popupOptionsBlockedAPIs: [String]
    var popupOptionsProductBlockedReason: String?
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailable: Bool
    var runtimeLoadable: Bool
    var toolbarActionUIDeferred: Bool
    var diagnostics: [String]

    static func evaluate(
        moduleEnabled: Bool,
        managerGate: ChromeMV3ExtensionManagerGate? = nil,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord? = nil,
        extensionEnabledOverride: Bool? = nil
    ) -> ChromeMV3ProductPopupOptionsUIGateRecord {
        #if DEBUG
            let developerPreviewGate =
                moduleEnabled
                    && (
                        managerGate?.managerAvailableInDeveloperPreview
                            ?? ChromeMV3InternalDiagnosticsGate.uiAvailable
                    )
        #else
            let developerPreviewGate = false
        #endif
        let installed = lifecycleRecord?.lifecycleState != .uninstalled
        let enabled =
            lifecycleRecord?.runtimeState.internalRuntimeEnabled
                ?? extensionEnabledOverride
                ?? false
        let developerPreviewAvailable =
            developerPreviewGate && (lifecycleRecord == nil || installed)
        let runtimeAllowed = developerPreviewAvailable && enabled
        let bridgeAllowed = runtimeAllowed
        var diagnostics: [String] = []
        if moduleEnabled == false {
            diagnostics.append(
                "The extensions module is disabled; popup/options UI gates are closed."
            )
        }
        if developerPreviewGate == false {
            diagnostics.append(
                "Developer-preview manager gate is closed for popup/options UI."
            )
        }
        if let lifecycleRecord, lifecycleRecord.lifecycleState == .uninstalled {
            diagnostics.append(
                "The lifecycle record is uninstalled; popup/options UI cannot open."
            )
        }
        if (lifecycleRecord != nil || extensionEnabledOverride != nil)
            && enabled == false
        {
            diagnostics.append(
                "The lifecycle record is disabled; popup/options UI cannot open."
            )
        }
        diagnostics.append(
            "Public product popup/options UI remains unavailable."
        )
        diagnostics.append(
            "Normal-tab runtime bridge and content-script attachment remain unavailable."
        )

        return ChromeMV3ProductPopupOptionsUIGateRecord(
            actionPopupUIAvailableInDeveloperPreview:
                developerPreviewAvailable,
            actionPopupUIAvailableInPublicProduct: false,
            optionsUIAvailableInDeveloperPreview:
                developerPreviewAvailable,
            optionsUIAvailableInPublicProduct: false,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                bridgeAllowed,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            popupOptionsRuntimeAllowed: runtimeAllowed,
            popupOptionsBridgeAllowed: bridgeAllowed,
            popupOptionsRuntimeNamespaceAllowed: bridgeAllowed,
            popupOptionsStorageNamespaceAllowed: bridgeAllowed,
            popupOptionsPermissionsNamespaceAllowed: bridgeAllowed,
            popupOptionsTabsNamespaceAllowed: bridgeAllowed,
            popupOptionsScriptingNamespaceAllowed: bridgeAllowed,
            popupOptionsNativeMessagingNamespaceAllowed: false,
            popupOptionsBlockedAPIs:
                ChromeMV3PopupOptionsAPIMethodPolicy.defaultBlockedAPIIDs,
            popupOptionsProductBlockedReason:
                "Public product popup/options support remains gated to internal developer preview.",
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailable: false,
            runtimeLoadable: false,
            toolbarActionUIDeferred: true,
            diagnostics: uniqueSortedPopupOptions(diagnostics)
        )
    }
}

struct ChromeMV3PopupOptionsAPISurfaceAvailability:
    Codable,
    Equatable,
    Sendable
{
    var implementedNamespaces: [String]
    var exposedNamespaces: [String]
    var blockedNamespaces: [String]
    var allowedMethods: [String]
    var blockedMethods: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]
    var pageReferencesExtensionAPI: Bool
    var runtimeAvailable: Bool
    var storageLocalAvailable: Bool
    var storageSessionAvailable: Bool
    var permissionsAvailable: Bool
    var tabsAvailable: Bool
    var scriptingAvailable: Bool
    var nativeMessagingAvailable: Bool
    var serviceWorkerWakeAllowed: Bool
    var diagnostics: [String]

    static func make(
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        gateRecord: ChromeMV3ProductPopupOptionsUIGateRecord,
        pageReferencesExtensionAPI: Bool,
        policy: ChromeMV3PopupOptionsAPIMethodPolicy = .defaultPolicy
    ) -> ChromeMV3PopupOptionsAPISurfaceAvailability {
        let reportNames = Set(
            report?.internalSyntheticReadinessSummary
                .syntheticAPIReportsAvailable ?? []
        )
        var implemented: [String] = []
        if reportNames.contains("chrome.runtime") {
            implemented.append("runtime")
        }
        if reportNames.contains("chrome.storage.local") {
            implemented.append("storage.local")
        }
        if reportNames.contains("chrome.permissions") {
            implemented.append("permissions")
        }
        if reportNames.contains("chrome.tabs/chrome.scripting") {
            implemented.append(contentsOf: ["tabs", "scripting"])
        }
        let exposed = gateRecord.popupOptionsBridgeAllowed
            ? policy.exposedNamespaces
            : []
        let blocked = gateRecord.popupOptionsBridgeAllowed
            ? policy.blockedNamespaces
            : Array(Set(implemented + ["runtime"])).sorted()
        var diagnostics: [String] = []
        if pageReferencesExtensionAPI {
            diagnostics.append(
                gateRecord.popupOptionsBridgeAllowed
                    ? "The page references extension APIs; the developer-preview popup/options bridge is available."
                    : "The page references extension APIs; bridge exposure is blocked by launch gates."
            )
        }
        diagnostics.append(
            "Popup/options bridge exposes only the developer-preview allowlist; unsupported methods return deterministic lastError diagnostics."
        )

        return ChromeMV3PopupOptionsAPISurfaceAvailability(
            implementedNamespaces: uniqueSortedPopupOptions(implemented),
            exposedNamespaces: uniqueSortedPopupOptions(exposed),
            blockedNamespaces: uniqueSortedPopupOptions(blocked),
            allowedMethods: gateRecord.popupOptionsBridgeAllowed
                ? policy.allowedMethods
                : [],
            blockedMethods: policy.blockedDiagnostics,
            pageReferencesExtensionAPI: pageReferencesExtensionAPI,
            runtimeAvailable: exposed.contains("runtime"),
            storageLocalAvailable: exposed.contains("storage.local"),
            storageSessionAvailable: exposed.contains("storage.session"),
            permissionsAvailable: exposed.contains("permissions"),
            tabsAvailable: exposed.contains("tabs"),
            scriptingAvailable: exposed.contains("scripting"),
            nativeMessagingAvailable: false,
            serviceWorkerWakeAllowed: false,
            diagnostics: uniqueSortedPopupOptions(diagnostics)
        )
    }
}

struct ChromeMV3ProductPopupOptionsLaunchRecord:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String {
        [
            profileID,
            extensionID,
            surface.rawValue,
            generatedBundleVersionID ?? "no-version",
            declaredPath ?? "no-path",
        ].joined(separator: ":")
    }

    var extensionID: String
    var profileID: String
    var surface: ChromeMV3ProductPopupOptionsSurface
    var popupPath: String?
    var optionsPagePath: String?
    var optionsUIPagePath: String?
    var optionsUIOpenInTab: Bool?
    var declaredPath: String?
    var normalizedPath: String?
    var generatedBundleVersionID: String?
    var managerStoreRootPath: String?
    var generatedBundleRootPath: String?
    var generatedRewrittenBundlePath: String?
    var generatedResourcePath: String?
    var manifestPermissions: [String]
    var manifestOptionalPermissions: [String]
    var manifestHostPermissions: [String]
    var manifestOptionalHostPermissions: [String]
    var resourceValidationState:
        ChromeMV3PopupOptionsResourceValidationState
    var productGateState: ChromeMV3PopupOptionsProductGateState
    var hostCreationState: ChromeMV3PopupOptionsHostCreationState
    var bridgeAPIAvailabilityState:
        ChromeMV3PopupOptionsBridgeAvailabilityState
    var lifecycleState: ChromeMV3PopupOptionsLifecycleState
    var lifecycleEvents: [ChromeMV3PopupOptionsLifecycleEvent]
    var gateRecord: ChromeMV3ProductPopupOptionsUIGateRecord
    var resourceResolution: ChromeMV3ExtensionPageResourceResolution?
    var apiMethodPolicy: ChromeMV3PopupOptionsAPIMethodPolicy
    var apiSurface: ChromeMV3PopupOptionsAPISurfaceAvailability
    var blockers: [ChromeMV3PopupOptionsBlocker]
    var blockingReasons: [String]
    var diagnostics: [String]

    var canOpen: Bool {
        blockers.isEmpty
            && productGateState == .developerPreviewAllowed
            && resourceValidationState == .valid
    }
}

struct ChromeMV3ProductPopupOptionsLaunchState:
    Codable,
    Equatable,
    Sendable
{
    var gateRecord: ChromeMV3ProductPopupOptionsUIGateRecord
    var actionPopup: ChromeMV3ProductPopupOptionsLaunchRecord
    var optionsPages: [ChromeMV3ProductPopupOptionsLaunchRecord]
    var primaryOptions:
        ChromeMV3ProductPopupOptionsLaunchRecord?
    var toolbarActionUIDeferred: Bool
    var lastRunResult: ChromeMV3ProductPopupOptionsRunResult?
}

enum ChromeMV3ProductPopupOptionsLaunchPlanner {
    static func makeLaunchState(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        managerGate: ChromeMV3ExtensionManagerGate,
        moduleEnabled: Bool,
        lastRunResult: ChromeMV3ProductPopupOptionsRunResult? = nil,
        fileManager: FileManager = .default
    ) -> ChromeMV3ProductPopupOptionsLaunchState {
        let registry = ChromeMV3ExtensionLifecycleRegistry(
            rootURL: rootURL,
            fileManager: fileManager
        )
        let record = registry.loadLifecycleRecord(
            profileID: profileID,
            extensionID: extensionID
        )
        let report = registry.latestEndToEndDiagnosticsReport(
            profileID: profileID,
            extensionID: extensionID
        )
        let gate = ChromeMV3ProductPopupOptionsUIGateRecord.evaluate(
            moduleEnabled: moduleEnabled,
            managerGate: managerGate,
            lifecycleRecord: record
        )
        let action = launchRecord(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            surface: .actionPopup,
            gateRecord: gate,
            lifecycleRecord: record,
            report: report,
            fileManager: fileManager
        )
        let optionsRecords = [
            launchRecord(
                rootURL: rootURL,
                profileID: profileID,
                extensionID: extensionID,
                surface: .optionsPage,
                gateRecord: gate,
                lifecycleRecord: record,
                report: report,
                fileManager: fileManager
            ),
            launchRecord(
                rootURL: rootURL,
                profileID: profileID,
                extensionID: extensionID,
                surface: .optionsUI,
                gateRecord: gate,
                lifecycleRecord: record,
                report: report,
                fileManager: fileManager
            ),
        ]
        return ChromeMV3ProductPopupOptionsLaunchState(
            gateRecord: gate,
            actionPopup: action,
            optionsPages: optionsRecords,
            primaryOptions:
                optionsRecords.first { $0.surface == .optionsUI && $0.canOpen }
                    ?? optionsRecords.first {
                        $0.surface == .optionsPage && $0.canOpen
                    }
                    ?? optionsRecords.first { $0.surface == .optionsUI }
                    ?? optionsRecords.first,
            toolbarActionUIDeferred: gate.toolbarActionUIDeferred,
            lastRunResult: lastRunResult
        )
    }

    static func launchRecord(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        gateRecord: ChromeMV3ProductPopupOptionsUIGateRecord,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        fileManager: FileManager = .default
    ) -> ChromeMV3ProductPopupOptionsLaunchRecord {
        var blockers: [ChromeMV3PopupOptionsBlocker] = []
        var diagnostics: [String] = gateRecord.diagnostics
        var declaration: ChromeMV3ExtensionPageDeclaration?
        var resolution: ChromeMV3ExtensionPageResourceResolution?
        var validation: ChromeMV3PopupOptionsResourceValidationState =
            .notEvaluated
        var manifestFacts = ChromeMV3PopupOptionsManifestFacts.empty
        var activeVersion: ChromeMV3GeneratedBundleVersionRecord?
        var generatedRootPath: String?

        if gateRecord.actionPopupUIAvailableInPublicProduct == false
            || gateRecord.optionsUIAvailableInPublicProduct == false
        {
            diagnostics.append(
                ChromeMV3PopupOptionsBlocker.publicProductBlocked.reason
            )
        }
        if gateRecord.normalTabRuntimeBridgeAvailable == false {
            diagnostics.append(
                ChromeMV3PopupOptionsBlocker.normalTabRuntimeUnavailable.reason
            )
        }
        if gateRecord.contentScriptAttachmentAvailable == false {
            diagnostics.append(
                ChromeMV3PopupOptionsBlocker
                    .contentScriptAttachmentUnavailable.reason
            )
        }

        guard let lifecycleRecord else {
            blockers.append(.recordMissing)
            return record(
                rootURL: rootURL,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface,
                gateRecord: gateRecord,
                validation: .missingDeclaration,
                productGate: .blocked,
                blockers: blockers,
                diagnostics: diagnostics,
                manifestFacts: manifestFacts,
                activeVersion: nil,
                generatedRootPath: nil,
                declaration: nil,
                resolution: nil,
                apiSurface: .make(
                    report: report,
                    gateRecord: gateRecord,
                    pageReferencesExtensionAPI: false
                )
            )
        }

        if lifecycleRecord.lifecycleState == .uninstalled {
            blockers.append(.extensionUninstalled)
        }
        if lifecycleRecord.runtimeState.internalRuntimeEnabled == false {
            blockers.append(.extensionDisabled)
        }
        if gateRecord.popupOptionsRuntimeAllowed == false {
            blockers.append(.productGateBlocked)
        }

        activeVersion = activeGeneratedVersion(in: lifecycleRecord)
        if activeVersion == nil {
            blockers.append(.generatedBundleMissing)
            validation = .generatedBundleMissing
        }
        if let version = activeVersion {
            generatedRootPath = version.generatedBundleRootPath
            if let generatedRootPath,
               directoryExists(
                URL(fileURLWithPath: generatedRootPath, isDirectory: true),
                fileManager: fileManager
               )
            {
                let model = ChromeMV3ExtensionPageDeclarationReader.read(
                    generatedRewrittenRootPath: generatedRootPath,
                    fileManager: fileManager
                )
                manifestFacts = manifestFactsFromManifest(
                    model.manifestPath
                )
                declaration = model.declarations.first {
                    $0.kind == surface.pageKind
                }
                if let declaration {
                    resolution = ChromeMV3ExtensionPageResourceResolver
                        .resolve(declaration: declaration)
                    validation = validationState(
                        declaration: declaration,
                        resolution: resolution
                    )
                } else {
                    validation = .missingDeclaration
                }
            } else {
                blockers.append(.generatedRewrittenBundleMissing)
                validation = .generatedBundleMissing
            }
        }

        appendDeclarationBlockers(
            surface: surface,
            manifestFacts: manifestFacts,
            declaration: declaration,
            validation: validation,
            blockers: &blockers
        )

        let pageReferencesAPI = pageReferencesExtensionAPI(
            resolution: resolution
        )
        let apiSurface = ChromeMV3PopupOptionsAPISurfaceAvailability.make(
            report: report,
            gateRecord: gateRecord,
            pageReferencesExtensionAPI: pageReferencesAPI
        )
        if pageReferencesAPI && gateRecord.popupOptionsBridgeAllowed == false {
            blockers.append(.bridgeUnavailableForPageAPI)
        }
        if manifestFacts.permissions.contains("nativeMessaging") {
            diagnostics.append(
                ChromeMV3PopupOptionsBlocker.nativeMessagingBlocked.reason
            )
        }
        if manifestFacts.backgroundServiceWorkerPath != nil {
            diagnostics.append(
                ChromeMV3PopupOptionsBlocker.serviceWorkerWakeBlocked.reason
            )
        }
        blockers = uniqueBlockers(blockers)
        let productGate: ChromeMV3PopupOptionsProductGateState
        if blockers.contains(.extensionDisabled) {
            productGate = .extensionDisabled
        } else if gateRecord.popupOptionsRuntimeAllowed
                    && blockers.contains(.productGateBlocked) == false
                    && blockers.contains(.developerPreviewGateBlocked) == false
        {
            productGate = .developerPreviewAllowed
        } else {
            productGate = .blocked
        }

        return record(
            rootURL: rootURL,
            profileID: lifecycleRecord.profileID,
            extensionID: lifecycleRecord.extensionID,
            surface: surface,
            gateRecord: gateRecord,
            validation: validation,
            productGate: productGate,
            blockers: blockers,
            diagnostics: diagnostics,
            manifestFacts: manifestFacts,
            activeVersion: activeVersion,
            generatedRootPath: generatedRootPath,
            declaration: declaration,
            resolution: resolution,
            apiSurface: apiSurface
        )
    }

    static func controlledActionPopupLaunchRecord(
        rootURL: URL,
        profileID: String,
        installedExtension: InstalledExtension,
        managerGate: ChromeMV3ExtensionManagerGate,
        moduleEnabled: Bool,
        fileManager: FileManager = .default
    ) -> ChromeMV3ProductPopupOptionsLaunchRecord {
        let policy = ChromeMV3PopupOptionsAPIMethodPolicy
            .controlledActionPopupPolicy
        let gate = ChromeMV3ProductPopupOptionsUIGateRecord.evaluate(
            moduleEnabled: moduleEnabled,
            managerGate: managerGate,
            lifecycleRecord: nil,
            extensionEnabledOverride: installedExtension.isEnabled
        )
        var blockers: [ChromeMV3PopupOptionsBlocker] = []
        var diagnostics = gate.diagnostics + [
            "Controlled URL-hub action popup host is selected only by the explicit local experimental developer-preview gate.",
            "The host resolves action.default_popup from the installed generated package and does not synthesize popup UI.",
            "Package-local popup JavaScript, CSS, image, locale, frame, and asset resources are preserved through file-backed read access to the generated package root.",
            "Remote, missing, unsafe-path, and inline-script popup resources remain blocked in the controlled action popup host.",
            "CSP is preserved only to the extent WebKit enforces it for the loaded file-backed HTML; chrome-extension:// origin semantics are approximated by bridge metadata and chrome.runtime.getURL, not by a custom extension URL scheme.",
            "storage.local get/set/remove/clear are routed through the developer-preview broker when the controlled bridge is installed.",
            "storage.session get/set/remove/clear are routed through a memory-only developer-preview broker when the controlled bridge is installed.",
            "storage.sync get/set/remove/clear are routed through a developer-preview local compatibility backend when the controlled bridge is installed; no cloud sync is claimed.",
            "Native messaging, managed storage, scripting, permissions, DNR, webRequest, offscreen, contextMenus, and Web Store APIs remain outside this controlled action popup policy.",
        ]
        var declaration: ChromeMV3ExtensionPageDeclaration?
        var resolution: ChromeMV3ExtensionPageResourceResolution?
        var validation: ChromeMV3PopupOptionsResourceValidationState =
            .notEvaluated
        var manifestFacts = ChromeMV3PopupOptionsManifestFacts.empty
        let generatedRootPath = installedExtension.packagePath

        if installedExtension.isEnabled == false {
            blockers.append(.extensionDisabled)
        }
        if gate.popupOptionsRuntimeAllowed == false {
            blockers.append(.productGateBlocked)
        }
        if directoryExists(
            URL(fileURLWithPath: generatedRootPath, isDirectory: true),
            fileManager: fileManager
        ) {
            let model = ChromeMV3ExtensionPageDeclarationReader.read(
                generatedRewrittenRootPath: generatedRootPath,
                fileManager: fileManager
            )
            manifestFacts = manifestFactsFromManifest(model.manifestPath)
            declaration = model.declarations.first {
                $0.kind == ChromeMV3ProductPopupOptionsSurface.actionPopup
                    .pageKind
            }
            if let declaration {
                resolution = ChromeMV3ExtensionPageResourceResolver
                    .resolve(declaration: declaration)
                validation = controlledActionPopupValidationState(
                    declaration: declaration,
                    resolution: resolution
                )
            } else {
                validation = .missingDeclaration
            }
        } else {
            blockers.append(.generatedRewrittenBundleMissing)
            validation = .generatedBundleMissing
        }

        appendDeclarationBlockers(
            surface: .actionPopup,
            manifestFacts: manifestFacts,
            declaration: declaration,
            validation: validation,
            blockers: &blockers
        )
        let pageReferencesAPI = pageReferencesExtensionAPI(
            resolution: resolution
        )
        let apiSurface = ChromeMV3PopupOptionsAPISurfaceAvailability.make(
            report: nil,
            gateRecord: gate,
            pageReferencesExtensionAPI: pageReferencesAPI,
            policy: policy
        )
        if pageReferencesAPI && gate.popupOptionsBridgeAllowed == false {
            blockers.append(.bridgeUnavailableForPageAPI)
        }
        if manifestFacts.permissions.contains("nativeMessaging") {
            diagnostics.append(
                ChromeMV3PopupOptionsBlocker.nativeMessagingBlocked.reason
            )
        }
        if manifestFacts.backgroundServiceWorkerPath != nil {
            diagnostics.append(
                "A manifest service worker exists; popup messages are routed through the generic bridge without launching a native host."
            )
        }
        blockers = uniqueBlockers(blockers)
        let productGate: ChromeMV3PopupOptionsProductGateState
        if blockers.contains(.extensionDisabled) {
            productGate = .extensionDisabled
        } else if gate.popupOptionsRuntimeAllowed
            && blockers.contains(.productGateBlocked) == false
            && blockers.contains(.developerPreviewGateBlocked) == false
        {
            productGate = .developerPreviewAllowed
        } else {
            productGate = .blocked
        }

        return record(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: installedExtension.id,
            surface: .actionPopup,
            gateRecord: gate,
            validation: validation,
            productGate: productGate,
            blockers: blockers,
            diagnostics: diagnostics,
            manifestFacts: manifestFacts,
            activeVersion: nil,
            generatedRootPath: generatedRootPath,
            declaration: declaration,
            resolution: resolution,
            apiSurface: apiSurface,
            apiMethodPolicy: policy
        )
    }

    private static func record(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        gateRecord: ChromeMV3ProductPopupOptionsUIGateRecord,
        validation: ChromeMV3PopupOptionsResourceValidationState,
        productGate: ChromeMV3PopupOptionsProductGateState,
        blockers: [ChromeMV3PopupOptionsBlocker],
        diagnostics: [String],
        manifestFacts: ChromeMV3PopupOptionsManifestFacts,
        activeVersion: ChromeMV3GeneratedBundleVersionRecord?,
        generatedRootPath: String?,
        declaration: ChromeMV3ExtensionPageDeclaration?,
        resolution: ChromeMV3ExtensionPageResourceResolution?,
        apiSurface: ChromeMV3PopupOptionsAPISurfaceAvailability,
        apiMethodPolicy: ChromeMV3PopupOptionsAPIMethodPolicy = .defaultPolicy
    ) -> ChromeMV3ProductPopupOptionsLaunchRecord {
        let unique = uniqueBlockers(blockers)
        let bridgeState: ChromeMV3PopupOptionsBridgeAvailabilityState
        if apiSurface.pageReferencesExtensionAPI
            && gateRecord.popupOptionsBridgeAllowed == false
        {
            bridgeState = .blocked
        } else if gateRecord.popupOptionsBridgeAllowed {
            bridgeState = .limitedAllowed
        } else if apiSurface.pageReferencesExtensionAPI {
            bridgeState = .unavailable
        } else {
            bridgeState = .notRequired
        }
        return ChromeMV3ProductPopupOptionsLaunchRecord(
            extensionID: extensionID,
            profileID: profileID,
            surface: surface,
            popupPath: manifestFacts.actionDefaultPopupPath,
            optionsPagePath: manifestFacts.optionsPagePath,
            optionsUIPagePath: manifestFacts.optionsUIPagePath,
            optionsUIOpenInTab: manifestFacts.optionsUIOpenInTab,
            declaredPath: declaration?.declaredPath,
            normalizedPath: declaration?.normalizedPath,
            generatedBundleVersionID: activeVersion?.id,
            managerStoreRootPath: rootURL.path,
            generatedBundleRootPath:
                activeVersion?.generatedBundleRootPath ?? generatedRootPath,
            generatedRewrittenBundlePath: generatedRootPath,
            generatedResourcePath: declaration?.generatedResourcePath,
            manifestPermissions: manifestFacts.permissions,
            manifestOptionalPermissions: manifestFacts.optionalPermissions,
            manifestHostPermissions: manifestFacts.hostPermissions,
            manifestOptionalHostPermissions:
                manifestFacts.optionalHostPermissions,
            resourceValidationState: validation,
            productGateState: productGate,
            hostCreationState:
                unique.isEmpty ? .notRequested : .blocked,
            bridgeAPIAvailabilityState: bridgeState,
            lifecycleState: .notOpened,
            lifecycleEvents: [],
            gateRecord: gateRecord,
            resourceResolution: resolution,
            apiMethodPolicy: apiMethodPolicy,
            apiSurface: apiSurface,
            blockers: unique,
            blockingReasons: unique.map(\.reason).sorted(),
            diagnostics: uniqueSortedPopupOptions(
                diagnostics + apiSurface.diagnostics
            )
        )
    }

    private static func appendDeclarationBlockers(
        surface: ChromeMV3ProductPopupOptionsSurface,
        manifestFacts: ChromeMV3PopupOptionsManifestFacts,
        declaration: ChromeMV3ExtensionPageDeclaration?,
        validation: ChromeMV3PopupOptionsResourceValidationState,
        blockers: inout [ChromeMV3PopupOptionsBlocker]
    ) {
        if declaration == nil {
            switch surface {
            case .actionPopup:
                if manifestFacts.actionDeclared {
                    blockers.append(.actionDeclaredWithoutPopup)
                } else {
                    blockers.append(.noActionDeclared)
                }
            case .optionsPage, .optionsUI:
                blockers.append(.noOptionsPageDeclared)
            }
        }
        switch validation {
        case .unsafePath:
            blockers.append(.unsafePagePath)
        case .missingResource:
            blockers.append(.missingPageResource)
        case .unsafeHTML:
            blockers.append(.unsafePageHTML)
        case .generatedBundleMissing:
            blockers.append(.generatedBundleMissing)
        case .notEvaluated, .valid, .missingDeclaration:
            break
        }
    }

    private static func validationState(
        declaration: ChromeMV3ExtensionPageDeclaration,
        resolution: ChromeMV3ExtensionPageResourceResolution?
    ) -> ChromeMV3PopupOptionsResourceValidationState {
        switch declaration.pathSafety {
        case .unsafe:
            return .unsafePath
        case .missing:
            return .missingResource
        case .safe:
            break
        }
        guard let resolution else { return .notEvaluated }
        if resolution.resourceSafeForExtensionPageHost {
            return .valid
        }
        if resolution.htmlPageExists == false {
            return .missingResource
        }
        return .unsafeHTML
    }

    private static func controlledActionPopupValidationState(
        declaration: ChromeMV3ExtensionPageDeclaration,
        resolution: ChromeMV3ExtensionPageResourceResolution?
    ) -> ChromeMV3PopupOptionsResourceValidationState {
        switch declaration.pathSafety {
        case .unsafe:
            return .unsafePath
        case .missing:
            return .missingResource
        case .safe:
            break
        }
        guard let resolution else { return .notEvaluated }
        if resolution.htmlPageExists == false {
            return .missingResource
        }
        if resolution.missingResourcePaths.isEmpty == false {
            return .missingResource
        }
        if resolution.unsafeResourcePaths.isEmpty == false {
            return .unsafeHTML
        }
        if resolution.remoteResourceReferences.isEmpty == false {
            return .unsafeHTML
        }
        if resolution.linkedResources.contains(where: {
            $0.kind == .inlineScript
        }) {
            return .unsafeHTML
        }
        return .valid
    }

    private static func activeGeneratedVersion(
        in record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3GeneratedBundleVersionRecord? {
        guard let activeID = record.activeGeneratedVersionID else {
            return nil
        }
        return record.generatedBundleVersions.first { $0.id == activeID }
    }

    private static func pageReferencesExtensionAPI(
        resolution: ChromeMV3ExtensionPageResourceResolution?
    ) -> Bool {
        guard let path = resolution?.declaration.generatedResourcePath,
              let html = try? String(contentsOfFile: path, encoding: .utf8)
        else { return false }
        let lowered = html.lowercased()
        return lowered.contains("chrome.")
            || lowered.contains("browser.")
            || lowered.contains("runtime.")
    }

    private static func manifestFactsFromManifest(
        _ manifestPath: String
    ) -> ChromeMV3PopupOptionsManifestFacts {
        guard
            let data = try? Data(
                contentsOf: URL(fileURLWithPath: manifestPath)
            ),
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else { return .empty }
        let action = object["action"] as? [String: Any]
        let optionsUI = object["options_ui"] as? [String: Any]
        let background = object["background"] as? [String: Any]
        return ChromeMV3PopupOptionsManifestFacts(
            actionDeclared: action != nil,
            actionDefaultPopupPath: action?["default_popup"] as? String,
            optionsPagePath: object["options_page"] as? String,
            optionsUIPagePath: optionsUI?["page"] as? String,
            optionsUIOpenInTab: optionsUI?["open_in_tab"] as? Bool,
            permissions: object["permissions"] as? [String] ?? [],
            optionalPermissions:
                object["optional_permissions"] as? [String] ?? [],
            hostPermissions:
                object["host_permissions"] as? [String] ?? [],
            optionalHostPermissions:
                object["optional_host_permissions"] as? [String] ?? [],
            backgroundServiceWorkerPath:
                background?["service_worker"] as? String
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
}

private struct ChromeMV3PopupOptionsManifestFacts {
    var actionDeclared: Bool
    var actionDefaultPopupPath: String?
    var optionsPagePath: String?
    var optionsUIPagePath: String?
    var optionsUIOpenInTab: Bool?
    var permissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var backgroundServiceWorkerPath: String?

    static let empty = ChromeMV3PopupOptionsManifestFacts(
        actionDeclared: false,
        actionDefaultPopupPath: nil,
        optionsPagePath: nil,
        optionsUIPagePath: nil,
        optionsUIOpenInTab: nil,
        permissions: [],
        optionalPermissions: [],
        hostPermissions: [],
        optionalHostPermissions: [],
        backgroundServiceWorkerPath: nil
    )
}

enum ChromeMV3ProductPopupOptionsRunStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case succeeded
    case blocked
    case failed

    static func < (
        lhs: ChromeMV3ProductPopupOptionsRunStatus,
        rhs: ChromeMV3ProductPopupOptionsRunStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ProductPopupOptionsTeardownReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case userClosed
    case disabledWhileOpen
    case uninstalledWhileOpen
    case resetWhileOpen
    case moduleDisabled

    static func < (
        lhs: ChromeMV3ProductPopupOptionsTeardownReason,
        rhs: ChromeMV3ProductPopupOptionsTeardownReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var lifecycleEvent: ChromeMV3PopupOptionsLifecycleEvent {
        switch self {
        case .userClosed, .moduleDisabled:
            return .closed
        case .disabledWhileOpen:
            return .disabledWhileOpen
        case .uninstalledWhileOpen:
            return .uninstalledWhileOpen
        case .resetWhileOpen:
            return .resetWhileOpen
        }
    }

    var lifecycleState: ChromeMV3PopupOptionsLifecycleState {
        switch self {
        case .userClosed, .moduleDisabled:
            return .closed
        case .disabledWhileOpen:
            return .disabledWhileOpen
        case .uninstalledWhileOpen:
            return .uninstalledWhileOpen
        case .resetWhileOpen:
            return .resetWhileOpen
        }
    }
}

struct ChromeMV3ProductPopupOptionsRunResult:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ProductPopupOptionsRunStatus
    var requestedSurface: ChromeMV3ProductPopupOptionsSurface?
    var launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord?
    var lifecycleEvents: [ChromeMV3PopupOptionsLifecycleEvent]
    var webViewCreated: Bool
    var webViewReleased: Bool
    var scriptHandlersRemoved: Bool
    var normalTabAttached: Bool
    var contentScriptsInjectedIntoProductPages: Bool
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool
    var popupOptionsBridgeInstalled: Bool
    var popupOptionsUserScriptInstalled: Bool
    var popupOptionsAPIAllowlist: [String]
    var popupOptionsAPICallsObserved: [ChromeMV3PopupOptionsJSBridgeCallRecord]
    var popupOptionsBlockedAPIs: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]
    var popupOptionsLastAPIErrorSummary: String?
    var diagnostics: [String]

    static func blocked(
        requestedSurface: ChromeMV3ProductPopupOptionsSurface?,
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord?,
        diagnostics: [String]
    ) -> ChromeMV3ProductPopupOptionsRunResult {
        ChromeMV3ProductPopupOptionsRunResult(
            status: .blocked,
            requestedSurface: requestedSurface,
            launchRecord: launchRecord,
            lifecycleEvents: [],
            webViewCreated: false,
            webViewReleased: false,
            scriptHandlersRemoved: false,
            normalTabAttached: false,
            contentScriptsInjectedIntoProductPages: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            popupOptionsBridgeInstalled: false,
            popupOptionsUserScriptInstalled: false,
            popupOptionsAPIAllowlist: [],
            popupOptionsAPICallsObserved: [],
            popupOptionsBlockedAPIs:
                launchRecord?.apiSurface.blockedMethods ?? [],
            popupOptionsLastAPIErrorSummary: nil,
            diagnostics: uniqueSortedPopupOptions(diagnostics)
        )
    }
}

#if canImport(AppKit)
@MainActor
final class ChromeMV3PopupOptionsPresentationContext {
    weak var anchorView: NSView?
    let preferredEdge: NSRectEdge
    let preferredContentSize: NSSize
    let anchorKind: String
    let onClosed: @MainActor () -> Void

    init(
        anchorView: NSView?,
        preferredEdge: NSRectEdge = .maxY,
        preferredContentSize: NSSize = NSSize(width: 380, height: 600),
        anchorKind: String = "urlHubActionTile",
        onClosed: @escaping @MainActor () -> Void = {}
    ) {
        self.anchorView = anchorView
        self.preferredEdge = preferredEdge
        self.preferredContentSize = preferredContentSize
        self.anchorKind = anchorKind
        self.onClosed = onClosed
    }
}
#else
@MainActor
final class ChromeMV3PopupOptionsPresentationContext {}
#endif

@MainActor
protocol ChromeMV3PopupOptionsWebViewHandle: AnyObject {
    var popupOptionsBridgeDiagnosticsSnapshot:
        ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot? { get }

    #if DEBUG
    func evaluateJavaScriptForTesting(_ script: String) async throws -> Any?
    #endif

    func tearDown()
}

@MainActor
extension ChromeMV3PopupOptionsWebViewHandle {
    var popupOptionsBridgeDiagnosticsSnapshot:
        ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot? {
        nil
    }

    #if DEBUG
    func evaluateJavaScriptForTesting(_ script: String) async throws -> Any? {
        _ = script
        return nil
    }
    #endif
}

@MainActor
protocol ChromeMV3PopupOptionsWebViewFactory: AnyObject {
    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL
    ) throws -> ChromeMV3PopupOptionsWebViewHandle

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) throws -> ChromeMV3PopupOptionsWebViewHandle

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        contentScriptEndpointRegistry:
            ChromeMV3ContentScriptEndpointRegistry?,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession?,
        presentationContext:
            ChromeMV3PopupOptionsPresentationContext?,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) throws -> ChromeMV3PopupOptionsWebViewHandle
}

@MainActor
extension ChromeMV3PopupOptionsWebViewFactory {
    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting? = nil,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching? = nil
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        _ = bridgeInstallation
        _ = permissionPromptPresenter
        _ = permissionEventDispatcher
        return try createWebView(
            loadFileURL: loadFileURL,
            allowingReadAccessTo: readAccessURL
        )
    }

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        contentScriptEndpointRegistry:
            ChromeMV3ContentScriptEndpointRegistry?,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil,
        presentationContext:
            ChromeMV3PopupOptionsPresentationContext? = nil,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting? = nil,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching? = nil
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        _ = contentScriptEndpointRegistry
        _ = sharedLifecycleSession
        _ = presentationContext
        return try createWebView(
            loadFileURL: loadFileURL,
            allowingReadAccessTo: readAccessURL,
            bridgeInstallation: bridgeInstallation,
            permissionPromptPresenter: permissionPromptPresenter,
            permissionEventDispatcher: permissionEventDispatcher
        )
    }
}

@MainActor
final class ChromeMV3ProductPopupOptionsHostController {
    private struct ActiveSession {
        var launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord
        var handle: ChromeMV3PopupOptionsWebViewHandle
    }

    private let factory: ChromeMV3PopupOptionsWebViewFactory
    private let permissionPromptPresenter:
        ChromeMV3PermissionPromptPresenting?
    private let permissionEventDispatcher:
        ChromeMV3PermissionEventDispatching?
    private let contentScriptEndpointRegistryProvider:
        @MainActor () -> ChromeMV3ContentScriptEndpointRegistry?
    private let sharedLifecycleSessionProvider:
        @MainActor (ChromeMV3ProductPopupOptionsLaunchRecord)
            -> ChromeMV3ServiceWorkerSharedLifecycleSession?
    private var sessions: [String: ActiveSession] = [:]

    init(
        factory: ChromeMV3PopupOptionsWebViewFactory,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting? = nil,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching? = nil,
        contentScriptEndpointRegistryProvider:
            @escaping @MainActor ()
                -> ChromeMV3ContentScriptEndpointRegistry? = { nil },
        sharedLifecycleSessionProvider:
            @escaping @MainActor (ChromeMV3ProductPopupOptionsLaunchRecord)
                -> ChromeMV3ServiceWorkerSharedLifecycleSession? = { _ in nil }
    ) {
        self.factory = factory
        self.permissionPromptPresenter = permissionPromptPresenter
        self.permissionEventDispatcher = permissionEventDispatcher
        self.contentScriptEndpointRegistryProvider =
            contentScriptEndpointRegistryProvider
        self.sharedLifecycleSessionProvider = sharedLifecycleSessionProvider
    }

    var activeSessionCount: Int {
        sessions.count
    }

    func hasActiveSession(
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface? = nil
    ) -> Bool {
        sessions.keys.contains {
            matchesSessionKey(
                $0,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface
            )
        }
    }

    #if DEBUG
    func diagnosticsSnapshot(
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface? = nil
    ) -> ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot? {
        let key = sessions.keys.first {
            matchesSessionKey(
                $0,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface
            )
        }
        guard let key else { return nil }
        return sessions[key]?.handle.popupOptionsBridgeDiagnosticsSnapshot
    }

    func evaluateJavaScriptForTesting(
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface? = nil,
        script: String
    ) async throws -> Any? {
        let key = sessions.keys.first {
            matchesSessionKey(
                $0,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface
            )
        }
        guard let key, let handle = sessions[key]?.handle else {
            return nil
        }
        return try await handle.evaluateJavaScriptForTesting(script)
    }
    #endif

    func open(
        _ launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord,
        presentationContext:
            ChromeMV3PopupOptionsPresentationContext? = nil
    ) -> ChromeMV3ProductPopupOptionsRunResult {
        guard launchRecord.canOpen else {
            return .blocked(
                requestedSurface: launchRecord.surface,
                launchRecord: launchRecord,
                diagnostics: launchRecord.blockingReasons
            )
        }
        guard let resourcePath = launchRecord.generatedResourcePath,
              let rootPath = launchRecord.generatedRewrittenBundlePath
        else {
            var blocked = launchRecord
            blocked.hostCreationState = .blocked
            blocked.lifecycleState = .failed
            blocked.lifecycleEvents = [.failed]
            blocked.blockers = uniqueBlockers(
                blocked.blockers + [.generatedRewrittenBundleMissing]
            )
            blocked.blockingReasons = blocked.blockers.map(\.reason).sorted()
            return .blocked(
                requestedSurface: launchRecord.surface,
                launchRecord: blocked,
                diagnostics: blocked.blockingReasons
            )
        }

        let fileURL = URL(fileURLWithPath: resourcePath)
        let readAccessURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let key = sessionKey(for: launchRecord)
        if sessions[key] != nil {
            _ = close(
                profileID: launchRecord.profileID,
                extensionID: launchRecord.extensionID,
                surface: launchRecord.surface,
                reason: .userClosed
            )
        }

        do {
            let bridgeInstallation =
                ChromeMV3PopupOptionsJSBridgeInstallation.make(
                    launchRecord: launchRecord
                )
            let handle = try factory.createWebView(
                loadFileURL: fileURL,
                allowingReadAccessTo: readAccessURL,
                bridgeInstallation: bridgeInstallation,
                contentScriptEndpointRegistry:
                    contentScriptEndpointRegistryProvider(),
                sharedLifecycleSession:
                    sharedLifecycleSessionProvider(launchRecord),
                presentationContext: presentationContext,
                permissionPromptPresenter: permissionPromptPresenter,
                permissionEventDispatcher: permissionEventDispatcher
            )
            var opened = launchRecord
            opened.hostCreationState = .created
            opened.lifecycleState = .loaded
            opened.lifecycleEvents = [.opened, .loaded]
            sessions[key] = ActiveSession(
                launchRecord: opened,
                handle: handle
            )
            return ChromeMV3ProductPopupOptionsRunResult(
                status: .succeeded,
                requestedSurface: opened.surface,
                launchRecord: opened,
                lifecycleEvents: opened.lifecycleEvents,
                webViewCreated: true,
                webViewReleased: false,
                scriptHandlersRemoved: false,
                normalTabAttached: false,
                contentScriptsInjectedIntoProductPages: false,
                serviceWorkerWakeAttempted: false,
                nativeHostLaunchAttempted: false,
                popupOptionsBridgeInstalled:
                    bridgeInstallation.bridgeAvailable,
                popupOptionsUserScriptInstalled:
                    bridgeInstallation.bridgeAvailable,
                popupOptionsAPIAllowlist:
                    bridgeInstallation.allowlist.allowedMethods,
                popupOptionsAPICallsObserved: [],
                popupOptionsBlockedAPIs:
                    bridgeInstallation.allowlist.blockedDiagnostics,
                popupOptionsLastAPIErrorSummary: nil,
                diagnostics: [
                    "Popup/options WebView was created only after explicit developer-preview launch gates passed.",
                    bridgeInstallation.bridgeAvailable
                        ? "Popup/options JS bridge was installed only in the extension-owned WebView."
                        : "Popup/options JS bridge was not installed because launch gates did not allow it.",
                    "No normal tab was attached and no content scripts were injected.",
                ]
            )
        } catch {
            var failed = launchRecord
            failed.hostCreationState = .failed
            failed.lifecycleState = .failed
            failed.lifecycleEvents = [.failed]
            failed.blockers = uniqueBlockers(
                failed.blockers + [.hostCreationFailed]
            )
            failed.blockingReasons = failed.blockers.map(\.reason).sorted()
            failed.diagnostics = uniqueSortedPopupOptions(
                failed.diagnostics + [error.localizedDescription]
            )
            return ChromeMV3ProductPopupOptionsRunResult(
                status: .failed,
                requestedSurface: failed.surface,
                launchRecord: failed,
                lifecycleEvents: failed.lifecycleEvents,
                webViewCreated: false,
                webViewReleased: false,
                scriptHandlersRemoved: false,
                normalTabAttached: false,
                contentScriptsInjectedIntoProductPages: false,
                serviceWorkerWakeAttempted: false,
                nativeHostLaunchAttempted: false,
                popupOptionsBridgeInstalled: false,
                popupOptionsUserScriptInstalled: false,
                popupOptionsAPIAllowlist: [],
                popupOptionsAPICallsObserved: [],
                popupOptionsBlockedAPIs: failed.apiSurface.blockedMethods,
                popupOptionsLastAPIErrorSummary: nil,
                diagnostics: failed.diagnostics
            )
        }
    }

    @discardableResult
    func close(
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface? = nil,
        reason: ChromeMV3ProductPopupOptionsTeardownReason
    ) -> ChromeMV3ProductPopupOptionsRunResult {
        let keys = sessions.keys.filter {
            matchesSessionKey(
                $0,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface
            )
        }
        guard keys.isEmpty == false else {
            return ChromeMV3ProductPopupOptionsRunResult(
                status: .succeeded,
                requestedSurface: surface,
                launchRecord: nil,
                lifecycleEvents: [],
                webViewCreated: false,
                webViewReleased: false,
                scriptHandlersRemoved: false,
                normalTabAttached: false,
                contentScriptsInjectedIntoProductPages: false,
                serviceWorkerWakeAttempted: false,
                nativeHostLaunchAttempted: false,
                popupOptionsBridgeInstalled: false,
                popupOptionsUserScriptInstalled: false,
                popupOptionsAPIAllowlist: [],
                popupOptionsAPICallsObserved: [],
                popupOptionsBlockedAPIs: [],
                popupOptionsLastAPIErrorSummary: nil,
                diagnostics: [
                    "No popup/options WebView session was active.",
                ]
            )
        }

        var lastRecord: ChromeMV3ProductPopupOptionsLaunchRecord?
        var lastBridgeSnapshot:
            ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot?
        for key in keys {
            guard let session = sessions.removeValue(forKey: key) else {
                continue
            }
            lastBridgeSnapshot =
                session.handle.popupOptionsBridgeDiagnosticsSnapshot
            session.handle.tearDown()
            var closed = session.launchRecord
            closed.hostCreationState = .tornDown
            closed.lifecycleState = .teardownComplete
            closed.lifecycleEvents.append(reason.lifecycleEvent)
            closed.lifecycleEvents.append(.teardownComplete)
            lastRecord = closed
        }

        return ChromeMV3ProductPopupOptionsRunResult(
            status: .succeeded,
            requestedSurface: surface ?? lastRecord?.surface,
            launchRecord: lastRecord,
            lifecycleEvents:
                lastRecord?.lifecycleEvents
                    ?? [reason.lifecycleEvent, .teardownComplete],
            webViewCreated: false,
            webViewReleased: true,
            scriptHandlersRemoved: true,
            normalTabAttached: false,
            contentScriptsInjectedIntoProductPages: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            popupOptionsBridgeInstalled: false,
            popupOptionsUserScriptInstalled: false,
            popupOptionsAPIAllowlist:
                lastRecord?.apiSurface.allowedMethods ?? [],
            popupOptionsAPICallsObserved:
                lastBridgeSnapshot?.callRecords ?? [],
            popupOptionsBlockedAPIs:
                lastBridgeSnapshot?.blockedAPIs
                    ?? lastRecord?.apiSurface.blockedMethods
                    ?? [],
            popupOptionsLastAPIErrorSummary:
                lastBridgeSnapshot?.lastAPIErrorSummary,
            diagnostics: [
                "Popup/options WebView teardown completed.",
                "No script message handlers, native hosts, service-worker sessions, or normal-tab attachments were retained.",
            ]
        )
    }

    @discardableResult
    func closeAll(
        reason: ChromeMV3ProductPopupOptionsTeardownReason
    ) -> ChromeMV3ProductPopupOptionsRunResult {
        let keys = Array(sessions.keys)
        guard keys.isEmpty == false else {
            return ChromeMV3ProductPopupOptionsRunResult(
                status: .succeeded,
                requestedSurface: nil,
                launchRecord: nil,
                lifecycleEvents: [],
                webViewCreated: false,
                webViewReleased: false,
                scriptHandlersRemoved: false,
                normalTabAttached: false,
                contentScriptsInjectedIntoProductPages: false,
                serviceWorkerWakeAttempted: false,
                nativeHostLaunchAttempted: false,
                popupOptionsBridgeInstalled: false,
                popupOptionsUserScriptInstalled: false,
                popupOptionsAPIAllowlist: [],
                popupOptionsAPICallsObserved: [],
                popupOptionsBlockedAPIs: [],
                popupOptionsLastAPIErrorSummary: nil,
                diagnostics: ["No popup/options WebView session was active."]
            )
        }
        var last: ChromeMV3ProductPopupOptionsRunResult?
        for key in keys {
            guard let parsed = parseSessionKey(key) else { continue }
            last = close(
                profileID: parsed.profileID,
                extensionID: parsed.extensionID,
                surface: parsed.surface,
                reason: reason
            )
        }
        return last ?? ChromeMV3ProductPopupOptionsRunResult(
            status: .succeeded,
            requestedSurface: nil,
            launchRecord: nil,
            lifecycleEvents: [reason.lifecycleEvent, .teardownComplete],
            webViewCreated: false,
            webViewReleased: true,
            scriptHandlersRemoved: true,
            normalTabAttached: false,
            contentScriptsInjectedIntoProductPages: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            popupOptionsBridgeInstalled: false,
            popupOptionsUserScriptInstalled: false,
            popupOptionsAPIAllowlist: [],
            popupOptionsAPICallsObserved: [],
            popupOptionsBlockedAPIs: [],
            popupOptionsLastAPIErrorSummary: nil,
            diagnostics: ["Popup/options WebView teardown completed."]
        )
    }

    private func sessionKey(
        for record: ChromeMV3ProductPopupOptionsLaunchRecord
    ) -> String {
        [
            record.profileID,
            record.extensionID,
            record.surface.rawValue,
        ].joined(separator: "\u{1f}")
    }

    private func matchesSessionKey(
        _ key: String,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface?
    ) -> Bool {
        guard let parsed = parseSessionKey(key) else { return false }
        return parsed.profileID == profileID
            && parsed.extensionID == extensionID
            && (surface == nil || parsed.surface == surface)
    }

    private func parseSessionKey(
        _ key: String
    ) -> (
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface
    )? {
        let parts = key.split(separator: "\u{1f}", omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 3,
              let surface = ChromeMV3ProductPopupOptionsSurface(
                rawValue: parts[2]
              )
        else { return nil }
        return (parts[0], parts[1], surface)
    }
}

#if canImport(WebKit)
@MainActor
final class ChromeMV3ProductPopupOptionsWKWebViewFactory:
    ChromeMV3PopupOptionsWebViewFactory
{
    private let loadingMode: ChromeMV3ProductPopupOptionsLoadingMode

    init(
        loadingMode: ChromeMV3ProductPopupOptionsLoadingMode = .fileBacked
    ) {
        self.loadingMode = loadingMode
    }

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        ChromeMV3ProductPopupOptionsWKWebViewHandle(
            loadFileURL: loadFileURL,
            readAccessURL: readAccessURL,
            loadingMode: loadingMode
        )
    }

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        try createWebView(
            loadFileURL: loadFileURL,
            allowingReadAccessTo: readAccessURL,
            bridgeInstallation: bridgeInstallation,
            contentScriptEndpointRegistry: nil,
            permissionPromptPresenter: permissionPromptPresenter,
            permissionEventDispatcher: permissionEventDispatcher
        )
    }

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        contentScriptEndpointRegistry:
            ChromeMV3ContentScriptEndpointRegistry?,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        try createWebView(
            loadFileURL: loadFileURL,
            allowingReadAccessTo: readAccessURL,
            bridgeInstallation: bridgeInstallation,
            contentScriptEndpointRegistry:
                contentScriptEndpointRegistry,
            sharedLifecycleSession: nil,
            presentationContext: nil,
            permissionPromptPresenter: permissionPromptPresenter,
            permissionEventDispatcher: permissionEventDispatcher
        )
    }

    func createWebView(
        loadFileURL: URL,
        allowingReadAccessTo readAccessURL: URL,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        contentScriptEndpointRegistry:
            ChromeMV3ContentScriptEndpointRegistry?,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession?,
        presentationContext:
            ChromeMV3PopupOptionsPresentationContext?,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) throws -> ChromeMV3PopupOptionsWebViewHandle {
        ChromeMV3ProductPopupOptionsWKWebViewHandle(
            loadFileURL: loadFileURL,
            readAccessURL: readAccessURL,
            loadingMode: loadingMode,
            bridgeInstallation: bridgeInstallation,
            contentScriptEndpointRegistry:
                contentScriptEndpointRegistry,
            sharedLifecycleSession: sharedLifecycleSession,
            presentationContext: presentationContext,
            permissionPromptPresenter: permissionPromptPresenter,
            permissionEventDispatcher: permissionEventDispatcher
        )
    }
}

@MainActor
final class ChromeMV3ProductPopupOptionsWKWebViewHandle:
    ChromeMV3PopupOptionsWebViewHandle
{
    private var webView: WKWebView?
    private var userContentController: WKUserContentController?
    private var scriptHandler:
        ChromeMV3PopupOptionsWKScriptMessageHandler?
    private let messageHandlerName: String?
    private var bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler?
    #if DEBUG
    private var diagnosticsDelegate:
        ChromeMV3ProductPopupOptionsWKDiagnosticsDelegate?
    private var diagnosticSchemeHandler:
        ChromeMV3PopupOptionsDiagnosticURLSchemeHandler?
    #endif
    private(set) var installedUserScriptCount = 0
    private(set) var installedScriptMessageHandlerCount = 0
    #if canImport(AppKit)
    private var popover: NSPopover?
    private var popoverDelegate:
        ChromeMV3ProductPopupOptionsPopoverDelegate?
    private var popoverContentViewController: NSViewController?
    private var isTearingDown = false
    #endif

    init(
        loadFileURL: URL,
        readAccessURL: URL,
        loadingMode: ChromeMV3ProductPopupOptionsLoadingMode = .fileBacked
    ) {
        self.messageHandlerName = nil
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        #if DEBUG
        let diagnosticSchemeHandler = Self.installDiagnosticSchemeHandlerIfNeeded(
            into: configuration,
            loadingMode: loadingMode,
            readAccessURL: readAccessURL,
            bridgeHandler: nil
        )
        self.diagnosticSchemeHandler = diagnosticSchemeHandler
        #endif
        let webView = WKWebView(frame: .zero, configuration: configuration)
        Self.load(
            webView: webView,
            loadFileURL: loadFileURL,
            readAccessURL: readAccessURL,
            loadingMode: loadingMode
        )
        self.webView = webView
    }

    init(
        loadFileURL: URL,
        readAccessURL: URL,
        loadingMode: ChromeMV3ProductPopupOptionsLoadingMode = .fileBacked,
        bridgeInstallation:
            ChromeMV3PopupOptionsJSBridgeInstallation,
        contentScriptEndpointRegistry:
            ChromeMV3ContentScriptEndpointRegistry? = nil,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil,
        presentationContext:
            ChromeMV3PopupOptionsPresentationContext? = nil,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting?,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching?
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let userContentController = WKUserContentController()
        var messageHandlerName: String?
        if bridgeInstallation.bridgeAvailable,
           let scriptSource = bridgeInstallation.scriptSource
        {
            let handler = ChromeMV3PopupOptionsJSBridgeHandler(
                configuration: bridgeInstallation.configuration,
                contentScriptEndpointRegistry:
                    contentScriptEndpointRegistry,
                permissionPromptPresenter: permissionPromptPresenter,
                permissionEventDispatcher: permissionEventDispatcher,
                sharedLifecycleSession: sharedLifecycleSession
            )
            let scriptHandler =
                ChromeMV3PopupOptionsWKScriptMessageHandler(
                    handler: handler
                )
            #if DEBUG
            handler.recordHostDiagnosticEvents(
                bridgeInstallation.hostDiagnosticEvents
            )
            #endif
            userContentController.addScriptMessageHandler(
                scriptHandler,
                contentWorld: .page,
                name: bridgeInstallation.messageHandlerName
            )
            let userScript = WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .page
            )
            userContentController.addUserScript(userScript)
            self.scriptHandler = scriptHandler
            self.bridgeHandler = handler
            self.installedUserScriptCount = 1
            self.installedScriptMessageHandlerCount = 1
            messageHandlerName = bridgeInstallation.messageHandlerName
        } else {
            self.scriptHandler = nil
            self.bridgeHandler = nil
        }
        configuration.userContentController = userContentController
        #if DEBUG
        let diagnosticSchemeHandler = Self.installDiagnosticSchemeHandlerIfNeeded(
            into: configuration,
            loadingMode: loadingMode,
            readAccessURL: readAccessURL,
            bridgeHandler: bridgeHandler
        )
        self.diagnosticSchemeHandler = diagnosticSchemeHandler
        #endif
        self.userContentController = userContentController
        self.messageHandlerName = messageHandlerName
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        if let bridgeHandler {
            let diagnosticsDelegate =
                ChromeMV3ProductPopupOptionsWKDiagnosticsDelegate(
                    bridgeHandler: bridgeHandler,
                    readAccessURL: readAccessURL
                )
            webView.navigationDelegate = diagnosticsDelegate
            webView.uiDelegate = diagnosticsDelegate
            self.diagnosticsDelegate = diagnosticsDelegate
        } else {
            self.diagnosticsDelegate = nil
        }
        #endif
        Self.load(
            webView: webView,
            loadFileURL: loadFileURL,
            readAccessURL: readAccessURL,
            loadingMode: loadingMode
        )
        self.webView = webView
        #if canImport(AppKit)
        presentIfNeeded(webView: webView, context: presentationContext)
        #endif
        if bridgeInstallation.bridgeAvailable {
            permissionEventDispatcher?
                .registerChromeMV3PermissionEventPage(
                    surfaceID: bridgeInstallation.configuration.surfaceID,
                    profileID: bridgeInstallation.configuration.profileID,
                    extensionID: bridgeInstallation.configuration.extensionID,
                    surface: bridgeInstallation.configuration.surface,
                    dispatchHandler: { [weak webView] payload in
                        guard let webView else { return false }
                        guard
                            let data = try? JSONSerialization.data(
                                withJSONObject: [
                                    "eventKind": payload.eventKind.rawValue,
                                    "permissions": payload.permissions,
                                    "origins": payload.origins,
                                    "extensionID": payload.extensionID,
                                    "profileID": payload.profileID,
                                ],
                                options: [.sortedKeys]
                            ),
                            let json = String(data: data, encoding: .utf8)
                        else { return false }
                        webView.evaluateJavaScript(
                            "globalThis.__sumiDispatchChromeMV3PermissionEvent && globalThis.__sumiDispatchChromeMV3PermissionEvent(\(json));",
                            completionHandler: nil
                        )
                        return true
                    }
                )
        }
    }

    var popupOptionsBridgeDiagnosticsSnapshot:
        ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot? {
        bridgeHandler?.diagnosticsSnapshot
    }

    #if canImport(AppKit)
    private func presentIfNeeded(
        webView: WKWebView,
        context: ChromeMV3PopupOptionsPresentationContext?
    ) {
        guard let context,
              let anchorView = context.anchorView,
              anchorView.window != nil
        else { return }

        let contentViewController = NSViewController()
        webView.frame = NSRect(
            origin: .zero,
            size: context.preferredContentSize
        )
        webView.autoresizingMask = [.width, .height]
        contentViewController.view = webView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = context.preferredContentSize
        popover.contentViewController = contentViewController

        let delegate = ChromeMV3ProductPopupOptionsPopoverDelegate {
            [weak self, context] in
            guard let self, self.isTearingDown == false else { return }
            context.onClosed()
            self.tearDown()
        }
        popover.delegate = delegate
        self.popover = popover
        self.popoverDelegate = delegate
        self.popoverContentViewController = contentViewController
        popover.show(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: context.preferredEdge
        )
    }
    #endif

    func tearDown() {
        #if canImport(AppKit)
        if isTearingDown { return }
        isTearingDown = true
        if let popover, popover.isShown {
            popover.close()
        }
        popover?.delegate = nil
        popover?.contentViewController = nil
        popover = nil
        popoverDelegate = nil
        popoverContentViewController = nil
        #endif
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        if let messageHandlerName {
            userContentController?.removeScriptMessageHandler(
                forName: messageHandlerName,
                contentWorld: .page
            )
        }
        userContentController?.removeAllUserScripts()
        bridgeHandler?.tearDown()
        webView?.removeFromSuperview()
        webView = nil
        scriptHandler = nil
        bridgeHandler = nil
        #if DEBUG
        diagnosticsDelegate = nil
        diagnosticSchemeHandler = nil
        #endif
        userContentController = nil
        installedUserScriptCount = 0
        installedScriptMessageHandlerCount = 0
    }

    private static func load(
        webView: WKWebView,
        loadFileURL: URL,
        readAccessURL: URL,
        loadingMode: ChromeMV3ProductPopupOptionsLoadingMode
    ) {
        #if DEBUG
        if loadingMode == .diagnosticCustomScheme,
           let url = ChromeMV3PopupOptionsDiagnosticURLSchemeHandler
            .diagnosticURL(
                forFileURL: loadFileURL,
                rootURL: readAccessURL
            )
        {
            webView.load(URLRequest(url: url))
            return
        }
        #endif
        webView.loadFileURL(
            loadFileURL,
            allowingReadAccessTo: readAccessURL
        )
    }

    #if DEBUG
    private static func installDiagnosticSchemeHandlerIfNeeded(
        into configuration: WKWebViewConfiguration,
        loadingMode: ChromeMV3ProductPopupOptionsLoadingMode,
        readAccessURL: URL,
        bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler?
    ) -> ChromeMV3PopupOptionsDiagnosticURLSchemeHandler? {
        guard loadingMode == .diagnosticCustomScheme else { return nil }
        let scheme = ChromeMV3PopupOptionsDiagnosticURLSchemeHandler.scheme
        guard WKWebView.handlesURLScheme(scheme) == false else { return nil }
        let handler = ChromeMV3PopupOptionsDiagnosticURLSchemeHandler(
            rootURL: readAccessURL,
            bridgeHandler: bridgeHandler
        )
        configuration.setURLSchemeHandler(handler, forURLScheme: scheme)
        return handler
    }
    #endif

    #if DEBUG
    private var loadWaiter:
        ChromeMV3ProductPopupOptionsWKLoadWaiter?

    func waitForLoadForTesting() async throws {
        guard let webView else { return }
        let waiter = ChromeMV3ProductPopupOptionsWKLoadWaiter()
        loadWaiter = waiter
        webView.navigationDelegate = waiter
        defer {
            webView.navigationDelegate = nil
            loadWaiter = nil
        }
        if webView.isLoading == false {
            return
        }
        try await waiter.wait()
    }

    func evaluateJavaScriptForTesting(_ script: String) async throws -> Any? {
        guard let webView else { return nil }
        return try await webView.evaluateJavaScript(script)
    }

    func callAsyncJavaScriptForTesting(_ script: String) async throws -> Any? {
        guard let webView else { return nil }
        return try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }
    #endif
}

#if DEBUG
@MainActor
private final class ChromeMV3ProductPopupOptionsWKDiagnosticsDelegate:
    NSObject,
    WKNavigationDelegate,
    WKUIDelegate
{
    private weak var bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler?
    private let readAccessURL: URL

    init(
        bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler,
        readAccessURL: URL
    ) {
        self.bridgeHandler = bridgeHandler
        self.readAccessURL = readAccessURL.standardizedFileURL
        super.init()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler:
            @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        record(
            ChromeMV3PopupOptionsHostDiagnostics.navigationEvent(
                kind: "hostNavigationAction",
                apiName: "webkit.navigationAction",
                url: navigationAction.request.url,
                readAccessURL: readAccessURL,
                resultClassifier: "navigation action allowed",
                extraDiagnostics: [
                    "navigationType=\(navigationAction.navigationType.rawValue)",
                    "mainFrame=\(navigationAction.targetFrame?.isMainFrame ?? false)",
                ]
            )
        )
        _ = webView
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler:
            @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response
        var diagnostics = [
            "mainFrame=\(navigationResponse.isForMainFrame)",
            "mimeType=\(safeToken(response.mimeType ?? "none"))",
            "expectedContentLength=\(safeContentLength(response.expectedContentLength))",
        ]
        if let http = response as? HTTPURLResponse {
            diagnostics.append("status=\(http.statusCode)")
        } else {
            diagnostics.append("status=unavailable")
        }
        record(
            ChromeMV3PopupOptionsHostDiagnostics.navigationEvent(
                kind: "hostNavigationResponse",
                apiName: "webkit.navigationResponse",
                url: response.url,
                readAccessURL: readAccessURL,
                resultClassifier: "navigation response allowed",
                extraDiagnostics: diagnostics
            )
        )
        _ = webView
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        record(
            ChromeMV3PopupOptionsHostDiagnostics.navigationEvent(
                kind: "hostNavigationFinish",
                apiName: "webkit.didFinish",
                url: webView.url,
                readAccessURL: readAccessURL,
                resultClassifier: "navigation finished"
            )
        )
        _ = navigation
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = navigation
        recordNavigationFailure(webView: webView, error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = navigation
        recordNavigationFailure(webView: webView, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        record(
            ChromeMV3PopupOptionsHostDiagnostics.navigationEvent(
                kind: "webContentProcessTerminated",
                apiName: "webkit.webContentProcessDidTerminate",
                url: webView.url,
                readAccessURL: readAccessURL,
                resultClassifier: "web content process terminated",
                firstError: "web content process terminated"
            )
        )
    }

    private func recordNavigationFailure(
        webView: WKWebView,
        error: Error
    ) {
        let nsError = error as NSError
        record(
            ChromeMV3PopupOptionsHostDiagnostics.navigationEvent(
                kind: "hostNavigationFailure",
                apiName: "webkit.navigationFailure",
                url: webView.url,
                readAccessURL: readAccessURL,
                resultClassifier: "navigation failed",
                firstError:
                    "navigation failed: \(safeToken(nsError.domain))#\(nsError.code)",
                extraDiagnostics: [
                    "errorDomain=\(safeToken(nsError.domain))",
                    "errorCode=\(nsError.code)",
                ]
            )
        )
    }

    private func record(_ event: ChromeMV3PopupOptionsHostDiagnosticEvent) {
        bridgeHandler?.recordHostDiagnosticEvent(event)
    }

    private func safeToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              trimmed.count <= 96,
              trimmed.range(
                  of: #"^[A-Za-z0-9._+\-/=:# ]+$"#,
                  options: .regularExpression
              ) != nil
        else { return "redacted" }
        return trimmed
    }

    private func safeContentLength(_ value: Int64) -> String {
        guard value >= 0, value <= 100_000_000 else {
            return "unavailable"
        }
        return String(value)
    }
}

@MainActor
final class ChromeMV3PopupOptionsDiagnosticURLSchemeHandler:
    NSObject,
    WKURLSchemeHandler
{
    static let scheme = "sumi-extension-page-diagnostic"
    private static let host = "extension"

    private let rootURL: URL
    private weak var bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler?
    private let fileManager: FileManager
    private var stoppedTasks: Set<ObjectIdentifier> = []

    init(
        rootURL: URL,
        bridgeHandler: ChromeMV3PopupOptionsJSBridgeHandler?,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.bridgeHandler = bridgeHandler
        self.fileManager = fileManager
        super.init()
    }

    static func diagnosticURL(
        forFileURL fileURL: URL,
        rootURL: URL
    ) -> URL? {
        let root = rootURL.standardizedFileURL.path
        let file = fileURL.standardizedFileURL.path
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        guard file.hasPrefix(rootPrefix) else { return nil }
        let relativePath = String(file.dropFirst(rootPrefix.count))
        return diagnosticURL(relativePath: relativePath)
    }

    static func diagnosticURL(relativePath: String) -> URL? {
        switch ChromeMV3ExtensionPageResourcePath.normalize(relativePath) {
        case .failure:
            return nil
        case .success(let normalizedPath):
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.path = "/" + normalizedPath
            return components.url
        }
    }

    func resolveForTesting(
        _ url: URL?
    ) -> ChromeMV3PopupOptionsDiagnosticURLSchemeResolution {
        resolve(url)
    }

    func webView(
        _ webView: WKWebView,
        start urlSchemeTask: WKURLSchemeTask
    ) {
        _ = webView
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        stoppedTasks.remove(taskID)
        defer { stoppedTasks.remove(taskID) }

        let resolution = resolve(urlSchemeTask.request.url)
        switch resolution.status {
        case .served:
            guard let data = resolution.data,
                  let mimeType = resolution.mimeType,
                  isStopped(taskID) == false
            else { return }
            let response = URLResponse(
                url: resolution.url
                    ?? urlSchemeTask.request.url
                    ?? Self.diagnosticURL(relativePath: resolution.relativePath)
                    ?? URL(string: "\(Self.scheme)://\(Self.host)/")!,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName:
                    ChromeMV3PopupOptionsDiagnosticMIME.isText(mimeType)
                        ? "utf-8"
                        : nil
            )
            record(resolution: resolution)
            guard isStopped(taskID) == false else { return }
            urlSchemeTask.didReceive(response)
            guard isStopped(taskID) == false else { return }
            urlSchemeTask.didReceive(data)
            guard isStopped(taskID) == false else { return }
            urlSchemeTask.didFinish()
        case .failed:
            record(resolution: resolution)
            guard isStopped(taskID) == false else { return }
            urlSchemeTask.didFailWithError(
                NSError(
                    domain: "Sumi.ChromeMV3PopupDiagnosticScheme",
                    code: resolution.errorCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            resolution.failureReason
                                ?? "resource load failed",
                    ]
                )
            )
        }
    }

    func webView(
        _ webView: WKWebView,
        stop urlSchemeTask: WKURLSchemeTask
    ) {
        _ = webView
        stoppedTasks.insert(ObjectIdentifier(urlSchemeTask as AnyObject))
    }

    private func isStopped(_ taskID: ObjectIdentifier) -> Bool {
        stoppedTasks.contains(taskID)
    }

    private func resolve(
        _ url: URL?
    ) -> ChromeMV3PopupOptionsDiagnosticURLSchemeResolution {
        guard let url,
              url.scheme?.lowercased() == Self.scheme
        else {
            return .failed(
                url: url,
                relativePath: "none",
                reason: "diagnostic scheme request had an unsupported scheme",
                code: 1
            )
        }
        guard url.host == Self.host else {
            return .failed(
                url: url,
                relativePath: "none",
                reason: "diagnostic scheme request had an unsupported host",
                code: 2
            )
        }

        let requestPath = String(url.path.drop(while: { $0 == "/" }))
        switch ChromeMV3ExtensionPageResourcePath.normalize(requestPath) {
        case .failure(let reason):
            return .failed(
                url: url,
                relativePath:
                    ChromeMV3PopupOptionsHostDiagnostics.safeRelativePath(
                        requestPath
                    ),
                reason: reason,
                code: 3
            )
        case .success(let relativePath):
            guard rootIsUsable() else {
                return .failed(
                    url: url,
                    relativePath: relativePath,
                    reason:
                        "diagnostic scheme generated package root is missing or is a symlink",
                    code: 4
                )
            }
            guard let fileURL = ChromeMV3ExtensionPageResourcePath.resourceURL(
                normalizedRelativePath: relativePath,
                rootURL: rootURL
            ) else {
                return .failed(
                    url: url,
                    relativePath: relativePath,
                    reason:
                        "diagnostic scheme resource path escaped the generated package root",
                    code: 5
                )
            }
            guard resourcePathContainsNoSymlink(fileURL: fileURL) else {
                return .failed(
                    url: url,
                    relativePath: relativePath,
                    reason:
                        "diagnostic scheme resource path contains a symlink",
                    code: 6
                )
            }
            guard fileExistsAndIsRegular(fileURL) else {
                return .failed(
                    url: url,
                    relativePath: relativePath,
                    reason: "diagnostic scheme resource is missing",
                    code: 7
                )
            }
            guard let mimeType =
                    ChromeMV3PopupOptionsDiagnosticMIME.mimeType(
                        for: fileURL.pathExtension
                    )
            else {
                return .failed(
                    url: url,
                    relativePath: relativePath,
                    reason:
                        "diagnostic scheme resource MIME type is unsupported",
                    code: 8
                )
            }
            do {
                let data = try Data(contentsOf: fileURL)
                return .served(
                    url: url,
                    relativePath: relativePath,
                    fileURL: fileURL,
                    mimeType: mimeType,
                    data: data
                )
            } catch {
                return .failed(
                    url: url,
                    relativePath: relativePath,
                    reason:
                        "diagnostic scheme resource could not be read",
                    code: 9
                )
            }
        }
    }

    private func rootIsUsable() -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return false
        }
        return isSymbolicLink(rootURL) == false
    }

    private func resourcePathContainsNoSymlink(fileURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(rootPrefix) else { return false }
        let relativePath = String(filePath.dropFirst(rootPrefix.count))
        var current = rootURL
        for component in relativePath.split(separator: "/").map(String.init) {
            current = current.appendingPathComponent(component)
            if isSymbolicLink(current) {
                return false
            }
        }
        return true
    }

    private func fileExistsAndIsRegular(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue == false else {
            return false
        }
        return isSymbolicLink(url) == false
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
            .isSymbolicLink) == true
    }

    private func record(
        resolution: ChromeMV3PopupOptionsDiagnosticURLSchemeResolution
    ) {
        let served = resolution.status == .served
        let insideReadAccessRoot = resolution.fileURL.map {
            ChromeMV3PopupOptionsHostDiagnostics.urlInsideRoot(
                $0,
                rootURL: rootURL
            )
        } ?? false
        var diagnostics = [
            served
                ? "Diagnostic custom scheme served a generated package resource."
                : "Diagnostic custom scheme blocked a generated package resource.",
            "loadScheme=\(Self.scheme)",
            "resource=\(ChromeMV3PopupOptionsHostDiagnostics.safeRelativePath(resolution.relativePath))",
            "urlShape=\(ChromeMV3PopupOptionsHostDiagnostics.safeURLShape(resolution.url?.absoluteString ?? ""))",
            "insideReadAccessRoot=\(insideReadAccessRoot)",
        ]
        if let mimeType = resolution.mimeType {
            diagnostics.append("mimeType=\(mimeType)")
        }
        let safeFailure = resolution.failureReason.map {
            ChromeMV3PopupOptionsHostDiagnostics.safeDiagnosticToken($0)
        }
        if let reason = resolution.failureReason {
            diagnostics.append(
                "failure=\(ChromeMV3PopupOptionsHostDiagnostics.safeDiagnosticToken(reason))"
            )
        }
        bridgeHandler?.recordHostDiagnosticEvent(
            ChromeMV3PopupOptionsHostDiagnosticEvent(
                eventKind: served ? "resourceLoaded" : "resourceLoadError",
                apiName: "customScheme.resource",
                targetContext: "resource",
                safeMessageShapeClassification: "customSchemeResource",
                resultClassifier:
                    served ? "custom scheme resource served"
                        : "custom scheme resource blocked",
                firstMissingAPIOrPermissionOrLifecycleError:
                    served ? nil : safeFailure,
                diagnostics: diagnostics
            )
        )
    }
}

struct ChromeMV3PopupOptionsDiagnosticURLSchemeResolution:
    Equatable,
    Sendable
{
    enum Status: String, Equatable, Sendable {
        case served
        case failed
    }

    var status: Status
    var url: URL?
    var relativePath: String
    var fileURL: URL?
    var mimeType: String?
    var data: Data?
    var failureReason: String?
    var errorCode: Int

    static func served(
        url: URL,
        relativePath: String,
        fileURL: URL,
        mimeType: String,
        data: Data
    ) -> ChromeMV3PopupOptionsDiagnosticURLSchemeResolution {
        ChromeMV3PopupOptionsDiagnosticURLSchemeResolution(
            status: .served,
            url: url,
            relativePath: relativePath,
            fileURL: fileURL,
            mimeType: mimeType,
            data: data,
            failureReason: nil,
            errorCode: 0
        )
    }

    static func failed(
        url: URL?,
        relativePath: String,
        reason: String,
        code: Int
    ) -> ChromeMV3PopupOptionsDiagnosticURLSchemeResolution {
        ChromeMV3PopupOptionsDiagnosticURLSchemeResolution(
            status: .failed,
            url: url,
            relativePath: relativePath,
            fileURL: nil,
            mimeType: nil,
            data: nil,
            failureReason: reason,
            errorCode: code
        )
    }
}

enum ChromeMV3PopupOptionsDiagnosticMIME {
    static func mimeType(for pathExtension: String) -> String? {
        switch pathExtension.lowercased() {
        case "html", "htm":
            return "text/html"
        case "js", "mjs", "cjs":
            return "text/javascript"
        case "css":
            return "text/css"
        case "json", "map":
            return "application/json"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "ico":
            return "image/x-icon"
        case "svg":
            return "image/svg+xml"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        case "eot":
            return "application/vnd.ms-fontobject"
        default:
            return nil
        }
    }

    static func isText(_ mimeType: String) -> Bool {
        mimeType.hasPrefix("text/")
            || mimeType == "application/json"
            || mimeType == "image/svg+xml"
    }
}
#endif

#if canImport(AppKit)
@MainActor
private final class ChromeMV3ProductPopupOptionsPopoverDelegate:
    NSObject,
    NSPopoverDelegate
{
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func popoverDidClose(_ notification: Notification) {
        _ = notification
        onClose()
    }
}
#endif

#if DEBUG
@MainActor
private final class ChromeMV3ProductPopupOptionsWKLoadWaiter:
    NSObject,
    WKNavigationDelegate
{
    private var continuation: CheckedContinuation<Void, Error>?
    private var completed = false

    func wait() async throws {
        if completed { return }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        _ = webView
        _ = navigation
        finish()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(error)
    }

    private func finish(_ error: Error? = nil) {
        guard completed == false else { return }
        completed = true
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
#endif
#endif

private func uniqueBlockers(
    _ blockers: [ChromeMV3PopupOptionsBlocker]
) -> [ChromeMV3PopupOptionsBlocker] {
    Array(Set(blockers)).sorted()
}

private func uniqueSortedPopupOptions(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}
