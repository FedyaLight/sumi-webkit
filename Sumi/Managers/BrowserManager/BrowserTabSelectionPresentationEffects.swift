import Foundation

@MainActor
final class BrowserTabSelectionPresentationEffects {
    private let chrome: BrowserTabSelectionChromeEffects
    private let media: BrowserTabSelectionMediaEffects

    init(
        chrome: BrowserTabSelectionChromeEffects,
        media: BrowserTabSelectionMediaEffects
    ) {
        self.chrome = chrome
        self.media = media
    }

    func prepare(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        previousSpaceID: UUID?,
        updateTheme: Bool,
        reconcileSplitSelection: Bool
    ) {
        media.prepare(tab)
        chrome.publish(
            tab,
            in: windowState,
            previousSpaceID: previousSpaceID,
            updateTheme: updateTheme,
            reconcileSplitSelection: reconcileSplitSelection
        )
    }

    func publish(_ tab: Tab, in windowState: BrowserWindowState) {
        media.publish(tab, in: windowState)
    }

    func publishEmptyState(in windowState: BrowserWindowState) {
        chrome.publishEmptyState(in: windowState)
        media.publishEmptyState(in: windowState)
    }
}
