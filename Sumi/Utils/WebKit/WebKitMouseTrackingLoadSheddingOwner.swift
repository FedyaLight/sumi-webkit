import AppKit
import WebKit

@MainActor
final class WebKitMouseTrackingLoadSheddingOwner {
    private static let webKitMouseTrackingObserverClassName = "WKMouseTrackingObserver"

    private weak var webView: WKWebView?
    private let addTrackingArea: (NSTrackingArea) -> Void
    private let removeTrackingArea: (NSTrackingArea) -> Void
    private let containsTrackingArea: (NSTrackingArea) -> Bool
    private let keepsMouseTrackingDuringLoad: () -> Bool
    private var observer: NSKeyValueObservation?
    private var trackingArea: NSTrackingArea?
    private var isLoading = false

    init(
        webView: WKWebView,
        addTrackingArea: @escaping (NSTrackingArea) -> Void,
        removeTrackingArea: @escaping (NSTrackingArea) -> Void,
        containsTrackingArea: @escaping (NSTrackingArea) -> Bool,
        keepsMouseTrackingDuringLoad: @escaping () -> Bool
    ) {
        self.webView = webView
        self.addTrackingArea = addTrackingArea
        self.removeTrackingArea = removeTrackingArea
        self.containsTrackingArea = containsTrackingArea
        self.keepsMouseTrackingDuringLoad = keepsMouseTrackingDuringLoad
    }

    deinit {
        observer?.invalidate()
    }

    static func canHandle(_ trackingArea: NSTrackingArea) -> Bool {
        canHandle(ownerClassName: trackingArea.owner?.className)
    }

    static func canHandle(ownerClassName: String?) -> Bool {
        ownerClassName == webKitMouseTrackingObserverClassName
    }

    func installTrackingArea(_ trackingArea: NSTrackingArea) {
        installObserverIfNeeded(for: trackingArea)
        updateTrackingArea(trackingArea)
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
        // WebKit installs this tracking area from inside WKWebView.init. Do not
        // read WKWebView properties until WebKit reports a loading transition.
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

    private func updateTrackingArea(_ trackingArea: NSTrackingArea) {
        if shouldSuspendTracking {
            guard containsTrackingArea(trackingArea) else { return }
            removeTrackingArea(trackingArea)
        } else {
            guard !containsTrackingArea(trackingArea) else { return }
            addTrackingArea(trackingArea)
        }
    }

    private var shouldSuspendTracking: Bool {
        isLoading && !keepsMouseTrackingDuringLoad()
    }
}
