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
            guard let pin = pins.shortcutPin(by: pinID),
                  let placement = returnPlacement(
                      for: pin,
                      windowState: windowState
                  ) else {
                return nil
            }
            return .shortcutPin(pinID, returnPlacement: placement)
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
              let targetPin = pins.shortcutPin(by: targetPinID),
              incomingPin.role == .spacePinned,
              targetPin.role == .spacePinned,
              let spaceID = incomingPin.spaceId,
              targetPin.spaceId == spaceID,
              incomingPin.folderId == targetPin.folderId else {
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

        return .shortcutSidebar(
            spaceId: spaceID,
            profileId: incomingPin.profileId
                ?? targetPin.profileId
                ?? windowState.currentProfileId,
            folderId: incomingPin.folderId,
            index: min(incomingPin.index, targetPin.index)
        )
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
        guard case .shortcutSidebar(
            let spaceID,
            _,
            let folderID,
            _
        ) = container,
              case .shortcutPin(let pinID) = memberID,
              let pin = pins.shortcutPin(by: pinID) else {
            return false
        }
        return pin.role == .spacePinned
            && pin.spaceId == spaceID
            && pin.folderId == folderID
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

    private func returnPlacement(
        for pin: ShortcutPin,
        windowState: BrowserWindowState
    ) -> SplitShortcutReturnPlacement? {
        switch pin.role {
        case .essential:
            return .essential(profileId: pin.profileId, index: pin.index)
        case .spacePinned:
            guard let spaceID = pin.spaceId ?? windowState.currentSpaceId else {
                return nil
            }
            return .spacePinned(
                spaceId: spaceID,
                folderId: pin.folderId,
                index: pin.index
            )
        }
    }
}
