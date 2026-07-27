import Foundation

@MainActor
final class SidebarShortcutEditorPresentationService {
    private let settings: BrowserSettingsAttachmentCoordinator
    private let pinCommands: SidebarPinCommands
    private let faviconImages: any BrowserFaviconImageReading
    private let presenter: ShortcutEditorPopoverPresenter

    init(
        settings: BrowserSettingsAttachmentCoordinator,
        pinCommands: SidebarPinCommands,
        faviconImages: any BrowserFaviconImageReading,
        presenter: ShortcutEditorPopoverPresenter
    ) {
        self.settings = settings
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
              let launchURL = session.normalizedURL else { return }
        _ = pinCommands.update(
            session.pin,
            title: session.effectiveTitle,
            launchURL: launchURL,
            iconAsset: session.iconAsset,
            titleIsCustom: session.resolvedTitleIsCustom
        )
    }
}
