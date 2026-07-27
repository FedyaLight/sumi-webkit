import Foundation

@MainActor
final class SidebarShortcutEditorPresentationService {
    private let settings: BrowserSettingsAttachmentCoordinator
    private let pins: ShortcutPinCollectionStateOwner
    private let pinCommands: SidebarPinCommands
    private let faviconImages: any BrowserFaviconImageReading
    private let presenter: ShortcutEditorPopoverPresenter

    init(
        settings: BrowserSettingsAttachmentCoordinator,
        pins: ShortcutPinCollectionStateOwner,
        pinCommands: SidebarPinCommands,
        faviconImages: any BrowserFaviconImageReading,
        presenter: ShortcutEditorPopoverPresenter
    ) {
        self.settings = settings
        self.pins = pins
        self.pinCommands = pinCommands
        self.faviconImages = faviconImages
        self.presenter = presenter
    }

    func show(
        pin: ShortcutPin,
        in windowState: BrowserWindowState,
        themeContext: ResolvedThemeContext,
        source: SidebarTransientPresentationSource
    ) {
        guard let settings = settings.settings else { return }
        presenter.present(
            pin: pin,
            in: windowState,
            themeContext: themeContext,
            presentationContext: ShortcutEditorPopoverPresentationContext(
                sidebarPosition: settings.sidebarPosition,
                settings: settings,
                faviconImageReader: faviconImages,
                commit: { [weak self] in self?.commit($0) }
            ),
            source: source
        )
    }

    func commit(_ session: ShortcutLinkEditorSession) {
        guard session.hasChanges,
              let launchURL = session.normalizedURL,
              let currentPin = pins.shortcutPin(by: session.pin.id)
        else { return }
        let titleChanged = session.effectiveTitle != session.pin.title
        let urlChanged = launchURL != session.pin.launchURL
        let iconChanged = session.iconAsset != session.pin.iconAsset
        _ = pinCommands.update(
            currentPin,
            title: titleChanged ? session.effectiveTitle : currentPin.title,
            launchURL: urlChanged ? launchURL : currentPin.launchURL,
            iconAsset: iconChanged ? session.iconAsset : currentPin.iconAsset,
            titleIsCustom: titleChanged
                ? session.resolvedTitleIsCustom
                : currentPin.titleIsCustom
        )
    }
}
