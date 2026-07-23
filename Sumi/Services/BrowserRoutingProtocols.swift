import AppKit
import SwiftData

@MainActor
protocol BrowserMouseButtonCommandRouting: AnyObject {
    func focusCommandPalette(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    )
    func goBack(in windowState: BrowserWindowState)
    func goForward(in windowState: BrowserWindowState)
}

@MainActor
protocol BrowserWindowLifecycleHandling: AnyObject {
    func persistWindowSession(for windowState: BrowserWindowState)
}

@MainActor
protocol ExternalURLHandling: AnyObject {
    func presentExternalURL(_ url: URL)
}

@MainActor
protocol BrowserTerminationCoordinating: AnyObject {
    /// Closes transient browser UI before an optional quit confirmation is shown.
    func prepareForTermination()

    /// Synchronously promotes the weak runtime boundary into the one strong
    /// lease captured by AppKit's asynchronous finalizer.
    func acquireFinalizationLease() -> (any BrowserTerminationFinalizing)?
}

@MainActor
protocol BrowserTerminationFinalizing: AnyObject {
    func finalizeTermination() async
}
