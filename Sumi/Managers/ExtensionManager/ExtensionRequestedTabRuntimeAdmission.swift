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
            // WebKit may ask an extension to open an ordinary page while a
            // sibling context in the same profile is still settling. The
            // browser tab is a valid user-visible result even when extension
            // publication must be deferred; normal tab lifecycle will retry
            // registration after the profile contexts become ready. Internal
            // extension URLs still fail closed because they cannot be safely
            // represented without their owning context.
            return registrar.register(tab, reason: reason)
                || isOrdinaryBrowserTab(tab, load: load)
        }
        return isOrdinaryBrowserTab(tab, load: load)
    }

    private func isOrdinaryBrowserTab(
        _ tab: Tab,
        load: ExtensionRequestedTabLoad
    ) -> Bool {
        load.isOrdinaryBrowserRequest
            && tab.isEphemeral == false
            && tab.webExtensionContextOverride == nil
            && ExtensionURLIdentity.isOwned(tab.url) == false
    }
}
