//
//  ExtensionLiveWebViewRuntimePreparation.swift
//  Sumi
//
//  Admits an already-created live WebView to the extension runtime and routes
//  controller mismatches through the normal repair/publication transaction.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionLiveWebViewRuntimePreparation:
    ExtensionLiveWebViewRuntimePreparing {
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var controllers: (any ExtensionTabControllerQuery)?
    private weak var admission: (any ExtensionWebViewControllerAdmitting)?
    private let tabRegistration: ExtensionNormalTabRegistration
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        profiles: any ExtensionTabProfileResolving,
        controllers: any ExtensionTabControllerQuery,
        admission: any ExtensionWebViewControllerAdmitting,
        tabRegistration: ExtensionNormalTabRegistration,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profiles = profiles
        self.controllers = controllers
        self.admission = admission
        self.tabRegistration = tabRegistration
        self.diagnostics = diagnostics
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        let existingController = webView.configuration.webExtensionController
        let owningTab = (webView as? FocusableWKWebView)?.owningTab
        let profileID = owningTab.flatMap { profiles?.profileID(for: $0) }
        let expectedController = owningTab.flatMap {
            controllers?.existingController(for: $0)
        }
        let admissionOutcome: ExtensionWebViewControllerAdmissionOutcome =
            if let owningTab, let profileID, let expectedController {
                admission?.admit(
                    expectedController,
                    profileID: profileID,
                    to: webView,
                    for: owningTab
                ) ?? .rejected
            } else {
                .rejected
            }

        if let owningTab,
           admissionOutcome == .requiresRebuild {
            tabRegistration.register(
                owningTab,
                reason: "prepareWebViewForExtensionRuntime.rebuild"
            )
        }

        diagnostics.trace(
            "prepareWebView reason=\(reason) webView=\(ExtensionRuntimeDiagnostics.objectDescription(webView)) configuration=\(ExtensionRuntimeDiagnostics.objectDescription(webView.configuration)) userContentController=\(ExtensionRuntimeDiagnostics.objectDescription(webView.configuration.userContentController)) currentURL=\(currentURL?.absoluteString ?? "nil") existingController=\(ExtensionRuntimeDiagnostics.objectDescription(existingController)) expectedController=\(ExtensionRuntimeDiagnostics.objectDescription(expectedController)) admission=\(String(describing: admissionOutcome))"
        )
    }
}
