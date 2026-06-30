import AppKit
import Foundation
import WebKit

struct SumiWindowVisibilityState: Equatable {
    var hasAttachedWindow: Bool
    var isVisible: Bool
    var isMiniaturized: Bool
    var isOccluded: Bool

    static let unknown = Self(
        hasAttachedWindow: false,
        isVisible: true,
        isMiniaturized: false,
        isOccluded: false
    )

    init(
        hasAttachedWindow: Bool,
        isVisible: Bool,
        isMiniaturized: Bool,
        isOccluded: Bool
    ) {
        self.hasAttachedWindow = hasAttachedWindow
        self.isVisible = isVisible
        self.isMiniaturized = isMiniaturized
        self.isOccluded = isOccluded
    }

    @MainActor
    init(window: NSWindow?) {
        guard let window else {
            self = .unknown
            return
        }

        self.init(
            hasAttachedWindow: true,
            isVisible: window.isVisible,
            isMiniaturized: window.isMiniaturized,
            isOccluded: !window.occlusionState.contains(.visible)
        )
    }

    var isEffectivelyVisible: Bool {
        guard hasAttachedWindow else { return true }
        return isVisible && !isMiniaturized && !isOccluded
    }
}

enum SumiBackgroundMediaOptimizationMode: String, Equatable {
    case visible
    case hiddenPreserveAudio
    case hiddenPauseSilentVideo
}

struct SumiBackgroundMediaOptimizationPolicy: Equatable {
    static let defaultHiddenGraceInterval: TimeInterval = 10
    static let energySaverHiddenGraceInterval: TimeInterval = 2

    var hiddenGraceInterval: TimeInterval

    static func make(energySaverActive: Bool) -> Self {
        Self(
            hiddenGraceInterval: energySaverActive
                ? energySaverHiddenGraceInterval
                : defaultHiddenGraceInterval
        )
    }

    func mode(
        isVisible: Bool,
        isEligible: Bool,
        isAudible: Bool
    ) -> SumiBackgroundMediaOptimizationMode {
        guard !isVisible, isEligible else { return .visible }
        return isAudible ? .hiddenPreserveAudio : .hiddenPauseSilentVideo
    }

    var hiddenGraceMilliseconds: Int {
        Int((max(0, hiddenGraceInterval) * 1000).rounded())
    }
}

private struct SumiBackgroundMediaOptimizationCommand: Equatable {
    let mode: SumiBackgroundMediaOptimizationMode
    let graceMilliseconds: Int
}

@MainActor
struct SumiBackgroundMediaOptimizationRuntime {
    typealias JavaScriptCommandExecutor = @MainActor (
        _ webView: WKWebView,
        _ source: String,
        _ arguments: [String: Any]
    ) -> Void

    let webViewCoordinator: () -> WebViewCoordinator?
    let energySaverActive: () -> Bool
    let allKnownTabs: () -> [Tab]
    let visibleTabIDsByWindow: () -> [UUID: Set<UUID>]
    let executeJavaScriptCommand: JavaScriptCommandExecutor

    init(
        webViewCoordinator: @escaping @MainActor () -> WebViewCoordinator?,
        energySaverActive: @escaping @MainActor () -> Bool,
        allKnownTabs: @escaping @MainActor () -> [Tab],
        visibleTabIDsByWindow: @escaping @MainActor () -> [UUID: Set<UUID>],
        executeJavaScriptCommand: @escaping JavaScriptCommandExecutor =
            SumiBackgroundMediaOptimizationRuntime.defaultJavaScriptCommandExecutor
    ) {
        self.webViewCoordinator = webViewCoordinator
        self.energySaverActive = energySaverActive
        self.allKnownTabs = allKnownTabs
        self.visibleTabIDsByWindow = visibleTabIDsByWindow
        self.executeJavaScriptCommand = executeJavaScriptCommand
    }

    static let defaultJavaScriptCommandExecutor: JavaScriptCommandExecutor = { webView, source, arguments in
        webView.callAsyncJavaScript(
            source,
            arguments: arguments,
            in: nil,
            in: .defaultClient,
            completionHandler: nil
        )
    }
}

@MainActor
final class SumiBackgroundMediaOptimizationService {
    private var runtime: SumiBackgroundMediaOptimizationRuntime?
    private var energySaverPolicyObserver: NSObjectProtocol?
    private var scheduledReconcileTask: Task<Void, Never>?
    private var pendingReasons: [String] = []
    private var didTruncatePendingReasons = false
    private var appliedCommandsByWebView: [ObjectIdentifier: SumiBackgroundMediaOptimizationCommand] = [:]

    init() {
        energySaverPolicyObserver = NotificationCenter.default.addObserver(
            forName: .sumiEnergySaverPolicyChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleReconcile(reason: "energy-saver-policy-changed")
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            scheduledReconcileTask?.cancel()
            if let energySaverPolicyObserver {
                NotificationCenter.default.removeObserver(energySaverPolicyObserver)
            }
        }
    }

    func attach(runtime: SumiBackgroundMediaOptimizationRuntime) {
        self.runtime = runtime
    }

    func scheduleReconcile(reason: String) {
        notePendingReason(reason)
        guard scheduledReconcileTask == nil else { return }

        scheduledReconcileTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }

            let reasons = self.pendingReasons
            let didTruncate = self.didTruncatePendingReasons
            self.pendingReasons.removeAll()
            self.didTruncatePendingReasons = false
            self.scheduledReconcileTask = nil

            self.reconcileNow(
                reason: didTruncate
                    ? "\(reasons.joined(separator: ",")).truncated"
                    : reasons.joined(separator: ",")
            )
        }
    }

    func reconcileNow(reason: String) {
        guard let runtime,
              let coordinator = runtime.webViewCoordinator()
        else { return }

        if shouldResetAppliedCommands(for: reason) {
            appliedCommandsByWebView.removeAll()
        }

        let policy = SumiBackgroundMediaOptimizationPolicy.make(
            energySaverActive: runtime.energySaverActive()
        )
        let visibleTabIDsByWindow = runtime.visibleTabIDsByWindow()
        var liveWebViewIDs = Set<ObjectIdentifier>()

        for tab in runtime.allKnownTabs() {
            let entries = liveWebViewEntries(for: tab, coordinator: coordinator)
            guard !entries.isEmpty else { continue }

            for entry in entries {
                liveWebViewIDs.insert(ObjectIdentifier(entry.webView))
                let mode = policy.mode(
                    isVisible: isVisible(tab: tab, in: entry.windowID, visibleTabIDsByWindow: visibleTabIDsByWindow),
                    isEligible: isEligibleForOptimization(tab: tab, webView: entry.webView),
                    isAudible: tab.audioState.isPlayingAudio || entry.webView.sumiAudioIsPlayingAudio
                )

                apply(
                    mode: mode,
                    graceMilliseconds: policy.hiddenGraceMilliseconds,
                    to: entry.webView,
                    reason: reason,
                    runtime: runtime
                )
            }
        }

        appliedCommandsByWebView = appliedCommandsByWebView.filter { liveWebViewIDs.contains($0.key) }
    }

    private func apply(
        mode: SumiBackgroundMediaOptimizationMode,
        graceMilliseconds: Int,
        to webView: WKWebView,
        reason: String,
        runtime: SumiBackgroundMediaOptimizationRuntime
    ) {
        let command = SumiBackgroundMediaOptimizationCommand(
            mode: mode,
            graceMilliseconds: graceMilliseconds
        )
        let webViewID = ObjectIdentifier(webView)
        guard appliedCommandsByWebView[webViewID] != command else { return }
        appliedCommandsByWebView[webViewID] = command

        let source = """
        if (window.__sumiBackgroundVideoOptimizer) {
            window.__sumiBackgroundVideoOptimizer.setNativeVisibility(mode, graceMs, reason);
        }
        """
        let arguments: [String: Any] = [
            "mode": mode.rawValue,
            "graceMs": graceMilliseconds,
            "reason": reason,
        ]

        runtime.executeJavaScriptCommand(
            webView,
            source,
            arguments
        )
    }

    private func isVisible(
        tab: Tab,
        in windowID: UUID?,
        visibleTabIDsByWindow: [UUID: Set<UUID>]
    ) -> Bool {
        guard let windowID else { return true }
        return visibleTabIDsByWindow[windowID]?.contains(tab.id) ?? false
    }

    private func isEligibleForOptimization(tab: Tab, webView: WKWebView) -> Bool {
        guard isOptimizableContentURL(tab.url) else { return false }
        guard !tab.isDisplayingPDFDocument else { return false }
        guard !tab.hasPictureInPictureVideo else { return false }
        guard !tab.isSuspended else { return false }
        guard webView.cameraCaptureState == .none else { return false }
        guard webView.microphoneCaptureState == .none else { return false }
        guard !webView.sumiIsInFullscreenElementPresentation else { return false }
        return true
    }

    private func isOptimizableContentURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func liveWebViewEntries(
        for tab: Tab,
        coordinator: WebViewCoordinator
    ) -> [(windowID: UUID?, webView: WKWebView)] {
        var seen = Set<ObjectIdentifier>()
        var entries: [(windowID: UUID?, webView: WKWebView)] = []

        func append(windowID: UUID?, webView: WKWebView?) {
            guard let webView else { return }
            guard seen.insert(ObjectIdentifier(webView)).inserted else { return }
            entries.append((windowID, webView))
        }

        for windowID in coordinator.windowIDs(for: tab.id) {
            append(
                windowID: windowID,
                webView: coordinator.getWebView(for: tab.id, in: windowID)
            )
        }

        for webView in coordinator.trackedLiveWebViews(for: tab) {
            append(
                windowID: coordinator.windowID(containing: webView) ?? tab.primaryWindowId,
                webView: webView
            )
        }

        return entries
    }

    private func notePendingReason(_ reason: String) {
        guard pendingReasons.count < 6 else {
            didTruncatePendingReasons = true
            return
        }
        pendingReasons.append(reason)
    }

    private func shouldResetAppliedCommands(for reason: String) -> Bool {
        reason.contains("navigation-did-finish")
    }
}
