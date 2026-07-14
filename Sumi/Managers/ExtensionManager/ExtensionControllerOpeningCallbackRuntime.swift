import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionRequestedTabCallbackPreloading {
    func prepare(
        load: ExtensionRequestedTabLoad,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?
    ) async throws -> UUID?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionRequestedTabCallbackOpening {
    func open(
        url: URL?,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext?,
        evidence: ExtensionControllerCallbackEvidence?,
        callbackAdmission: ExtensionControllerCallbackAdmission?,
        reason: String
    ) throws -> Tab
}

extension ExtensionRequestedTabContextPreloader:
    ExtensionRequestedTabCallbackPreloading {}

extension ExtensionRequestedTabOpeningService:
    ExtensionRequestedTabCallbackOpening {}

@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerTabOpeningCallbackRuntime {
    let admission: ExtensionControllerCallbackAdmission
    let loadResolver: ExtensionRequestedTabLoadResolver
    let contextPreloader: any ExtensionRequestedTabCallbackPreloading
    let tabOpening: any ExtensionRequestedTabCallbackOpening
    let adapterResolver: any ExtensionTabAdapterResolving
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerOpeningCallbackRuntime {
    let admission: ExtensionControllerCallbackAdmission
    let contextPreloader: ExtensionRequestedTabContextPreloader
    let tabOpening: ExtensionRequestedTabOpeningService
    let adapterResolver: any ExtensionTabAdapterResolving
    let windowRouter: ExtensionWindowRequestRouter
    let windowQuery: any ExtensionWindowQuery
    let windowPresentation: any ExtensionWindowPresentation
    let auxiliaryRuntime: ExtensionAuxiliaryWindowCallbackRuntime

    var tabOpeningCallback: ExtensionControllerTabOpeningCallbackRuntime {
        ExtensionControllerTabOpeningCallbackRuntime(
            admission: admission,
            loadResolver: auxiliaryRuntime.loadResolver,
            contextPreloader: contextPreloader,
            tabOpening: tabOpening,
            adapterResolver: adapterResolver
        )
    }
}
