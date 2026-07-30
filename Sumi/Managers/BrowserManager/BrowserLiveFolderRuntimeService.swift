import Foundation

@MainActor
enum BrowserLiveFolderRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> SumiLiveFolderRuntime {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        let spaces = browserManager.spaceStateOwner
        let folderCommands = browserManager.sidebarFolderCommands
        let folderState = browserManager.folderCollectionStateOwner
        let profiles = browserManager.profileManager
        let itemTabs = BrowserLiveFolderShortcutBridge(
            pins: browserManager.shortcutPinCollectionStateOwner,
            store: browserManager.shortcutPinStoreOwner,
            commands: browserManager.sidebarPinCommands,
            activation: browserManager.shortcutPresentationActivation,
            selection: browserManager.browserTabSelection,
            spaces: spaces
        )
        return SumiLiveFolderRuntime(
            spaceContext: { [spaces] spaceId in
                guard let space = spaces.space(with: spaceId) else {
                    return nil
                }
                return SumiLiveFolderRuntime.SpaceContext(profileId: space.profileId)
            },
            createLiveFolder: { [folderCommands] spaceId, name in
                folderCommands.createFolder(
                    in: spaceId,
                    name: name,
                    isLiveFolder: true
                )?.id
            },
            markFolderLive: { [folderCommands] folderID in
                folderCommands.markFolderLive(folderID)
            },
            updateFolderIcon: { [folderCommands] folderId, icon in
                folderCommands.updateFolderIcon(folderId, icon: icon)
            },
            openNewTab: { [weak browserManager] urlString, windowState, preferredSpaceId in
                browserManager?.tabOpening.openNewTab(
                    url: urlString,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            profile: { [profiles, spaces] profileId, spaceId in
                if let profileId,
                   let profile = profiles.profiles.first(where: { $0.id == profileId }) {
                    return profile
                }
                if let space = spaces.space(with: spaceId),
                   let profileId = space.profileId {
                    return profiles.profiles.first { $0.id == profileId }
                }
                return currentProfileAuthority.currentProfile
            },
            folderIds: { [folderState] in
                Set(folderState.allFolders().map(\.id))
            },
            itemTabs: SumiLiveFolderItemTabRuntime(
                reconcile: itemTabs.reconcile,
                remove: itemTabs.remove,
                detach: itemTabs.detach,
                activate: itemTabs.activate
            )
        )
    }
}

/// Adapter from Live Folder results to Sumi's native durable launcher and
/// per-window lazy-tab machinery. The Live Folder manager never needs to know
/// how shortcut catalogs, materialization, or selection are coordinated.
@MainActor
private final class BrowserLiveFolderShortcutBridge {
    private let pins: ShortcutPinCollectionStateOwner
    private let store: ShortcutPinStoreOwner
    private let commands: SidebarPinCommands
    private let activation: ShortcutPresentationActivationService
    private let selection: BrowserTabSelectionOwner
    private let spaces: TabSpaceCollectionStateOwner

    init(
        pins: ShortcutPinCollectionStateOwner,
        store: ShortcutPinStoreOwner,
        commands: SidebarPinCommands,
        activation: ShortcutPresentationActivationService,
        selection: BrowserTabSelectionOwner,
        spaces: TabSpaceCollectionStateOwner
    ) {
        self.pins = pins
        self.store = store
        self.commands = commands
        self.activation = activation
        self.selection = selection
        self.spaces = spaces
    }

    func reconcile(
        source: SumiLiveFolderSource,
        items: [SumiLiveFolderItem]
    ) -> [SumiLiveFolderItem] {
        let existingFolderPins = pins.folderPinnedPins(
            for: source.folderId,
            in: source.spaceId
        )
        var claimedPinIDs = Set<UUID>()
        var reconciled: [SumiLiveFolderItem] = []

        for item in items {
            guard let url = item.url else { continue }
            var next = item
            let iconAsset = shortcutIconAsset(for: item)
            var pin = item.shortcutPinId.flatMap(pins.shortcutPin(by:))
            if pin?.folderId != source.folderId || pin?.spaceId != source.spaceId {
                pin = existingFolderPins.first { candidate in
                    !claimedPinIDs.contains(candidate.id)
                        && candidate.launchURL == url
                }
            }

            if let current = pin {
                if current.title != item.title
                    || current.launchURL != url
                    || current.iconAsset != iconAsset {
                    pin = commands.update(
                        current,
                        title: item.title,
                        launchURL: url,
                        iconAsset: iconAsset,
                        titleIsCustom: false
                    )
                }
            } else {
                let candidate = ShortcutPin(
                    id: item.shortcutPinId ?? UUID(),
                    role: .spacePinned,
                    executionProfileId: spaces.space(with: source.spaceId)?.profileId,
                    spaceId: source.spaceId,
                    index: pins.folderPinnedPins(
                        for: source.folderId,
                        in: source.spaceId
                    ).count,
                    folderId: source.folderId,
                    launchURL: url,
                    title: item.title,
                    iconAsset: iconAsset
                )
                pin = store.insert(
                    candidate,
                    at: candidate.index,
                    openTargetFolder: false
                )
            }

            guard let pin else { continue }
            claimedPinIDs.insert(pin.id)
            next.shortcutPinId = pin.id
            reconciled.append(next)
        }

        let obsolete = pins.folderPinnedPins(
            for: source.folderId,
            in: source.spaceId
        ).filter { !claimedPinIDs.contains($0.id) }
        if !obsolete.isEmpty {
            _ = commands.remove(obsolete, presentNotification: false)
        }
        return reconciled
    }

    func remove(
        source: SumiLiveFolderSource,
        items: [SumiLiveFolderItem]
    ) {
        let doomed = items.compactMap(\.shortcutPinId)
            .reduce(into: [UUID: ShortcutPin]()) { result, pinID in
                if let pin = pins.shortcutPin(by: pinID),
                   pin.folderId == source.folderId,
                   pin.spaceId == source.spaceId {
                    result[pinID] = pin
                }
            }
            .values
        if !doomed.isEmpty {
            _ = commands.remove(Array(doomed), presentNotification: false)
        }
    }

    func activate(
        item: SumiLiveFolderItem,
        source: SumiLiveFolderSource,
        windowState: BrowserWindowState
    ) -> Bool {
        guard let pinID = item.shortcutPinId,
              let pin = pins.shortcutPin(by: pinID),
              pin.folderId == source.folderId,
              let tab = activation.activate(
                  pin,
                  in: windowState.id,
                  presentationSpaceID: source.spaceId
              ) else {
            return false
        }
        _ = selection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
        return true
    }

    func detach(
        item: SumiLiveFolderItem,
        source: SumiLiveFolderSource
    ) -> Bool {
        guard let pinID = item.shortcutPinId,
              let pin = pins.shortcutPin(by: pinID),
              pin.folderId == source.folderId,
              pin.spaceId == source.spaceId else {
            return false
        }
        return commands.move(pin, toSpace: source.spaceId)
    }

    private func shortcutIconAsset(for item: SumiLiveFolderItem) -> String? {
        guard let iconSystemName = item.iconSystemName,
              iconSystemName.hasPrefix(SumiZenFolderIconCatalog.folderValuePrefix) == false else {
            return nil
        }
        return iconSystemName
    }
}
