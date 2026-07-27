import Foundation

@testable import Sumi

/// Shared factory for browser-database fixtures that must not touch disk.
@MainActor
func makeInMemoryStartupDatabase() throws -> SumiDatabase {
    try SumiDatabase.inMemory()
}

/// Installs explicit Space state for tests whose subject is below the catalog
/// command boundary.
@MainActor
func installTestSpace(
    in spaces: TabSpaceCollectionStateOwner,
    name: String,
    profileID: UUID? = nil
) -> Space {
    let space = Space(name: name, profileId: profileID)
    spaces.append(space)
    return space
}
