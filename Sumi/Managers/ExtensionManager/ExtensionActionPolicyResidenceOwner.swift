import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPolicyResidenceOwner {
    private let toolbarPinning: ExtensionToolbarPinningOwner
    private let hubOrdering: ExtensionHubOrderingOwner
    private let siteAccess: ExtensionSiteAccessPolicyCoordinator
    private let permissionDecisions: ExtensionPermissionDecisionStore
    private let permissionPrompt: ExtensionPermissionPromptPresenter

    init(
        toolbarPinning: ExtensionToolbarPinningOwner,
        hubOrdering: ExtensionHubOrderingOwner,
        siteAccess: ExtensionSiteAccessPolicyCoordinator,
        permissionDecisions: ExtensionPermissionDecisionStore,
        permissionPrompt: ExtensionPermissionPromptPresenter
    ) {
        self.toolbarPinning = toolbarPinning
        self.hubOrdering = hubOrdering
        self.siteAccess = siteAccess
        self.permissionDecisions = permissionDecisions
        self.permissionPrompt = permissionPrompt
    }
}
