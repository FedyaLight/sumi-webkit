import Foundation
import SumiDomain

/// Selects the exact live lease (or creates the future regular tab) and records
/// every window whose selection can be affected. It performs no mutation.
@MainActor
final class ShortcutTabPromotionSourcePlanner {
    struct Source {
        let tab: Tab
        let chosenEntry: LiveShortcutTabEntry?
        let selectedWindowStates: [BrowserWindowState]
        let runtime: RuntimePortRegistry?
    }

    private let registry: LiveShortcutTabRegistry
    private let tabFactory: TabFactory
    private let runtimeConnection: TabRuntimePortConnection

    init(
        registry: LiveShortcutTabRegistry,
        tabFactory: TabFactory,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.registry = registry
        self.tabFactory = tabFactory
        self.runtimeConnection = runtimeConnection
    }

    func prepareSource(
        _ pin: ShortcutPin,
        targetSpaceID: UUID,
        preferredWindowID: UUID?
    ) -> Source? {
        let entries = registry.entries(for: pin.id)
        let runtime = runtimeConnection.current
        guard entries.isEmpty || runtime != nil else { return nil }
        let chosen = preferredWindowID.flatMap { preferred in
            entries.first { $0.windowId == preferred }
        } ?? entries.first
        let tab = chosen?.tab ?? makeTab(from: pin, spaceID: targetSpaceID)
        return Source(
            tab: tab,
            chosenEntry: chosen,
            selectedWindowStates: selectedWindows(
                pinID: pin.id,
                runtime: runtime
            ),
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
