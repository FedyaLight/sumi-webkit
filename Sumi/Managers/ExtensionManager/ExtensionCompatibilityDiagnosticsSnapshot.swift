import Foundation

/// Read-only, point-in-time inputs for the compatibility diagnostics surface.
/// The surface receives no manager, graph, or mutation-capable runtime role.
@available(macOS 15.5, *)
@MainActor
struct ExtensionCompatibilityDiagnosticsSnapshot {
    let installedExtensions: [InstalledExtension]
    let reportRuntime: SafariCompatibilityReportRuntime
    let nativeMessagingAdapters: SumiNativeMessagingAdapterRegistry
}

/// Terminal diagnostics query. Its exact snapshot closure cannot expose or
/// mutate any retained extension subsystem node.
@available(macOS 15.5, *)
@MainActor
struct ExtensionCompatibilityDiagnosticsSnapshotProvider {
    private let snapshotProvider:
        @MainActor () -> ExtensionCompatibilityDiagnosticsSnapshot

    init(
        snapshot: @escaping @MainActor () ->
            ExtensionCompatibilityDiagnosticsSnapshot
    ) {
        snapshotProvider = snapshot
    }

    func snapshot() -> ExtensionCompatibilityDiagnosticsSnapshot {
        snapshotProvider()
    }
}
