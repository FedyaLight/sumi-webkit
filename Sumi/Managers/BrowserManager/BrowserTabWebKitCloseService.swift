import SumiWebRuntime
import WebKit

@MainActor
protocol WebKitChildWindowClosing: AnyObject {
    func closeIfDedicatedChild(_ target: TrackedWebKitCloseTarget) -> Bool
}

@MainActor
protocol BrowserWebKitCloseCommanding: AnyObject {
    func closeTrackedTab(_ target: TrackedWebKitCloseTarget)
    func closeUntrackedTab(_ target: UntrackedWebKitCloseTarget)
    func discardStaleTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    )
    func discardOrphanWebView(_ webView: WKWebView)
}

/// Applies one already-resolved WebKit close target. Physical target
/// resolution and dedicated child-window policy are separate collaborators,
/// so this coordinator cannot grow back into a browser-runtime closure bag.
@MainActor
final class BrowserTabWebKitCloseService {
    private let targets: any WebKitCloseTargetResolving
    private let childWindows: any WebKitChildWindowClosing
    private let commands: any BrowserWebKitCloseCommanding

    init(
        targets: any WebKitCloseTargetResolving,
        childWindows: any WebKitChildWindowClosing,
        commands: any BrowserWebKitCloseCommanding
    ) {
        self.targets = targets
        self.childWindows = childWindows
        self.commands = commands
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        switch targets.resolve(webView) {
        case .deferred:
            break
        case .tracked(let target):
            if childWindows.closeIfDedicatedChild(target) == false {
                commands.closeTrackedTab(target)
            }
        case .untracked(let target):
            commands.closeUntrackedTab(target)
        case .staleTracked(let owner):
            commands.discardStaleTrackedWebView(webView, owner: owner)
        case .orphan:
            commands.discardOrphanWebView(webView)
        }
        return true
    }
}
