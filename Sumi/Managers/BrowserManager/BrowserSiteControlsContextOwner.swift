import Foundation

@MainActor
final class BrowserSiteControlsContextOwner {
    private let protection: SumiProtectionCoordinator
    private let extensions: SumiExtensionsModule

    init(
        protection: SumiProtectionCoordinator,
        extensions: SumiExtensionsModule
    ) {
        self.protection = protection
        self.extensions = extensions
    }

    func snapshot(
        url: URL?,
        profile: Profile?,
        protectionReloadRequired: Bool,
        contentBlockerReloadRequired: Bool,
        hasApprovedInvalidCertificate: Bool
    ) -> SiteControlsSnapshot {
        SiteControlsSnapshot.resolve(
            url: url,
            profile: profile,
            protectionCoordinator: protection,
            protectionReloadRequired: protectionReloadRequired,
            extensionsModule: extensions,
            safariContentBlockerReloadRequired: contentBlockerReloadRequired,
            hasApprovedInvalidCertificate: hasApprovedInvalidCertificate
        )
    }
}
