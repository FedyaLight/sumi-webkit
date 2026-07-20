import Foundation
import SumiDomain

@MainActor
final class SidebarDragPayloadResolver {
    private let membership: TabCollectionMembershipOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let presentation: TabShortcutPresentationOwner
    private let folders: TabFolderCollectionStateOwner
    private let splits: SplitGroupStore

    init(
        membership: TabCollectionMembershipOwner,
        pins: ShortcutPinCollectionStateOwner,
        presentation: TabShortcutPresentationOwner,
        folders: TabFolderCollectionStateOwner,
        splits: SplitGroupStore
    ) {
        self.membership = membership
        self.pins = pins
        self.presentation = presentation
        self.folders = folders
        self.splits = splits
    }

    func tab(for id: UUID) -> Tab? {
        membership.tab(for: id)
    }

    func shortcutPin(for id: UUID) -> ShortcutPin? {
        pins.shortcutPin(by: id)
    }

    func folder(for id: UUID) -> TabFolder? {
        folders.folder(by: id)
    }

    func splitGroup(for id: UUID) -> SplitGroup? {
        splits.group(id: id)
    }

    func resolveTab(for id: UUID) -> Tab? {
        if let live = tab(for: id) {
            return live
        }
        if let pin = shortcutPin(for: id) {
            return presentation.dragProxyTab(for: pin)
        }
        return nil
    }

    func resolveTab(for item: SumiDragItem) -> Tab? {
        guard item.splitMemberID != nil else {
            return resolveTab(for: item.tabId)
        }
        guard let memberID = validatedMemberID(for: item) else {
            return nil
        }
        switch memberID {
        case .regularTab(let tabID):
            return tab(for: tabID)
        case .shortcutPin(let pinID):
            guard let pin = shortcutPin(for: pinID) else { return nil }
            return presentation.dragProxyTab(for: pin)
        }
    }

    func resolvePayload(for item: SumiDragItem) -> DragOperation.Payload? {
        if item.splitMemberID != nil {
            guard let memberID = validatedMemberID(for: item) else {
                return nil
            }
            switch memberID {
            case .regularTab(let tabID):
                return tab(for: tabID).map(DragOperation.Payload.tab)
            case .shortcutPin(let pinID):
                return shortcutPin(for: pinID).map(DragOperation.Payload.pin)
            }
        }

        switch item.kind {
        case .tab:
            if let pin = shortcutPin(for: item.tabId) {
                return .pin(pin)
            }
            return resolveTab(for: item.tabId).map(DragOperation.Payload.tab)
        case .folder:
            return folder(for: item.tabId).map(DragOperation.Payload.folder)
        case .splitGroup:
            return splitGroup(for: item.tabId).map(
                DragOperation.Payload.splitGroup
            )
        }
    }

    func canonicalPayload(
        for payload: DragOperation.Payload
    ) -> DragOperation.Payload? {
        switch payload {
        case .tab(let tab):
            guard membership.tab(for: tab.id) === tab else { return nil }
            return .tab(tab)
        case .pin(let pin):
            return pins.shortcutPin(by: pin.id).map(DragOperation.Payload.pin)
        case .folder(let folder):
            guard folders.folder(by: folder.id) === folder else { return nil }
            return .folder(folder)
        case .splitGroup(let group):
            guard let canonical = splits.group(id: group.id),
                  canonical == group else { return nil }
            return .splitGroup(canonical)
        }
    }

    private func validatedMemberID(for item: SumiDragItem) -> SplitMemberID? {
        guard let memberID = item.splitMemberID else { return nil }
        guard let groupID = item.splitGroupID else { return memberID }
        guard splitGroup(for: groupID)?.contains(memberID) == true else {
            return nil
        }
        return memberID
    }
}
