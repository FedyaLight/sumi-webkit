import Foundation
import SumiDomain

@MainActor
final class FavoriteShortcutPlacementOwner {
    enum CapacityPolicy {
        static let maxColumns = 3
        static let maxRows = 4
        static let maxItems = maxColumns * maxRows
        static let maxStoredMembers = maxItems * SplitGroup.maximumMembers
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
    private let splitGroups: SplitGroupStore

    init(
        spaces: TabSpaceCollectionStateOwner,
        runtimeConnection: TabRuntimePortConnection,
        pins: ShortcutPinCollectionStateOwner,
        splitGroups: SplitGroupStore
    ) {
        self.spaces = spaces
        self.runtimeConnection = runtimeConnection
        self.pins = pins
        self.splitGroups = splitGroups
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
        canAddURLs([url], using: context)
    }

    func canAddURLs(
        _ urls: [URL],
        using context: TargetContext? = nil
    ) -> Bool {
        guard let profileId = resolvedProfileId(using: context) else { return false }
        let profilePins = pins.favoritePins(for: profileId)
        guard urls.isEmpty == false,
              Set(urls).count == urls.count,
              profilePins.count + urls.count <= CapacityPolicy.maxStoredMembers,
              urls.allSatisfy({ url in
                  profilePins.contains { $0.launchURL == url } == false
              }) else {
            return false
        }
        guard visualItemCount(
            profilePins: profilePins,
            profileID: profileId
        ) < CapacityPolicy.maxItems else { return false }
        return true
    }

    func resolveInsertion(using context: InsertionContext) -> InsertionPlan? {
        let resolution = resolveTarget(using: context.target)
        guard let profileId = resolution.profileId else { return nil }

        var profilePins = pins.favoritePins(for: profileId)
        if let movingPinId = context.movingPinId,
           let existingIndex = profilePins.firstIndex(where: {
               $0.id == movingPinId
           }) {
            profilePins.remove(at: existingIndex)
        }

        guard visualItemCount(
            profilePins: profilePins,
            profileID: profileId
        ) < CapacityPolicy.maxItems else { return nil }

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

    private func visualItemCount(
        profilePins: [ShortcutPin],
        profileID: UUID
    ) -> Int {
        let pinIDs = Set(profilePins.map(\.id))
        let groups = splitGroups.groups.filter { group in
            guard case .favoriteSidebar(let ownerID, _) = group.container,
                  ownerID == nil || ownerID == profileID else { return false }
            return group.memberIDs.allSatisfy { memberID in
                guard case .shortcutPin(let pinID) = memberID else {
                    return false
                }
                return pinIDs.contains(pinID)
            }
        }
        let groupedPinIDs = Set(groups.flatMap(\.memberIDs).compactMap {
            memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        })
        return profilePins.count - groupedPinIDs.count + groups.count
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
            "⚠️ [Favorite] Fallback profile mismatch visible=\(visibleProfileId.uuidString) resolved=\(resolvedProfileId.uuidString)"
        )
    }
}
