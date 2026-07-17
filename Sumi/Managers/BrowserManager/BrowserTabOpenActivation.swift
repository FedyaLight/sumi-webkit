import Foundation

@MainActor
final class BrowserTabOpenActivation {
    private let selection: BrowserTabSelectionOwner
    private let startupProtection: BrowserStartupProtectionRuntime
    private let membership: TabCollectionMembershipOwner
    private let windows: WindowRegistry

    init(
        selection: BrowserTabSelectionOwner,
        startupProtection: BrowserStartupProtectionRuntime,
        membership: TabCollectionMembershipOwner,
        windows: WindowRegistry
    ) {
        self.selection = selection
        self.startupProtection = startupProtection
        self.membership = membership
        self.windows = windows
    }

    func apply(
        _ policy: BrowserTabOpenActivationPolicy,
        to tab: Tab,
        resolvedWindow: BrowserWindowState?
    ) {
        switch policy {
        case let .foreground(windowState, loadPolicy):
            _ = selection.selectTab(
                tab,
                in: windowState,
                loadPolicy: loadPolicy
            )
        case .background:
            prepareBackgroundTabIfNeeded(tab)
        }
    }

    func selectAfterSidebarInsertion(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        guard let windowReceipt = windows.registrationReceipt(
            for: windowState
        ) else {
            return
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SidebarDropMotion.contentLayoutDuration
        ) { [weak self, weak tab] in
            guard let self,
                  let tab,
                  membership.tab(for: tab.id) === tab,
                  let currentWindow = windows.window(
                      ifCurrent: windowReceipt
                  ) else {
                return
            }
            _ = selection.selectTab(
                tab,
                in: currentWindow,
                loadPolicy: .deferred
            )
        }
    }

    func prepareBackgroundTabIfNeeded(_ tab: Tab) {
        guard tab.requiresPrimaryWebView else { return }
        guard startupProtection.canMaterializeWebViewDuringStartup(tab) else {
            startupProtection.deferBackgroundTabUntilStartupReady(tab)
            return
        }
        tab.loadWebViewIfNeeded()
    }
}
