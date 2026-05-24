//
//  ChromeMV3ManifestRewritePreview.swift
//  Sumi
//
//  Deterministic planning records for future generated-manifest rewrites.
//  This file does not rewrite, load, register, or execute extension code.
//

import CryptoKit
import Foundation

enum ChromeMV3ManifestRewritePreviewOperationType: String, Codable, CaseIterable, Comparable, Sendable {
    case replaceServiceWorkerWithWrapper
    case preserveOriginalServiceWorkerPath
    case prependContentScriptShims
    case injectExtensionPageShimMetadata
    case recordHostBridgeDeferred
    case recordUnsupportedAPIs
    case recordDeferredNativeHostAPIs
    case recordFixtureVerificationRequired

    static func < (
        lhs: ChromeMV3ManifestRewritePreviewOperationType,
        rhs: ChromeMV3ManifestRewritePreviewOperationType
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ManifestRewritePreviewSourceKind: String, Codable, Sendable {
    case chromeDocumentation
    case currentSumiCode
}

struct ChromeMV3ManifestRewritePreviewSource: Codable, Equatable, Sendable {
    var kind: ChromeMV3ManifestRewritePreviewSourceKind
    var title: String
    var url: String?
    var note: String
}

enum ChromeMV3ServiceWorkerWrapperKind: String, Codable, Sendable {
    case classic
    case module
}

struct ChromeMV3ManifestRewriteRuntimeTemplateFile: Codable, Equatable, Sendable {
    var moduleName: ChromeMV3RuntimeTemplateModuleName
    var outputRelativePath: String
    var sha256: String
    var inert: Bool
    var runtimeLoadable: Bool
    var requiredByRuntimeResourcePlan: Bool
    var manifestRewriteRequiredLater: Bool
    var fixtureVerificationRequiredLater: Bool
    var sourceManifestFields: [String]
}

struct ChromeMV3ServiceWorkerRewritePreview: Codable, Equatable, Sendable {
    var originalServiceWorkerPath: String
    var originalBackgroundType: String?
    var wrapperKind: ChromeMV3ServiceWorkerWrapperKind
    var futureWrapperModuleName: ChromeMV3RuntimeTemplateModuleName
    var futureWrapperPath: String
    var futureServiceWorkerShimModules: [ChromeMV3RuntimeTemplateModuleName]
    var futureServiceWorkerShimPaths: [String]
}

struct ChromeMV3ContentScriptRewritePreview: Codable, Equatable, Sendable {
    var index: Int
    var sourceManifestField: String
    var plannedShimPrefix: [String]
    var originalScripts: [String]
    var plannedScriptsAfterPrepend: [String]
    var css: [String]
    var matches: [String]
    var excludeMatches: [String]
    var includeGlobs: [String]
    var excludeGlobs: [String]
    var runAt: String?
    var allFrames: Bool?
    var matchAboutBlank: Bool?
    var matchOriginAsFallback: Bool?
    var world: String?
}

enum ChromeMV3ExtensionPageShimContext: String, Codable, Comparable, Sendable {
    case actionPopup
    case optionsPage
    case sidePanel

    static func < (
        lhs: ChromeMV3ExtensionPageShimContext,
        rhs: ChromeMV3ExtensionPageShimContext
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ExtensionPageShimInjectionPreview: Codable, Equatable, Sendable {
    var context: ChromeMV3ExtensionPageShimContext
    var sourceManifestField: String
    var pagePath: String
    var optionsDeclarationKey: String?
    var futureShimModuleNames: [ChromeMV3RuntimeTemplateModuleName]
    var futureShimPaths: [String]
    var runtimeTemplateCurrentlyRequired: Bool
    var nativeHostPlanningOnly: Bool
    var deferredAPIs: [ChromeMV3API]
    var htmlRewriteAppliedNow: Bool
    var manifestRewriteAppliedNow: Bool
}

enum ChromeMV3ManifestRewritePreviewWarningCode: String, Codable, Comparable, Sendable {
    case previewNotApplied
    case runtimeLoadableAfterPreviewFalse
    case unsupportedAPIsBlockRuntimeLoadability
    case deferredAPIsBlockRuntimeLoadability
    case fixtureVerificationRequired
    case sidePanelNativeHostPlanningOnly

    static func < (
        lhs: ChromeMV3ManifestRewritePreviewWarningCode,
        rhs: ChromeMV3ManifestRewritePreviewWarningCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ManifestRewritePreviewWarning: Codable, Equatable, Sendable {
    var code: ChromeMV3ManifestRewritePreviewWarningCode
    var message: String
    var sourceManifestFields: [String]
    var apis: [ChromeMV3API]
}

struct ChromeMV3ManifestRewritePreviewOperation: Codable, Equatable, Sendable {
    var order: Int
    var type: ChromeMV3ManifestRewritePreviewOperationType
    var sourceManifestFields: [String]
    var reason: String
    var sources: [ChromeMV3ManifestRewritePreviewSource]
    var appliedNow: Bool
    var needsFixtureVerification: Bool
    var warnings: [String]
    var blockedByAPIs: [ChromeMV3API]
    var serviceWorker: ChromeMV3ServiceWorkerRewritePreview?
    var contentScript: ChromeMV3ContentScriptRewritePreview?
    var extensionPage: ChromeMV3ExtensionPageShimInjectionPreview?
    var runtimeTemplateFiles: [ChromeMV3ManifestRewriteRuntimeTemplateFile]
}

struct ChromeMV3ManifestRewritePreview: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var originalManifestSHA256: String
    var generatedManifestSHA256BeforeRewrite: String
    var runtimeResourcePlanID: String?
    var runtimeResourcePlanSHA256: String?
    var operationOrdering: [ChromeMV3ManifestRewritePreviewOperationType]
    var plannedOperations: [ChromeMV3ManifestRewritePreviewOperation]
    var requiredRuntimeTemplateFiles: [ChromeMV3ManifestRewriteRuntimeTemplateFile]
    var warnings: [ChromeMV3ManifestRewritePreviewWarning]
    var unsupportedAPIsBlockingRuntimeLoadability: [ChromeMV3API]
    var deferredAPIsBlockingRuntimeLoadability: [ChromeMV3API]
    var unresolvedVerificationGaps: [String]
    var appliedNow: Bool
    var runtimeLoadableAfterPreview: Bool
}

enum ChromeMV3ManifestRewritePreviewPlanner {
    static func preview(
        originalManifestSHA256: String,
        generatedManifestSHA256BeforeRewrite: String,
        manifest: ChromeMV3Manifest,
        manifestJSONObject: [String: Any],
        installReport: ChromeMV3InstallReport,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
    ) -> ChromeMV3ManifestRewritePreview {
        let runtimeTemplateFiles = runtimeTemplateFileRecords(
            for: runtimeResourcePlan
        )
        var operations: [ChromeMV3ManifestRewritePreviewOperation] = []
        var order = 1

        appendServiceWorkerOperations(
            manifest: manifest,
            manifestJSONObject: manifestJSONObject,
            runtimeTemplateFiles: runtimeTemplateFiles,
            operations: &operations,
            order: &order
        )
        appendContentScriptOperations(
            manifestJSONObject: manifestJSONObject,
            runtimeTemplateFiles: runtimeTemplateFiles,
            operations: &operations,
            order: &order
        )
        appendExtensionPageOperations(
            manifestJSONObject: manifestJSONObject,
            installReport: installReport,
            runtimeResourcePlan: runtimeResourcePlan,
            runtimeTemplateFiles: runtimeTemplateFiles,
            operations: &operations,
            order: &order
        )
        appendDeferredCapabilityOperations(
            installReport: installReport,
            runtimeResourcePlan: runtimeResourcePlan,
            runtimeTemplateFiles: runtimeTemplateFiles,
            operations: &operations,
            order: &order
        )

        let warnings = previewWarnings(
            installReport: installReport,
            runtimeResourcePlan: runtimeResourcePlan
        )
        let unresolvedGaps = unresolvedVerificationGaps(
            manifest: manifest,
            installReport: installReport,
            runtimeResourcePlan: runtimeResourcePlan
        )

        return ChromeMV3ManifestRewritePreview(
            schemaVersion: 1,
            id: "manifest-rewrite-preview-\(generatedManifestSHA256BeforeRewrite.prefix(32))",
            originalManifestSHA256: originalManifestSHA256,
            generatedManifestSHA256BeforeRewrite: generatedManifestSHA256BeforeRewrite,
            runtimeResourcePlanID: "runtime-resource-plan-v\(runtimeResourcePlan.schemaVersion)",
            runtimeResourcePlanSHA256: runtimeResourcePlanHash(runtimeResourcePlan),
            operationOrdering: operations.map(\.type),
            plannedOperations: operations,
            requiredRuntimeTemplateFiles: runtimeTemplateFiles,
            warnings: warnings,
            unsupportedAPIsBlockingRuntimeLoadability: installReport
                .unsupportedAPIs
                .sorted(),
            deferredAPIsBlockingRuntimeLoadability: installReport
                .deferredAPIs
                .sorted(),
            unresolvedVerificationGaps: unresolvedGaps,
            appliedNow: false,
            runtimeLoadableAfterPreview: false
        )
    }

    private static func appendServiceWorkerOperations(
        manifest: ChromeMV3Manifest,
        manifestJSONObject: [String: Any],
        runtimeTemplateFiles: [ChromeMV3ManifestRewriteRuntimeTemplateFile],
        operations: inout [ChromeMV3ManifestRewritePreviewOperation],
        order: inout Int
    ) {
        guard
            let background = manifestJSONObject["background"] as? [String: Any],
            let serviceWorkerPath = stringValue(background["service_worker"])
                ?? manifest.background?.serviceWorker
        else {
            return
        }

        let backgroundType = stringValue(background["type"])
            ?? manifest.background?.type
        let wrapperModule: ChromeMV3RuntimeTemplateModuleName =
            backgroundType == "module"
                ? .serviceWorkerWrapperModule
                : .serviceWorkerWrapperClassic
        let wrapperTemplate = ChromeMV3RuntimeResourceTemplateCatalog.template(
            named: wrapperModule
        )
        let serviceWorkerShimModules = [
            ChromeMV3RuntimeTemplateModuleName.chromeShimCommon,
            .chromeShimServiceWorker,
        ]
        let serviceWorker = ChromeMV3ServiceWorkerRewritePreview(
            originalServiceWorkerPath: serviceWorkerPath,
            originalBackgroundType: backgroundType,
            wrapperKind: backgroundType == "module" ? .module : .classic,
            futureWrapperModuleName: wrapperModule,
            futureWrapperPath: wrapperTemplate.outputRelativePath,
            futureServiceWorkerShimModules: serviceWorkerShimModules,
            futureServiceWorkerShimPaths: serviceWorkerShimModules
                .map { ChromeMV3RuntimeResourceTemplateCatalog.template(named: $0).outputRelativePath }
        )

        let fields = backgroundType == nil
            ? ["background.service_worker"]
            : ["background.service_worker", "background.type"]
        operations.append(
            operation(
                order: order,
                type: .replaceServiceWorkerWithWrapper,
                sourceManifestFields: fields,
                reason: "Plan a future replacement of background.service_worker with the Sumi service-worker wrapper that matches background.type.",
                sources: [backgroundSource(), serviceWorkerLifecycleSource()],
                needsFixtureVerification: true,
                serviceWorker: serviceWorker,
                runtimeTemplateFiles: runtimeTemplateFiles.filter {
                    $0.moduleName == wrapperModule
                        || $0.moduleName == .chromeShimServiceWorker
                        || $0.moduleName == .chromeShimCommon
                }
            )
        )
        order += 1

        operations.append(
            operation(
                order: order,
                type: .preserveOriginalServiceWorkerPath,
                sourceManifestFields: ["background.service_worker"],
                reason: "Record the original service worker path as metadata for a later wrapper import plan without changing manifest.json.",
                sources: [backgroundSource(), currentSumiPreviewSource()],
                needsFixtureVerification: true,
                serviceWorker: serviceWorker,
                runtimeTemplateFiles: []
            )
        )
        order += 1
    }

    private static func appendContentScriptOperations(
        manifestJSONObject: [String: Any],
        runtimeTemplateFiles: [ChromeMV3ManifestRewriteRuntimeTemplateFile],
        operations: inout [ChromeMV3ManifestRewritePreviewOperation],
        order: inout Int
    ) {
        guard let scripts = manifestJSONObject["content_scripts"] as? [[String: Any]] else {
            return
        }

        let shimModules = [
            ChromeMV3RuntimeTemplateModuleName.chromeShimCommon,
            .chromeShimContentScript,
        ]
        let shimPrefix = shimModules.map {
            ChromeMV3RuntimeResourceTemplateCatalog.template(named: $0)
                .outputRelativePath
        }
        for (index, script) in scripts.enumerated() {
            let originalScripts = stringArray(script["js"])
            let preview = ChromeMV3ContentScriptRewritePreview(
                index: index,
                sourceManifestField: "content_scripts[\(index)]",
                plannedShimPrefix: shimPrefix,
                originalScripts: originalScripts,
                plannedScriptsAfterPrepend: shimPrefix + originalScripts,
                css: stringArray(script["css"]),
                matches: stringArray(script["matches"]),
                excludeMatches: stringArray(script["exclude_matches"]),
                includeGlobs: stringArray(script["include_globs"]),
                excludeGlobs: stringArray(script["exclude_globs"]),
                runAt: stringValue(script["run_at"]),
                allFrames: boolValue(script["all_frames"]),
                matchAboutBlank: boolValue(script["match_about_blank"]),
                matchOriginAsFallback: boolValue(script["match_origin_as_fallback"]),
                world: stringValue(script["world"])
            )
            operations.append(
                operation(
                    order: order,
                    type: .prependContentScriptShims,
                    sourceManifestFields: [
                        "content_scripts[\(index)]",
                        "content_scripts[\(index)].js",
                    ],
                    reason: "Plan future common and content-script shim prepends while preserving the existing script order after the prefix.",
                    sources: [contentScriptsSource()],
                    needsFixtureVerification: true,
                    contentScript: preview,
                    runtimeTemplateFiles: runtimeTemplateFiles.filter {
                        shimModules.contains($0.moduleName)
                    }
                )
            )
            order += 1
        }
    }

    private static func appendExtensionPageOperations(
        manifestJSONObject: [String: Any],
        installReport: ChromeMV3InstallReport,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan,
        runtimeTemplateFiles: [ChromeMV3ManifestRewriteRuntimeTemplateFile],
        operations: inout [ChromeMV3ManifestRewritePreviewOperation],
        order: inout Int
    ) {
        let pageShimModule = ChromeMV3RuntimeTemplateModuleName
            .chromeShimExtensionPage
        let pageShimPath = ChromeMV3RuntimeResourceTemplateCatalog
            .template(named: pageShimModule)
            .outputRelativePath

        var targets: [ChromeMV3ExtensionPageShimInjectionPreview] = []
        if
            let action = manifestJSONObject["action"] as? [String: Any],
            let popup = stringValue(action["default_popup"])
        {
            targets.append(
                extensionPageTarget(
                    context: .actionPopup,
                    sourceManifestField: "action.default_popup",
                    pagePath: popup,
                    optionsDeclarationKey: nil,
                    futureShimPath: pageShimPath,
                    installReport: installReport,
                    runtimeResourcePlan: runtimeResourcePlan
                )
            )
        }
        if let optionsPage = stringValue(manifestJSONObject["options_page"]) {
            targets.append(
                extensionPageTarget(
                    context: .optionsPage,
                    sourceManifestField: "options_page",
                    pagePath: optionsPage,
                    optionsDeclarationKey: "options_page",
                    futureShimPath: pageShimPath,
                    installReport: installReport,
                    runtimeResourcePlan: runtimeResourcePlan
                )
            )
        }
        if
            let optionsUI = manifestJSONObject["options_ui"] as? [String: Any],
            let page = stringValue(optionsUI["page"])
        {
            targets.append(
                extensionPageTarget(
                    context: .optionsPage,
                    sourceManifestField: "options_ui.page",
                    pagePath: page,
                    optionsDeclarationKey: "options_ui",
                    futureShimPath: pageShimPath,
                    installReport: installReport,
                    runtimeResourcePlan: runtimeResourcePlan
                )
            )
        }
        if
            let sidePanel = manifestJSONObject["side_panel"] as? [String: Any],
            let defaultPath = stringValue(sidePanel["default_path"])
        {
            targets.append(
                extensionPageTarget(
                    context: .sidePanel,
                    sourceManifestField: "side_panel.default_path",
                    pagePath: defaultPath,
                    optionsDeclarationKey: nil,
                    futureShimPath: pageShimPath,
                    installReport: installReport,
                    runtimeResourcePlan: runtimeResourcePlan
                )
            )
        }

        for target in targets {
            operations.append(
                operation(
                    order: order,
                    type: .injectExtensionPageShimMetadata,
                    sourceManifestFields: [target.sourceManifestField],
                    reason: "Record future extension-page shim injection metadata without editing HTML or manifest entries.",
                    sources: extensionPageSources(for: target.context),
                    needsFixtureVerification: true,
                    warnings: target.nativeHostPlanningOnly
                        ? ["sidePanel remains deferred/native-host planning only."]
                        : [],
                    blockedByAPIs: target.deferredAPIs,
                    extensionPage: target,
                    runtimeTemplateFiles: runtimeTemplateFiles.filter {
                        $0.moduleName == pageShimModule
                    }
                )
            )
            order += 1
        }
    }

    private static func appendDeferredCapabilityOperations(
        installReport: ChromeMV3InstallReport,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan,
        runtimeTemplateFiles: [ChromeMV3ManifestRewriteRuntimeTemplateFile],
        operations: inout [ChromeMV3ManifestRewritePreviewOperation],
        order: inout Int
    ) {
        if installReport.detectedAPIs.contains(.nativeMessaging) {
            operations.append(
                operation(
                    order: order,
                    type: .recordHostBridgeDeferred,
                    sourceManifestFields: ["permissions.nativeMessaging"],
                    reason: "Native messaging remains a deferred host-bridge plan; this preview does not launch a host process.",
                    sources: [runtimeMessagingSource(), currentSumiPreviewSource()],
                    needsFixtureVerification: true,
                    blockedByAPIs: [.nativeMessaging],
                    runtimeTemplateFiles: runtimeTemplateFiles.filter {
                        $0.moduleName == .hostBridgeStub
                    }
                )
            )
            order += 1
        }

        if installReport.unsupportedAPIs.isEmpty == false {
            operations.append(
                operation(
                    order: order,
                    type: .recordUnsupportedAPIs,
                    sourceManifestFields: manifestFields(
                        for: installReport.unsupportedAPIs,
                        runtimeResourcePlan: runtimeResourcePlan
                    ),
                    reason: "Unsupported APIs block runtime loadability after the preview.",
                    sources: [currentSumiPreviewSource()],
                    needsFixtureVerification: false,
                    blockedByAPIs: installReport.unsupportedAPIs.sorted(),
                    runtimeTemplateFiles: []
                )
            )
            order += 1
        }

        let nativeHostPlanningOnlyAPIs = runtimeResourcePlan.deferredCapabilityPlans
            .filter(\.nativeHostPlanningOnly)
            .map(\.api)
            .sorted()
        if nativeHostPlanningOnlyAPIs.isEmpty == false {
            operations.append(
                operation(
                    order: order,
                    type: .recordDeferredNativeHostAPIs,
                    sourceManifestFields: manifestFields(
                        for: nativeHostPlanningOnlyAPIs,
                        runtimeResourcePlan: runtimeResourcePlan
                    ),
                    reason: "Deferred native-host APIs remain planning-only and keep the generated bundle not runtime-loadable.",
                    sources: [currentSumiPreviewSource()],
                    needsFixtureVerification: runtimeResourcePlan
                        .fixtureVerificationRequiredLater,
                    blockedByAPIs: nativeHostPlanningOnlyAPIs,
                    runtimeTemplateFiles: []
                )
            )
            order += 1
        }

        if installReport.needsVerificationAPIs.isEmpty == false
            || runtimeResourcePlan.fixtureVerificationRequiredLater
        {
            operations.append(
                operation(
                    order: order,
                    type: .recordFixtureVerificationRequired,
                    sourceManifestFields: manifestFields(
                        for: installReport.needsVerificationAPIs,
                        runtimeResourcePlan: runtimeResourcePlan
                    ),
                    reason: "The planned rewrite remains fixture-gated and is not safe to execute in this prompt.",
                    sources: [currentSumiPreviewSource()],
                    needsFixtureVerification: true,
                    blockedByAPIs: installReport.needsVerificationAPIs.sorted(),
                    runtimeTemplateFiles: []
                )
            )
            order += 1
        }
    }

    private static func extensionPageTarget(
        context: ChromeMV3ExtensionPageShimContext,
        sourceManifestField: String,
        pagePath: String,
        optionsDeclarationKey: String?,
        futureShimPath: String,
        installReport: ChromeMV3InstallReport,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
    ) -> ChromeMV3ExtensionPageShimInjectionPreview {
        let isSidePanel = context == .sidePanel
        let nativeHostPlanningOnly = isSidePanel
            && (
                installReport.deferredAPIs.contains(.sidePanel)
                    || installReport.nativeHostAPIs.contains(.sidePanel)
            )
        return ChromeMV3ExtensionPageShimInjectionPreview(
            context: context,
            sourceManifestField: sourceManifestField,
            pagePath: pagePath,
            optionsDeclarationKey: optionsDeclarationKey,
            futureShimModuleNames: [.chromeShimExtensionPage],
            futureShimPaths: [futureShimPath],
            runtimeTemplateCurrentlyRequired: runtimeResourcePlan
                .requires(.chromeShimExtensionPage),
            nativeHostPlanningOnly: nativeHostPlanningOnly,
            deferredAPIs: nativeHostPlanningOnly ? [.sidePanel] : [],
            htmlRewriteAppliedNow: false,
            manifestRewriteAppliedNow: false
        )
    }

    private static func operation(
        order: Int,
        type: ChromeMV3ManifestRewritePreviewOperationType,
        sourceManifestFields: [String],
        reason: String,
        sources: [ChromeMV3ManifestRewritePreviewSource],
        needsFixtureVerification: Bool,
        warnings: [String] = [],
        blockedByAPIs: [ChromeMV3API] = [],
        serviceWorker: ChromeMV3ServiceWorkerRewritePreview? = nil,
        contentScript: ChromeMV3ContentScriptRewritePreview? = nil,
        extensionPage: ChromeMV3ExtensionPageShimInjectionPreview? = nil,
        runtimeTemplateFiles: [ChromeMV3ManifestRewriteRuntimeTemplateFile]
    ) -> ChromeMV3ManifestRewritePreviewOperation {
        ChromeMV3ManifestRewritePreviewOperation(
            order: order,
            type: type,
            sourceManifestFields: sourceManifestFields.sorted(),
            reason: reason,
            sources: sources,
            appliedNow: false,
            needsFixtureVerification: needsFixtureVerification,
            warnings: warnings.sorted(),
            blockedByAPIs: blockedByAPIs.sorted(),
            serviceWorker: serviceWorker,
            contentScript: contentScript,
            extensionPage: extensionPage,
            runtimeTemplateFiles: runtimeTemplateFiles.sorted {
                $0.outputRelativePath < $1.outputRelativePath
            }
        )
    }

    private static func runtimeTemplateFileRecords(
        for plan: ChromeMV3RuntimeResourcePlan
    ) -> [ChromeMV3ManifestRewriteRuntimeTemplateFile] {
        plan.templateRequirements.map { requirement in
            let template = ChromeMV3RuntimeResourceTemplateCatalog.template(
                named: requirement.templateModuleName
            )
            return ChromeMV3ManifestRewriteRuntimeTemplateFile(
                moduleName: requirement.templateModuleName,
                outputRelativePath: requirement.outputRelativePath,
                sha256: sha256Hex(Data(template.contents.utf8)),
                inert: requirement.inert,
                runtimeLoadable: template.runtimeLoadable,
                requiredByRuntimeResourcePlan: true,
                manifestRewriteRequiredLater: requirement
                    .manifestRewriteRequiredLater,
                fixtureVerificationRequiredLater: requirement
                    .fixtureVerificationRequiredLater,
                sourceManifestFields: requirement.sourceManifestFields
            )
        }
        .sorted { $0.outputRelativePath < $1.outputRelativePath }
    }

    private static func previewWarnings(
        installReport: ChromeMV3InstallReport,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
    ) -> [ChromeMV3ManifestRewritePreviewWarning] {
        var warnings: [ChromeMV3ManifestRewritePreviewWarning] = [
            ChromeMV3ManifestRewritePreviewWarning(
                code: .previewNotApplied,
                message: "Manifest rewrite preview is planning metadata only; no rewrite is applied.",
                sourceManifestFields: [],
                apis: []
            ),
            ChromeMV3ManifestRewritePreviewWarning(
                code: .runtimeLoadableAfterPreviewFalse,
                message: "Generated bundle remains not runtime-loadable after this preview.",
                sourceManifestFields: [],
                apis: []
            ),
        ]

        if installReport.unsupportedAPIs.isEmpty == false {
            warnings.append(
                ChromeMV3ManifestRewritePreviewWarning(
                    code: .unsupportedAPIsBlockRuntimeLoadability,
                    message: "Unsupported APIs block runtime loadability.",
                    sourceManifestFields: manifestFields(
                        for: installReport.unsupportedAPIs,
                        runtimeResourcePlan: runtimeResourcePlan
                    ),
                    apis: installReport.unsupportedAPIs.sorted()
                )
            )
        }
        if installReport.deferredAPIs.isEmpty == false {
            warnings.append(
                ChromeMV3ManifestRewritePreviewWarning(
                    code: .deferredAPIsBlockRuntimeLoadability,
                    message: "Deferred APIs keep the generated bundle planning-only.",
                    sourceManifestFields: manifestFields(
                        for: installReport.deferredAPIs,
                        runtimeResourcePlan: runtimeResourcePlan
                    ),
                    apis: installReport.deferredAPIs.sorted()
                )
            )
        }
        if installReport.needsVerificationAPIs.isEmpty == false
            || runtimeResourcePlan.fixtureVerificationRequiredLater
        {
            warnings.append(
                ChromeMV3ManifestRewritePreviewWarning(
                    code: .fixtureVerificationRequired,
                    message: "Fixture verification is required before any generated-manifest rewrite can be enabled.",
                    sourceManifestFields: manifestFields(
                        for: installReport.needsVerificationAPIs,
                        runtimeResourcePlan: runtimeResourcePlan
                    ),
                    apis: installReport.needsVerificationAPIs.sorted()
                )
            )
        }
        if installReport.deferredAPIs.contains(.sidePanel) {
            warnings.append(
                ChromeMV3ManifestRewritePreviewWarning(
                    code: .sidePanelNativeHostPlanningOnly,
                    message: "sidePanel.default_path is recorded as extension-page metadata only; no side-panel host is created.",
                    sourceManifestFields: ["side_panel.default_path"],
                    apis: [.sidePanel]
                )
            )
        }

        return warnings.sorted { lhs, rhs in
            if lhs.code == rhs.code {
                return lhs.sourceManifestFields.joined(separator: ".")
                    < rhs.sourceManifestFields.joined(separator: ".")
            }
            return lhs.code < rhs.code
        }
    }

    private static func unresolvedVerificationGaps(
        manifest: ChromeMV3Manifest,
        installReport: ChromeMV3InstallReport,
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
    ) -> [String] {
        var gaps: [String] = [
            "Future rewrites require fixture verification before Sumi can claim Chrome behavior parity.",
        ]
        if manifest.background?.serviceWorker != nil {
            gaps.append(
                "Verify service-worker wrapper lifecycle, module/classic import behavior, wakeups, and termination behavior against Chrome fixtures."
            )
        }
        if manifest.contentScripts.isEmpty == false {
            gaps.append(
                "Verify content-script shim ordering, run_at, all_frames, match_about_blank, match_origin_as_fallback, and world behavior against Chrome fixtures."
            )
        }
        if manifest.action?.defaultPopup != nil
            || manifest.optionsPage != nil
            || manifest.optionsUI?.page != nil
        {
            gaps.append(
                "Verify extension-page shim injection, CSP interaction, runtime messaging, and page load ordering before any HTML rewrite."
            )
        }
        if manifest.sidePanel?.defaultPath != nil {
            gaps.append(
                "Verify sidePanel.default_path as native-host/browser-UI planning only before any side-panel runtime host exists."
            )
        }
        if manifest.webAccessibleResources.isEmpty == false {
            gaps.append(
                "Verify whether future shim resources require web_accessible_resources exposure; this preview does not add exposure."
            )
        }
        if installReport.detectedAPIs.contains(.runtime) {
            gaps.append(
                "Verify runtime.sendMessage/connect event routing and sender metadata before runtime loading."
            )
        }
        if runtimeResourcePlan.deferredCapabilityPlans.isEmpty == false {
            gaps.append(
                "Deferred capability plans still need host, consent, lifecycle, and privacy rules before runtime loading."
            )
        }
        return Array(Set(gaps)).sorted()
    }

    private static func manifestFields(
        for apis: [ChromeMV3API],
        runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
    ) -> [String] {
        var fields = Set<String>()
        for api in apis {
            var apiFields = Set<String>()
            for deferred in runtimeResourcePlan.deferredCapabilityPlans
                where deferred.api == api
            {
                apiFields.formUnion(deferred.sourceManifestFields)
            }
            for requirement in runtimeResourcePlan.templateRequirements
                where requirement.sourceAPIs.contains(api)
            {
                apiFields.formUnion(requirement.sourceManifestFields)
            }
            if apiFields.isEmpty {
                fields.insert(api.rawValue)
            } else {
                fields.formUnion(apiFields)
            }
        }
        return fields.sorted()
    }

    private static func extensionPageSources(
        for context: ChromeMV3ExtensionPageShimContext
    ) -> [ChromeMV3ManifestRewritePreviewSource] {
        switch context {
        case .actionPopup:
            return [actionSource(), runtimeMessagingSource()]
        case .optionsPage:
            return [optionsPageSource(), runtimeMessagingSource()]
        case .sidePanel:
            return [sidePanelSource(), runtimeMessagingSource()]
        }
    }

    private static func backgroundSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: "Chrome manifest background",
            url: "https://developer.chrome.com/docs/extensions/reference/manifest/background",
            note: "background.service_worker names the extension service worker, and background.type may be module."
        )
    }

    private static func contentScriptsSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: "Chrome manifest content_scripts",
            url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts",
            note: "Content-script js files run in array order and preserve match/frame/run_at/world metadata."
        )
    }

    private static func actionSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: "Chrome action default_popup",
            url: "https://developer.chrome.com/docs/extensions/reference/api/action",
            note: "action.default_popup points to an extension popup page."
        )
    }

    private static func optionsPageSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: "Chrome options pages",
            url: "https://developer.chrome.com/docs/extensions/develop/ui/options-page",
            note: "options_page and options_ui.page register extension options pages."
        )
    }

    private static func sidePanelSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: "Chrome sidePanel default_path",
            url: "https://developer.chrome.com/docs/extensions/reference/api/sidePanel",
            note: "side_panel.default_path points to an extension page hosted by Chrome's side panel UI."
        )
    }

    private static func serviceWorkerLifecycleSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: "Chrome extension service worker lifecycle",
            url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
            note: "Service worker wake and shutdown behavior must be fixture-verified before rewrites are executable."
        )
    }

    private static func runtimeMessagingSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: "Chrome runtime messaging",
            url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
            note: "runtime messaging sender and response behavior remains a verification gap."
        )
    }

    private static func currentSumiPreviewSource() -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .currentSumiCode,
            title: "Sumi Chrome MV3 generated-bundle planning",
            url: nil,
            note: "Current Sumi generated bundles write inert templates and keep runtimeLoadable false."
        )
    }

    private static func runtimeResourcePlanHash(
        _ plan: ChromeMV3RuntimeResourcePlan
    ) -> String? {
        guard
            let json = try? ChromeMV3DeterministicJSON.encodedString(plan),
            let data = json.data(using: .utf8)
        else {
            return nil
        }
        return sha256Hex(data)
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func stringArray(_ value: Any?) -> [String] {
        value as? [String] ?? []
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type == "c" else { return nil }
        return number.boolValue
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
