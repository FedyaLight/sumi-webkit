import Foundation

/// Immutable page authority captured from the shortcut's presentation
/// container before its execution profile is applied to the live tab.
struct LiveShortcutPresentationPageReceipt: Equatable, Sendable {
    let page: TabStructurePageScope

    init(windowID: UUID, spaceID: UUID, profileID: UUID?) {
        page = TabStructurePageScope(
            windowID: windowID,
            spaceID: spaceID,
            profileID: profileID
        )
    }
}

/// Exact physical registry residence and its immutable presentation page.
@MainActor
struct LiveShortcutTabEntry {
    let windowId: UUID
    let pinId: UUID
    let tab: Tab
    let presentationPage: LiveShortcutPresentationPageReceipt

    var pageScope: TabStructureChangeScope {
        .page(presentationPage.page)
    }

    func isIdentical(to other: LiveShortcutTabEntry) -> Bool {
        windowId == other.windowId
            && pinId == other.pinId
            && tab === other.tab
            && presentationPage == other.presentationPage
    }
}
