import Foundation

/// Retires the outgoing profile's extension surfaces as the runtime moves to a
/// new profile: per-profile action anchors, the pinned toolbar, a controller
/// still published for a different profile, and contexts loaded for profiles
/// that are no longer current.
@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileSurfaceHandoff {
    private let actionAnchors: ExtensionActionPopupAnchorStore
    private let toolbarProfiles: any ExtensionToolbarProfileReloading
    private let browserConfiguration: BrowserConfiguration
    private let profileRuntime: ExtensionProfileRuntime
    private let inactiveContextRetirement:
        any ExtensionInactiveProfileContextRetiring

    init(
        actionAnchors: ExtensionActionPopupAnchorStore,
        toolbarProfiles: any ExtensionToolbarProfileReloading,
        browserConfiguration: BrowserConfiguration,
        profileRuntime: ExtensionProfileRuntime,
        inactiveContextRetirement: any ExtensionInactiveProfileContextRetiring
    ) {
        self.actionAnchors = actionAnchors
        self.toolbarProfiles = toolbarProfiles
        self.browserConfiguration = browserConfiguration
        self.profileRuntime = profileRuntime
        self.inactiveContextRetirement = inactiveContextRetirement
    }

    /// Drops anchors owned by other profiles and rebuilds the pinned toolbar.
    func prepareForActivation(of profileID: UUID) {
        actionAnchors.clearAnchors(notMatching: profileID)
        toolbarProfiles.reloadPinnedToolbarExtensionsForCurrentProfile()
    }

    /// Unpublishes a controller that belongs to a different profile so the
    /// base configuration never advertises foreign extension state.
    func detachForeignPublishedController(for profileID: UUID) {
        guard let publishedController = browserConfiguration
            .webViewConfiguration.webExtensionController,
              profileRuntime.profileId(for: publishedController) != profileID
        else { return }
        browserConfiguration.webViewConfiguration.webExtensionController = nil
    }

    func retireInactiveProfiles(keeping profileID: UUID) {
        inactiveContextRetirement.unloadExtensionContextsForInactiveProfiles(
            keepingProfileId: profileID
        )
    }
}
