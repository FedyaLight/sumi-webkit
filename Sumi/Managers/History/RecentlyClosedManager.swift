//
//  RecentlyClosedManager.swift
//  Sumi
//

import Foundation

@MainActor
final class RecentlyClosedManager: ObservableObject {
    private enum Const {
        static let maxItems = 30
    }

    @Published private(set) var items: [RecentlyClosedItem] = []
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger?

    init(
        profileReferenceAdmission: ProfileReferenceAdmissionLedger? = nil
    ) {
        self.profileReferenceAdmission = profileReferenceAdmission
    }

    var mostRecentItem: RecentlyClosedItem? {
        items.first
    }

    var canReopenRecentlyClosedItem: Bool {
        !items.isEmpty
    }

    func captureClosedTab(
        _ tab: Tab,
        sourceSpaceId: UUID?,
        currentURL: URL?,
        canGoBack: Bool,
        canGoForward: Bool
    ) {
        guard !tab.representsSumiEmptySurface else { return }
        guard tab.profileId.map(profileReferenceIsAllowed) != false else {
            return
        }

        let item = RecentlyClosedItem.tab(
            RecentlyClosedTabState(
                id: UUID(),
                title: tab.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? tab.url.absoluteString
                    : tab.name,
                url: tab.url,
                sourceSpaceId: sourceSpaceId,
                currentURL: currentURL,
                canGoBack: canGoBack,
                canGoForward: canGoForward,
                profileId: tab.profileId
            )
        )
        prepend(item)
    }

    func captureClosedShortcutLiveInstance(
        tab: Tab,
        pin: ShortcutPin,
        sourceWindowId: UUID?
    ) {
        guard !tab.representsSumiEmptySurface else { return }
        guard ProfileReferenceInventory(shortcutPin: pin).profileIDs
            .allSatisfy(profileReferenceIsAllowed)
        else { return }

        let title = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = RecentlyClosedItem.shortcutLiveInstance(
            RecentlyClosedShortcutLiveState(
                id: UUID(),
                pin: RecentlyClosedShortcutPinState(pin: pin),
                title: title.isEmpty ? tab.url.absoluteString : tab.name,
                url: tab.url,
                sourceWindowId: sourceWindowId,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward
            )
        )
        prepend(item)
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        guard ProfileReferenceInventory(shortcutPin: pin).profileIDs
            .allSatisfy(profileReferenceIsAllowed)
        else { return }
        let item = RecentlyClosedItem.shortcutLauncher(
            RecentlyClosedShortcutLauncherState(
                id: UUID(),
                pin: RecentlyClosedShortcutPinState(pin: pin)
            )
        )
        prepend(item)
    }

    func captureClosedWindow(
        sessionWindowId: UUID,
        title: String,
        session: WindowSessionSnapshot
    ) {
        guard ProfileReferenceInventory(windowSnapshot: session).profileIDs
            .allSatisfy(profileReferenceIsAllowed)
        else { return }
        let item = RecentlyClosedItem.window(
            RecentlyClosedWindowState(
                id: UUID(),
                sessionWindowId: sessionWindowId,
                title: title,
                session: session
            )
        )
        prepend(item)
    }

    func remove(_ item: RecentlyClosedItem) {
        items.removeAll { $0.id == item.id }
    }

    func retireProfileReferences(
        to profileID: UUID,
        mutationLease: ProfileReferenceMutationLease
    ) -> Bool {
        guard let profileReferenceAdmission,
              profileReferenceAdmission.validate(mutationLease)
        else { return false }
        items.removeAll {
            ProfileReferenceInventory(recentlyClosedItem: $0)
                .contains(profileID)
        }
        return profileReferenceAdmission.validate(mutationLease)
            && containsProfileReference(to: profileID) == false
    }

    func containsProfileReference(to profileID: UUID) -> Bool {
        items.contains {
            ProfileReferenceInventory(recentlyClosedItem: $0)
                .contains(profileID)
        }
    }

    private func profileReferenceIsAllowed(_ profileID: UUID) -> Bool {
        profileReferenceAdmission?.isReferenceAllowed(profileID) ?? true
    }

    private func prepend(_ item: RecentlyClosedItem) {
        items.removeAll { existing in
            switch (existing, item) {
            case (.tab(let lhs), .tab(let rhs)):
                return lhs.url == rhs.url && lhs.profileId == rhs.profileId
            case (.shortcutLiveInstance(let lhs), .shortcutLiveInstance(let rhs)):
                return lhs.pin.id == rhs.pin.id
            case (.shortcutLiveInstance(let lhs), .shortcutLauncher(let rhs)):
                return lhs.pin.id == rhs.pin.id
            case (.shortcutLauncher(let lhs), .shortcutLiveInstance(let rhs)):
                return lhs.pin.id == rhs.pin.id
            case (.shortcutLauncher(let lhs), .shortcutLauncher(let rhs)):
                return lhs.pin.id == rhs.pin.id
            case (.window(let lhs), .window(let rhs)):
                return lhs.sessionWindowId == rhs.sessionWindowId
            default:
                return false
            }
        }
        items.insert(item, at: 0)
        if items.count > Const.maxItems {
            items = Array(items.prefix(Const.maxItems))
        }
    }
}
