import Foundation

@MainActor
final class ClosedShortcutLauncherRestoreTransaction {
    private let pins: ShortcutPinCollectionStateOwner
    private let pinStore: ShortcutPinStoreOwner
    private let persistence: TabStructuralPersistenceService
    private let destinations: ClosedShortcutLauncherDestinationResolver

    init(
        pins: ShortcutPinCollectionStateOwner,
        pinStore: ShortcutPinStoreOwner,
        persistence: TabStructuralPersistenceService,
        destinations: ClosedShortcutLauncherDestinationResolver
    ) {
        self.pins = pins
        self.pinStore = pinStore
        self.persistence = persistence
        self.destinations = destinations
    }

    func restore(
        _ pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> ShortcutPin? {
        if let existing = pins.shortcutPin(by: pinState.id) {
            return existing
        }
        guard let pin = makePin(pinState, fallbackWindow: fallbackWindow),
              let inserted = pinStore.insert(pin, at: pinState.index) else {
            return nil
        }
        persistence.scheduleStructuralPersistence()
        return inserted
    }

    private func makePin(
        _ pinState: RecentlyClosedShortcutPinState,
        fallbackWindow: BrowserWindowState?
    ) -> ShortcutPin? {
        switch pinState.role {
        case .essential:
            guard let profileID = destinations.essentialProfileID(
                for: pinState,
                fallbackWindow: fallbackWindow
            ) else { return nil }
            return ShortcutPin(
                id: pinState.id,
                role: .essential,
                profileId: profileID,
                executionProfileId: pinState.executionProfileId,
                spaceId: nil,
                index: pinState.index,
                folderId: nil,
                launchURL: pinState.launchURL,
                title: pinState.title,
                iconAsset: pinState.iconAsset,
                titleIsCustom: pinState.titleIsCustom
            )
        case .spacePinned:
            guard let spaceID = destinations.spaceID(
                for: pinState,
                fallbackWindow: fallbackWindow
            ) else { return nil }
            return ShortcutPin(
                id: pinState.id,
                role: .spacePinned,
                profileId: nil,
                executionProfileId: pinState.executionProfileId,
                spaceId: spaceID,
                index: pinState.index,
                folderId: destinations.folderID(
                    pinState.folderId,
                    in: spaceID
                ),
                launchURL: pinState.launchURL,
                title: pinState.title,
                iconAsset: pinState.iconAsset,
                titleIsCustom: pinState.titleIsCustom
            )
        }
    }
}
