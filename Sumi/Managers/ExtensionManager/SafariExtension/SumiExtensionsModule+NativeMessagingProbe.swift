//
//  SumiExtensionsModule+NativeMessagingProbe.swift
//  Sumi
//
//  SumiExtensionsModule adapter for the native-messaging diagnostic probe.
//

import Foundation

@MainActor
extension SumiExtensionsModule {
    func safariExtensionNativeMessagingProbe() -> SafariExtensionNativeMessagingProbeReport {
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
        SafariExtensionImportStore.shared.refreshDiscoveredCandidates(
            discovered.filter { $0.bundleKind == .webExtension }
        )

        let manager = managerIfLoadedAndEnabled()
        let report = SafariExtensionNativeMessagingProbeBuilder.build(
            discovered: discovered,
            installedExtensions: manager?.installedExtensions ?? [],
            extensionManager: manager,
            extensionsModuleEnabled: isEnabled
        )
        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    #if DEBUG
    func printSafariExtensionNativeMessagingProbeToConsole() {
        guard isEnabled else {
            print("SafariExtensionNativeMessagingProbe: skipped — Extensions module is disabled")
            return
        }

        let report = safariExtensionNativeMessagingProbe()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8)
        else {
            print("SafariExtensionNativeMessagingProbe: encode failed")
            return
        }

        print("SafariExtensionNativeMessagingProbe:\n\(json)")
        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
    }
    #endif
}
