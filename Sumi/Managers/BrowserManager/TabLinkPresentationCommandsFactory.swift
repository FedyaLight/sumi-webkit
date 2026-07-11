import Foundation

@MainActor
enum TabLinkPresentationCommandsFactory {
    static func make(
        sourceResolver: PhysicalWebViewSourceResolver,
        openTab: @escaping TabLinkPresentationCommands.OpenTab,
        openWindow: @escaping TabLinkPresentationCommands.OpenWindow,
        activateSource: @escaping TabLinkPresentationCommands.ActivateSource,
        presentGlance: @escaping TabLinkPresentationCommands.PresentGlance
    ) -> TabLinkPresentationCommands {
        TabLinkPresentationCommands(
            resolveSource: { [sourceResolver] webView in
                sourceResolver.resolve(webView)
            },
            openTab: openTab,
            openWindow: openWindow,
            activateSource: activateSource,
            presentGlance: presentGlance
        )
    }
}
