import Foundation

/// Answers "is this profile's extension runtime ready" from the one place that
/// knows the enabled-extension demand. The profile transition consults it both
/// when activating a profile and again before publishing a controller, so the
/// two decisions cannot drift apart.
@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileReadinessProbe {
    private let installedExtensions: InstalledExtensionCollection
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority

    init(
        installedExtensions: InstalledExtensionCollection,
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    ) {
        self.installedExtensions = installedExtensions
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
    }

    var enabledExtensionIDs: Set<String> {
        Set(installedExtensions.records.lazy.filter(\.isEnabled).map(\.id))
    }

    func isProfileReady(
        _ profileID: UUID,
        enabledExtensionIDs: Set<String>
    ) -> Bool {
        profileRuntime.readinessContext(
            for: profileID,
            hasEnabledExtensionDemand: enabledExtensionIDs.isEmpty == false,
            enabledExtensionIDs: enabledExtensionIDs,
            globalRuntimeReady: runtimeLifecycle.isReady
        ).isProfileReady
    }
}
