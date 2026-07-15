import Foundation

/// Selects a Space and resolves the exact tab that should become active in the
/// caller's window context. Catalog mutation and Space deletion live in their
/// own services; this service only performs selection handoff and persistence.
@MainActor
final class SpaceActivationService {
    private let state: TabStateStore
    private let projection: SpaceLauncherProjectionService
    private let persistence: TabStructuralPersistenceService
    private let profileAdmission: SpaceActivationProfileAdmission
    private let activeEssentialTabs: @MainActor (UUID?) -> [Tab]

    init(
        state: TabStateStore,
        projection: SpaceLauncherProjectionService,
        persistence: TabStructuralPersistenceService,
        profileAdmission: SpaceActivationProfileAdmission,
        activeEssentialTabs: @escaping @MainActor (UUID?) -> [Tab]
    ) {
        self.state = state
        self.projection = projection
        self.persistence = persistence
        self.profileAdmission = profileAdmission
        self.activeEssentialTabs = activeEssentialTabs
    }

    @discardableResult
    func setActiveSpace(
        _ space: Space,
        preferredTab: Tab? = nil,
        contextWindowId: UUID? = nil
    ) -> Bool {
        guard state.spaces.contains(spaceId: space.id),
              admitProfileIfNeeded(for: space, retry: { [weak self, weak space] in
                  guard let self, let space else { return }
                  self.setActiveSpace(
                      space,
                      preferredTab: preferredTab,
                      contextWindowId: contextWindowId
                  )
              }) else { return false }

        let previousTab = state.selection.currentTab
        if let previousSpace = state.spaces.currentSpace,
           let previousTab {
            previousSpace.activeTabId = previousTab.id
            persistence.markSpacesSnapshotDirty()
        }

        state.spaces.replaceCurrentSpace(space)
        let projection = projection.projection(
            for: space.id,
            in: contextWindowId
        )
        let spacePinnedTabs = orderedLiveSpacePins(
            projection.liveTabsByPinId.values,
            in: space.id
        )
        let targetTab = resolvedTargetTab(
            preferredTab: preferredTab,
            space: space,
            regularTabs: projection.regularTabs,
            spacePinnedTabs: spacePinnedTabs
        )

        if targetTab?.id != state.selection.currentTab?.id {
            state.selection.replaceCurrentTab(targetTab)
        }
        if targetTab?.id == space.activeTabId {
            persistence.markSpacesSnapshotDirty()
        }
        persistence.persistSelection()
        return true
    }

    func admitProfileIfNeeded(
        for space: Space,
        retry: @escaping @MainActor () -> Void
    ) -> Bool {
        profileAdmission.admit(space, retry: retry)
    }

    private func orderedLiveSpacePins(
        _ liveTabs: Dictionary<UUID, Tab>.Values,
        in spaceId: UUID
    ) -> [Tab] {
        let orderByPinId = Dictionary(
            state.shortcutPins.spacePinnedPins(for: spaceId)
                .map { ($0.id, $0.index) },
            uniquingKeysWith: { first, _ in first }
        )
        return liveTabs.sorted { lhs, rhs in
            let leftOrder = lhs.shortcutPinId.flatMap { orderByPinId[$0] }
                ?? lhs.index
            let rightOrder = rhs.shortcutPinId.flatMap { orderByPinId[$0] }
                ?? rhs.index
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func resolvedTargetTab(
        preferredTab: Tab?,
        space: Space,
        regularTabs: [Tab],
        spacePinnedTabs: [Tab]
    ) -> Tab? {
        var cachedEssentialTabs: [Tab] = []
        var didResolveEssentialTabs = false
        func essentialTabs() -> [Tab] {
            if !didResolveEssentialTabs {
                cachedEssentialTabs = activeEssentialTabs(
                    profileAdmission.currentProfileID
                )
                didResolveEssentialTabs = true
            }
            return cachedEssentialTabs
        }

        var target = validPreferredTab(preferredTab, for: space)
        if let activeTabId = space.activeTabId {
            target = target
                ?? regularTabs.first { $0.id == activeTabId }
                ?? spacePinnedTabs.first { $0.id == activeTabId }
                ?? essentialTabs().first { $0.id == activeTabId }
        }
        if target == nil {
            if state.selection.currentTab?.spaceId == space.id {
                target = state.selection.currentTab
            } else {
                target = regularTabs.first
                    ?? spacePinnedTabs.first
                    ?? essentialTabs().first
            }
        }
        return target
    }

    private func validPreferredTab(_ tab: Tab?, for space: Space) -> Tab? {
        guard let tab else { return nil }
        let belongsToSpace = tab.spaceId == space.id
        let isGlobalPinned = tab.isPinned
        let isSpacePinnedForSpace = tab.isSpacePinned
            && tab.spaceId == space.id
        return belongsToSpace || isGlobalPinned || isSpacePinnedForSpace
            ? tab
            : nil
    }
}
