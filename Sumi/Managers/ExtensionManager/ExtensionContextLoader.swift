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
        @MainActor (UUID) async -> Bool
    private let sourceCache: WebExtensionRuntimeSourceCache
    private let contextPreparation: ExtensionContextPreparation
    private let storagePlanner: WebExtensionStorageCleanupPlanner
    private let runtimeMetrics: ExtensionRuntimeMetricsAuthority
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let expectedControllerDelegate: ExtensionControllerDelegateBridge
    private let controllerTransaction: ExtensionContextControllerTransaction
    private let bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission

    init(
        authority: ExtensionLoadedContextAuthority,
        profileRuntime: ExtensionProfileRuntime,
        controllerProvisioning:
            any ExtensionWebViewConfigurationProvisioning,
        waitForWebsiteDataMutationAdmission:
            @escaping @MainActor (UUID) async -> Bool,
        sourceCache: WebExtensionRuntimeSourceCache,
        contextPreparation: ExtensionContextPreparation,
        storagePlanner: WebExtensionStorageCleanupPlanner,
        runtimeMetrics: ExtensionRuntimeMetricsAuthority,
        diagnostics: ExtensionRuntimeDiagnostics,
        expectedControllerDelegate: ExtensionControllerDelegateBridge,
        controllerTransaction: ExtensionContextControllerTransaction,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission =
            ExtensionBootstrapChromeAdmission()
    ) {
        self.authority = authority
        self.profileRuntime = profileRuntime
        self.controllerProvisioning = controllerProvisioning
        self.waitForWebsiteDataMutationAdmission =
            waitForWebsiteDataMutationAdmission
        self.sourceCache = sourceCache
        self.contextPreparation = contextPreparation
        self.storagePlanner = storagePlanner
        self.runtimeMetrics = runtimeMetrics
        self.diagnostics = diagnostics
        self.expectedControllerDelegate = expectedControllerDelegate
        self.controllerTransaction = controllerTransaction
        self.bootstrapChromeAdmission = bootstrapChromeAdmission
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
        guard let profileAdmission = profileRuntime.admitProfileReference(
            to: request.profileId
        ) else { throw CancellationError() }
        try validate(request, profileAdmission: profileAdmission)
        guard await waitForWebsiteDataMutationAdmission(request.profileId) else {
            throw CancellationError()
        }
        try validate(request, profileAdmission: profileAdmission)

        guard let controller = controllerProvisioning.controllerIfAdmitted(
            for: request.profileId,
            mutationLease: nil
        ) else { throw CancellationError() }
        guard let controllerBinding = profileRuntime.controllerBindingSnapshot(
            for: request.profileId
        ), controllerBinding.controller === controller else {
            throw CancellationError()
        }
        try validateController(
            controllerBinding,
            request: request,
            profileAdmission: profileAdmission
        )

        let activationScope = bootstrapChromeAdmission.begin(
            extensionIdentity: request.extensionId,
            version: request.manifest["version"] as? String ?? "0",
            profileID: request.profileId,
            cause: request.activationCause
        )
        diagnostics.trace(
            "\(request.operation.runtimeTraceOperation) activationCause=\(activationScope.cause.rawValue) globalBootstrapChromeAdmitted=\(activationScope.admitsBootstrapChrome)"
        )
        var didPublishLoadedContext = false
        defer {
            if didPublishLoadedContext == false {
                bootstrapChromeAdmission.finish(activationScope)
            }
        }

        let webExtensionStart = CFAbsoluteTimeGetCurrent()
        let source = try await sourceCache.resolve(
            extensionID: request.extensionId,
            sourceKind: request.sourceKind,
            sourceBundlePath: request.sourceBundlePath,
            packageRoot: request.packageRoot,
            claim: request.claim,
            mutationLease: request.mutationLease
        )
        try validateController(
            controllerBinding,
            request: request,
            profileAdmission: profileAdmission
        )
        guard await waitForWebsiteDataMutationAdmission(request.profileId) else {
            throw CancellationError()
        }
        try validateController(
            controllerBinding,
            request: request,
            profileAdmission: profileAdmission
        )

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
            runtimeMetrics.recordWebExtensionCreationDuration(
                CFAbsoluteTimeGetCurrent() - webExtensionStart,
                for: request.extensionId
            )
        }

        let prepared = contextPreparation.prepare(
            webExtension: source.webExtension,
            request: request
        )
        try validateController(
            controllerBinding,
            request: request,
            profileAdmission: profileAdmission
        )
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
        try validateController(
            controllerBinding,
            request: request,
            profileAdmission: profileAdmission
        )
        storage.prepare()
        storage.traceLifecycle(
            phase: request.operation.beforeControllerLoadStorePhase,
            capabilitySnapshot: storagePlanner.storeCapabilitySnapshot(
                for: request.manifest,
                unsupportedAPIs: prepared.context.unsupportedAPIs
            ),
            diagnostics: diagnostics
        )
        try validateController(
            controllerBinding,
            request: request,
            profileAdmission: profileAdmission
        )

        let loaded = try controllerTransaction.load(
            context: prepared.context,
            webExtension: source.webExtension,
            loadSource: source.loadSource,
            controllerBinding: controllerBinding,
            storage: storage,
            request: request,
            profileAdmission: profileAdmission
        )
        if request.operation.emitsLoadedTrace {
            diagnostics.trace(
                "loadEnabledExtension loaded extensionId=\(request.extensionId) context=\(ExtensionRuntimeDiagnostics.objectDescription(loaded.context)) controller=\(ExtensionRuntimeDiagnostics.objectDescription(loaded.controller))"
            )
        }
        // Keep the causal bootstrap gate with the loaded context. A secondary
        // profile leaves bootstrap only after an actual extension user gesture;
        // exact context retirement clears the remaining scope.
        didPublishLoadedContext = true
        return loaded
    }

    private func validate(_ request: ExtensionContextLoadRequest) throws {
        try authority.validate(
            request.claim,
            mutationLease: request.mutationLease
        )
    }

    private func validate(
        _ request: ExtensionContextLoadRequest,
        profileAdmission: ProfileReferenceAdmissionReceipt
    ) throws {
        try validate(request)
        guard profileAdmission.profileID == request.profileId,
              profileRuntime.validateProfileReference(profileAdmission)
        else { throw CancellationError() }
    }

    private func validateController(
        _ snapshot: ExtensionControllerBindingSnapshot,
        request: ExtensionContextLoadRequest,
        profileAdmission: ProfileReferenceAdmissionReceipt
    ) throws {
        try validate(request, profileAdmission: profileAdmission)
        guard snapshot.profileID == request.claim.key.profileId,
              profileRuntime.isCurrent(snapshot)
        else {
            throw CancellationError()
        }
    }
}
