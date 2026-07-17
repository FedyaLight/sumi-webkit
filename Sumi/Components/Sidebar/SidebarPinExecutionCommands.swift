import Foundation

@MainActor
final class SidebarPinExecutionCommands {
    private let runtime: TabRuntimePortConnection
    private let windows: SidebarWindowIdentityQuery
    private let pins: ShortcutPinCollectionStateOwner
    private let materializer: ShortcutTabMaterializer
    private let profiles: ShortcutExecutionProfileAssignmentService

    init(
        runtime: TabRuntimePortConnection,
        windows: SidebarWindowIdentityQuery,
        pins: ShortcutPinCollectionStateOwner,
        materializer: ShortcutTabMaterializer,
        profiles: ShortcutExecutionProfileAssignmentService
    ) {
        self.runtime = runtime
        self.windows = windows
        self.pins = pins
        self.materializer = materializer
        self.profiles = profiles
    }

    func assignExecutionProfile(_ pin: ShortcutPin, profileID: UUID) -> Bool {
        guard let pin = current(pin) else { return false }
        return profiles.assign(pin, toExecutionProfile: profileID) != nil
    }

    func materialize(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        currentSpaceID: UUID?
    ) -> Tab? {
        guard let pin = current(pin), windows.contains(windowState) else { return nil }
        return materializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: currentSpaceID
        )
    }

    private func current(_ pin: ShortcutPin) -> ShortcutPin? {
        guard runtime.current != nil,
              let current = pins.shortcutPin(by: pin.id),
              current === pin else { return nil }
        return current
    }
}
