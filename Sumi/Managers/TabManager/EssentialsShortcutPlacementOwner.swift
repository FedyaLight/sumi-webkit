import Foundation

@MainActor
final class EssentialsShortcutPlacementOwner {
    enum CapacityPolicy {
        static let maxColumns = 3
        static let maxRows = 4
        static let maxItems = maxColumns * maxRows
    }

    struct TargetContext {
        var windowState: BrowserWindowState?
        var spaceId: UUID?
        var profileId: UUID?

        init(
            windowState: BrowserWindowState? = nil,
            spaceId: UUID? = nil,
            profileId: UUID? = nil
        ) {
            self.windowState = windowState
            self.spaceId = spaceId
            self.profileId = profileId
        }
    }

    enum TargetSource {
        case space
        case window
        case explicitProfile
        case globalFallback
        case unresolved
    }

    struct TargetResolution {
        let profileId: UUID?
        let source: TargetSource
    }

    struct InsertionContext {
        var target: TargetContext?
        var targetIndex: Int?
        var movingPinId: UUID?
    }

    struct InsertionPlan {
        let profileId: UUID
        let index: Int
        let resolution: TargetResolution
    }

    private let spaces: TabSpaceCollectionStateOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let pins: ShortcutPinCollectionStateOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.spaces = spaces
        self.runtimeConnection = runtimeConnection
        self.pins = pins
    }

    func resolveTarget(using context: TargetContext? = nil) -> TargetResolution {
        let resolvedSpaceId = context?.spaceId ?? context?.windowState?.currentSpaceId
        if let resolvedSpaceId,
           let profileId = spaces.space(with: resolvedSpaceId)?.profileId {
            return TargetResolution(profileId: profileId, source: .space)
        }

        if let profileId = context?.windowState?.currentProfileId {
            return TargetResolution(profileId: profileId, source: .window)
        }

        if let profileId = context?.profileId {
            return TargetResolution(profileId: profileId, source: .explicitProfile)
        }

        if let profileId = runtimeConnection.current?.currentProfileId {
            return TargetResolution(profileId: profileId, source: .globalFallback)
        }

        return TargetResolution(profileId: nil, source: .unresolved)
    }

    func resolvedProfileId(using context: TargetContext? = nil) -> UUID? {
        resolveTarget(using: context).profileId
    }

    func canAddURL(_ url: URL, using context: TargetContext? = nil) -> Bool {
        guard let profileId = resolvedProfileId(using: context) else { return false }
        let profilePins = pins.essentialPins(for: profileId)
        guard profilePins.count < CapacityPolicy.maxItems else { return false }
        return profilePins.contains { $0.launchURL == url } == false
    }

    func resolveInsertion(using context: InsertionContext) -> InsertionPlan? {
        let resolution = resolveTarget(using: context.target)
        guard let profileId = resolution.profileId else { return nil }

        var profilePins = pins.essentialPins(for: profileId)
        if let movingPinId = context.movingPinId,
           let existingIndex = profilePins.firstIndex(where: {
               $0.id == movingPinId
           }) {
            profilePins.remove(at: existingIndex)
        }

        guard profilePins.count < CapacityPolicy.maxItems else { return nil }

        let targetIndex = max(
            0,
            min(context.targetIndex ?? profilePins.count, profilePins.count)
        )
        return InsertionPlan(
            profileId: profileId,
            index: targetIndex,
            resolution: resolution
        )
    }

    func resolvedProfileId(for operation: DragOperation) -> UUID? {
        operation.scope.profileId
            ?? resolvedProfileId(
                using: TargetContext(spaceId: operation.scope.spaceId)
            )
    }

    func logTargetMismatchIfNeeded(
        resolution: TargetResolution,
        context: TargetContext?
    ) {
        guard resolution.source == .globalFallback,
              let resolvedProfileId = resolution.profileId,
              let visibleProfileId = context?.windowState?.currentProfileId,
              visibleProfileId != resolvedProfileId else {
            return
        }

        RuntimeDiagnostics.emit(
            "⚠️ [Essentials] Fallback profile mismatch visible=\(visibleProfileId.uuidString) resolved=\(resolvedProfileId.uuidString)"
        )
    }
}
