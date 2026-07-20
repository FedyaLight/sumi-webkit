import Foundation
import SumiDomain

struct ResolvedSplitRuntimeMember {
    let member: SplitMember
    let liveTab: Tab
}

/// Translates at the runtime boundary between durable split-member identity
/// and one window's concrete tab. It performs no structural mutation.
@MainActor
final class SplitRuntimeMemberResolver {
    private let membership: SplitGroupMembershipQuery
    private let splitGroups: SplitGroupStore
    private let regularTabs: RegularTabCollectionOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let activation: ShortcutPresentationActivationService

    init(
        membership: SplitGroupMembershipQuery,
        splitGroups: SplitGroupStore,
        regularTabs: RegularTabCollectionOwner,
        pins: ShortcutPinCollectionStateOwner,
        activation: ShortcutPresentationActivationService
    ) {
        self.membership = membership
        self.splitGroups = splitGroups
        self.regularTabs = regularTabs
        self.pins = pins
        self.activation = activation
    }

    func memberID(for tab: Tab) -> SplitMemberID? {
        membership.memberID(for: tab)
    }

    func memberID(forLookupID id: UUID) -> SplitMemberID? {
        membership.memberID(forLookupID: id)
    }

    func sourceGroup(for tab: Tab) -> SumiDomain.SplitGroup? {
        splitGroups.group(containing: membership.memberID(for: tab))
    }

    func resolveExisting(
        _ tab: Tab,
        sourceGroup: SumiDomain.SplitGroup?,
        in windowState: BrowserWindowState
    ) -> ResolvedSplitRuntimeMember? {
        let memberID = membership.memberID(for: tab)
        let member = sourceGroup?.member(for: memberID)
            ?? makeMember(for: memberID, windowState: windowState)
        guard let member,
              let liveTab = liveTab(
                  for: memberID,
                  candidate: tab,
                  in: windowState
              ) else {
            return nil
        }
        return ResolvedSplitRuntimeMember(member: member, liveTab: liveTab)
    }

    func liveTab(
        for memberID: SplitMemberID,
        candidate: Tab? = nil,
        in windowState: BrowserWindowState
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID):
            guard let canonical = regularTabs.tab(
                for: tabID
            ), candidate == nil || candidate === canonical else {
                return nil
            }
            return canonical

        case .shortcutPin(let pinID):
            guard let pin = pins.shortcutPin(by: pinID) else {
                return nil
            }
            var activated: Tab?
            let accepted = activation.withActivation(
                pin,
                in: windowState.id,
                presentationSpaceID: pin.spaceId ?? windowState.currentSpaceId
            ) { liveTab in
                guard candidate == nil || candidate === liveTab else {
                    return false
                }
                activated = liveTab
                return true
            }
            return accepted ? activated : nil
        }
    }

    func makeMember(
        for memberID: SplitMemberID,
        windowState: BrowserWindowState
    ) -> SplitMember? {
        switch memberID {
        case .regularTab(let tabID):
            guard regularTabs.tab(for: tabID) != nil else {
                return nil
            }
            return .regularTab(tabID)

        case .shortcutPin(let pinID):
            guard pins.shortcutPin(by: pinID) != nil else {
                return nil
            }
            return .shortcutPin(pinID)
        }
    }

    func initialContainer(
        incoming: SplitMemberID,
        target: SplitMemberID,
        windowState: BrowserWindowState
    ) -> SplitGroupContainer {
        guard case .shortcutPin(let incomingPinID) = incoming,
              case .shortcutPin(let targetPinID) = target,
              let incomingPin = pins.shortcutPin(by: incomingPinID),
              let targetPin = pins.shortcutPin(by: targetPinID) else {
            let targetSpaceID: UUID?
            switch target {
            case .regularTab(let tabID):
                targetSpaceID = regularTabs.tab(for: tabID)?.spaceId
            case .shortcutPin:
                targetSpaceID = nil
            }
            return .regularTabs(
                spaceId: targetSpaceID ?? windowState.currentSpaceId
            )
        }

        if incomingPin.role == .essential,
           targetPin.role == .essential,
           let profileID = incomingPin.profileId,
           targetPin.profileId == profileID {
            return .essentialSidebar(
                profileId: profileID,
                index: min(incomingPin.index, targetPin.index)
            )
        }

        if incomingPin.role == .spacePinned,
           targetPin.role == .spacePinned,
           let spaceID = incomingPin.spaceId,
           targetPin.spaceId == spaceID,
           incomingPin.folderId == targetPin.folderId {
            return .shortcutSidebar(
                spaceId: spaceID,
                profileId: incomingPin.profileId
                    ?? targetPin.profileId
                    ?? windowState.currentProfileId,
                folderId: incomingPin.folderId,
                index: min(incomingPin.index, targetPin.index)
            )
        }

        // A new saved split belongs to the drop target. The incoming launcher
        // is moved into that target container by SplitDropService's atomic
        // topology + launcher-placement transaction.
        switch targetPin.role {
        case .essential:
            return .essentialSidebar(
                profileId: targetPin.profileId ?? windowState.currentProfileId,
                index: targetPin.index
            )
        case .spacePinned:
            guard let targetSpaceID = targetPin.spaceId else {
                return .regularTabs(spaceId: windowState.currentSpaceId)
            }
            return .shortcutSidebar(
                spaceId: targetSpaceID,
                profileId: targetPin.profileId ?? windowState.currentProfileId,
                folderId: targetPin.folderId,
                index: targetPin.index
            )
        }
    }

    func canJoinShortcutSidebar(
        _ memberID: SplitMemberID,
        group: SumiDomain.SplitGroup
    ) -> Bool {
        canPlaceShortcut(memberID, in: group.container)
    }

    func canMoveShortcut(
        _ memberID: SplitMemberID,
        from sourceGroup: SumiDomain.SplitGroup?,
        into destination: SplitGroupContainer
    ) -> Bool {
        guard case .shortcutPin = memberID,
              sourceGroup?.container.isShortcutSidebar == true else {
            return true
        }
        return canPlaceShortcut(memberID, in: destination)
    }

    private func canPlaceShortcut(
        _ memberID: SplitMemberID,
        in container: SplitGroupContainer
    ) -> Bool {
        guard case .shortcutPin(let pinID) = memberID,
              let pin = pins.shortcutPin(by: pinID) else {
            return false
        }
        switch container {
        case .regularTabs:
            return false
        case .essentialSidebar(let profileID, _):
            return pin.role == .essential
                && (profileID == nil || pin.profileId == profileID)
        case .shortcutSidebar(let spaceID, _, let folderID, _):
            return pin.role == .spacePinned
                && pin.spaceId == spaceID
                && pin.folderId == folderID
        }
    }

    func canCreateShortcutGroup(
        incoming: SplitMemberID,
        target: SplitMemberID,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard case .shortcutPin = incoming, case .shortcutPin = target else {
            return true
        }
        return initialContainer(
            incoming: incoming,
            target: target,
            windowState: windowState
        ).isShortcutSidebar
    }

    func preferredFocusTab(
        afterRemoving group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> Tab? {
        let preferredIDs = [
            windowState.splitSelection?.activeMemberID,
            memberIDForCurrentSelection(in: windowState),
        ] + group.memberIDs.map(Optional.some)

        for memberID in preferredIDs.compactMap({ $0 }) {
            if let tab = liveTab(for: memberID, in: windowState) {
                return tab
            }
        }
        return nil
    }

    func memberIDForCurrentSelection(
        in windowState: BrowserWindowState
    ) -> SplitMemberID? {
        if let pinID = windowState.currentShortcutPinId {
            return .shortcutPin(pinID)
        }
        return windowState.currentTabId.map(SplitMemberID.regularTab)
    }
}
