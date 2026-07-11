import Foundation
import WebKit
import SumiWebRuntime

/// Window-scoped browser capabilities consumed by WebView services. This is
/// immutable composition input, not a runtime locator: the graph distributes
/// the individual closures to the concrete consumers that need them.
@MainActor
struct WebViewWindowServices {
    let liveWindowIDs: @MainActor @Sendable () -> Set<UUID>
    let containsWindow: @MainActor @Sendable (UUID) -> Bool
    let currentTabID: @MainActor @Sendable (UUID) -> UUID?
    let selectTab: @MainActor @Sendable (_ tabID: UUID, _ windowID: UUID) -> Void
    let refreshCompositor: @MainActor @Sendable (UUID) -> Void
    let notifyTabActivatedIfCurrent: @MainActor @Sendable (
        _ tab: Tab,
        _ windowID: UUID
    ) -> Void
}

/// Browser actions replayed after compositor protection releases. Validation
/// and execution stay explicit so deferred commands cannot reach unrelated
/// browser state through a general-purpose context.
@MainActor
struct DeferredWebViewServices {
    let handleWebKitClose: @MainActor @Sendable (WKWebView) -> Bool
    let executeProfileAssignment: @MainActor @Sendable (
        UUID,
        UUID?,
        DeferredWebViewProfileAssignmentIntent
    ) -> Bool
    let validateSpaceProfileAssignment: @MainActor @Sendable (
        DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool
    let executeSpaceProfileAssignment: @MainActor @Sendable (
        DeferredWebViewSpaceProfileAssignmentIntent
    ) -> Bool
}
