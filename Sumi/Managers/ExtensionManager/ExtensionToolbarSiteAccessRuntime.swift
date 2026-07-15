import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionToolbarSiteAccessRuntime {
    private let policies: ExtensionSiteAccessPolicyCoordinator
    private let currentProfileID: @MainActor () -> UUID?

    init(
        policies: ExtensionSiteAccessPolicyCoordinator,
        currentProfileID: @escaping @MainActor () -> UUID?
    ) {
        self.policies = policies
        self.currentProfileID = currentProfileID
    }

    func resolvedProfileID(_ explicitProfileID: UUID?) -> UUID? {
        explicitProfileID ?? currentProfileID()
    }

    func policy(
        extensionID: String,
        profileID: UUID
    ) -> SafariExtensionSiteAccessPolicy {
        policies.siteAccessPolicy(
            extensionId: extensionID,
            profileId: profileID
        )
    }

    func setDefault(
        _ access: SafariExtensionSiteAccessLevel,
        extensionID: String,
        profileID: UUID
    ) {
        policies.setDefaultSiteAccess(
            access,
            extensionId: extensionID,
            profileId: profileID
        )
    }

    func setPrivateBrowsing(
        _ isAllowed: Bool,
        extensionID: String,
        profileID: UUID
    ) {
        policies.setPrivateBrowsingAccess(
            isAllowed,
            extensionId: extensionID,
            profileId: profileID
        )
    }

    func setConfigured(
        _ access: SafariExtensionSiteAccessLevel,
        extensionID: String,
        profileID: UUID,
        matchPatternString: String
    ) {
        policies.setConfiguredSiteAccess(
            access,
            extensionId: extensionID,
            profileId: profileID,
            matchPatternString: matchPatternString
        )
    }
}
