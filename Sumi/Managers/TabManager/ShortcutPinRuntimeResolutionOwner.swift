import Foundation
import SumiDomain

@MainActor
final class ShortcutPinRuntimeResolutionOwner {
    private let spaces: TabSpaceCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let faviconService: any BrowserFaviconServicing

    init(
        spaces: TabSpaceCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        faviconService: any BrowserFaviconServicing
    ) {
        self.spaces = spaces
        self.runtimeConnection = runtimeConnection
        self.faviconService = faviconService
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
                spaces.space(with: spaceId)?.profileId
            }
        }
    }

    func desiredLiveTabProfileId(for pin: ShortcutPin) -> UUID? {
        switch pin.role {
        case .essential:
            return pin.executionProfileId ?? pin.profileId
        case .spacePinned:
            return pin.executionProfileId
        }
    }

    func presentationPageReceipt(
        for pin: ShortcutPin,
        windowID: UUID,
        presentationSpaceID: UUID?
    ) -> LiveShortcutPresentationPageReceipt? {
        guard let presentationSpaceID,
              let presentationSpace = spaces.space(with: presentationSpaceID)
        else {
            return nil
        }
        switch pin.role {
        case .essential:
            guard let profileID = pin.profileId,
                  presentationSpace.profileId == profileID else {
                return nil
            }
        case .spacePinned:
            guard let spaceID = pin.spaceId,
                  spaceID == presentationSpace.id else {
                return nil
            }
        }
        return LiveShortcutPresentationPageReceipt(
            windowID: windowID,
            spaceID: presentationSpace.id,
            profileID: presentationSpace.profileId
        )
    }

    func resolvedFaviconPartition(for pin: ShortcutPin, currentSpaceId: UUID? = nil) -> SumiFaviconPartition {
        let profileId = resolvedExecutionProfileId(for: pin, currentSpaceId: currentSpaceId)
        guard let profileId,
              let profile = runtimeConnection.captureLease().registry?
                .profile(with: profileId)
        else {
            return .regular(profileId)
        }
        return faviconService.partition(profile: profile)
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
                spaces.space(with: targetSpaceId)?.profileId
            }
        }

        return tabProfileId == containerProfileId ? nil : tabProfileId
    }
}
