import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabRuntimeAdmission {
    private let registrar: ExtensionCreatedTabRuntimeRegistrar

    init(registrar: ExtensionCreatedTabRuntimeRegistrar) {
        self.registrar = registrar
    }

    /// An ordinary web URL remains a browser Tab when extension runtime
    /// publication is not ready. Deferral requires explicit resolver
    /// classification and revalidates the materialized Tab; a nil context
    /// override alone is never ownership evidence.
    func admit(
        _ tab: Tab,
        load: ExtensionRequestedTabLoad,
        publicationControllerIsReady: Bool,
        reason: String
    ) -> Bool {
        if publicationControllerIsReady {
            return registrar.register(tab, reason: reason)
        }
        return load.isOrdinaryBrowserRequest
            && tab.isEphemeral == false
            && tab.webExtensionContextOverride == nil
            && ExtensionURLIdentity.isOwned(tab.url) == false
    }
}
