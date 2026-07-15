import Foundation
import SumiDomain

/// Owns user-level launcher pin commands: pinning tabs to essentials or a
/// space, copying, removing, updating, resetting, and reordering shortcut
/// pins in response to explicit user actions.
@MainActor
final class ShortcutPinCommandOwner {
    struct Dependencies {
        let transactPin: @MainActor (@MainActor () -> ShortcutPin?) -> ShortcutPin?
        let withStructuralUpdateTransactionBool: @MainActor (@MainActor () -> Bool) -> Bool
        let withStructuralUpdateTransactionVoid: @MainActor (@MainActor () -> Void) -> Void
        let shortcutPinStoreOwner: ShortcutPinStoreOwner
        let shortcutTabBindings: ShortcutTabBindingSynchronizer
        let shortcutLiveTabRetirement: ShortcutLiveTabRetirementService
        let regularTabShortcutConversion: RegularTabShortcutConversionService
        let shortcutPinToRegularTab: ShortcutPinToRegularTabService
        let essentialsShortcutPlacementOwner: EssentialsShortcutPlacementOwner
        let shortcutPinCollectionStateOwner: ShortcutPinCollectionStateOwner
        let shortcutPinRuntimeResolutionOwner: ShortcutPinRuntimeResolutionOwner
        let structuralCollectionMutationOwner: TabStructuralCollectionMutationOwner
        let spacePinnedStructureOwner: SpacePinnedStructureOwner
        let shortcutPresentationOwner: TabShortcutPresentationOwner
        let tabCollectionMembershipOwner: TabCollectionMembershipOwner
        let regularTabCollectionOwner: RegularTabCollectionOwner
        let spaceStateOwner: TabSpaceCollectionStateOwner
        let tabFactory: TabFactory
        let runtimePorts: @MainActor () -> RuntimePortRegistry?
        let scheduleStructuralPersistence: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func moveShortcutPin(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        dependencies.transactPin {
            if let folderId,
               dependencies.runtimePorts()?.isLiveFolder(folderId) == true {
                return nil
            }
            guard let preview = dependencies.shortcutPinStoreOwner.previewMove(
                pin,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                proposedIndex: index
            ), let admission = dependencies.shortcutTabBindings
                .refreshAdmission(for: preview) else { return nil }
            let inserted = dependencies.shortcutPinStoreOwner.move(
                pin,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: index,
                openTargetFolder: openTargetFolder,
                applying: {
                    self.dependencies.shortcutTabBindings.refreshInstances(
                        for: $0,
                        admission: admission
                    )
                }
            )
            if inserted != nil {
                dependencies.scheduleStructuralPersistence()
            }
            return inserted
        }
    }

    @discardableResult
    func convertShortcutPinToRegularTab(
        _ pin: ShortcutPin,
        in targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> Bool {
        dependencies.shortcutPinToRegularTab.convert(
            pin,
            into: targetSpaceId,
            at: targetIndex,
            preferredWindowId: preferredWindowId
        )
    }

    @discardableResult
    func convertTabToShortcutPin(
        _ tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        at targetIndex: Int,
        openTargetFolder: Bool = true,
        preferredWindowId: UUID? = nil
    ) -> ShortcutPin? {
        dependencies.transactPin {
            if let folderId,
               dependencies.runtimePorts()?.isLiveFolder(folderId) == true {
                return nil
            }
            return dependencies.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    index: targetIndex,
                    opensFolder: openTargetFolder
                ),
                preferredWindowId: preferredWindowId
            )
        }
    }

    func pinTab(_ tab: Tab, context: EssentialsShortcutPlacementOwner.TargetContext?) {
        dependencies.withStructuralUpdateTransactionVoid {
            guard let insertion = dependencies.essentialsShortcutPlacementOwner.resolveInsertion(
                using: EssentialsShortcutPlacementOwner.InsertionContext(target: context)
            ) else { return }
            if dependencies.shortcutPinCollectionStateOwner.essentialPins(for: insertion.profileId)
                .contains(where: { $0.launchURL == tab.url }) { return }

            guard dependencies.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .essential,
                    profileId: insertion.profileId,
                    spaceId: nil,
                    folderId: nil,
                    index: insertion.index,
                    opensFolder: true
                ),
                preferredWindowId: context?.windowState?.id
            ) != nil else { return }
            dependencies.essentialsShortcutPlacementOwner.logTargetMismatchIfNeeded(
                resolution: insertion.resolution,
                context: context
            )
        }
    }

    @discardableResult
    func copyShortcutPinToEssentials(
        _ pin: ShortcutPin,
        title: String,
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) -> ShortcutPin? {
        dependencies.transactPin {
            guard let insertion = dependencies.essentialsShortcutPlacementOwner.resolveInsertion(
                using: EssentialsShortcutPlacementOwner.InsertionContext(target: context)
            ) else { return nil }
            if dependencies.shortcutPinCollectionStateOwner.essentialPins(for: insertion.profileId)
                .contains(where: { $0.launchURL == pin.launchURL }) {
                return nil
            }

            let copiedPin = ShortcutPin(
                id: UUID(),
                role: .essential,
                profileId: insertion.profileId,
                executionProfileId: copiedShortcutExecutionProfileId(
                    for: pin,
                    targetProfileId: insertion.profileId,
                    context: context
                ),
                spaceId: nil,
                index: insertion.index,
                folderId: nil,
                launchURL: pin.launchURL,
                title: title,
                iconAsset: pin.iconAsset
            )
            guard let insertedPin = dependencies.shortcutPinStoreOwner.insert(copiedPin, at: insertion.index) else {
                return nil
            }

            dependencies.essentialsShortcutPlacementOwner.logTargetMismatchIfNeeded(
                resolution: insertion.resolution,
                context: context
            )
            dependencies.scheduleStructuralPersistence()
            return insertedPin
        }
    }

    private func copiedShortcutExecutionProfileId(
        for pin: ShortcutPin,
        targetProfileId: UUID,
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) -> UUID? {
        let currentSpaceId = context?.spaceId ?? context?.windowState?.currentSpaceId
        let executionProfileId = dependencies.shortcutPinRuntimeResolutionOwner.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceId
        )
        return executionProfileId == targetProfileId ? nil : executionProfileId
    }

    func removeShortcutPin(_ pin: ShortcutPin) {
        dependencies.withStructuralUpdateTransactionVoid {
            guard let retirement = dependencies.shortcutLiveTabRetirement
                .prepareDeletedPinRetirement(pin.id) else {
                return
            }
            if dependencies.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id) != nil {
                dependencies.runtimePorts()?.captureDeletedShortcutLauncher(pin)
            }

            dependencies.shortcutPinStoreOwner.removeFromContainers(pin)
            dependencies.shortcutLiveTabRetirement
                .finishAfterCurrentBatch(retirement)
            dependencies.scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func updateShortcutPin(
        _ pin: ShortcutPin,
        title: String? = nil,
        launchURL: URL? = nil,
        iconAsset: String?? = nil,
        executionProfileId: UUID?? = nil
    ) -> ShortcutPin? {
        dependencies.transactPin {
            let updatedPin = pin.updated(
                title: title,
                launchURL: launchURL,
                iconAsset: iconAsset,
                executionProfileId: executionProfileId
            )

            switch pin.role {
            case .essential:
                guard let profileId = pin.profileId else {
                    return nil
                }
                var pins = dependencies.shortcutPinCollectionStateOwner.essentialPins(for: profileId)
                guard let index = pins.firstIndex(where: { $0.id == pin.id }) else {
                    return nil
                }

                pins[index] = updatedPin.refreshed(index: pin.index)
                dependencies.structuralCollectionMutationOwner.setPinnedTabs(
                    dependencies.shortcutPinStoreOwner.reindexed(pins),
                    for: profileId
                )
                if let inserted = dependencies.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id) {
                    dependencies.shortcutTabBindings.refreshInstances(for: inserted)
                    dependencies.scheduleStructuralPersistence()
                    return inserted
                }
            case .spacePinned:
                guard let spaceId = pin.spaceId else { return nil }
                if pin.folderId == nil {
                    let items = dependencies.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId)
                        .map { item -> SpacePinnedStructureOwner.SpacePinnedTopLevelItem in
                            guard case .shortcut(let existingPin) = item, existingPin.id == pin.id else {
                                return item
                            }
                            return .shortcut(updatedPin.refreshed(index: pin.index))
                        }
                    dependencies.spacePinnedStructureOwner.applyTopLevelSpacePinnedOrder(items, for: spaceId)
                } else {
                    dependencies.spacePinnedStructureOwner.withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { pins in
                        if let index = pins.firstIndex(where: { $0.id == pin.id }) {
                            pins[index] = updatedPin.refreshed(index: pin.index)
                        }
                    }
                }

                if let inserted = dependencies.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id) {
                    dependencies.shortcutTabBindings.refreshInstances(for: inserted)
                    dependencies.scheduleStructuralPersistence()
                    return inserted
                }
            }

            return nil
        }
    }

    @discardableResult
    func replaceShortcutPinURLWithCurrent(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> ShortcutPin? {
        guard let liveTab = dependencies.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id) else {
            return nil
        }

        let liveTitle = liveTab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = liveTitle.isEmpty ? pin.title : liveTitle
        let updated = updateShortcutPin(
            pin,
            title: resolvedTitle,
            launchURL: liveTab.url
        )
        return updated
    }

    @discardableResult
    func resetShortcutPinToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        preserveCurrentPage: Bool
    ) -> ShortcutPin? {
        dependencies.transactPin {
            guard let liveTab = dependencies.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id) else {
                return nil
            }

            let shouldPreserveCurrentPage = preserveCurrentPage
                && liveTab.url.absoluteString != pin.launchURL.absoluteString

            if shouldPreserveCurrentPage {
                guard let targetSpaceId = pin.spaceId ?? windowState.currentSpaceId else {
                    return nil
                }
                let duplicateTab = dependencies.tabFactory.makeTab(
                    url: liveTab.url,
                    name: liveTab.name,
                    favicon: SumiPersistentGlyph.launcherSystemImageFallback,
                    spaceId: targetSpaceId,
                    index: 0
                )
                duplicateTab.faviconPresentation = liveTab.faviconPresentation
                duplicateTab.faviconIsTemplateGlobePlaceholder = liveTab.faviconIsTemplateGlobePlaceholder
                duplicateTab.profileId = liveTab.profileId
                dependencies.tabCollectionMembershipOwner.attach(duplicateTab)
                var spaceTabs = dependencies.regularTabCollectionOwner.tabs(in: targetSpaceId)
                spaceTabs.append(duplicateTab)
                dependencies.structuralCollectionMutationOwner.setTabs(spaceTabs, for: targetSpaceId)
            }

            _ = liveTab.acceptResolvedDisplayTitle(pin.title, url: pin.launchURL)
            liveTab.url = pin.launchURL
            liveTab.loadURL(pin.launchURL)

            let updated = updateShortcutPin(
                pin,
                title: pin.title,
                launchURL: pin.launchURL
            )
            return updated
        }
    }

    @discardableResult
    func reorderEssential(_ pin: ShortcutPin, to index: Int) -> Bool {
        dependencies.withStructuralUpdateTransactionBool {
            guard let pid = pin.profileId else { return false }
            var arr = dependencies.shortcutPinCollectionStateOwner.essentialPins(for: pid)
            guard let currentIndex = arr.firstIndex(where: { $0.id == pin.id }) else { return false }
            let adjustedIndex = dependencies.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
                currentIndex: currentIndex,
                proposedIndex: index
            )
            guard adjustedIndex != currentIndex else { return false }
            if currentIndex < arr.count { arr.remove(at: currentIndex) }
            arr.insert(pin, at: max(0, min(adjustedIndex, arr.count)))
            dependencies.structuralCollectionMutationOwner.setPinnedTabs(
                dependencies.shortcutPinStoreOwner.reindexed(arr),
                for: pid
            )
            dependencies.scheduleStructuralPersistence()
            return true
        }
    }

    @discardableResult
    func reorderSpacePinned(_ pin: ShortcutPin, in spaceId: UUID, to index: Int) -> Bool {
        dependencies.withStructuralUpdateTransactionBool {
            var didReorder = false
            if pin.folderId == nil {
                didReorder = dependencies.spacePinnedStructureOwner.reorderTopLevelSpacePinnedShortcut(
                    pin,
                    in: spaceId,
                    to: index
                ) != nil
            } else {
                dependencies.spacePinnedStructureOwner.withSpacePinnedShortcutGroup(for: spaceId, folderId: pin.folderId) { arr in
                    guard let currentIndex = arr.firstIndex(where: { $0.id == pin.id }) else { return }
                    let adjustedIndex = dependencies.spacePinnedStructureOwner.adjustedSameContainerInsertionIndex(
                        currentIndex: currentIndex,
                        proposedIndex: index
                    )
                    guard adjustedIndex != currentIndex else { return }
                    if currentIndex < arr.count { arr.remove(at: currentIndex) }
                    arr.insert(pin, at: max(0, min(adjustedIndex, arr.count)))
                    didReorder = true
                }
            }
            if didReorder {
                dependencies.scheduleStructuralPersistence()
            }
            return didReorder
        }
    }

    func pinTabToSpace(_ tab: Tab, spaceId: UUID) {
        dependencies.withStructuralUpdateTransactionVoid {
            guard dependencies.spaceStateOwner.contains(spaceId: spaceId) else { return }
            if dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId)
                .contains(where: { $0.launchURL == tab.url }) { return }

            if tab.isShortcutLiveInstance,
               let shortcutId = tab.shortcutPinId,
               let sourcePin = dependencies.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutId),
               sourcePin.role == .essential {
                let targetIndex = dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).count
                let detachedPin = dependencies.shortcutPinRuntimeResolutionOwner.makeShortcutPin(
                    from: tab,
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: spaceId,
                    folderId: nil,
                    index: targetIndex
                )

                guard dependencies.shortcutTabBindings.canRebind(
                    tab,
                    from: sourcePin
                ) else { return }
                guard let insertedPin = dependencies.shortcutPinStoreOwner.insert(detachedPin, at: targetIndex) else {
                    return
                }

                guard dependencies.shortcutTabBindings.rebind(
                    tab,
                    from: sourcePin,
                    to: insertedPin
                ) else {
                    dependencies.shortcutPinStoreOwner
                        .removeFromContainers(insertedPin)
                    return
                }

                dependencies.scheduleStructuralPersistence()
                return
            }

            _ = convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                at: dependencies.shortcutPinCollectionStateOwner.spacePinnedPins(for: spaceId).count
            )
        }
    }
}

extension ShortcutPinCommandOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            transactPin: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            withStructuralUpdateTransactionBool: { [weak tabManager] operation in
                guard let tabManager else { return operation() }
                return tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            withStructuralUpdateTransactionVoid: { [weak tabManager] operation in
                guard let tabManager else {
                    operation()
                    return
                }
                tabManager.structuralLookupCoordinator.withTransaction(operation)
            },
            shortcutPinStoreOwner: tabManager.shortcutPinStoreOwner,
            shortcutTabBindings: tabManager.shortcutTabBindings,
            shortcutLiveTabRetirement: tabManager.shortcutLiveTabRetirement,
            regularTabShortcutConversion: tabManager.regularTabShortcutConversion,
            shortcutPinToRegularTab: tabManager.shortcutPinToRegularTab,
            essentialsShortcutPlacementOwner: tabManager.essentialsShortcutPlacementOwner,
            shortcutPinCollectionStateOwner: tabManager.shortcutPinCollectionStateOwner,
            shortcutPinRuntimeResolutionOwner: tabManager.shortcutPinRuntimeResolutionOwner,
            structuralCollectionMutationOwner: tabManager.structuralCollectionMutationOwner,
            spacePinnedStructureOwner: tabManager.spacePinnedStructureOwner,
            shortcutPresentationOwner: tabManager.shortcutPresentationOwner,
            tabCollectionMembershipOwner: tabManager.tabCollectionMembershipOwner,
            regularTabCollectionOwner: tabManager.regularTabCollectionOwner,
            spaceStateOwner: tabManager.spaceStateOwner,
            tabFactory: tabManager.tabFactory,
            runtimePorts: { [weak tabManager] in
                tabManager?.runtimePorts
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.structuralPersistence.scheduleStructuralPersistence()
            }
        )
    }
}
