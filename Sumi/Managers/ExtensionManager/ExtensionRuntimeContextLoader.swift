//
//  ExtensionRuntimeContextLoader.swift
//  Sumi
//
//  Creates WebKit WebExtension objects, prepares contexts, and performs
//  controller loading for install, enable, and lazy runtime paths.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeContextLoader {
    struct LoadedContext {
        let context: WKWebExtensionContext
        let controller: WKWebExtensionController
        let bindingReceipt: ExtensionContextBindingReceipt
        let loadClaim: ExtensionContextLoadClaim
        let mutationLease: ExtensionRuntimeMutationLease?
    }

    enum Operation {
        case loadEnabled
        case install
        case safariEnable

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
        let claim: ExtensionContextLoadClaim
        let mutationLease: ExtensionRuntimeMutationLease?
    }

    private let manager: ExtensionManager

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func load(_ request: Request) async throws -> LoadedContext {
        guard request.claim.key == .init(
            profileId: request.profileId,
            extensionId: request.extensionId
        ) else {
            throw CancellationError()
        }
        try manager.loadedContextAuthority.validate(
            request.claim,
            mutationLease: request.mutationLease
        )
        guard await manager.runtime.waitForWebsiteDataMutationAdmission(
            request.profileId
        ) else {
            throw CancellationError()
        }
        try validate(request.claim, mutationLease: request.mutationLease)
        let extensionController = manager.ensureExtensionController(
            for: request.profileId
        )
        let controllerRevision = manager.profileRuntime
            .controllerBindingRevision(for: request.profileId)
        try validateController(
            extensionController,
            revision: controllerRevision,
            request: request
        )

        let webExtensionStart = CFAbsoluteTimeGetCurrent()
        let (webExtension, runtimeLoadSource) = try await cachedOrCreateWebExtension(
            extensionId: request.extensionId,
            sourceKind: request.sourceKind,
            sourceBundlePath: request.sourceBundlePath,
            packageRoot: request.packageRoot,
            request: request
        )
        try validateController(
            extensionController,
            revision: controllerRevision,
            request: request
        )
        // WebExtension creation may suspend. Re-enter the same admission
        // barrier before any context is attached to the profile data store.
        guard await manager.runtime.waitForWebsiteDataMutationAdmission(
            request.profileId
        ) else {
            throw CancellationError()
        }
        try validateController(
            extensionController,
            revision: controllerRevision,
            request: request
        )
        manager.runtimeDiagnostics.traceNativeMessagingContextBinding(
            phase: request.operation.webExtensionCreatedPhase,
            extensionId: request.extensionId,
            profileId: request.profileId,
            loadSource: runtimeLoadSource,
            webExtension: webExtension,
            controller: extensionController,
            manager: manager
        )
        manager.runtimeDiagnostics.trace(
            "\(request.operation.runtimeTraceOperation) webExtension source=\(runtimeLoadSource.rawValue) packagePath=\(request.packageRoot.path) sourceBundlePath=\(request.sourceBundlePath)"
        )
        if request.operation.recordsRuntimeMetrics {
            manager.runtimeSession.recordRuntimeMetric(for: request.extensionId) {
                $0.webExtensionCreationDuration =
                    CFAbsoluteTimeGetCurrent() - webExtensionStart
            }
        }

        let extensionContext = WKWebExtensionContext(for: webExtension)
        Self.configureContextIdentity(
            extensionContext,
            extensionId: request.extensionId,
            profileId: request.profileId,
            sourceKind: request.sourceKind,
            sourceBundlePath: request.sourceBundlePath
        )
        manager.grantRequestedPermissions(
            to: extensionContext,
            webExtension: webExtension,
            extensionId: request.extensionId,
            profileId: request.profileId,
            manifest: request.manifest
        )
        if request.sourceKind == .safariAppExtension {
            manager.seedSafariAppExtensionDefaultAccessIfNeeded(
                extensionId: request.extensionId,
                profileId: request.profileId
            )
        }
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
        manager.prepareExtensionContextForRuntime(
            extensionContext,
            extensionId: request.extensionId,
            profileId: request.profileId,
            manifest: request.manifest
        )
        manager.runtimeDiagnostics.traceNativeMessagingContextBinding(
            phase: request.operation.contextPreparedPhase,
            extensionId: request.extensionId,
            profileId: request.profileId,
            loadSource: runtimeLoadSource,
            webExtension: webExtension,
            extensionContext: extensionContext,
            controller: extensionController,
            manager: manager
        )
        manager.adoptLegacyWebExtensionStorageIfNeeded(
            for: request.extensionId,
            profileId: request.profileId,
            sourceKind: request.sourceKind,
            sourceBundlePath: request.sourceBundlePath
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
        try validateController(
            extensionController,
            revision: controllerRevision,
            request: request
        )

        var bindingReceipt: ExtensionContextBindingReceipt?
        do {
            manager.setExtensionContext(
                extensionContext,
                extensionId: request.extensionId,
                profileId: request.profileId
            )
            let receipt = try requireBindingReceipt(
                extensionContext,
                controller: extensionController,
                request: request
            )
            bindingReceipt = receipt
            manager.observeExtensionErrors(
                for: extensionContext,
                extensionId: request.extensionId,
                profileId: request.profileId
            )
            manager.runtimeDiagnostics.traceNativeMessagingContextBinding(
                phase: request.operation.beforeControllerLoadPhase,
                extensionId: request.extensionId,
                profileId: request.profileId,
                loadSource: runtimeLoadSource,
                webExtension: webExtension,
                extensionContext: extensionContext,
                controller: extensionController,
                manager: manager
            )
            #if DEBUG
                try manager.testHooks.beforeControllerLoad?(
                    request.extensionId,
                    manager.webExtensionStorageSnapshot(for: request.extensionId)
                )
            #endif
            try validateBoundContext(
                receipt,
                context: extensionContext,
                controller: extensionController,
                request: request
            )
            let contextLoadStart = CFAbsoluteTimeGetCurrent()
            try extensionController.load(extensionContext)
            try validateBoundContext(
                receipt,
                context: extensionContext,
                controller: extensionController,
                request: request
            )
            if request.operation.recordsRuntimeMetrics {
                manager.runtimeSession.recordRuntimeMetric(for: request.extensionId) {
                    $0.contextLoadDuration =
                        CFAbsoluteTimeGetCurrent() - contextLoadStart
                }
            }
            manager.runtimeDiagnostics.traceNativeMessagingContextBinding(
                phase: request.operation.afterControllerLoadPhase,
                extensionId: request.extensionId,
                profileId: request.profileId,
                loadSource: runtimeLoadSource,
                webExtension: webExtension,
                extensionContext: extensionContext,
                controller: extensionController,
                configuration: extensionContext.webViewConfiguration,
                    manager: manager
            )
        } catch {
            if let bindingReceipt {
                let rollback = manager.runtimeRollback.rollBack(
                    LoadedContext(
                        context: extensionContext,
                        controller: extensionController,
                        bindingReceipt: bindingReceipt,
                        loadClaim: request.claim,
                        mutationLease: request.mutationLease
                    )
                )
                if rollback.exactRollbackCompleted == false {
                    throw ExtensionRuntimeTransactionFailure(
                        operationError: error,
                        rollback: rollback
                    )
                }
            }
            throw error
        }

        if request.operation.emitsLoadedTrace {
            manager.runtimeDiagnostics.trace(
                "loadEnabledExtension loaded extensionId=\(request.extensionId) context=\(ExtensionRuntimeDiagnostics.objectDescription(extensionContext)) controller=\(ExtensionRuntimeDiagnostics.objectDescription(extensionController))"
            )
        }

        guard let bindingReceipt else {
            assertionFailure(
                "A successful WebExtension load must retain its binding receipt"
            )
            throw CancellationError()
        }
        return LoadedContext(
            context: extensionContext,
            controller: extensionController,
            bindingReceipt: bindingReceipt,
            loadClaim: request.claim,
            mutationLease: request.mutationLease
        )
    }

    private func cachedOrCreateWebExtension(
        extensionId: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL,
        request: Request
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
        try validate(request.claim, mutationLease: request.mutationLease)
        if let cached = manager.runtimeSession.cachedWebExtensionsByID[extensionId],
           manager.runtimeSession.cachedWebExtensionRuntimeSourceKeysByID[extensionId] == sourceKey {
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
        try validate(request.claim, mutationLease: request.mutationLease)
        manager.runtimeSession.cachedWebExtensionsByID[extensionId] = created.extension
        manager.runtimeSession.cachedWebExtensionRuntimeSourceKeysByID[extensionId] = sourceKey
        return created
    }

    private func validate(
        _ claim: ExtensionContextLoadClaim,
        mutationLease: ExtensionRuntimeMutationLease?
    ) throws {
        try manager.loadedContextAuthority.validate(
            claim,
            mutationLease: mutationLease
        )
    }

    private func validateController(
        _ controller: WKWebExtensionController,
        revision: UInt64,
        request: Request
    ) throws {
        try validate(
            request.claim,
            mutationLease: request.mutationLease
        )
        guard manager.profileRuntime.controller(for: request.claim.key.profileId)
                === controller,
              manager.profileRuntime.controllerBindingRevision(
                  for: request.claim.key.profileId
              ) == revision
        else {
            throw CancellationError()
        }
    }

    private func requireBindingReceipt(
        _ context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        request: Request
    ) throws -> ExtensionContextBindingReceipt {
        try validate(
            request.claim,
            mutationLease: request.mutationLease
        )
        guard let receipt = manager.profileRuntime.contextBindingReceipt(
            extensionId: request.claim.key.extensionId,
            profileId: request.claim.key.profileId
        ), manager.profileRuntime.context(ifCurrent: receipt) === context,
           manager.profileRuntime.controller(ifCurrent: receipt) === controller
        else {
            throw CancellationError()
        }
        return receipt
    }

    private func validateBoundContext(
        _ receipt: ExtensionContextBindingReceipt,
        context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        request: Request
    ) throws {
        try validate(
            request.claim,
            mutationLease: request.mutationLease
        )
        guard manager.profileRuntime.context(ifCurrent: receipt) === context,
              manager.profileRuntime.controller(ifCurrent: receipt)
                === controller
        else {
            throw CancellationError()
        }
    }

    static func configureContextIdentity(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        sourceKind: WebExtensionSourceKind = .directory,
        sourceBundlePath: String? = nil
    ) {
        let scopedIdentifier = "\(profileId.uuidString):\(extensionId)"
        // Safari exposes app extensions to web pages and to `browser.runtime.id`
        // as "<bundleId> (<teamId>)". Web apps (e.g. account.proton.me) message
        // this composed identifier via `externally_connectable`, so WebKit must
        // match it against `uniqueIdentifier` for delivery. Non-Safari sources
        // keep the internal extension id.
        extensionContext.uniqueIdentifier = safariRuntimeIdentifier(
            extensionId: extensionId,
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath
        )
        let host =
            "ext-"
            + scopedIdentifier.utf8.map { String(format: "%02x", $0) }.joined()
        if let baseURL = URL(
            string: "\(ExtensionManager.safariWebExtensionURLScheme)://\(host)"
        ) {
            extensionContext.baseURL = baseURL
        }
    }

    /// The identifier WebKit exposes as `browser.runtime.id` and matches for
    /// `externally_connectable` message routing. Safari app extensions use the
    /// composed "<bundleId> (<teamId>)" form; everything else uses the internal
    /// extension id.
    static func safariRuntimeIdentifier(
        extensionId: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String?
    ) -> String {
        SafariWebExtensionRuntimeIdentity.webKitStorageIdentifier(
            extensionId: extensionId,
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath
        )
    }
}
