import Foundation
import SumiDomain

@MainActor
struct ShortcutSplitLauncherReleasePlacement {
    let pin: ShortcutSplitLauncherCatalogPinReceipt
    let destination: ShortcutSplitLauncherDestination
}

/// Admits the no-move case only while every released split member retains its
/// exact durable launcher placement.
@MainActor
final class ShortcutSplitLauncherReleasePlanner {
    private let pins: ShortcutPinCollectionStateOwner
    private let destinationResolver: ShortcutSplitLauncherDestinationResolver

    init(
        pins: ShortcutPinCollectionStateOwner,
        destinationResolver: ShortcutSplitLauncherDestinationResolver
    ) {
        self.pins = pins
        self.destinationResolver = destinationResolver
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
                  let pin = pins.shortcutPin(by: pinID),
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
            planner: self,
            placements: placements
        )
    }

    func accepts(_ placements: [ShortcutSplitLauncherReleasePlacement]) -> Bool {
        placements.allSatisfy { placement in
            guard let pin = pins.shortcutPin(by: placement.pin.pin.id) else {
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
