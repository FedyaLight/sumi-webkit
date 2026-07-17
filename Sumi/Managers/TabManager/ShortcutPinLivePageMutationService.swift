import Foundation
import SumiDomain

@MainActor
final class ShortcutPinLivePageMutationService {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let pins: ShortcutPinCollectionStateOwner
    private let presentation: TabShortcutPresentationOwner
    private let preservation: ShortcutLivePagePreservationTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        pins: ShortcutPinCollectionStateOwner,
        presentation: TabShortcutPresentationOwner,
        preservation: ShortcutLivePagePreservationTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.pins = pins
        self.presentation = presentation
        self.preservation = preservation
    }

    func liveTab(
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Tab? {
        presentation.shortcutLiveTab(for: pin.id, in: windowState.id)
    }

    func reset(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        preserveCurrentPage: Bool
    ) -> ShortcutPin? {
        structuralLookup.withTransaction {
            guard self.pins.shortcutPin(by: pin.id) === pin else { return nil }
            guard let liveTab = liveTab(for: pin, in: windowState) else {
                return nil
            }
            if preserveCurrentPage,
               liveTab.url.absoluteString != pin.launchURL.absoluteString,
               preservation.preserveCurrentPage(
                    from: liveTab,
                    for: pin,
                    in: windowState
               ) == false {
                return nil
            }
            _ = liveTab.acceptResolvedDisplayTitle(
                pin.title,
                url: pin.launchURL
            )
            liveTab.url = pin.launchURL
            liveTab.loadURL(pin.launchURL)
            return pin
        }
    }
}
