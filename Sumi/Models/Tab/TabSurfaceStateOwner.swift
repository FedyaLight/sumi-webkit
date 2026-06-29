import Foundation

@MainActor
final class TabSurfaceStateOwner {
    var isPopupHost = false
    var isAuxiliaryMiniWindow = false

    func representsSumiEmptySurface(for url: URL) -> Bool {
        !isPopupHost && SumiSurface.isEmptyNewTabURL(url)
    }

    func representsSumiSettingsSurface(for url: URL) -> Bool {
        !isPopupHost && SumiSurface.isSettingsSurfaceURL(url)
    }

    func representsSumiHistorySurface(for url: URL) -> Bool {
        !isPopupHost && SumiSurface.isHistorySurfaceURL(url)
    }

    func representsSumiBookmarksSurface(for url: URL) -> Bool {
        !isPopupHost && SumiSurface.isBookmarksSurfaceURL(url)
    }

    func representsSumiNativeSurface(for url: URL) -> Bool {
        representsSumiSettingsSurface(for: url)
            || representsSumiHistorySurface(for: url)
            || representsSumiBookmarksSurface(for: url)
    }

    func representsSumiInternalSurface(for url: URL) -> Bool {
        representsSumiNativeSurface(for: url)
    }

    func requiresPrimaryWebView(for url: URL) -> Bool {
        !representsSumiNativeSurface(for: url) && !representsSumiEmptySurface(for: url)
    }

    func usesChromeThemedTemplateFavicon(
        for url: URL,
        faviconIsTemplateGlobePlaceholder: Bool
    ) -> Bool {
        !isPopupHost
            && (
                representsSumiEmptySurface(for: url)
                    || representsSumiInternalSurface(for: url)
                    || faviconIsTemplateGlobePlaceholder
            )
    }
}
