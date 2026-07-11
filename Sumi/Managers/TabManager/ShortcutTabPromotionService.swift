import Foundation

@MainActor
struct ShortcutTabPromotionResult {
    let tab: Tab
    let retirement: ShortcutLiveTabRetirementResult
}

@MainActor
struct PreparedShortcutTabPromotion {
    let tab: Tab
    let retirement: PreparedShortcutLiveTabRetirement
    let selectedWindowState: BrowserWindowState?
}

/// Promotes one launcher instance into a regular tab and retires every other
/// per-window instance of that launcher after the model commit.
@MainActor
final class ShortcutTabPromotionService {
    private let registry: LiveShortcutTabRegistry
    private let retirement: ShortcutLiveTabRetirementService
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let tabFactory: TabFactory
    private let runtimePorts: () -> RuntimePortRegistry?

    init(
        registry: LiveShortcutTabRegistry,
        retirement: ShortcutLiveTabRetirementService,
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        spaces: TabSpaceCollectionStateOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        tabFactory: TabFactory,
        runtimePorts: @escaping () -> RuntimePortRegistry?
    ) {
        self.registry = registry
        self.retirement = retirement
        self.membership = membership
        self.regularTabs = regularTabs
        self.spaces = spaces
        self.structuralLookup = structuralLookup
        self.tabFactory = tabFactory
        self.runtimePorts = runtimePorts
    }

    convenience init(tabManager: TabManager) {
        self.init(
            registry: tabManager.liveShortcutTabs,
            retirement: tabManager.shortcutLiveTabRetirement,
            membership: tabManager.tabCollectionMembershipOwner,
            regularTabs: tabManager.regularTabCollectionOwner,
            spaces: tabManager.spaceStateOwner,
            structuralLookup: tabManager.structuralLookupCoordinator,
            tabFactory: tabManager.tabFactory,
            runtimePorts: { [weak tabManager] in tabManager?.runtimePorts }
        )
    }

    func promote(
        _ pin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> ShortcutTabPromotionResult? {
        let prepared = structuralLookup.withTransaction {
            preparePromotion(
                pin,
                into: targetSpaceId,
                at: targetIndex,
                preferredWindowId: preferredWindowId
            )
        }
        return prepared.map(finish)
    }

    func preparePromotion(
        _ pin: ShortcutPin,
        into targetSpaceId: UUID,
        at targetIndex: Int? = nil,
        preferredWindowId: UUID? = nil
    ) -> PreparedShortcutTabPromotion? {
        guard spaces.contains(spaceId: targetSpaceId) else { return nil }
        let entries = registry.entries(for: pin.id)
        guard entries.isEmpty || runtimePorts() != nil else { return nil }
        let chosen = preferredWindowId.flatMap { preferred in
            entries.first { $0.windowId == preferred }
        } ?? entries.first

        let tab: Tab
        var wasSelected = false
        var chosenWindowState: BrowserWindowState?
        if let chosen {
            chosenWindowState = runtimePorts()?.windowState(for: chosen.windowId)
            wasSelected = chosenWindowState.map {
                ShortcutSelectionIdentity.isSelected(
                    tabId: chosen.tab.id,
                    pinId: pin.id,
                    in: $0
                )
            } ?? false
            guard registry.remove(
                pinId: pin.id,
                in: chosen.windowId
            )?.tab === chosen.tab else {
                preconditionFailure("Live shortcut promotion lost its registry lease")
            }
            tab = chosen.tab
            tab.clearShortcutBinding()
            tab.folderId = nil
            tab.isPinned = false
            tab.isSpacePinned = false
        } else {
            tab = tabFactory.makeTab(
                url: pin.launchURL,
                name: pin.title,
                favicon: SumiPersistentGlyph.launcherSystemImageFallback,
                spaceId: targetSpaceId,
                index: 0
            )
            _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        }

        guard let preparedRetirement = retirement
            .prepareDeletedPinRetirement(pin.id) else {
            preconditionFailure("Shortcut promotion lost its runtime preflight")
        }
        membership.attach(tab)
        regularTabs.insert(tab, in: targetSpaceId, at: targetIndex)
        if wasSelected, let chosenWindowState {
            _ = WindowTabSelectionStateApplicator.apply(
                tab,
                to: chosenWindowState,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        }
        return PreparedShortcutTabPromotion(
            tab: tab,
            retirement: preparedRetirement,
            selectedWindowState: wasSelected ? chosenWindowState : nil
        )
    }

    func finish(
        _ prepared: PreparedShortcutTabPromotion
    ) -> ShortcutTabPromotionResult {
        retirement.finishAfterCurrentBatch(prepared.retirement)
        if let windowState = prepared.selectedWindowState,
           prepared.retirement.result.windowStatesNeedingPersistence
            .contains(where: { $0.id == windowState.id }) == false,
           let runtime = prepared.retirement.runtime {
            structuralLookup.runAfterCurrentBatch {
                runtime.persistWindowSession(for: windowState)
            }
        }
        return ShortcutTabPromotionResult(
            tab: prepared.tab,
            retirement: prepared.retirement.result
        )
    }
}
