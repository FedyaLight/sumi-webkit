//
//  ChromeMV3RuntimeResources.swift
//  Sumi
//
//  Deterministic, inert Chrome MV3 runtime resource planning. These templates
//  are not wired into generated manifests and do not make bundles loadable.
//

import Foundation

enum ChromeMV3RuntimeTemplateModuleName: String, Codable, CaseIterable, Comparable, Sendable {
    case serviceWorkerWrapperModule = "sumi.service-worker-wrapper.module"
    case serviceWorkerWrapperClassic = "sumi.service-worker-wrapper.classic"
    case chromeShimCommon = "sumi.chrome-shim.common"
    case chromeShimServiceWorker = "sumi.chrome-shim.service-worker"
    case chromeShimContentScript = "sumi.chrome-shim.content-script"
    case chromeShimExtensionPage = "sumi.chrome-shim.extension-page"
    case hostBridgeStub = "sumi.host-bridge.stub"

    static func < (
        lhs: ChromeMV3RuntimeTemplateModuleName,
        rhs: ChromeMV3RuntimeTemplateModuleName
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3RuntimeResourceTemplate: Equatable, Sendable {
    var moduleName: ChromeMV3RuntimeTemplateModuleName
    var fileName: String
    var moduleIdentifier: String
    var inert: Bool
    var runtimeLoadable: Bool
    var contents: String

    var outputRelativePath: String {
        ChromeMV3RuntimeResourceTemplateCatalog.runtimeDirectoryName
            + "/"
            + fileName
    }
}

enum ChromeMV3RuntimeResourceTemplateCatalog {
    static let runtimeDirectoryName = "_sumi_runtime"

    static let allTemplates: [ChromeMV3RuntimeResourceTemplate] = [
        ChromeMV3RuntimeResourceTemplate(
            moduleName: .chromeShimCommon,
            fileName: "chrome-shim.common.js",
            moduleIdentifier: "sumi.chrome-shim.common",
            inert: true,
            runtimeLoadable: false,
            contents: """
            /*
            sumiRuntimeTemplate: sumi.chrome-shim.common
            inert: true
            runtimeLoadable: false
            notWired: true
            futureResponsibilities:
            - Share namespace and argument-normalization helpers across future shims.
            - Preserve Chrome MV3 error and callback contracts after fixture verification.
            currentSafety:
            - No extension API calls.
            - No event listeners.
            - No timers.
            - No page script insertion.
            */
            export {};

            """
        ),
        ChromeMV3RuntimeResourceTemplate(
            moduleName: .chromeShimContentScript,
            fileName: "chrome-shim.content-script.js",
            moduleIdentifier: "sumi.chrome-shim.content-script",
            inert: true,
            runtimeLoadable: false,
            contents: """
            /*
            sumiRuntimeTemplate: sumi.chrome-shim.content-script
            inert: true
            runtimeLoadable: false
            notWired: true
            futureResponsibilities:
            - Provide isolated-world content-script compatibility helpers.
            - Route future extension-context requests through a verified bridge.
            currentSafety:
            - No extension API calls.
            - No event listeners.
            - No timers.
            - No page script insertion.
            */
            export {};

            """
        ),
        ChromeMV3RuntimeResourceTemplate(
            moduleName: .chromeShimExtensionPage,
            fileName: "chrome-shim.extension-page.js",
            moduleIdentifier: "sumi.chrome-shim.extension-page",
            inert: true,
            runtimeLoadable: false,
            contents: """
            /*
            sumiRuntimeTemplate: sumi.chrome-shim.extension-page
            inert: true
            runtimeLoadable: false
            notWired: true
            futureResponsibilities:
            - Provide future popup and options-page compatibility helpers.
            - Keep UI-page behavior behind manifest and fixture verification.
            currentSafety:
            - No extension API calls.
            - No event listeners.
            - No timers.
            - No page script insertion.
            */
            export {};

            """
        ),
        ChromeMV3RuntimeResourceTemplate(
            moduleName: .chromeShimServiceWorker,
            fileName: "chrome-shim.service-worker.js",
            moduleIdentifier: "sumi.chrome-shim.service-worker",
            inert: true,
            runtimeLoadable: false,
            contents: """
            /*
            sumiRuntimeTemplate: sumi.chrome-shim.service-worker
            inert: true
            runtimeLoadable: false
            notWired: true
            futureResponsibilities:
            - Provide service-worker-context compatibility helpers.
            - Respect Chrome MV3 worker lifecycle limits after fixture verification.
            currentSafety:
            - No extension API calls.
            - No event listeners.
            - No timers.
            - No host process launch.
            */
            export {};

            """
        ),
        ChromeMV3RuntimeResourceTemplate(
            moduleName: .hostBridgeStub,
            fileName: "host-bridge.stub.js",
            moduleIdentifier: "sumi.host-bridge.stub",
            inert: true,
            runtimeLoadable: false,
            contents: """
            /*
            sumiRuntimeTemplate: sumi.host-bridge.stub
            inert: true
            runtimeLoadable: false
            notWired: true
            futureResponsibilities:
            - Describe a future host bridge contract after consent and validation design.
            - Keep host process lifecycle outside generated bundles.
            currentSafety:
            - No extension API calls.
            - No event listeners.
            - No timers.
            - No host process launch.
            */
            export {};

            """
        ),
        ChromeMV3RuntimeResourceTemplate(
            moduleName: .serviceWorkerWrapperClassic,
            fileName: "service-worker-wrapper.classic.js",
            moduleIdentifier: "sumi.service-worker-wrapper.classic",
            inert: true,
            runtimeLoadable: false,
            contents: """
            /*
            sumiRuntimeTemplate: sumi.service-worker-wrapper.classic
            inert: true
            runtimeLoadable: false
            notWired: true
            futureResponsibilities:
            - Wrap a classic Chrome MV3 background service worker without changing lifecycle semantics.
            - Load verified compatibility helpers only after manifest rewrite is explicitly enabled.
            currentSafety:
            - No extension API calls.
            - No event listeners.
            - No timers.
            - No imported extension code.
            */

            """
        ),
        ChromeMV3RuntimeResourceTemplate(
            moduleName: .serviceWorkerWrapperModule,
            fileName: "service-worker-wrapper.module.js",
            moduleIdentifier: "sumi.service-worker-wrapper.module",
            inert: true,
            runtimeLoadable: false,
            contents: """
            /*
            sumiRuntimeTemplate: sumi.service-worker-wrapper.module
            inert: true
            runtimeLoadable: false
            notWired: true
            futureResponsibilities:
            - Wrap a module Chrome MV3 background service worker without changing lifecycle semantics.
            - Load verified compatibility helpers only after manifest rewrite is explicitly enabled.
            currentSafety:
            - No extension API calls.
            - No event listeners.
            - No timers.
            - No imported extension code.
            */
            export {};

            """
        ),
    ].sorted { $0.moduleName < $1.moduleName }

    static func template(
        named moduleName: ChromeMV3RuntimeTemplateModuleName
    ) -> ChromeMV3RuntimeResourceTemplate {
        allTemplates.first { $0.moduleName == moduleName }!
    }
}

struct ChromeMV3RuntimeTemplateRequirement: Codable, Equatable, Sendable {
    var templateModuleName: ChromeMV3RuntimeTemplateModuleName
    var outputRelativePath: String
    var reason: String
    var sourceAPIs: [ChromeMV3API]
    var sourceManifestFields: [String]
    var inert: Bool
    var manifestRewriteRequiredLater: Bool
    var fixtureVerificationRequiredLater: Bool
}

struct ChromeMV3RuntimeDeferredCapabilityPlan: Codable, Equatable, Sendable {
    var api: ChromeMV3API
    var reason: String
    var sourceManifestFields: [String]
    var nativeHostPlanningOnly: Bool
    var runtimeTemplateModuleNames: [ChromeMV3RuntimeTemplateModuleName]
    var fixtureVerificationRequiredLater: Bool
}

struct ChromeMV3RuntimeResourcePlan: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var requiredTemplateModuleNames: [ChromeMV3RuntimeTemplateModuleName]
    var templateRequirements: [ChromeMV3RuntimeTemplateRequirement]
    var deferredCapabilityPlans: [ChromeMV3RuntimeDeferredCapabilityPlan]
    var manifestRewriteRequiredLater: Bool
    var fixtureVerificationRequiredLater: Bool
    var templatesAreInert: Bool
    var executableRuntimeFilesWritten: Bool
    var runtimeLoadable: Bool

    func requires(_ moduleName: ChromeMV3RuntimeTemplateModuleName) -> Bool {
        requiredTemplateModuleNames.contains(moduleName)
    }
}

enum ChromeMV3RuntimeResourcePlanner {
    static func plan(
        manifest: ChromeMV3Manifest,
        installReport: ChromeMV3InstallReport
    ) -> ChromeMV3RuntimeResourcePlan {
        var builder = RuntimeResourcePlanBuilder(
            manifest: manifest,
            installReport: installReport
        )

        builder.planCommonShimIfNeeded()
        builder.planServiceWorkerResourcesIfNeeded()
        builder.planContentScriptShimIfNeeded()
        builder.planExtensionPageShimIfNeeded()
        builder.planHostBridgeStubIfNeeded()
        builder.planDeferredNativeHostOnlyCapabilities()

        return builder.build()
    }
}

private struct RuntimeResourcePlanBuilder {
    var manifest: ChromeMV3Manifest
    var installReport: ChromeMV3InstallReport
    var requirementsByModule: [ChromeMV3RuntimeTemplateModuleName: ChromeMV3RuntimeTemplateRequirement] = [:]
    var deferredPlansByAPI: [ChromeMV3API: ChromeMV3RuntimeDeferredCapabilityPlan] = [:]

    mutating func planCommonShimIfNeeded() {
        let commonCandidateAPIs = installReport.detectedAPIs.filter { api in
            switch api {
            case .runtime,
                 .storage,
                 .action,
                 .permissions,
                 .activeTab,
                 .alarms,
                 .i18n,
                 .scripting:
                return true
            default:
                return false
            }
        }
        let contextLoadsExtensionCode = manifest.background?.serviceWorker != nil
            || manifest.contentScripts.isEmpty == false
            || manifest.action?.defaultPopup != nil
            || manifest.optionsPage != nil
            || manifest.optionsUI?.page != nil
        var sourceAPIs = commonCandidateAPIs.filter { $0 != .runtime }
        if contextLoadsExtensionCode, commonCandidateAPIs.contains(.runtime) {
            sourceAPIs.append(.runtime)
        }

        guard sourceAPIs.isEmpty == false else { return }
        insertRequirement(
            moduleName: .chromeShimCommon,
            reason: "Common Chrome compatibility helpers are planned for detected API surfaces.",
            sourceAPIs: sourceAPIs,
            sourceManifestFields: manifestFields(for: sourceAPIs),
            manifestRewriteRequiredLater: true,
            fixtureVerificationRequiredLater: needsFixtureVerification(sourceAPIs)
        )
    }

    mutating func planServiceWorkerResourcesIfNeeded() {
        guard manifest.background?.serviceWorker != nil else { return }

        let wrapper: ChromeMV3RuntimeTemplateModuleName
        if manifest.background?.type == "module" {
            wrapper = .serviceWorkerWrapperModule
        } else {
            wrapper = .serviceWorkerWrapperClassic
        }

        insertRequirement(
            moduleName: wrapper,
            reason: "A future wrapper is required before Sumi can adapt the MV3 background service worker.",
            sourceAPIs: [.runtime],
            sourceManifestFields: ["background.service_worker"],
            manifestRewriteRequiredLater: true,
            fixtureVerificationRequiredLater: true
        )
        insertRequirement(
            moduleName: .chromeShimServiceWorker,
            reason: "Service-worker-context shim planning follows the MV3 background service worker declaration.",
            sourceAPIs: [.runtime],
            sourceManifestFields: ["background.service_worker"],
            manifestRewriteRequiredLater: true,
            fixtureVerificationRequiredLater: true
        )
    }

    mutating func planContentScriptShimIfNeeded() {
        guard manifest.contentScripts.isEmpty == false else { return }
        insertRequirement(
            moduleName: .chromeShimContentScript,
            reason: "Content scripts run in an isolated extension world and need future context-specific shim verification.",
            sourceAPIs: [.scripting, .runtime],
            sourceManifestFields: ["content_scripts"],
            manifestRewriteRequiredLater: true,
            fixtureVerificationRequiredLater: true
        )
    }

    mutating func planExtensionPageShimIfNeeded() {
        let fields = extensionPageManifestFields()
        guard fields.isEmpty == false else { return }

        var apis: [ChromeMV3API] = [.runtime]
        if manifest.action?.defaultPopup != nil {
            apis.append(.action)
        }
        insertRequirement(
            moduleName: .chromeShimExtensionPage,
            reason: "Action popup and options pages are extension pages that need future UI-page shim verification.",
            sourceAPIs: uniqueSorted(apis),
            sourceManifestFields: fields,
            manifestRewriteRequiredLater: true,
            fixtureVerificationRequiredLater: true
        )
    }

    mutating func planHostBridgeStubIfNeeded() {
        guard installReport.detectedAPIs.contains(.nativeMessaging) else { return }

        insertRequirement(
            moduleName: .hostBridgeStub,
            reason: "Native messaging requires a future host bridge contract, but this plan leaves it inert and deferred.",
            sourceAPIs: [.nativeMessaging],
            sourceManifestFields: ["permissions.nativeMessaging"],
            manifestRewriteRequiredLater: false,
            fixtureVerificationRequiredLater: true
        )
        insertDeferredPlan(
            api: .nativeMessaging,
            reason: "Native messaging remains deferred until host validation, consent, and lifecycle rules are specified.",
            sourceManifestFields: ["permissions.nativeMessaging"],
            nativeHostPlanningOnly: false,
            runtimeTemplateModuleNames: [.hostBridgeStub],
            fixtureVerificationRequiredLater: true
        )
    }

    mutating func planDeferredNativeHostOnlyCapabilities() {
        for api in [ChromeMV3API.identity, .offscreen, .sidePanel] where installReport.detectedAPIs.contains(api) {
            insertDeferredPlan(
                api: api,
                reason: "\(api.rawValue) has internal compatibility diagnostics only; product runtime/UI support remains unavailable and no generated runtime template is implemented.",
                sourceManifestFields: manifestFields(for: [api]),
                nativeHostPlanningOnly: false,
                runtimeTemplateModuleNames: [],
                fixtureVerificationRequiredLater: installReport.needsVerificationAPIs.contains(api)
            )
        }
    }

    func build() -> ChromeMV3RuntimeResourcePlan {
        let requirements = requirementsByModule.values.sorted { lhs, rhs in
            lhs.templateModuleName < rhs.templateModuleName
        }
        let deferredPlans = deferredPlansByAPI.values.sorted { lhs, rhs in
            lhs.api < rhs.api
        }
        let fixtureVerificationRequired = requirements
            .contains { $0.fixtureVerificationRequiredLater }
            || deferredPlans.contains { $0.fixtureVerificationRequiredLater }

        return ChromeMV3RuntimeResourcePlan(
            schemaVersion: 1,
            requiredTemplateModuleNames: requirements
                .map(\.templateModuleName)
                .sorted(),
            templateRequirements: requirements,
            deferredCapabilityPlans: deferredPlans,
            manifestRewriteRequiredLater: requirements
                .contains { $0.manifestRewriteRequiredLater },
            fixtureVerificationRequiredLater: fixtureVerificationRequired,
            templatesAreInert: true,
            executableRuntimeFilesWritten: false,
            runtimeLoadable: false
        )
    }

    private mutating func insertRequirement(
        moduleName: ChromeMV3RuntimeTemplateModuleName,
        reason: String,
        sourceAPIs: [ChromeMV3API],
        sourceManifestFields: [String],
        manifestRewriteRequiredLater: Bool,
        fixtureVerificationRequiredLater: Bool
    ) {
        let template = ChromeMV3RuntimeResourceTemplateCatalog.template(
            named: moduleName
        )
        requirementsByModule[moduleName] = ChromeMV3RuntimeTemplateRequirement(
            templateModuleName: moduleName,
            outputRelativePath: template.outputRelativePath,
            reason: reason,
            sourceAPIs: sourceAPIs.sorted(),
            sourceManifestFields: sourceManifestFields.sorted(),
            inert: template.inert,
            manifestRewriteRequiredLater: manifestRewriteRequiredLater,
            fixtureVerificationRequiredLater: fixtureVerificationRequiredLater
        )
    }

    private mutating func insertDeferredPlan(
        api: ChromeMV3API,
        reason: String,
        sourceManifestFields: [String],
        nativeHostPlanningOnly: Bool,
        runtimeTemplateModuleNames: [ChromeMV3RuntimeTemplateModuleName],
        fixtureVerificationRequiredLater: Bool
    ) {
        deferredPlansByAPI[api] = ChromeMV3RuntimeDeferredCapabilityPlan(
            api: api,
            reason: reason,
            sourceManifestFields: sourceManifestFields.sorted(),
            nativeHostPlanningOnly: nativeHostPlanningOnly,
            runtimeTemplateModuleNames: runtimeTemplateModuleNames.sorted(),
            fixtureVerificationRequiredLater: fixtureVerificationRequiredLater
        )
    }

    private func extensionPageManifestFields() -> [String] {
        var fields: [String] = []
        if manifest.action?.defaultPopup != nil {
            fields.append("action.default_popup")
        }
        if manifest.optionsPage != nil {
            fields.append("options_page")
        }
        if manifest.optionsUI?.page != nil {
            fields.append("options_ui.page")
        }
        return fields.sorted()
    }

    private func needsFixtureVerification(_ apis: [ChromeMV3API]) -> Bool {
        apis.contains { installReport.needsVerificationAPIs.contains($0) }
    }

    private func manifestFields(for apis: [ChromeMV3API]) -> [String] {
        var fields: Set<String> = []
        for api in apis {
            switch api {
            case .runtime:
                if manifest.background?.serviceWorker != nil {
                    fields.insert("background.service_worker")
                } else {
                    fields.insert("manifest")
                }
            case .storage:
                fields.insert("permissions.storage")
            case .tabs:
                fields.insert("permissions.tabs")
            case .scripting:
                if manifest.contentScripts.isEmpty == false {
                    fields.insert("content_scripts")
                }
                if manifest.declaresPermission("scripting") {
                    fields.insert("permissions.scripting")
                }
            case .action:
                fields.insert("action")
            case .permissions:
                fields.insert("permissions")
            case .activeTab:
                fields.insert("permissions.activeTab")
            case .contextMenus:
                fields.insert("permissions.contextMenus")
            case .cookies:
                fields.insert("permissions.cookies")
            case .alarms:
                fields.insert("permissions.alarms")
            case .webNavigation:
                fields.insert("permissions.webNavigation")
            case .webRequest:
                fields.insert("permissions.webRequest")
            case .declarativeNetRequest:
                fields.insert("declarative_net_request")
            case .nativeMessaging:
                fields.insert("permissions.nativeMessaging")
            case .sidePanel:
                fields.insert(manifest.sidePanel == nil ? "permissions.sidePanel" : "side_panel")
            case .offscreen:
                fields.insert("permissions.offscreen")
            case .identity:
                fields.insert("permissions.identity")
            case .debugger:
                fields.insert("permissions.debugger")
            case .devtools:
                fields.insert("devtools_page")
            case .enterprise:
                fields.insert("permissions.enterprise")
            case .i18n:
                fields.insert("default_locale")
            case .notifications:
                fields.insert("permissions.notifications")
            case .downloads:
                fields.insert("permissions.downloads")
            case .bookmarks:
                fields.insert("permissions.bookmarks")
            case .history:
                fields.insert("permissions.history")
            }
        }
        return fields.sorted()
    }

    private func uniqueSorted(_ apis: [ChromeMV3API]) -> [ChromeMV3API] {
        var result: [ChromeMV3API] = []
        for api in apis.sorted() where result.contains(api) == false {
            result.append(api)
        }
        return result
    }
}
