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
        let runtime = lifetime.loadedCompatibilityDiagnosticsIfEnabled()
        let report = SafariExtensionCompatibilityReportBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: runtime?.installedExtensions ?? [],
            extensionsModuleEnabled: lifetime.isEnabled,
            runtime: runtime?.reportRuntime
        )
        SafariExtensionCompatibilityReportBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    func acceptanceMatrix() -> SafariExtensionAcceptanceMatrix {
        let discovered = scanAndRefreshCandidates()
        let runtime = lifetime.loadedCompatibilityDiagnosticsIfEnabled()
        let matrix = SafariExtensionAcceptanceMatrixBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: runtime?.installedExtensions ?? [],
            extensionsModuleEnabled: lifetime.isEnabled,
            runtime: runtime?.reportRuntime
        )
        SafariExtensionAcceptanceMatrixBuilder.logIfDiagnosticsEnabled(matrix)
        return matrix
    }

    func runtimeDiagnosticReport() -> SafariExtensionRuntimeDiagnosticReport {
        let discovered = scanAndRefreshCandidates()
        let runtime = lifetime.loadedCompatibilityDiagnosticsIfEnabled()
        let report = SafariExtensionRuntimeDiagnosticsBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: runtime?.installedExtensions ?? [],
            contentBlockerRecords: contentBlocking.installedContentBlockers(),
            attachedSafariContentRuleListIdentifiers: contentBlocking
                .attachedRuleListIdentifiers(),
            extensionsModuleEnabled: lifetime.isEnabled,
            runtime: runtime?.reportRuntime,
            adapterRegistry: runtime?.nativeMessagingAdapters ?? .production()
        )
        SafariExtensionRuntimeDiagnosticsBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    func nativeMessagingProbe() -> SafariExtensionNativeMessagingProbeReport {
        let discovered = scanAndRefreshCandidates()
        let runtime = lifetime.loadedCompatibilityDiagnosticsIfEnabled()
        let report = SafariExtensionNativeMessagingProbeBuilder.build(
            discovered: discovered,
            importStore: settingsCatalog.importRecordsForDiagnostics(),
            installedExtensions: runtime?.installedExtensions ?? [],
            extensionsModuleEnabled: lifetime.isEnabled,
            runtime: runtime?.reportRuntime,
            adapterRegistry: runtime?.nativeMessagingAdapters ?? .production()
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
