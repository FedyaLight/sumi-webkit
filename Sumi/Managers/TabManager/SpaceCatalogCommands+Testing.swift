#if DEBUG
    import Foundation
    import SumiDomain

    @MainActor
    extension SpaceCatalogCommands {
        func createSpace(
            id: UUID = UUID(),
            name: String,
            icon: String = SumiPersistentGlyph.spaceDefaultIconValue,
            workspaceTheme: WorkspaceTheme? = nil,
            profileId: UUID? = nil
        ) -> Space {
            guard let space = createSpaceIfAdmitted(
                id: id,
                name: name,
                icon: icon,
                workspaceTheme: workspaceTheme,
                profileId: profileId
            ) else {
                preconditionFailure(
                    "Test fixture attempted Space creation while admission was closed"
                )
            }
            return space
        }
    }
#endif
