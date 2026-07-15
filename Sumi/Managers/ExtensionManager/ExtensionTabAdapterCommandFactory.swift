import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapterCommandFactory {
    private let windowQuery: any ExtensionWindowQuery
    private let tabMutation: any ExtensionTabMutation
    private let webViewHosting: any ExtensionTabWebViewHosting
    private let auxiliaryWindows: any ExtensionAuxiliaryWindowControl

    init(
        windowQuery: any ExtensionWindowQuery,
        tabMutation: any ExtensionTabMutation,
        webViewHosting: any ExtensionTabWebViewHosting,
        auxiliaryWindows: any ExtensionAuxiliaryWindowControl
    ) {
        self.windowQuery = windowQuery
        self.tabMutation = tabMutation
        self.webViewHosting = webViewHosting
        self.auxiliaryWindows = auxiliaryWindows
    }

    func make(
        evidence: ExtensionTabCurrentPublicationEvidence,
        projection: ExtensionTabReadProjection
    ) -> ExtensionTabCommandMutation {
        ExtensionTabCommandMutation(
            evidence: evidence,
            projection: projection,
            windowQuery: windowQuery,
            tabMutation: tabMutation,
            webViewHosting: webViewHosting,
            auxiliaryWindows: auxiliaryWindows
        )
    }
}
