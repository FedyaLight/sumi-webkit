import Foundation
import SumiDomain

/// Creates and resolves the temporary blank member used by the “add split”
/// command. The session stores only one placeholder ID per window.
@MainActor
final class EmptySplitService {
    private let tabManager: () -> TabManager?
    private let currentTab: (BrowserWindowState) -> Tab?
    private let memberResolver: SplitRuntimeMemberResolver
    private let dropService: SplitDropService
    private let focusFloatingBar: (
        BrowserWindowState,
        FloatingBarPresentationReason
    ) -> Void
    private let session: EmptySplitSession

    init(
        tabManager: @escaping () -> TabManager?,
        currentTab: @escaping (BrowserWindowState) -> Tab?,
        memberResolver: SplitRuntimeMemberResolver,
        dropService: SplitDropService,
        focusFloatingBar: @escaping (
            BrowserWindowState,
            FloatingBarPresentationReason
        ) -> Void
    ) {
        self.tabManager = tabManager
        self.currentTab = currentTab
        self.memberResolver = memberResolver
        self.dropService = dropService
        self.focusFloatingBar = focusFloatingBar
        session = EmptySplitSession(
            replacePlaceholder: { tab, placeholderTabID, windowState in
                dropService.replacePlaceholder(
                    with: tab,
                    placeholderTabID: placeholderTabID,
                    in: windowState
                )
            },
            removeTab: { tabID in
                tabManager()?.tabRemovalOwner.removeTab(tabID)
            }
        )
    }

    func create(
        side: SplitDropSide,
        in windowState: BrowserWindowState,
        floatingBarReason: FloatingBarPresentationReason
    ) {
        guard let tabManager = tabManager(),
              let current = currentTab(windowState),
              current.representsSumiNativeSurface == false,
              let targetMemberID = memberResolver.memberID(for: current) else {
            return
        }
        let targetSpace = windowState.currentSpaceId.flatMap {
            tabManager.spaceStateOwner.space(with: $0)
        } ?? tabManager.spaceStateOwner.currentSpace
        let placeholder = tabManager.regularTabLifecycleOwner.createNewTab(
            url: SumiSurface.emptyTabURL.absoluteString,
            in: targetSpace,
            activate: false
        )
        guard dropService.drop(
            placeholder,
            on: SplitDropTarget(
                targetMemberID: targetMemberID,
                side: side,
                targetRect: .zero,
                intent: .firstSplit
            ),
            in: windowState
        ) else {
            tabManager.tabRemovalOwner.removeTab(placeholder.id)
            return
        }
        session.register(tabID: placeholder.id, in: windowState.id)
        focusFloatingBar(windowState, floatingBarReason)
    }

    func commit(tabID: UUID, in windowID: UUID) {
        session.commit(tabID: tabID, in: windowID)
    }

    func replace(with tab: Tab, in windowState: BrowserWindowState) -> Bool {
        session.replace(with: tab, in: windowState)
    }

    func cancel(in windowState: BrowserWindowState) -> Bool {
        session.cancel(in: windowState)
    }

    func removeWindow(_ windowID: UUID) {
        session.removeWindow(windowID)
    }
}
