import Foundation

/// Completes runtime-visible effects for one exact loaded context. Package
/// persistence and context loading remain outside this collaborator.
@available(macOS 15.5, *)
@MainActor
final class ExtensionLoadedContextFinalizer {
    enum Activation {
        case background(ExtensionManager.ExtensionBackgroundWakeReason?)
        case safariAppExtension

        var loadOperation: ExtensionContextLoadOperation {
            switch self {
            case .background:
                return .loadEnabled
            case .safariAppExtension:
                return .safariEnable
            }
        }
    }

    private let authority: ExtensionLoadedContextAuthority
    private let actionSurfaces: ExtensionActionSurfacePublisher
    private let retention: ExtensionContextRetentionOwner
    private let settlement: ExtensionContextSettlementOwner
    private let installationActivation: ExtensionInstallRuntimeActivator
    private let bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission?

    init(
        authority: ExtensionLoadedContextAuthority,
        actionSurfaces: ExtensionActionSurfacePublisher,
        retention: ExtensionContextRetentionOwner,
        settlement: ExtensionContextSettlementOwner,
        installationActivation: ExtensionInstallRuntimeActivator,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission? = nil
    ) {
        self.authority = authority
        self.actionSurfaces = actionSurfaces
        self.retention = retention
        self.settlement = settlement
        self.installationActivation = installationActivation
        self.bootstrapChromeAdmission = bootstrapChromeAdmission
    }

    func finalize(
        _ loadedContext: ExtensionLoadedContext,
        activation: Activation
    ) async throws {
        try authority.validate(loadedContext)
        defer {
            if let scope = loadedContext.bootstrapChromeScope {
                bootstrapChromeAdmission?.finish(scope)
            }
        }
        let key = loadedContext.bindingReceipt.key
        retention.retainActiveContext(
            extensionID: key.extensionId,
            profileID: key.profileId
        )
        try authority.validate(loadedContext)

        switch activation {
        case .background(let wakeReason):
            try await actionSurfaces.finalizeEnabledExtensionRuntime(
                loadedContext,
                backgroundWakeReason: wakeReason
            )
            try authority.validate(loadedContext)
        case .safariAppExtension:
            try await installationActivation.activate(
                .init(
                    loadedContext: loadedContext,
                    installedExtensionId: key.extensionId,
                    operation: .safariEnable
                )
            )
        }
        try authority.validate(loadedContext)
    }

    func settlePublication(
        _ loadedContext: ExtensionLoadedContext
    ) throws {
        try authority.validate(loadedContext)
        guard settlement.settle(loadedContext) else {
            throw CancellationError()
        }
    }
}
