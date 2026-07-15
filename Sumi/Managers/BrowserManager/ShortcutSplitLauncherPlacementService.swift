import SumiDomain

/// Restores only durable shortcut-container placement and cannot mutate window
/// selection or resolve dependencies through a manager façade.
@MainActor
final class ShortcutSplitLauncherPlacementService {
    private let shortcutPin: (UUID) -> ShortcutPin?
    private let destinationResolver: ShortcutSplitLauncherDestinationResolver
    private let moves: ShortcutSplitLauncherMoveTransaction

    init(
        shortcutPin: @escaping (UUID) -> ShortcutPin?,
        destinationResolver: ShortcutSplitLauncherDestinationResolver,
        moves: ShortcutSplitLauncherMoveTransaction
    ) {
        self.shortcutPin = shortcutPin
        self.destinationResolver = destinationResolver
        self.moves = moves
    }

    func prepareRestoration(
        for member: SplitMember
    ) -> PreparedShortcutSplitLauncherRestoration? {
        guard case .shortcutPin(let pinID) = member.memberID,
              let pin = shortcutPin(pinID),
              let destination = destinationResolver.destination(
                  for: member,
                  pin: pin
              ), moves.accepts(pin, destination: destination)
        else {
            return nil
        }
        return PreparedShortcutSplitLauncherRestoration(
            pin: pin,
            destination: destination
        )
    }

    func prepareRestorations(
        for members: [SplitMember]
    ) -> [PreparedShortcutSplitLauncherRestoration]? {
        let shortcutMembers = members.filter {
            if case .shortcutPin = $0.memberID { return true }
            return false
        }
        let restorations = shortcutMembers.compactMap(prepareRestoration(for:))
        guard restorations.count == shortcutMembers.count,
              Set(restorations.map { $0.pin.id }).count == restorations.count else {
            return nil
        }
        return restorations
    }

    func prepareNoMoveRelease(
        for members: [SplitMember]
    ) -> ShortcutSplitLauncherReleaseReceipt? {
        let shortcutMembers = members.filter {
            if case .shortcutPin = $0.memberID { return true }
            return false
        }
        var placements: [ShortcutSplitLauncherReleasePlacement] = []
        for member in shortcutMembers {
            guard case .shortcutPin(let pinID) = member.memberID,
                  let pin = shortcutPin(pinID),
                  let destination = destinationResolver.destination(
                      for: member,
                      pin: pin
                  ), Self.matches(pin, destination) else { return nil }
            placements.append(ShortcutSplitLauncherReleasePlacement(
                pin: ShortcutSplitLauncherCatalogPinReceipt(pin),
                destination: destination
            ))
        }
        guard Set(placements.map { $0.pin.pin.id }).count == placements.count
        else { return nil }
        return ShortcutSplitLauncherReleaseReceipt(
            placementService: self,
            placements: placements
        )
    }

    @discardableResult
    func applyAndCommit(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> Bool {
        guard let receipt = apply(restorations),
              receipt.settleModel() else { return false }
        receipt.commit()
        return true
    }

    /// Applies a preflighted batch without scheduling persistence. The caller
    /// must invoke this inside the same structural transaction as the split
    /// mutation. Unexpected catalog drift is rolled back before reporting
    /// failure.
    func apply(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> RegularTabShortcutSidebarMutation? {
        moves.stage(restorations)
    }

    func applyForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> RegularTabShortcutSidebarMutation? {
        moves.stageForComposedResidenceAggregate(restorations)
    }

    func mutationPreparation(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> RegularTabShortcutSidebarMutationPreparation {
        .launcher(transaction: moves, restorations: restorations)
    }

    func acceptsRelease(
        _ placements: [ShortcutSplitLauncherReleasePlacement]
    ) -> Bool {
        placements.allSatisfy { placement in
            guard let pin = shortcutPin(placement.pin.pin.id) else {
                return false
            }
            return placement.pin.accepts(pin)
                && Self.matches(pin, placement.destination)
        }
    }

    private static func matches(
        _ pin: ShortcutPin,
        _ destination: ShortcutSplitLauncherDestination
    ) -> Bool {
        pin.role == destination.role
            && pin.profileId == destination.profileId
            && pin.spaceId == destination.spaceId
            && pin.folderId == destination.folderId
            && pin.index == destination.index
    }
}

@MainActor
struct ShortcutSplitLauncherReleasePlacement {
    let pin: ShortcutSplitLauncherCatalogPinReceipt
    let destination: ShortcutSplitLauncherDestination
}

/// Exact proof that released shortcut members retain their durable launcher
/// placements and therefore require no catalog or residence mutation.
@MainActor
final class ShortcutSplitLauncherReleaseReceipt {
    private let placementService: ShortcutSplitLauncherPlacementService
    private let placements: [ShortcutSplitLauncherReleasePlacement]

    init(
        placementService: ShortcutSplitLauncherPlacementService,
        placements: [ShortcutSplitLauncherReleasePlacement]
    ) {
        self.placementService = placementService
        self.placements = placements
    }

    func isCurrent() -> Bool {
        placementService.acceptsRelease(placements)
    }
}
