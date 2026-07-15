import Foundation

/// Browser facts and publication effects used by one action invocation. The
/// projection resolves values and performs registration; it cannot expose the
/// attached graph or any mutable browser service.
@available(macOS 15.5, *)
@MainActor
protocol ExtensionActionInvocationBrowserProjection: AnyObject {
    func actionInvocationTabs() -> [Tab]
    func actionInvocationProfileID(for tab: Tab) -> UUID?
    func actionInvocationPrimaryWindowID(for tab: Tab) -> UUID?
    func actionInvocationActiveWindowID() -> UUID?
    func actionInvocationStableAdapter(for tab: Tab) -> ExtensionTabAdapter?
    func registerActionInvocationTab(_ tab: Tab, reason: String)
}
