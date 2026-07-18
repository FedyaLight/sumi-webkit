import Foundation
import SumiDomain

/// Authoritative sidebar projection and commands for the Space catalog.
/// Long-lived AppKit completions may retain this boundary, but every command
/// rechecks the browser runtime lifetime before mutating.
@MainActor
final class SidebarSpaceLifecycle {
    enum CommandError: LocalizedError {
        case runtimeUnavailable

        var errorDescription: String? {
            "The browser runtime is no longer available."
        }
    }

    private let runtimeIsAlive: @MainActor () -> Bool
    private let spaces: SidebarSpaceCatalogProjection
    private let inventory: SidebarSpaceInventoryProjection
    private let catalog: SpaceCatalogCommands
    private let removal: SpaceRemovalService
    private let clearing: SpaceClearingService

    init(
        runtimeIsAlive: @escaping @MainActor () -> Bool,
        spaces: SidebarSpaceCatalogProjection,
        inventory: SidebarSpaceInventoryProjection,
        catalog: SpaceCatalogCommands,
        removal: SpaceRemovalService,
        clearing: SpaceClearingService
    ) {
        self.runtimeIsAlive = runtimeIsAlive
        self.spaces = spaces
        self.inventory = inventory
        self.catalog = catalog
        self.removal = removal
        self.clearing = clearing
    }

    func availableSpaces(
        isIncognito: Bool,
        ephemeralSpaces: [Space]
    ) -> [Space] {
        spaces.availableSpaces(
            isIncognito: isIncognito,
            ephemeralSpaces: ephemeralSpaces
        )
    }

    func currentSpace() -> Space? {
        spaces.currentSpace()
    }

    func space(id: UUID) -> Space? {
        spaces.space(id: id)
    }

    func canDeleteSpace() -> Bool {
        runtimeIsAlive()
            && spaces.availableSpaces(
                isIncognito: false,
                ephemeralSpaces: []
            ).count > 1
    }

    func userVisibleTabCount(in spaceID: UUID) -> Int {
        inventory.snapshot(for: spaceID)?.userVisibleTabCount ?? 0
    }

    @discardableResult
    func createSpace(
        name: String,
        icon: String,
        workspaceTheme: WorkspaceTheme? = nil,
        profileID: UUID?
    ) -> Space? {
        guard runtimeIsAlive() else { return nil }
        return catalog.createSpaceIfAdmitted(
            name: name,
            icon: icon,
            workspaceTheme: workspaceTheme,
            profileId: profileID
        )
    }

    @discardableResult
    func reorderSpace(_ spaceID: UUID, to targetIndex: Int) -> Bool {
        guard runtimeIsAlive() else { return false }
        return catalog.reorderSpace(spaceId: spaceID, to: targetIndex)
    }

    func renameSpace(_ spaceID: UUID, to newName: String) throws {
        guard runtimeIsAlive() else { throw CommandError.runtimeUnavailable }
        try catalog.renameSpace(spaceId: spaceID, newName: newName)
    }

    func updateSpaceIcon(_ spaceID: UUID, to icon: String) throws {
        guard runtimeIsAlive() else { throw CommandError.runtimeUnavailable }
        try catalog.updateSpaceIcon(spaceId: spaceID, icon: icon)
    }

    @discardableResult
    func removeSpace(_ spaceID: UUID) -> Bool {
        guard runtimeIsAlive(), canDeleteSpace(), space(id: spaceID) != nil else {
            return false
        }
        removal.removeSpace(spaceID)
        return space(id: spaceID) == nil
    }

    @discardableResult
    func clearSpace(_ spaceID: UUID) -> Bool {
        guard runtimeIsAlive(), space(id: spaceID) != nil else {
            return false
        }
        clearing.clearSpace(spaceID)
        return true
    }
}
