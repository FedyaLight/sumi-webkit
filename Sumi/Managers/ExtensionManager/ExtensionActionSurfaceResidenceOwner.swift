import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionSurfaceResidenceOwner {
    private let installedExtensions: InstalledExtensionCollection
    private let surfacePublication: ExtensionManagerSurfacePublication
    private let actionSurfacePublisher: ExtensionActionSurfacePublisher
    private let actionInvocation: ExtensionActionInvocationService

    init(
        installedExtensions: InstalledExtensionCollection,
        surfacePublication: ExtensionManagerSurfacePublication,
        actionSurfacePublisher: ExtensionActionSurfacePublisher,
        actionInvocation: ExtensionActionInvocationService
    ) {
        self.installedExtensions = installedExtensions
        self.surfacePublication = surfacePublication
        self.actionSurfacePublisher = actionSurfacePublisher
        self.actionInvocation = actionInvocation
    }
}
