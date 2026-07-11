import Foundation

@MainActor
struct RegularTabShortcutStructurePlan {
    let sourceTabId: UUID
    let sourceSplitGroupSnapshot: SplitGroup?
    private let isCurrentBody: (Tab) -> Bool
    private let runtimeExposureIsValid: (
        UUID,
        [UUID],
        RuntimePortRegistry
    ) -> Bool
    private let structuralAuthorization: (
        ShortcutPin
    ) -> AuthorizedShortcutStructureTransition?

    init(
        sourceTabId: UUID,
        sourceSplitGroupSnapshot: SplitGroup?,
        isCurrent: @escaping (Tab) -> Bool,
        runtimeExposureIsValid: @escaping (
            UUID,
            [UUID],
            RuntimePortRegistry
        ) -> Bool,
        authorizeStructure: @escaping (
            ShortcutPin
        ) -> AuthorizedShortcutStructureTransition?
    ) {
        self.sourceTabId = sourceTabId
        self.sourceSplitGroupSnapshot = sourceSplitGroupSnapshot
        self.isCurrentBody = isCurrent
        self.runtimeExposureIsValid = runtimeExposureIsValid
        self.structuralAuthorization = authorizeStructure
    }

    func acceptsRuntimeExposure(
        of tabId: UUID,
        in windowIds: [UUID],
        using runtime: RuntimePortRegistry
    ) -> Bool {
        runtimeExposureIsValid(tabId, windowIds, runtime)
    }

    func authorize(
        _ pin: ShortcutPin,
        for tab: Tab
    ) -> AuthorizedShortcutStructureTransition? {
        guard tab.id == sourceTabId, isCurrentBody(tab) else { return nil }
        return structuralAuthorization(pin)
    }
}

@MainActor
struct AuthorizedShortcutStructureTransition {
    private let commitBody: (ShortcutPin) -> Void

    init(commit: @escaping (ShortcutPin) -> Void) {
        self.commitBody = commit
    }

    func commit(insertedPin: ShortcutPin) {
        commitBody(insertedPin)
    }

    static func forSplit(
        for candidatePin: ShortcutPin,
        sourceTabId: UUID,
        group: SplitGroup,
        upsertSplitGroup: @escaping (SplitGroup) -> Void
    ) -> Self? {
        let origin: (ShortcutPin) -> SplitGroupMemberOrigin
        switch candidatePin.role {
        case .essential:
            origin = { .essential(profileId: $0.profileId, index: $0.index) }
        case .spacePinned:
            guard let spaceId = candidatePin.spaceId else { return nil }
            let folderId = candidatePin.folderId
            origin = {
                .spacePinned(
                    spaceId: spaceId,
                    folderId: folderId,
                    index: $0.index
                )
            }
        }
        return Self { insertedPin in
            let member = SplitGroupMember(
                tabId: sourceTabId,
                pinId: insertedPin.id,
                origin: origin(insertedPin)
            )
            upsertSplitGroup(group.upsertingMember(member))
        }
    }
}
