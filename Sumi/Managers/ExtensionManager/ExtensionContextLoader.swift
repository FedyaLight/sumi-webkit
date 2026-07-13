import Foundation
import WebKit

/// Orchestrates source resolution and immutable context/storage preparation,
/// then delegates the only structural mutation to the controller transaction.
@available(macOS 15.5, *)
@MainActor
final class ExtensionContextLoader {
    private let authority: ExtensionLoadedContextAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let controllerProvisioning:
        any ExtensionWebViewConfigurationProvisioning
    private let waitForWebsiteDataMutationAdmission:
        ExtensionManagerRuntime.WebsiteDataMutationAdmissionWaiter
    private let sourceCache: WebExtensionRuntimeSourceCache
    private let contextPreparation: ExtensionContextPreparation
    private let storagePlanner: WebExtensionStorageCleanupPlanner
    private let runtimeSession: ExtensionRuntimeSession
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let expectedControllerDelegate: ExtensionControllerDelegateBridge
    private let controllerTransaction: ExtensionContextControllerTransaction

    init(
        authority: ExtensionLoadedContextAuthority,
        profileRuntime: ExtensionProfileRuntime,
        controllerProvisioning:
            any ExtensionWebViewConfigurationProvisioning,
        waitForWebsiteDataMutationAdmission:
            @escaping ExtensionManagerRuntime.WebsiteDataMutationAdmissionWaiter,
        sourceCache: WebExtensionRuntimeSourceCache,
        contextPreparation: ExtensionContextPreparation,
        storagePlanner: WebExtensionStorageCleanupPlanner,
        runtimeSession: ExtensionRuntimeSession,
        diagnostics: ExtensionRuntimeDiagnostics,
        expectedControllerDelegate: ExtensionControllerDelegateBridge,
        controllerTransaction: ExtensionContextControllerTransaction
    ) {
        self.authority = authority
        self.profileRuntime = profileRuntime
        self.controllerProvisioning = controllerProvisioning
        self.waitForWebsiteDataMutationAdmission =
            waitForWebsiteDataMutationAdmission
        self.sourceCache = sourceCache
        self.contextPreparation = contextPreparation
        self.storagePlanner = storagePlanner
        self.runtimeSession = runtimeSession
        self.diagnostics = diagnostics
        self.expectedControllerDelegate = expectedControllerDelegate
        self.controllerTransaction = controllerTransaction
    }

    func load(
        _ request: ExtensionContextLoadRequest
    ) async throws -> ExtensionLoadedContext {
        guard request.claim.key == .init(
            profileId: request.profileId,
            extensionId: request.extensionId
        ) else {
            throw CancellationError()
        }
        try validate(request)
        guard await waitForWebsiteDataMutationAdmission(request.profileId) else {
            throw CancellationError()
        }
        try validate(request)

        let controller = controllerProvisioning.ensureExtensionController(
            for: request.profileId
        )
        guard let controllerBinding = profileRuntime.controllerBindingSnapshot(
            for: request.profileId
        ), controllerBinding.controller === controller else {
            throw CancellationError()
        }
        try validateController(controllerBinding, request: request)

        let webExtensionStart = CFAbsoluteTimeGetCurrent()
        let source = try await sourceCache.resolve(
            extensionID: request.extensionId,
            sourceKind: request.sourceKind,
            sourceBundlePath: request.sourceBundlePath,
            packageRoot: request.packageRoot,
            claim: request.claim,
            mutationLease: request.mutationLease
        )
        try validateController(controllerBinding, request: request)
        guard await waitForWebsiteDataMutationAdmission(request.profileId) else {
            throw CancellationError()
        }
        try validateController(controllerBinding, request: request)

        diagnostics.traceNativeMessagingContextBinding(
            phase: request.operation.webExtensionCreatedPhase,
            extensionId: request.extensionId,
            profileId: request.profileId,
            loadSource: source.loadSource,
            webExtension: source.webExtension,
            controller: controller,
            profileController: controllerBinding.controller,
            expectedControllerDelegate: expectedControllerDelegate
        )
        diagnostics.trace(
            "\(request.operation.runtimeTraceOperation) webExtension source=\(source.loadSource.rawValue) packagePath=\(request.packageRoot.path) sourceBundlePath=\(request.sourceBundlePath)"
        )
        if request.operation.recordsRuntimeMetrics {
            runtimeSession.recordRuntimeMetric(for: request.extensionId) {
                $0.webExtensionCreationDuration =
                    CFAbsoluteTimeGetCurrent() - webExtensionStart
            }
        }

        let prepared = contextPreparation.prepare(
            webExtension: source.webExtension,
            request: request
        )
        try validateController(controllerBinding, request: request)
        diagnostics.traceNativeMessagingContextBinding(
            phase: request.operation.contextPreparedPhase,
            extensionId: request.extensionId,
            profileId: request.profileId,
            loadSource: source.loadSource,
            webExtension: source.webExtension,
            extensionContext: prepared.context,
            controller: controller,
            profileController: controllerBinding.controller,
            expectedControllerDelegate: expectedControllerDelegate
        )
        let storage = WebExtensionRuntimeStoragePreparation(
            extensionID: request.extensionId,
            runtimeIdentifier: prepared.runtimeIdentifier,
            controller: controller,
            planner: storagePlanner
        )
        try validateController(controllerBinding, request: request)
        storage.prepare()
        storage.traceLifecycle(
            phase: request.operation.beforeControllerLoadStorePhase,
            capabilitySnapshot: storagePlanner.storeCapabilitySnapshot(
                for: request.manifest,
                unsupportedAPIs: prepared.context.unsupportedAPIs
            ),
            diagnostics: diagnostics
        )
        try validateController(controllerBinding, request: request)

        let loaded = try controllerTransaction.load(
            context: prepared.context,
            webExtension: source.webExtension,
            loadSource: source.loadSource,
            controllerBinding: controllerBinding,
            storage: storage,
            request: request
        )
        if request.operation.emitsLoadedTrace {
            diagnostics.trace(
                "loadEnabledExtension loaded extensionId=\(request.extensionId) context=\(ExtensionRuntimeDiagnostics.objectDescription(loaded.context)) controller=\(ExtensionRuntimeDiagnostics.objectDescription(loaded.controller))"
            )
        }
        return loaded
    }

    private func validate(_ request: ExtensionContextLoadRequest) throws {
        try authority.validate(
            request.claim,
            mutationLease: request.mutationLease
        )
    }

    private func validateController(
        _ snapshot: ExtensionControllerBindingSnapshot,
        request: ExtensionContextLoadRequest
    ) throws {
        try validate(request)
        guard snapshot.profileID == request.claim.key.profileId,
              profileRuntime.isCurrent(snapshot)
        else {
            throw CancellationError()
        }
    }
}
