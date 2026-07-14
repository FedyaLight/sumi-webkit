import Foundation

/// Performs the ordered cleanup for one WindowRegistry removal. It resolves no
/// capabilities through BrowserManager; the weak root reference is only a
/// lifetime gate for collaborators whose internals intentionally weak-hop to
/// the live browser session.
@MainActor
final class BrowserWindowCloseWorkflow {
    private weak var browserRuntime: BrowserManager?
    private let recorder: ClosedWindowHistoryRecorder
    private let persistence: WindowSessionPersistenceCoordinator
    private weak var extensions: SumiExtensionsModule?
    private let webViews: WebViewLifecycleService
    private weak var emptySplitPlaceholders: EmptySplitService?
    private weak var splitPreviews: SplitPreviewSession?
    private weak var backgroundMedia: SumiBackgroundMediaOptimizationService?
    private weak var commands: BrowserWindowCommands?

    init(
        browserRuntime: BrowserManager,
        recorder: ClosedWindowHistoryRecorder,
        persistence: WindowSessionPersistenceCoordinator,
        extensions: SumiExtensionsModule,
        webViews: WebViewLifecycleService,
        emptySplitPlaceholders: EmptySplitService,
        splitPreviews: SplitPreviewSession,
        backgroundMedia: SumiBackgroundMediaOptimizationService,
        commands: BrowserWindowCommands
    ) {
        self.browserRuntime = browserRuntime
        self.recorder = recorder
        self.persistence = persistence
        self.extensions = extensions
        self.webViews = webViews
        self.emptySplitPlaceholders = emptySplitPlaceholders
        self.splitPreviews = splitPreviews
        self.backgroundMedia = backgroundMedia
        self.commands = commands
    }

    @discardableResult
    func handleWindowClose(_ windowState: BrowserWindowState) -> Task<Void, Never>? {
        guard let browserRuntime else {
            webViews.cleanupAfterBrowserRuntimeDeallocation()
            RuntimeDiagnostics.emit(
                "⚠️ [WindowLifecycle] Window \(windowState.id) closed after browser runtime deallocation; terminal WebView cleanup completed"
            )
            return nil
        }

        guard let extensions,
              let emptySplitPlaceholders,
              let splitPreviews,
              let backgroundMedia,
              let commands
        else {
            assertionFailure(
                "A live browser runtime lost a window-close collaborator"
            )
            return nil
        }

        if windowState.isIncognito == false {
            recorder.recordWindowWillClose(windowState)
        }
        persistence.persistBeforeClosing(windowState)
        extensions.notifyWindowClosedIfLoaded(windowState)
        webViews.cleanupWindow(windowState.id)
        emptySplitPlaceholders.removeWindow(windowState.id)
        splitPreviews.removeWindow(windowState.id)
        backgroundMedia.scheduleReconcile(reason: "window-closed")

        guard windowState.isIncognito else { return nil }

        return Task { @MainActor [browserRuntime, commands] in
            _ = browserRuntime
            await commands.closeIncognitoWindow(windowState)
        }
    }
}
