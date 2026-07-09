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

    private let spaces: @MainActor () -> [Space]
    private let runtimePorts: @MainActor () -> RuntimePortRegistry?
    private let essentialPins: @MainActor (UUID?) -> [ShortcutPin]

    init(
        spaces: @escaping @MainActor () -> [Space],
        runtimePorts: @escaping @MainActor () -> RuntimePortRegistry?,
        essentialPins: @escaping @MainActor (UUID?) -> [ShortcutPin]
    ) {
        self.spaces = spaces
        self.runtimePorts = runtimePorts
        self.essentialPins = essentialPins
    }

    func resolveTarget(using context: TargetContext? = nil) -> TargetResolution {
        let resolvedSpaceId = context?.spaceId ?? context?.windowState?.currentSpaceId
        if let resolvedSpaceId,
           let profileId = spaces().first(where: { $0.id == resolvedSpaceId })?.profileId {
            return TargetResolution(profileId: profileId, source: .space)
        }

        if let profileId = context?.windowState?.currentProfileId {
            return TargetResolution(profileId: profileId, source: .window)
        }

        if let profileId = context?.profileId {
            return TargetResolution(profileId: profileId, source: .explicitProfile)
        }

        if let profileId = runtimePorts()?.currentProfileId {
            return TargetResolution(profileId: profileId, source: .globalFallback)
        }

        return TargetResolution(profileId: nil, source: .unresolved)
    }

    func resolvedProfileId(using context: TargetContext? = nil) -> UUID? {
        resolveTarget(using: context).profileId
    }

    func canAddURL(_ url: URL, using context: TargetContext? = nil) -> Bool {
        guard let profileId = resolvedProfileId(using: context) else { return false }
        let pins = essentialPins(profileId)
        guard pins.count < CapacityPolicy.maxItems else { return false }
        return pins.contains { $0.launchURL == url } == false
    }

    func resolveInsertion(using context: InsertionContext) -> InsertionPlan? {
        let resolution = resolveTarget(using: context.target)
        guard let profileId = resolution.profileId else { return nil }

        var pins = essentialPins(profileId)
        if let movingPinId = context.movingPinId,
           let existingIndex = pins.firstIndex(where: { $0.id == movingPinId }) {
            pins.remove(at: existingIndex)
        }

        guard pins.count < CapacityPolicy.maxItems else { return nil }

        let targetIndex = max(0, min(context.targetIndex ?? pins.count, pins.count))
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
