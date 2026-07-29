import Foundation

@MainActor
struct PlannedSpaceContentRetirement {
    let spaceId: UUID
    let tabs: [Tab]
    let runtime: TabRuntimePortLease
    let runtimeTeardown: PreparedTabRuntimeTeardown
}

@MainActor
struct PreparedSpaceContentRetirement {
    let footprint: SpaceRemovalFootprint
    let runtime: TabRuntimePortLease
    let runtimeTeardown: PreparedTabRuntimeTeardown
}
