/// Composition-only Space subsystem. Behavior remains in the four focused
/// collaborators; this value exposes no forwarding methods.
@MainActor
struct TabSpaceServices {
    let catalog: SpaceCatalogCommands
    let removal: SpaceRemovalService
    let activation: SpaceActivationService
    let placement: TabCreationPlacementService
}
