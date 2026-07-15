import Foundation

/// One exact terminal operation for website-data mutations. The caller cannot
/// pull popup, options-window, or context-retirement services out of it and
/// therefore cannot perform only a partial quiescence.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWebsiteDataRuntimeQuiescence {
    private let optionsWindows: ExtensionOptionsWindowService
    private let popupRetirement: ExtensionActionPopupRetirementService
    private let contextResidency: ExtensionContextResidencyOwner

    init(
        optionsWindows: ExtensionOptionsWindowService,
        popupRetirement: ExtensionActionPopupRetirementService,
        contextResidency: ExtensionContextResidencyOwner
    ) {
        self.optionsWindows = optionsWindows
        self.popupRetirement = popupRetirement
        self.contextResidency = contextResidency
    }

    func quiesce(profileIDs: Set<UUID>) -> Bool {
        optionsWindows.closeWindows(backedBy: profileIDs)
        popupRetirement.closePopup(backedBy: profileIDs)
        return contextResidency.quiesceForWebsiteDataMutation(
            profileIDs: profileIDs
        )
    }
}
