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
        compatibilityDiagnostics.nativeMessagingProbe()
    }

    #if DEBUG
    func printSafariExtensionNativeMessagingProbeToConsole() {
        guard isEnabled else {
            print("SafariExtensionNativeMessagingProbe: skipped — Extensions module is disabled")
            return
        }

        let report = safariExtensionNativeMessagingProbe()
        do {
            let json = try SafariExtensionDiagnosticJSON.prettyPrintedString(report)
            print("SafariExtensionNativeMessagingProbe:\n\(json)")
        } catch {
            print("SafariExtensionNativeMessagingProbe: encode failed: \(error.localizedDescription)")
        }

        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
    }
    #endif
}
