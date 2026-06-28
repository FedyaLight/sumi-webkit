//
//  ExtensionRuntimeContextLoadOwner.swift
//  Sumi
//
//  Owns WebKit WebExtension object creation, context preparation, and
//  controller loading for install, enable, and lazy runtime paths.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeContextLoadOwner {
    enum Operation {
        case loadEnabled(expectedGeneration: UInt64)
        case install
        case safariEnable

        var expectedGeneration: UInt64? {
            switch self {
            case .loadEnabled(let expectedGeneration):
                return expectedGeneration
            case .install, .safariEnable:
                return nil
            }
        }

        var recordsRuntimeMetrics: Bool {
            switch self {
            case .loadEnabled:
                return true
            case .install, .safariEnable:
                return false
            }
        }

        var runtimeTraceOperation: String {
            switch self {
            case .loadEnabled:
                return "loadEnabledExtension"
            case .install:
                return "performInstallation"
            case .safariEnable:
                return "enableSafariAppExtension"
            }
        }

        var webExtensionCreatedPhase: String {
            switch self {
            case .loadEnabled:
                return "webExtensionCreated"
            case .install:
                return "installWebExtensionCreated"
            case .safariEnable:
                return "safariEnableWebExtensionCreated"
            }
        }

        var contextPreparedPhase: String {
            switch self {
            case .loadEnabled:
                return "contextPrepared"
            case .install:
                return "installContextPrepared"
            case .safariEnable:
                return "safariEnableContextPrepared"
            }
        }

        var beforeControllerLoadPhase: String {
            switch self {
            case .loadEnabled:
                return "beforeControllerLoad"
            case .install:
                return "installBeforeControllerLoad"
            case .safariEnable:
                return "safariEnableBeforeControllerLoad"
            }
        }

        var afterControllerLoadPhase: String {
            switch self {
            case .loadEnabled:
                return "afterControllerLoad"
            case .install:
                return "installAfterControllerLoad"
            case .safariEnable:
                return "safariEnableAfterControllerLoad"
            }
        }

        var beforeControllerLoadStorePhase: String {
            switch self {
            case .loadEnabled:
                return "before-loadEnabledExtension-controller-load"
            case .install:
                return "before-install-controller-load"
            case .safariEnable:
                return "before-safari-enable-controller-load"
            }
        }

        var emitsLoadedTrace: Bool {
            switch self {
            case .loadEnabled:
                return true
            case .install, .safariEnable:
                return false
            }
        }
    }

    struct Request {
        let extensionId: String
        let profileId: UUID
        let sourceKind: WebExtensionSourceKind
        let sourceBundlePath: String
        let packageRoot: URL
        let manifest: [String: Any]
        let operation: Operation
    }

    private let manager: ExtensionManager

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func load(_ request: Request) async throws -> WKWebExtensionContext {
        let extensionController = manager.ensureExtensionController(
            for: request.profileId
        )

        let webExtensionStart = CFAbsoluteTimeGetCurrent()
        let (webExtension, runtimeLoadSource) = try await cachedOrCreateWebExtension(
            extensionId: request.extensionId,
            sourceKind: request.sourceKind,
            sourceBundlePath: request.sourceBundlePath,
            packageRoot: request.packageRoot
        )
        manager.traceNativeMessagingContextBinding(
            phase: request.operation.webExtensionCreatedPhase,
            extensionId: request.extensionId,
            profileId: request.profileId,
            loadSource: runtimeLoadSource,
            webExtension: webExtension,
            controller: extensionController
        )
        manager.extensionRuntimeTrace(
            "\(request.operation.runtimeTraceOperation) webExtension source=\(runtimeLoadSource.rawValue) packagePath=\(request.packageRoot.path) sourceBundlePath=\(request.sourceBundlePath)"
        )
        if request.operation.recordsRuntimeMetrics {
            manager.recordRuntimeMetric(for: request.extensionId) {
                $0.webExtensionCreationDuration =
                    CFAbsoluteTimeGetCurrent() - webExtensionStart
            }
        }

        try manager.validateExpectedExtensionLoadGeneration(
            request.operation.expectedGeneration
        )

        let extensionContext = WKWebExtensionContext(for: webExtension)
        Self.configureContextIdentity(
            extensionContext,
            extensionId: request.extensionId,
            profileId: request.profileId
        )
        manager.grantRequestedPermissions(
            to: extensionContext,
            webExtension: webExtension,
            extensionId: request.extensionId,
            profileId: request.profileId,
            manifest: request.manifest
        )
        manager.applyConfiguredSiteAccessPolicy(
            to: extensionContext,
            extensionId: request.extensionId,
            profileId: request.profileId,
            webExtension: webExtension,
            manifest: request.manifest
        )
        manager.applyStoredExtensionPermissionDecisions(
            to: extensionContext,
            extensionId: request.extensionId,
            profileId: request.profileId
        )
        extensionContext.isInspectable =
            RuntimeDiagnostics.isDeveloperInspectionEnabled
        manager.observeExtensionErrors(
            for: extensionContext,
            extensionId: request.extensionId
        )
        manager.prepareExtensionContextForRuntime(
            extensionContext,
            extensionId: request.extensionId,
            profileId: request.profileId,
            manifest: request.manifest
        )
        manager.traceNativeMessagingContextBinding(
            phase: request.operation.contextPreparedPhase,
            extensionId: request.extensionId,
            profileId: request.profileId,
            loadSource: runtimeLoadSource,
            webExtension: webExtension,
            extensionContext: extensionContext,
            controller: extensionController
        )
        manager.ensureWebExtensionStorageDirectoryExists(
            for: request.extensionId,
            profileId: request.profileId
        )
        manager.traceWebExtensionStoreLifecycle(
            phase: request.operation.beforeControllerLoadStorePhase,
            extensionId: request.extensionId,
            manifest: request.manifest
        )

        manager.setExtensionContext(
            extensionContext,
            extensionId: request.extensionId,
            profileId: request.profileId
        )
        manager.loadedExtensionManifests[request.extensionId] = request.manifest
        manager.traceNativeMessagingContextBinding(
            phase: request.operation.beforeControllerLoadPhase,
            extensionId: request.extensionId,
            profileId: request.profileId,
            loadSource: runtimeLoadSource,
            webExtension: webExtension,
            extensionContext: extensionContext,
            controller: extensionController
        )

        do {
            #if DEBUG
                try manager.testHooks.beforeControllerLoad?(
                    request.extensionId,
                    manager.webExtensionStorageSnapshot(for: request.extensionId)
                )
            #endif
            try manager.validateExpectedExtensionLoadGeneration(
                request.operation.expectedGeneration
            )
            let contextLoadStart = CFAbsoluteTimeGetCurrent()
            try extensionController.load(extensionContext)
            if request.operation.recordsRuntimeMetrics {
                manager.recordRuntimeMetric(for: request.extensionId) {
                    $0.contextLoadDuration =
                        CFAbsoluteTimeGetCurrent() - contextLoadStart
                }
            }
            manager.traceNativeMessagingContextBinding(
                phase: request.operation.afterControllerLoadPhase,
                extensionId: request.extensionId,
                profileId: request.profileId,
                loadSource: runtimeLoadSource,
                webExtension: webExtension,
                extensionContext: extensionContext,
                controller: extensionController,
                configuration: extensionContext.webViewConfiguration
            )
        } catch {
            manager.tearDownExtensionRuntimeState(
                for: request.extensionId,
                removeUIState: false
            )
            throw error
        }

        if request.operation.emitsLoadedTrace {
            manager.extensionRuntimeTrace(
                "loadEnabledExtension loaded extensionId=\(request.extensionId) context=\(manager.extensionRuntimeObjectDescription(extensionContext)) controller=\(manager.extensionRuntimeControllerDescription(extensionController))"
            )
        }

        return extensionContext
    }

    private func cachedOrCreateWebExtension(
        extensionId: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL
    ) async throws -> (
        extension: WKWebExtension,
        loadSource: SafariAppExtensionRuntimeLoadSource
    ) {
        let runtimeSourceKind: WebExtensionSourceKind =
            sourceKind == .safariAppExtension
            && SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath
            ) == nil
            ? .directory
            : sourceKind
        let sourceKey = ExtensionManager.WebExtensionRuntimeSourceKey(
            sourceKind: runtimeSourceKind,
            sourceBundlePath: URL(
                fileURLWithPath: sourceBundlePath,
                isDirectory: true
            ).standardizedFileURL.path,
            packageRootPath: packageRoot.standardizedFileURL.path
        )
        if let cached = manager.cachedWebExtensionsByID[extensionId],
           manager.cachedWebExtensionRuntimeSourceKeysByID[extensionId] == sourceKey {
            let loadSource: SafariAppExtensionRuntimeLoadSource =
                runtimeSourceKind == .safariAppExtension
                    ? .originalAppexBundle
                    : .copiedPackage
            return (cached, loadSource)
        }

        let created = try await SafariAppExtensionResources.makeWebExtension(
            sourceKind: runtimeSourceKind,
            sourceBundlePath: sourceBundlePath,
            packageRoot: packageRoot
        )
        manager.cachedWebExtensionsByID[extensionId] = created.extension
        manager.cachedWebExtensionRuntimeSourceKeysByID[extensionId] = sourceKey
        return created
    }

    static func configureContextIdentity(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID
    ) {
        let scopedIdentifier = "\(profileId.uuidString):\(extensionId)"
        extensionContext.uniqueIdentifier = extensionId
        let host =
            "ext-"
            + scopedIdentifier.utf8.map { String(format: "%02x", $0) }.joined()
        if let baseURL = URL(
            string: "\(ExtensionManager.safariWebExtensionURLScheme)://\(host)"
        ) {
            extensionContext.baseURL = baseURL
        }
    }
}
