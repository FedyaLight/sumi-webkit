import Foundation

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
    private let inventory: SidebarInventoryProjection
    private let catalog: SpaceCatalogCommands
    private let removal: SpaceRemovalService

    init(
        runtimeIsAlive: @escaping @MainActor () -> Bool,
        inventory: SidebarInventoryProjection,
        catalog: SpaceCatalogCommands,
        removal: SpaceRemovalService
    ) {
        self.runtimeIsAlive = runtimeIsAlive
        self.inventory = inventory
        self.catalog = catalog
        self.removal = removal
    }

    func availableSpaces(
        isIncognito: Bool,
        ephemeralSpaces: [Space]
    ) -> [Space] {
        inventory.availableSpaces(
            isIncognito: isIncognito,
            ephemeralSpaces: ephemeralSpaces
        )
    }

    func currentSpace() -> Space? {
        inventory.currentSpace()
    }

    func space(id: UUID) -> Space? {
        inventory.space(id: id)
    }

    func canDeleteSpace() -> Bool {
        runtimeIsAlive()
            && inventory.availableSpaces(
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
        profileID: UUID?
    ) -> Space? {
        guard runtimeIsAlive() else { return nil }
        return catalog.createSpace(
            name: name,
            icon: icon,
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
}
