import SumiDomain
import SwiftUI

struct SidebarShortcutIconPresentation {
    /// Emoji the user picked for the pin, rendered as text.
    let glyphText: String?
    /// Template symbol, used when there is no favicon to show.
    let systemImageName: String?
    /// Resolved favicon, from the stored cache or the live tab.
    let image: Image?
}

/// The one place that decides which icon a shortcut shows.
///
/// The sidebar row and the collapsed-folder preview panel both render the same
/// pin, so they resolve it here rather than each keeping a copy of the chain —
/// a second copy is how the panel ended up without the live tab's favicon and
/// fell back to a globe.
@MainActor
enum SidebarShortcutIconResolver {
    static func resolve(
        pin: ShortcutPin,
        liveTab: Tab?,
        loadedStoredFavicon: Image?,
        partition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading
    ) -> SidebarShortcutIconPresentation {
        if let iconAsset = pin.iconAsset {
            if SumiPersistentGlyph.presentsAsEmoji(iconAsset) {
                return SidebarShortcutIconPresentation(
                    glyphText: iconAsset,
                    systemImageName: nil,
                    image: nil
                )
            }
            return SidebarShortcutIconPresentation(
                glyphText: nil,
                systemImageName: SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset),
                image: nil
            )
        }

        let cachedStoredFavicon = loadedStoredFavicon ?? ShortcutPin.cachedLaunchFavicon(
            for: pin.launchURL,
            partition: partition,
            imageReader: imageReader
        )

        if let systemImageName = templateSystemImageName(
            pin: pin,
            liveTab: liveTab,
            loadedStoredFavicon: loadedStoredFavicon,
            cachedStoredFavicon: cachedStoredFavicon,
            partition: partition,
            imageReader: imageReader
        ) {
            return SidebarShortcutIconPresentation(
                glyphText: nil,
                systemImageName: systemImageName,
                image: nil
            )
        }

        return SidebarShortcutIconPresentation(
            glyphText: nil,
            systemImageName: nil,
            image: favicon(
                pin: pin,
                liveTab: liveTab,
                cachedStoredFavicon: cachedStoredFavicon,
                partition: partition,
                imageReader: imageReader
            )
        )
    }

    private static func favicon(
        pin: ShortcutPin,
        liveTab: Tab?,
        cachedStoredFavicon: Image?,
        partition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading
    ) -> Image {
        if let cachedStoredFavicon {
            return cachedStoredFavicon
        }
        if let liveTab, !liveTab.faviconIsTemplateGlobePlaceholder {
            return liveTab.favicon
        }
        return pin.storedFaviconImage(
            partition: partition,
            imageReader: imageReader
        )
    }

    private static func templateSystemImageName(
        pin: ShortcutPin,
        liveTab: Tab?,
        loadedStoredFavicon: Image?,
        cachedStoredFavicon: Image?,
        partition: SumiFaviconPartition,
        imageReader: any BrowserFaviconImageReading
    ) -> String? {
        if let liveTab {
            if SumiSurface.isSettingsSurfaceURL(liveTab.url) {
                return SumiSurface.settingsTabFaviconSystemImageName
            }
            if cachedStoredFavicon != nil {
                return nil
            }
            if liveTab.faviconIsTemplateGlobePlaceholder {
                return SumiPersistentGlyph.launcherSystemImageFallback
            }
            return nil
        }
        if loadedStoredFavicon != nil {
            return nil
        }
        return pin.storedChromeTemplateSystemImageName(
            for: partition,
            imageReader: imageReader
        )
    }
}
