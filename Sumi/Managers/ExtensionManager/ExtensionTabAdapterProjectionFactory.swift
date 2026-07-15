import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapterProjectionFactory {
    private let windowQuery: any ExtensionWindowQuery
    private let tabQuery: any ExtensionTabQuery
    private let webViews: any ExtensionTabWebViewProjectionQuery
    private let auxiliaryWindows: any ExtensionAuxiliaryWindowControl
    private let windowPublications: ExtensionWindowPublicationQuery

    init(
        windowQuery: any ExtensionWindowQuery,
        tabQuery: any ExtensionTabQuery,
        webViews: any ExtensionTabWebViewProjectionQuery,
        auxiliaryWindows: any ExtensionAuxiliaryWindowControl,
        windowPublications: ExtensionWindowPublicationQuery
    ) {
        self.windowQuery = windowQuery
        self.tabQuery = tabQuery
        self.webViews = webViews
        self.auxiliaryWindows = auxiliaryWindows
        self.windowPublications = windowPublications
    }

    func make(
        evidence: ExtensionTabCurrentPublicationEvidence
    ) -> ExtensionTabReadProjection {
        ExtensionTabReadProjection(
            evidence: evidence,
            windowQuery: windowQuery,
            tabQuery: tabQuery,
            webViews: webViews,
            auxiliaryWindows: auxiliaryWindows,
            windowPublications: windowPublications
        )
    }
}
