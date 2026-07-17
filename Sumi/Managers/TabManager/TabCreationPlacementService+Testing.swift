#if DEBUG
    @MainActor
    extension TabCreationPlacementService {
        func withCreationPlacement(
            preferred space: Space?,
            fallbackSpaceId: UUID? = nil,
            bootstrapProfileId: UUID? = nil,
            inheritsSpaceProfile: Bool = true,
            install: (TabCreationPlacement) -> Tab
        ) -> Tab {
            guard let installed = withAdmittedCreationPlacement(
                preferred: space,
                fallbackSpaceId: fallbackSpaceId,
                bootstrapProfileId: bootstrapProfileId,
                inheritsSpaceProfile: inheritsSpaceProfile,
                admission: { _ in true },
                install: { install($0) }
            ) else {
                preconditionFailure(
                    "Test fixture attempted Tab placement while admission was closed"
                )
            }
            return installed
        }
    }
#endif
