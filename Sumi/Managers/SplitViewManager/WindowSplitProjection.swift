import Foundation
import SumiDomain

enum WindowSplitResolution: Equatable, Sendable {
    enum InvalidReason: Equatable, Sendable {
        case missingGroup
        case selectedMemberNotInGroup(SplitMemberID)
        case missingMembers([SplitMemberID])
        case duplicateLiveTabIDs
    }

    case inactive
    case needsMaterialization(
        group: SumiDomain.SplitGroup,
        selection: WindowSplitSelection,
        shortcutPinIDs: [UUID]
    )
    case ready(WindowSplitPresentation)
    case invalid(groupID: UUID, reason: InvalidReason)

    var presentation: WindowSplitPresentation? {
        guard case .ready(let presentation) = self else { return nil }
        return presentation
    }

    var hasReadyPresentation: Bool {
        presentation != nil
    }
}

/// Pure, on-demand projection from stable split members to one window's live
/// tab identities. It owns no cache, observers, tasks, tabs, or WebViews.
@MainActor
struct WindowSplitProjection {
    private let group: (UUID) -> SumiDomain.SplitGroup?
    private let regularTabExists: (UUID) -> Bool
    private let shortcutPinExists: (UUID) -> Bool
    private let shortcutLiveTabID: (UUID, UUID) -> UUID?

    init(
        group: @escaping (UUID) -> SumiDomain.SplitGroup?,
        regularTabExists: @escaping (UUID) -> Bool,
        shortcutPinExists: @escaping (UUID) -> Bool,
        shortcutLiveTabID: @escaping (_ pinID: UUID, _ windowID: UUID) -> UUID?
    ) {
        self.group = group
        self.regularTabExists = regularTabExists
        self.shortcutPinExists = shortcutPinExists
        self.shortcutLiveTabID = shortcutLiveTabID
    }

    func resolve(
        selection: WindowSplitSelection?,
        in windowID: UUID
    ) -> WindowSplitResolution {
        guard let selection else { return .inactive }
        guard let group = group(selection.groupID) else {
            return .invalid(
                groupID: selection.groupID,
                reason: .missingGroup
            )
        }
        guard group.memberIDs.contains(selection.activeMemberID) else {
            return .invalid(
                groupID: group.id,
                reason: .selectedMemberNotInGroup(selection.activeMemberID)
            )
        }

        var liveTabIDs: [SplitMemberID: UUID] = [:]
        var missingMembers: [SplitMemberID] = []
        var pinsNeedingMaterialization: [UUID] = []

        for memberID in group.memberIDs {
            switch memberID {
            case .regularTab(let tabID):
                if regularTabExists(tabID) {
                    liveTabIDs[memberID] = tabID
                } else {
                    missingMembers.append(memberID)
                }

            case .shortcutPin(let pinID):
                guard shortcutPinExists(pinID) else {
                    missingMembers.append(memberID)
                    continue
                }
                if let tabID = shortcutLiveTabID(pinID, windowID) {
                    liveTabIDs[memberID] = tabID
                } else {
                    pinsNeedingMaterialization.append(pinID)
                }
            }
        }

        if !missingMembers.isEmpty {
            return .invalid(
                groupID: group.id,
                reason: .missingMembers(missingMembers)
            )
        }
        if !pinsNeedingMaterialization.isEmpty {
            return .needsMaterialization(
                group: group,
                selection: selection,
                shortcutPinIDs: pinsNeedingMaterialization
            )
        }
        guard Set(liveTabIDs.values).count == liveTabIDs.count else {
            return .invalid(
                groupID: group.id,
                reason: .duplicateLiveTabIDs
            )
        }
        guard let presentation = WindowSplitPresentation(
            windowID: windowID,
            group: group,
            selection: selection,
            liveTabIDByMemberID: liveTabIDs
        ) else {
            return .invalid(
                groupID: group.id,
                reason: .duplicateLiveTabIDs
            )
        }
        return .ready(presentation)
    }
}
