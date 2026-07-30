import Foundation

/// Owns profile memory and post-install reconciliation. It cannot assemble or
/// publish an attachment, keeping profile transition policy separate from the
/// lifecycle state machine.
@available(macOS 15.5, *)
@MainActor
final class ExtensionBrowserAttachmentProfileCoordinator {
    private let profileRuntime: ExtensionProfileRuntime
    private let profileTransition: ExtensionProfileRuntimeTransition
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let browserEvents: ExtensionBrowserAttachmentAuthority.BrowserEvents

    init(
        profileRuntime: ExtensionProfileRuntime,
        profileTransition: ExtensionProfileRuntimeTransition,
        diagnostics: ExtensionRuntimeDiagnostics,
        browserEvents: ExtensionBrowserAttachmentAuthority.BrowserEvents
    ) {
        self.profileRuntime = profileRuntime
        self.profileTransition = profileTransition
        self.diagnostics = diagnostics
        self.browserEvents = browserEvents
    }

    func rememberProfiles(in bridge: BrowserExtensionBridgeComposition) {
        profileRuntime.bindBrowserProfileQuery(bridge.profiles)
        if let currentProfile = bridge.profiles.currentProfile() {
            profileRuntime.rememberProfile(currentProfile)
        }
        for window in bridge.windows.allExtensionWindowStates {
            if let profile = window.ephemeralProfile {
                profileRuntime.rememberProfile(profile)
            } else if let profileID = window.currentProfileId,
                      let profile = bridge.profiles.profile(profileID) {
                profileRuntime.rememberProfile(profile)
            }
        }
    }

    func settleInstalledAttachment(
        bridge: BrowserExtensionBridgeComposition,
        controllerRuntime: ExtensionControllerRuntimeComposition
    ) {
        var transitionReceipt: ExtensionProfileRuntimeTransition.Receipt?
        if bridge.windows.activeExtensionWindowState == nil,
           let currentProfile = bridge.profiles.currentProfile() {
            transitionReceipt = profileTransition.switchProfile(
                profileID: currentProfile.id
            )
        }
        guard let controller = profileRuntime.controllerForCurrentProfile()
        else { return }
        diagnostics.trace(
            "attach browserManager controller=\(ExtensionRuntimeDiagnostics.objectDescription(controller)) windows=\(bridge.windows.allExtensionWindowStates.count) tabs=\(bridge.tabs.allExtensionTabs.count)"
        )
        if let transitionReceipt {
            profileTransition.settleImmediately(transitionReceipt)
        } else if let profileID = profileRuntime.currentProfileId {
            controllerRuntime.reconciler.reconcile(
                profileID: profileID,
                reason: "ExtensionManager.attach"
            )
        }
        browserEvents.publishExistingWindows()
    }
}
