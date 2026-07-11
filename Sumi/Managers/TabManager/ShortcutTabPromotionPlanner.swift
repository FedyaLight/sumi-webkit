import Foundation
import SumiDomain

/// Selects the exact live lease (or creates the future regular tab) and records
/// every window whose selection can be affected. It performs no mutation.
@MainActor
final class ShortcutTabPromotionPlanner {
    private let registry: LiveShortcutTabRegistry
    private let spaces: TabSpaceCollectionStateOwner
    private let splitGroups: SplitGroupStore
    private let tabFactory: TabFactory
    private let runtimePorts: () -> RuntimePortRegistry?

    init(
        registry: LiveShortcutTabRegistry,
        spaces: TabSpaceCollectionStateOwner,
        splitGroups: SplitGroupStore,
        tabFactory: TabFactory,
        runtimePorts: @escaping () -> RuntimePortRegistry?
    ) {
        self.registry = registry
        self.spaces = spaces
        self.splitGroups = splitGroups
        self.tabFactory = tabFactory
        self.runtimePorts = runtimePorts
    }

    func prepare(
        _ pin: ShortcutPin,
        targetSpaceID: UUID,
        targetIndex: Int?,
        preferredWindowID: UUID?,
        allowsGroupedPin: Bool
    ) -> ShortcutTabPromotionPlan? {
        guard spaces.contains(spaceId: targetSpaceID),
              allowsGroupedPin || splitGroups.group(
                  containing: .shortcutPin(pin.id)
              ) == nil else { return nil }

        let entries = registry.entries(for: pin.id)
        let runtime = runtimePorts()
        guard entries.isEmpty || runtime != nil else { return nil }
        let chosen = preferredWindowID.flatMap { preferred in
            entries.first { $0.windowId == preferred }
        } ?? entries.first
        let tab = chosen?.tab ?? makeTab(from: pin, spaceID: targetSpaceID)
        return ShortcutTabPromotionPlan(
            pinID: pin.id,
            tab: tab,
            chosenEntry: chosen,
            selectedWindowStates: selectedWindows(
                pinID: pin.id,
                runtime: runtime
            ),
            targetSpaceID: targetSpaceID,
            targetIndex: targetIndex,
            runtime: runtime
        )
    }

    private func makeTab(from pin: ShortcutPin, spaceID: UUID) -> Tab {
        let tab = tabFactory.makeTab(
            url: pin.launchURL,
            name: pin.title,
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: spaceID,
            index: 0
        )
        _ = tab.applyCachedFaviconOrPlaceholder(for: pin.launchURL)
        return tab
    }

    private func selectedWindows(
        pinID: UUID,
        runtime: RuntimePortRegistry?
    ) -> [BrowserWindowState] {
        var result: [BrowserWindowState] = []
        runtime?.forEachWindowState { state in
            let liveTabID = registry.tab(for: pinID, in: state.id)?.id
            let selectsLive = ShortcutSelectionIdentity.isSelected(
                tabId: liveTabID,
                pinId: pinID,
                in: state
            )
            let selectsSplit = state.splitSelection?.activeMemberID
                == .shortcutPin(pinID)
            if selectsLive || selectsSplit { result.append(state) }
        }
        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
