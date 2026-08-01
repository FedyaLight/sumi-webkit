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
        loadedStoredFavicon: Image?
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

        if let loadedStoredFavicon {
            return SidebarShortcutIconPresentation(
                glyphText: nil,
                systemImageName: nil,
                image: loadedStoredFavicon
            )
        }

        if let liveTab, !liveTab.faviconIsTemplateGlobePlaceholder {
            return SidebarShortcutIconPresentation(
                glyphText: nil,
                systemImageName: nil,
                image: liveTab.favicon
            )
        }

        return SidebarShortcutIconPresentation(
            glyphText: nil,
            systemImageName: SumiPersistentGlyph.launcherSystemImageFallback,
            image: nil
        )
    }
}
