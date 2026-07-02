import AppKit
import ObjectiveC.runtime
import WebKit

@MainActor
final class WebKitMouseTrackingLoadSheddingOwner {
    struct Dependencies {
        let addTrackingArea: (NSTrackingArea) -> Void
        let removeTrackingArea: (NSTrackingArea) -> Void
        let containsTrackingArea: (NSTrackingArea) -> Bool
        let keepsMouseTrackingDuringLoad: () -> Bool
        let isTransientChromeMouseTrackingSuppressed: () -> Bool
    }

    private static let isEnabled = true
    private static let webKitMouseTrackingObserverClassName = "WKMouseTrackingObserver"

    private weak var webView: WKWebView?
    private let dependencies: Dependencies
    private var observer: NSKeyValueObservation?
    private var trackingArea: NSTrackingArea?
    private var isLoading = false

    init(webView: WKWebView, dependencies: Dependencies) {
        self.webView = webView
        self.dependencies = dependencies
    }

    deinit {
        observer?.invalidate()
    }

    static func canHandle(_ trackingArea: NSTrackingArea) -> Bool {
        guard isEnabled,
              trackingArea.options.contains(.mouseMoved),
              let owner = trackingArea.owner
        else { return false }

        let ownerClassName = NSStringFromClass(object_getClass(owner) ?? Swift.type(of: owner))
        return ownerClassName == webKitMouseTrackingObserverClassName
            || ownerClassName.hasSuffix(".\(webKitMouseTrackingObserverClassName)")
            || ownerClassName.contains(webKitMouseTrackingObserverClassName)
    }

    func installTrackingArea(_ trackingArea: NSTrackingArea) {
        installObserverIfNeeded(for: trackingArea)
        updateTrackingArea(trackingArea)
        scheduleRefresh(for: trackingArea)
    }

    func refresh() {
        guard let trackingArea else { return }
        updateTrackingArea(trackingArea)
    }

    private func installObserverIfNeeded(for trackingArea: NSTrackingArea) {
        guard self.trackingArea !== trackingArea ||
              observer == nil
        else { return }

        observer?.invalidate()
        self.trackingArea = trackingArea
        let trackingAreaID = ObjectIdentifier(trackingArea)
        // WKWebView delivers KVO for its own properties on the main thread, so
        // the tracking area can be updated synchronously without allocating a
        // fresh Task on every loading transition.
        observer = webView?.observe(\.isLoading, options: [.new]) { [weak self, trackingAreaID] _, change in
            guard let isLoading = change.newValue else { return }
            MainActor.assumeIsolated {
                guard let self,
                      let trackingArea = self.trackingArea,
                      ObjectIdentifier(trackingArea) == trackingAreaID
                else { return }
                self.isLoading = isLoading
                self.updateTrackingArea(trackingArea)
            }
        }
    }

    private func scheduleRefresh(for trackingArea: NSTrackingArea) {
        let trackingAreaID = ObjectIdentifier(trackingArea)
        Task { @MainActor [weak self, trackingAreaID] in
            guard let self,
                  let trackingArea = self.trackingArea,
                  ObjectIdentifier(trackingArea) == trackingAreaID
            else { return }
            self.updateTrackingArea(trackingArea)
        }
    }

    private func updateTrackingArea(_ trackingArea: NSTrackingArea) {
        if shouldSuspendTracking {
            guard dependencies.containsTrackingArea(trackingArea) else { return }
            dependencies.removeTrackingArea(trackingArea)
        } else {
            guard !dependencies.containsTrackingArea(trackingArea) else { return }
            dependencies.addTrackingArea(trackingArea)
        }
    }

    private var shouldSuspendTracking: Bool {
        (isLoading && !dependencies.keepsMouseTrackingDuringLoad())
            || dependencies.isTransientChromeMouseTrackingSuppressed()
    }
}
