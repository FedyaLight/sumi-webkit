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
    private let actionSurfaces: @MainActor () ->
        ExtensionActionSurfacePublisher?
    private let residency: ExtensionContextResidencyOwner
    private let installationActivation: ExtensionInstallRuntimeActivator

    init(
        authority: ExtensionLoadedContextAuthority,
        actionSurfaces: @escaping @MainActor () ->
            ExtensionActionSurfacePublisher?,
        residency: ExtensionContextResidencyOwner,
        installationActivation: ExtensionInstallRuntimeActivator
    ) {
        self.authority = authority
        self.actionSurfaces = actionSurfaces
        self.residency = residency
        self.installationActivation = installationActivation
    }

    func finalize(
        _ loadedContext: ExtensionLoadedContext,
        activation: Activation
    ) async throws {
        try authority.validate(loadedContext)
        let key = loadedContext.bindingReceipt.key
        residency.touchLiveExtensionContext(
            extensionId: key.extensionId,
            profileId: key.profileId
        )
        residency.enforceBoundedLiveExtensionContexts(
            keepingProfileId: key.profileId,
            keepingExtensionId: key.extensionId
        )
        try authority.validate(loadedContext)

        switch activation {
        case .background(let wakeReason):
            guard let actionSurfaces = actionSurfaces() else {
                throw CancellationError()
            }
            try await actionSurfaces.finalizeEnabledExtensionRuntime(
                loadedContext,
                backgroundWakeReason: wakeReason
            )
            try authority.validate(loadedContext)
            residency.markExtensionRuntimeReadyIfProfileContextsLoaded(
                for: key.profileId
            )
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
}
