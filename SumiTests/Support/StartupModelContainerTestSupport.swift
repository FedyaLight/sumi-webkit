import Foundation
import SwiftData

@testable import Sumi

/// Shared factory for startup-schema fixtures that must not touch disk.
@MainActor
func makeInMemoryStartupModelContainer() throws -> ModelContainer {
    try ModelContainer(
        for: SumiStartupPersistence.schema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
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
