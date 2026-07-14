import Foundation

/// Compatibility and diagnostic reporting for extensions. Scanning is
/// demand-driven; constructing the module does not start filesystem work.
@MainActor
final class SumiExtensionCompatibilityDiagnosticsSurface {
    private let lifetime: SumiExtensionManagerLifetime
    private let settingsCatalog: SumiExtensionSettingsCatalogSurface
    private let contentBlocking: SumiExtensionContentBlockingSurface

    init(
        lifetime: SumiExtensionManagerLifetime,
        settingsCatalog: SumiExtensionSettingsCatalogSurface,
        contentBlocking: SumiExtensionContentBlockingSurface
    ) {
        self.lifetime = lifetime
        self.settingsCatalog = settingsCatalog
        self.contentBlocking = contentBlocking
    }

    func compatibilityReport() -> SafariExtensionCompatibilityReport {
        let discovered = scanAndRefreshCandidates()
        let manager = lifetime.loadedManagerIfEnabled()
        let report = SafariExtensionCompatibilityReportBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: manager?.installedExtensionCollection.records ?? [],
            extensionManager: manager,
            extensionsModuleEnabled: lifetime.isEnabled,
            runtime: .make(extensionManager: manager)
        )
        SafariExtensionCompatibilityReportBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    func acceptanceMatrix() -> SafariExtensionAcceptanceMatrix {
        let discovered = scanAndRefreshCandidates()
        let manager = lifetime.loadedManagerIfEnabled()
        let matrix = SafariExtensionAcceptanceMatrixBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: manager?.installedExtensionCollection.records ?? [],
            extensionManager: manager,
            extensionsModuleEnabled: lifetime.isEnabled
        )
        SafariExtensionAcceptanceMatrixBuilder.logIfDiagnosticsEnabled(matrix)
        return matrix
    }

    func runtimeDiagnosticReport() -> SafariExtensionRuntimeDiagnosticReport {
        let discovered = scanAndRefreshCandidates()
        let manager = lifetime.loadedManagerIfEnabled()
        let adapterRegistry =
            manager?.loadedNativeMessagingRelayOwner?.loadedRelay?.diagnosticsAdapterRegistry
            ?? SumiNativeMessagingAdapterRegistry.production()
        let report = SafariExtensionRuntimeDiagnosticsBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: manager?.installedExtensionCollection.records ?? [],
            contentBlockerRecords: contentBlocking.installedContentBlockers(),
            attachedSafariContentRuleListIdentifiers: contentBlocking
                .attachedRuleListIdentifiers(),
            extensionManager: manager,
            extensionsModuleEnabled: lifetime.isEnabled,
            adapterRegistry: adapterRegistry
        )
        SafariExtensionRuntimeDiagnosticsBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    func nativeMessagingProbe() -> SafariExtensionNativeMessagingProbeReport {
        let discovered = scanAndRefreshCandidates()
        let manager = lifetime.loadedManagerIfEnabled()
        let adapterRegistry =
            manager?.loadedNativeMessagingRelayOwner?.loadedRelay?.diagnosticsAdapterRegistry
            ?? SumiNativeMessagingAdapterRegistry.production()
        let report = SafariExtensionNativeMessagingProbeBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: manager?.installedExtensionCollection.records ?? [],
            extensionManager: manager,
            extensionsModuleEnabled: lifetime.isEnabled,
            adapterRegistry: adapterRegistry
        )
        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    private func scanAndRefreshCandidates() -> [DiscoveredSafariExtensionCandidate] {
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
        settingsCatalog.refreshDiscoveredSafariWebExtensionCandidates(discovered)
        return discovered
    }
}
