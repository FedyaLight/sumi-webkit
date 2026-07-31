import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionToolbarOrderingRuntime {
    private let pinning: ExtensionToolbarPinningOwner
    private let hubOrdering: ExtensionHubOrderingOwner

    init(
        pinning: ExtensionToolbarPinningOwner,
        hubOrdering: ExtensionHubOrderingOwner
    ) {
        self.pinning = pinning
        self.hubOrdering = hubOrdering
    }

    func orderedPinnedSlots(
        enabledExtensions: [BrowserExtensionToolbarDisplayRecord],
        profileID: UUID?
    ) -> [PinnedToolbarSlot] {
        pinning.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            profileId: profileID
        )
    }

    func pinnedExtensionIDs(profileID: UUID?) -> [String] {
        pinning.pinnedToolbarExtensionIDs(profileId: profileID)
    }

    func isPinned(_ extensionID: String, profileID: UUID?) -> Bool {
        pinnedExtensionIDs(profileID: profileID).contains(extensionID)
    }

    @discardableResult
    func pin(_ extensionID: String, profileID: UUID?) -> Bool {
        pinning.pinToToolbar(extensionID, profileId: profileID)
    }

    @discardableResult
    func unpin(_ extensionID: String, profileID: UUID?) -> Bool {
        pinning.unpinFromToolbar(extensionID, profileId: profileID)
    }

    @discardableResult
    func movePinned(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String],
        profileID: UUID?
    ) -> Bool {
        pinning.movePinnedToolbarSlot(
            id: id,
            to: targetIndex,
            within: currentOrder,
            profileId: profileID
        )
    }

    func orderedUnpinned(
        candidateIDs: [String],
        profileID: UUID?
    ) -> [String] {
        hubOrdering.orderedUnpinnedExtensionIDs(
            candidateIDs: candidateIDs,
            profileId: profileID
        )
    }

    @discardableResult
    func moveUnpinned(
        id: String,
        to targetIndex: Int,
        within currentOrder: [String],
        profileID: UUID?
    ) -> Bool {
        hubOrdering.moveUnpinnedExtension(
            id: id,
            to: targetIndex,
            within: currentOrder,
            profileId: profileID
        )
    }
}
