import Foundation

@MainActor
final class ShortcutPinRuntimeResolutionOwner {
    struct Dependencies {
        let spaces: @MainActor () -> [Space]
        let runtimeContext: @MainActor () -> TabManagerRuntimeContext?
        let faviconService: @MainActor () -> any BrowserFaviconServicing
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func makeShortcutPin(
        from tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        folderId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            executionProfileId: shortcutExecutionProfileId(
                from: tab,
                role: role,
                profileId: profileId,
                spaceId: spaceId
            ),
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: tab.url,
            title: tab.name
        )
    }

    func resolvedLiveSpaceId(for pin: ShortcutPin, currentSpaceId: UUID?) -> UUID? {
        switch pin.role {
        case .essential:
            return nil
        case .spacePinned:
            return pin.spaceId ?? currentSpaceId
        }
    }

    func resolvedExecutionProfileId(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> UUID? {
        if let executionProfileId = pin.executionProfileId {
            return executionProfileId
        }

        switch pin.role {
        case .essential:
            return pin.profileId
        case .spacePinned:
            return (pin.spaceId ?? currentSpaceId).flatMap { spaceId in
                dependencies.spaces().first(where: { $0.id == spaceId })?.profileId
            }
        }
    }

    func resolvedFaviconPartition(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> SumiFaviconPartition {
        let profileId = resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
        guard let profileId,
              let profile = dependencies.runtimeContext()?.profile(with: profileId)
        else {
            return .regular(profileId)
        }
        return dependencies.faviconService().partition(profile: profile)
    }
}

private extension ShortcutPinRuntimeResolutionOwner {
    func shortcutExecutionProfileId(
        from tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?
    ) -> UUID? {
        guard let tabProfileId = tab.profileId else { return nil }

        let containerProfileId: UUID?
        switch role {
        case .essential:
            containerProfileId = profileId
        case .spacePinned:
            containerProfileId = spaceId.flatMap { targetSpaceId in
                dependencies.spaces().first(where: { $0.id == targetSpaceId })?.profileId
            }
        }

        return tabProfileId == containerProfileId ? nil : tabProfileId
    }
}

extension ShortcutPinRuntimeResolutionOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            spaces: { [weak tabManager] in
                tabManager?.spaceStateOwner.spaces ?? []
            },
            runtimeContext: { [weak tabManager] in
                tabManager?.runtimeContext
            },
            faviconService: { [weak tabManager] in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.faviconService
            }
        )
    }
}
