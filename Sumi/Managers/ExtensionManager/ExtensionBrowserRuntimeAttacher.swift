import Foundation
import OSLog

/// The only public command that can drive detached -> attached. Assembly,
/// delegate-route installation and profile settlement are independently
/// bounded; this coordinator owns only their ordering and admission policy.
@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserRuntimeAttacher {
    private let attachment: ExtensionBrowserAttachmentAuthority
    private let runtimeAssembler: ExtensionAttachedBrowserRuntimeAssembler
    private let routeInstaller: ExtensionControllerBrowserRouteInstaller
    private let profiles: ExtensionBrowserAttachmentProfileCoordinator

    init(
        attachment: ExtensionBrowserAttachmentAuthority,
        runtimeAssembler: ExtensionAttachedBrowserRuntimeAssembler,
        routeInstaller: ExtensionControllerBrowserRouteInstaller,
        profiles: ExtensionBrowserAttachmentProfileCoordinator
    ) {
        self.attachment = attachment
        self.runtimeAssembler = runtimeAssembler
        self.routeInstaller = routeInstaller
        self.profiles = profiles
    }

    func attach(browserManager: BrowserManager) {
        let browserIdentity = ObjectIdentifier(browserManager)
        switch attachment.admission(for: browserIdentity) {
        case .alreadyAttached:
            return
        case .rejectDifferentBrowser:
            ExtensionManager.logger.error(
                "Rejected ExtensionManager attachment to a second browser runtime"
            )
            return
        case .rejectRetired:
            ExtensionManager.logger.error(
                "Rejected ExtensionManager attachment after terminal retirement"
            )
            return
        case .install:
            break
        }

        let bridge = browserManager.extensionBridgeComposition
        profiles.rememberProfiles(in: bridge)
        let assembly = runtimeAssembler.assemble(
            browserIdentity: browserIdentity,
            bridge: bridge,
            browserRoutes: routeInstaller
        )
        guard routeInstaller.install(
            requestedTabs: assembly.requestedTabs,
            optionsComposer: assembly.optionsComposer
        ) else {
            ExtensionManager.logger.error(
                "Rejected ExtensionManager attachment after delegate routes were already installed"
            )
            return
        }
        guard attachment.install(
            assembly.runtime,
            browserIdentity: browserIdentity
        ) != nil else {
            ExtensionManager.logger.error(
                "Rejected ExtensionManager browser runtime publication after graph assembly"
            )
            return
        }
        profiles.settleInstalledAttachment(
            bridge: bridge,
            controllerRuntime: assembly.controller
        )
    }
}
