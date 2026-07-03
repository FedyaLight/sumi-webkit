import SwiftData

@testable import Sumi

/// Shared factory for the in-memory SwiftData container tests use to host a `TabManager`
/// (or any startup-schema fixture) without touching the on-disk store.
@MainActor
func makeInMemoryStartupModelContainer() throws -> ModelContainer {
    try ModelContainer(
        for: SumiStartupPersistence.schema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
}
