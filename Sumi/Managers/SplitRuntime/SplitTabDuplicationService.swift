import Foundation

/// Materializes launcher-backed pages as regular tabs when a split cannot
/// stay in one launcher container. The launcher remains canonical; the copy is
/// the member owned by the regular split, matching Zen's duplication model.
@MainActor
final class SplitTabDuplicationService {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: TabRegularLifecycleOwner
    private let closure: TabClosureService

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: TabRegularLifecycleOwner,
        closure: TabClosureService
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.closure = closure
    }

    func duplicate(
        _ source: Tab,
        in windowState: BrowserWindowState
    ) -> Tab {
        let targetSpace = windowState.currentSpaceId.flatMap(spaces.space(with:))
            ?? spaces.currentSpace
        return duplicate(source, in: targetSpace)
    }

    func duplicate(
        _ source: Tab,
        into spaceID: UUID,
        in _: BrowserWindowState
    ) -> Tab {
        duplicate(source, in: spaces.space(with: spaceID) ?? spaces.currentSpace)
    }

    private func duplicate(_ source: Tab, in targetSpace: Space?) -> Tab {
        return regularTabs.createNewTab(
            url: source.url.absoluteString,
            in: targetSpace,
            activate: false,
            executionProfileID: source.profileId,
            prepareBeforePublication: { copy in
                copy.name = source.name
                copy.faviconPresentation = source.faviconPresentation
                copy.faviconIsTemplateGlobePlaceholder =
                    source.faviconIsTemplateGlobePlaceholder
                copy.profileId = source.profileId
            }
        )
    }

    func discard(_ tab: Tab) {
        guard let spaceID = tab.spaceId else { return }
        _ = closure.removeExactRegularTab(tab, in: spaceID)
    }
}
