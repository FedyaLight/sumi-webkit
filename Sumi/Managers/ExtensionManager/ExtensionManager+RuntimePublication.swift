import AppKit
import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    /// Routes physical main-window focus without stealing extension focus from
    /// an auxiliary session that is currently the actual key window.
    func focusPublishedWindow(_ windowState: BrowserWindowState) {
        guard runtimePublicationGate.acceptsBrowserEvents else { return }
        if let keyWindow = NSApp.keyWindow,
           let auxiliaryWindows = extensionAuxiliaryWindows,
           let session = auxiliaryWindows.auxiliaryWindowSession(for: keyWindow),
           let receipt = auxiliaryWindows.auxiliaryWindowSessionReceipt(
                for: session
           ) {
            auxiliaryWindows.focusAuxiliaryWindowSession(receipt)
            return
        }

        normalWindowLifecycle.focused(windowState)
        #if DEBUG
            testHooks.didFocusWindow?(windowState.id)
        #endif
    }

    func reloadRuntimePublications(
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false,
        profileID: UUID? = nil
    ) {
        // Runtime publication is a browser-attached capability. Install and
        // enable flows also run while ExtensionManager is intentionally cold;
        // they may load WebKit contexts, but must not assemble a browser graph.
        guard attachedBrowserManager != nil,
              controllerRuntimeComposition != nil
        else {
            return
        }

        let loaded = extensionsLoaded
        guard loaded || allowWhenExtensionsNotLoaded else { return }

        let runtimeSnapshot = runtime
        let windowQuery = extensionWindowQuery
        guard let commit = runtimePublicationReconciler.reload(
            ExtensionRuntimeReloadTransaction.Request(
                reason: reason,
                allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded,
                requestedProfileID: profileID,
                extensionsLoaded: loaded,
                runtime: runtimeSnapshot,
                windowQuery: windowQuery
            ),
            auxiliaryControl: extensionAuxiliaryWindows
        ) else {
            return
        }

        settleRuntimePublicationCommit(commit)
    }

    func settleRuntimePublicationCommit(
        _ commit: ExtensionRuntimeReloadTransaction.Commit
    ) {
        if let activeWindow = commit.activeWindow,
           commit.activeTab != nil {
            focusPublishedWindow(activeWindow)
            guard let target = runtimeReloadTransaction.activationTarget(
                after: commit,
                windowQuery: extensionWindowQuery
            ) else {
                return
            }
            normalTabActivation.activate(target.tab, previous: nil)
        }
    }

    func publishExistingRuntimeWindowsIfAttached() {
        guard runtimePublicationGate.acceptsBrowserEvents,
              let windowQuery = extensionWindowQuery
        else {
            return
        }

        let windows = windowQuery.allExtensionWindowStates
        runtimeDiagnostics.trace(
            "registerExistingWindowState start generation=\(extensionLoadRevisions.issue().generation) windows=\(windows.count) controller=\(ExtensionRuntimeDiagnostics.objectDescription(extensionController))"
        )
        for windowState in windows {
            _ = normalWindowLifecycle.opened(windowState)
        }
        if let activeWindow = windowQuery.activeExtensionWindowState {
            focusPublishedWindow(activeWindow)
        }
        runtimeDiagnostics.trace(
            "registerExistingWindowState complete generation=\(extensionLoadRevisions.issue().generation) windows=\(windows.count)"
        )
    }
}
