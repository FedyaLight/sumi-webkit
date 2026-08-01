import Foundation

public struct TabSurfaceState: Equatable, Sendable {
    public var isPopupHost = false
    public var isAuxiliaryMiniWindow = false

    public init() {}

    public func representsSumiEmptySurface(for url: URL) -> Bool {
        !isPopupHost && SumiSurface.isEmptyNewTabURL(url)
    }

    public func representsSumiHistorySurface(for url: URL) -> Bool {
        !isPopupHost && SumiSurface.isHistorySurfaceURL(url)
    }

    public func representsSumiBookmarksSurface(for url: URL) -> Bool {
        !isPopupHost && SumiSurface.isBookmarksSurfaceURL(url)
    }

    public func representsSumiNativeSurface(for url: URL) -> Bool {
        representsSumiHistorySurface(for: url)
            || representsSumiBookmarksSurface(for: url)
    }

    public func representsSumiInternalSurface(for url: URL) -> Bool {
        representsSumiNativeSurface(for: url)
    }

    public func requiresPrimaryWebView(for url: URL) -> Bool {
        !representsSumiNativeSurface(for: url) && !representsSumiEmptySurface(for: url)
    }

    public func usesChromeThemedTemplateFavicon(
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
