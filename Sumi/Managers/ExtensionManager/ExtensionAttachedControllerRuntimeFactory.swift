import Foundation

/// Browser-bound controller projection factory. It consumes only the five
/// detached authorities required to derive exact controller/tab/WebView roles.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAttachedControllerRuntimeFactory {
    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let contexts: ExtensionContextPublicationQuery
    private let preludeInstaller:
        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        contexts: ExtensionContextPublicationQuery,
        preludeInstaller:
            ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimeLoadStatus = runtimeLoadStatus
        self.profileRuntime = profileRuntime
        self.contexts = contexts
        self.preludeInstaller = preludeInstaller
        self.diagnostics = diagnostics
    }

    func assemble(
        bridge: BrowserExtensionBridgeComposition
    ) -> ExtensionControllerRuntimeComposition {
        ExtensionControllerRuntimeAssembler.assemble(
            tabs: bridge.tabs,
            inventory: bridge.tabs,
            selectedWebViews: bridge.webViews,
            residences: bridge.webViews,
            rebuilder: bridge.webViews,
            windowProfiles: bridge.windows,
            runtimeLoadStatus: runtimeLoadStatus,
            profileRuntime: profileRuntime,
            contexts: contexts,
            preludeInstaller: preludeInstaller,
            diagnostics: diagnostics
        )
    }
}
