import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    /// Attaches the extension subsystem to one immutable browser-runtime graph.
    /// Repeated attachment to that same graph is idempotent; moving a manager
    /// between browser roots is rejected.
    func attach(browserManager: BrowserManager) {
        if let attachedBrowserManager {
            precondition(
                attachedBrowserManager === browserManager,
                "ExtensionManager cannot move between browser runtimes"
            )
            return
        }
        precondition(
            controllerRuntimeComposition == nil,
            "ExtensionManager supports one browser runtime attachment"
        )
        attachedBrowserManager = browserManager
        let bridge = browserManager.extensionBridgeComposition
        extensionWindowQuery = bridge.windows
        extensionTabQuery = bridge.tabs
        controllerRuntimeComposition = ExtensionControllerRuntimeAssembler
            .assemble(
                tabs: bridge.tabs,
                inventory: bridge.tabs,
                selectedWebViews: bridge.webViews,
                residences: bridge.webViews,
                rebuilder: bridge.webViews,
                windowProfiles: bridge.windows,
                runtimeSession: runtimeSession,
                profileRuntime: profileRuntime,
                contexts: contextPublications,
                preludeInstaller:
                    permissionsOriginsCompatibilityPreludeInstallationOwner,
                diagnostics: runtimeDiagnostics
            )
        requestedTabTargetQuery = bridge.requestedTabTargets
        extensionTabMutation = bridge.tabMutation
        extensionWindowActivation = bridge.windowActivation
        extensionWebViewHosting = bridge.webViews
        extensionAuxiliaryWindows = bridge.auxiliaryWindows
        extensionWindowPresentation = bridge.presentation
        extensionRequestedWindowCreation = bridge.requestedWindows
        runtime = BrowserExtensionManagerRuntimeFactory.runtime(for: browserManager)
        var transitionReceipt: ExtensionProfileRuntimeTransition.Receipt?
        if runtime.activeWindowState() == nil,
           let currentProfile = runtime.currentProfile() {
            transitionReceipt = profileRuntimeTransition.switchProfile(
                profileID: currentProfile.id
            )
        }

        if let controller = extensionController {
            runtimeDiagnostics.trace(
                "attach browserManager controller=\(ExtensionRuntimeDiagnostics.objectDescription(controller)) windows=\(runtime.allWindowStates().count) tabs=\(runtime.allTabs().count)"
            )
            if let transitionReceipt {
                profileRuntimeTransition.settleImmediately(transitionReceipt)
            } else if let profileId = profileRuntime.currentProfileId {
                profileWebViewRuntimeReconciler.reconcile(
                    profileID: profileId,
                    reason: "ExtensionManager.attach"
                )
            }
            publishExistingRuntimeWindowsIfAttached()
        }
    }
}
