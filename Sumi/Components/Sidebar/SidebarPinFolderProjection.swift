import Foundation
import SumiDomain

/// Non-selection presentation inputs for pinned shortcuts and folders.
@MainActor
final class SidebarPinFolderProjection {
    private let runtimeIsAlive: @MainActor () -> Bool
    private let windows: SidebarWindowIdentityQuery
    private let essentials: EssentialsShortcutPlacementOwner
    private let resolution: ShortcutPinRuntimeResolutionOwner

    init(
        runtimeIsAlive: @escaping @MainActor () -> Bool,
        windows: SidebarWindowIdentityQuery,
        essentials: EssentialsShortcutPlacementOwner,
        resolution: ShortcutPinRuntimeResolutionOwner
    ) {
        self.runtimeIsAlive = runtimeIsAlive
        self.windows = windows
        self.essentials = essentials
        self.resolution = resolution
    }

    func canAddToEssentials(
        url: URL,
        in windowState: BrowserWindowState,
        spaceID: UUID?
    ) -> Bool {
        guard runtimeIsAlive(), windows.contains(windowState) else {
            return false
        }
        return essentials.canAddURL(
            url,
            using: .init(windowState: windowState, spaceId: spaceID)
        )
    }

    func executionProfileID(
        for pin: ShortcutPin,
        currentSpaceID: UUID?
    ) -> UUID? {
        guard runtimeIsAlive() else { return nil }
        return resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceID
        )
    }

    func faviconPartition(
        for pin: ShortcutPin,
        currentSpaceID: UUID?
    ) -> SumiFaviconPartition {
        guard runtimeIsAlive() else { return .regular(nil) }
        return resolution.resolvedFaviconPartition(
            for: pin,
            currentSpaceId: currentSpaceID
        )
    }
}
