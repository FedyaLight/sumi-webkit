import Foundation
import WebKit

/// Performs the atomic bind/load/compensate transaction for one prepared
/// WebExtension context. Every authority check uses the exact captured claim,
/// controller revision, and binding receipt.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextControllerTransaction {
    typealias BeforeControllerLoad = @MainActor (
        String,
        WebExtensionStorageCleanupPlanner.StorageSnapshot
    ) throws -> Void

    private let authority: ExtensionLoadedContextAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let rollback: ExtensionRuntimeRollback
    private let errorObservation: ExtensionContextErrorObservation
    private let runtimeMetrics: ExtensionRuntimeMetricsAuthority
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let expectedControllerDelegate: ExtensionControllerDelegateBridge
    private let controllerDelegateReadiness:
        ExtensionControllerDelegateReadiness
    #if DEBUG
        private var debugBeforeControllerLoad:
            (@MainActor () -> BeforeControllerLoad?)?
    #endif

    init(
        authority: ExtensionLoadedContextAuthority,
        profileRuntime: ExtensionProfileRuntime,
        rollback: ExtensionRuntimeRollback,
        errorObservation: ExtensionContextErrorObservation,
        runtimeMetrics: ExtensionRuntimeMetricsAuthority,
        diagnostics: ExtensionRuntimeDiagnostics,
        expectedControllerDelegate: ExtensionControllerDelegateBridge,
        controllerDelegateReadiness:
            ExtensionControllerDelegateReadiness
    ) {
        self.authority = authority
        self.profileRuntime = profileRuntime
        self.rollback = rollback
        self.errorObservation = errorObservation
        self.runtimeMetrics = runtimeMetrics
        self.diagnostics = diagnostics
        self.expectedControllerDelegate = expectedControllerDelegate
        self.controllerDelegateReadiness = controllerDelegateReadiness
    }

    #if DEBUG
        func installDebugBeforeControllerLoad(
            _ provider: @escaping @MainActor () -> BeforeControllerLoad?
        ) {
            debugBeforeControllerLoad = provider
        }
    #endif

    func load(
        context: WKWebExtensionContext,
        webExtension: WKWebExtension,
        loadSource: SafariAppExtensionRuntimeLoadSource,
        controllerBinding: ExtensionControllerBindingSnapshot,
        storage: WebExtensionRuntimeStoragePreparation,
        request: ExtensionContextLoadRequest
    ) throws -> ExtensionLoadedContext {
        try validateController(controllerBinding, request: request)
        let controller = controllerBinding.controller
        var bindingReceipt: ExtensionContextBindingReceipt?
        do {
            let receipt = profileRuntime.setContext(
                context,
                extensionId: request.extensionId,
                profileId: request.profileId
            )
            bindingReceipt = receipt
            diagnostics.trace(
                "contextBinding profile=\(request.profileId.uuidString) extensionId=\(request.extensionId) generation=\(profileRuntime.contextBindingGeneration(for: request.profileId))"
            )
            errorObservation.observe(
                context,
                extensionId: request.extensionId,
                profileId: request.profileId
            )
            diagnostics.traceNativeMessagingContextBinding(
                phase: request.operation.beforeControllerLoadPhase,
                extensionId: request.extensionId,
                profileId: request.profileId,
                loadSource: loadSource,
                webExtension: webExtension,
                extensionContext: context,
                controller: controller,
                profileController: controllerBinding.controller,
                expectedControllerDelegate: expectedControllerDelegate
            )
            #if DEBUG
                try debugBeforeControllerLoad?()?(
                    request.extensionId,
                    storage.snapshot()
                )
            #endif
            try validateBoundContext(
                receipt,
                context: context,
                controller: controller,
                request: request
            )
            let contextLoadStart = CFAbsoluteTimeGetCurrent()
            try controller.load(context)
            try validateBoundContext(
                receipt,
                context: context,
                controller: controller,
                request: request
            )
            controllerDelegateReadiness.controllerDidBecomeReady(
                controllerBinding
            )
            if request.operation.recordsRuntimeMetrics {
                runtimeMetrics.recordContextLoadDuration(
                    CFAbsoluteTimeGetCurrent() - contextLoadStart,
                    for: request.extensionId
                )
            }
            diagnostics.traceNativeMessagingContextBinding(
                phase: request.operation.afterControllerLoadPhase,
                extensionId: request.extensionId,
                profileId: request.profileId,
                loadSource: loadSource,
                webExtension: webExtension,
                extensionContext: context,
                controller: controller,
                configuration: context.webViewConfiguration,
                profileController: controllerBinding.controller,
                expectedControllerDelegate: expectedControllerDelegate
            )
        } catch {
            if let bindingReceipt {
                let rollbackResult = rollback.rollBack(
                    ExtensionLoadedContext(
                        context: context,
                        controller: controller,
                        bindingReceipt: bindingReceipt,
                        loadClaim: request.claim,
                        mutationLease: request.mutationLease
                    )
                )
                if rollbackResult.externalStateDisposition != .rollbackAllowed {
                    throw ExtensionRuntimeTransactionFailure(
                        operationError: error,
                        rollback: rollbackResult
                    )
                }
            }
            throw error
        }

        guard let bindingReceipt else {
            assertionFailure(
                "A successful WebExtension load must retain its binding receipt"
            )
            throw CancellationError()
        }
        return ExtensionLoadedContext(
            context: context,
            controller: controller,
            bindingReceipt: bindingReceipt,
            loadClaim: request.claim,
            mutationLease: request.mutationLease
        )
    }

    private func validateController(
        _ snapshot: ExtensionControllerBindingSnapshot,
        request: ExtensionContextLoadRequest
    ) throws {
        try authority.validate(
            request.claim,
            mutationLease: request.mutationLease
        )
        guard snapshot.profileID == request.claim.key.profileId,
              profileRuntime.isCurrent(snapshot)
        else {
            throw CancellationError()
        }
    }

    private func validateBoundContext(
        _ receipt: ExtensionContextBindingReceipt,
        context: WKWebExtensionContext,
        controller: WKWebExtensionController,
        request: ExtensionContextLoadRequest
    ) throws {
        try authority.validate(
            request.claim,
            mutationLease: request.mutationLease
        )
        guard profileRuntime.context(ifCurrent: receipt) === context,
              profileRuntime.controller(ifCurrent: receipt) === controller
        else {
            throw CancellationError()
        }
    }
}
